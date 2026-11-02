import AppKit
import SwiftUI
import UniformTypeIdentifiers
import KoolertronCore

private struct OfflineDraftReview:Codable {
    let keymap:PagePlan?
    let macros:MacroPagePlan?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var profile: Profile?
    @Published var connection=ConnectionTracker()
    var identity: DeviceIdentity? { connection.identity }
    @Published var busy=false
    @Published var selectedKey=0
    @Published var selectedLayer=0
    @Published var selectedMacro=0
    @Published var status="Looking for the keypad…"
    @Published var error: String?
    @Published var source="No configuration loaded"
    @Published var log:[String]=[]
    @Published var backupURL: URL?
    @Published var showDiagnostics=false
    @Published var pendingTransactionURL:URL?
    @Published var pendingStage:HardwareTransaction.Stage?
    @Published var lastVerifiedUploadURL:URL?
    @Published var uploadRecoveryBlocked=false
    @Published var restoreSummary=""
    private var applicationSupportRoot:URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
            .appendingPathComponent("Koolertron Configurator",isDirectory:true)
    }
    var uploadUnresolved:Bool { pendingTransactionURL != nil || uploadRecoveryBlocked }
    var canUpload:Bool { identity != nil && changeCount > 0 && !busy && !uploadUnresolved }
    var canUploadMacros:Bool {
        guard identity != nil,macroChangeCount > 0,!busy,!uploadUnresolved,let profile else{return false}
        return (try? MacroPagePlan(snapshot:profile.snapshot,draftMacros:profile.draftMacros)) != nil
    }
    var canRestoreUpload:Bool {
        guard identity != nil,!hasEdits,!busy,!uploadUnresolved,let operation=try? lastVerifiedOperation() else{return false}
        return operation == .normalLayerUpload || operation == .restoreNormalLayer
    }
    var canRestoreMacroUpload:Bool {
        guard identity != nil,!hasEdits,!busy,!uploadUnresolved,let operation=try? lastVerifiedOperation() else{return false}
        return operation == .macroUpload || operation == .restoreMacros
    }
    var uploadSummary:String {
        guard let p=profile else {return ""}
        let rows=PagePlan.keyOffsets.filter {p.snapshot.layers[0][$0] != p.draftLayers[0][$0]}.map {offset in
            "Row \(offset/8+1), column \(offset%8+1): \(KeyChoice.label(p.snapshot.layers[0][offset])) → \(KeyChoice.label(p.draftLayers[0][offset]))"
        }
        return rows.joined(separator:"\n")+"\n\nA private original-state backup will be saved on this Mac. Keep the keypad connected until verification finishes. Stored macro contents and other layers are preserved."
    }
    var macroUploadSummary:String {
        guard let p=profile else{return ""}
        let slots=(0..<12).filter{p.snapshot.macros[$0] != p.draftMacros[$0]}.map {slot in
            let count=(try? MacroCodec.decode(p.draftMacros[slot],allowHeldKeys:true).count) ?? 0
            return "Slot \(slot+1): \(count) key events"
        }
        return slots.joined(separator:"\n")+"\n\nEvery key press must have a matching release before upload. The final flash page includes 32 bytes beyond the macro data; this version pads those unread bytes with 0xFF. Macro upload is not physically validated yet. The macro data can contain private text. A private original-state backup will be saved on this Mac. Keep the keypad connected until full readback verification finishes."
    }
    var hasEdits: Bool { profile.map { $0.draftLayers != $0.snapshot.layers || $0.draftMacros != $0.snapshot.macros } ?? false }
    var changeCount: Int { guard let p=profile else { return 0 };return PagePlan.keyOffsets.filter { p.snapshot.layers[0][$0] != p.draftLayers[0][$0] }.count }
    var macroChangeCount:Int { guard let p=profile else{return 0};return (0..<12).filter{p.snapshot.macros[$0] != p.draftMacros[$0]}.count }
    var canRestoreAnyUpload:Bool { identity != nil && lastVerifiedUploadURL != nil && !hasEdits && !busy && !uploadUnresolved }
    var selectedMacroActions:[MacroAction] { guard let profile else{return []};return (try? MacroCodec.decode(profile.draftMacros[selectedMacro],allowHeldKeys:true)) ?? [] }
    var selectedMacroDecodeError:String? { guard let profile else{return nil};do {_ = try MacroCodec.decode(profile.draftMacros[selectedMacro],allowHeldKeys:true);return nil} catch {return error.localizedDescription} }
    var selectedMacroUploadError:String? {do {try MacroCodec.validate(selectedMacroActions);return nil} catch {return error.localizedDescription} }
    var selectedOffset: Int { PagePlan.keyOffsets[selectedKey] }
    var selectedCode: UInt8 { profile?.draftLayers[selectedLayer][selectedOffset] ?? 0 }
    func note(_ message:String) {
        let stamp=Date().formatted(date:.omitted,time:.standard)
        log.append("\(stamp)  \(message)");if log.count>150 { log.removeFirst(log.count-150) }
    }
    func fail(_ failure:Error) { error=failure.localizedDescription;note(failure.localizedDescription) }
    func checkStorage() throws {
        try FileManager.default.createDirectory(at:applicationSupportRoot,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        guard FileManager.default.isWritableFile(atPath:applicationSupportRoot.path) else {
            throw ConfiguratorError("The private Koolertron application-support folder on this Mac is not writable.")
        }
    }
    func privateDirectory() throws -> URL {
        try checkStorage()
        let directory=applicationSupportRoot.appendingPathComponent("backups/native",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        return directory
    }
    func persistDraft(_ profile: Profile) throws {
        let directory=try privateDirectory()
        try DraftStore(url:directory.appendingPathComponent("working-draft.json")).save(profile)
    }
    func refreshUploadRecovery(finalizeVerified:Bool=false) throws {
        let journal=UploadJournal(directory:try privateDirectory())
        pendingTransactionURL=try journal.pendingURL()
        lastVerifiedUploadURL=try journal.lastVerifiedURL()
        pendingStage=nil
        if let pending=pendingTransactionURL {
            let record=try UploadJournal.readRecord(pending)
            pendingStage=record.stage
            if record.stage == .verified && finalizeVerified {
                let lock=try journal.acquireTransactionLock();defer {lock.release()}
                try finalizeUpload(record,url:pending,lock:lock)
            } else if profile == nil {
                profile=Profile(snapshot:record.original,draftLayers:record.proposedLayers,draftMacros:record.proposedMacros ?? record.original.macros)
                source="Unfinished upload; inspect or verify before uploading again"
            }
        }
        if let last=lastVerifiedUploadURL {
            let record=try UploadJournal.readRecord(last)
            guard record.stage == .verified else { throw ConfiguratorError("The saved previous-upload record is not verified.") }
            if let macroPlan=record.macroPlan {
                restoreSummary=macroPlan.changedSlots.map{"Macro slot \($0+1)"}.joined(separator:", ")+"\n\nThe current keypad must match the previous verified upload. A new backup is saved before restoration. Macro contents remain private."
            } else if let plan=record.plan {
                restoreSummary=plan.changedOffsets.map {offset in
                    "Row \(offset/8+1), column \(offset%8+1): \(KeyChoice.label(record.proposedLayers[0][offset])) → \(KeyChoice.label(record.original.layers[0][offset]))"
                }.joined(separator:"\n")+"\n\nThe current keypad must match the previous verified upload. A new backup is saved before restoration."
            }
        } else { restoreSummary="" }
        uploadRecoveryBlocked=false
    }
    func finalizeUpload(_ record:HardwareTransaction,url:URL,lock:UploadTransactionLock) throws {
        guard record.stage == .verified,let snapshot=record.observedSnapshot else { throw ConfiguratorError("Upload has no verified readback snapshot.") }
        let retainedMacros = record.macroPlan == nil ? (profile?.draftMacros ?? snapshot.macros) : snapshot.macros
        let retainedLayers = record.macroPlan == nil ? snapshot.layers : (profile?.draftLayers ?? snapshot.layers)
        let captured=Profile(snapshot:snapshot,draftLayers:retainedLayers,draftMacros:retainedMacros)
        profile=captured;backupURL=url
        source="Verified upload readback"
        try persistDraft(captured)
        try UploadJournal(directory:privateDirectory()).complete(url,lock:lock)
        pendingTransactionURL=nil;pendingStage=nil;lastVerifiedUploadURL=url;uploadRecoveryBlocked=false
    }
    private func lastVerifiedOperation() throws -> HardwareTransaction.Operation? {
        guard let lastVerifiedUploadURL else{return nil};return try UploadJournal.readRecord(lastVerifiedUploadURL).operation
    }
    func uploadDraft(restoring:Bool=false) async {
        guard !busy,!uploadUnresolved,let identity,let currentProfile=profile else {return}
        guard restoring ? canRestoreUpload : canUpload else {return}
        busy=true;defer {busy=false}
        status=restoring ? "Restoring previous mapping; keep the keypad connected…" : "Uploading draft; keep the keypad connected…"
        do {
            let directory=try privateDirectory()
            let journal=UploadJournal(directory:directory)
            let lock=try journal.acquireTransactionLock();defer {lock.release()}
            guard try journal.pendingURL() == nil else {throw ConfiguratorError("A previous upload is unresolved. Inspect it before continuing.")}
            let url=directory.appendingPathComponent("upload-\(UUID().uuidString).json")
            let previous=restoring ? try lastVerifiedUploadURL.map {try UploadJournal.readRecord($0)} : nil
            let record=try await Task.detached(priority:.userInitiated) { () throws -> HardwareTransaction in
                let io=NativeConfigurationIO(expectedLocation:identity.locationID)
                if let previous {
                    return try HardwareWriter.restoreProfileUpload(io:io,record:previous,transactionURL:url,beforeChanging:{try journal.begin(url,lock:lock)})
                }
                return try HardwareWriter.uploadProfile(currentProfile,io:io,transactionURL:url,beforeChanging:{try journal.begin(url,lock:lock)})
            }.value
            try finalizeUpload(record,url:url,lock:lock)
            try refreshUploadRecovery()
            status=restoring ? "Previous mapping restored and verified" : "Upload complete; readback verified"
            note(restoring ? "Restored previous normal-layer assignments; full readback verified." : "Uploaded normal-layer assignments; full readback verified.")
        } catch {
            status="Upload stopped; no automatic retry"
            do {try refreshUploadRecovery()} catch {uploadRecoveryBlocked=true;note("Recovery index needs inspection: \(error.localizedDescription)")}
            fail(error)
        }
    }
    func uploadMacroDraft(restoring:Bool=false) async {
        guard !busy,!uploadUnresolved,let identity,let currentProfile=profile else{return}
        guard restoring ? canRestoreMacroUpload : canUploadMacros else{return}
        busy=true;defer {busy=false}
        status=restoring ? "Restoring previous macros; keep the keypad connected…" : "Uploading macro drafts; keep the keypad connected…"
        do {
            let directory=try privateDirectory();let journal=UploadJournal(directory:directory)
            let lock=try journal.acquireTransactionLock();defer {lock.release()}
            guard try journal.pendingURL() == nil else {throw ConfiguratorError("A previous upload is unresolved. Inspect it before continuing.")}
            let url=directory.appendingPathComponent("upload-\(UUID().uuidString).json")
            let previous=restoring ? try lastVerifiedUploadURL.map {try UploadJournal.readRecord($0)} : nil
            let record=try await Task.detached(priority:.userInitiated) { () throws -> HardwareTransaction in
                let io=NativeConfigurationIO(expectedLocation:identity.locationID)
                if let previous {return try HardwareWriter.restoreMacroUpload(io:io,record:previous,transactionURL:url,beforeChanging:{try journal.begin(url,lock:lock)})}
                return try HardwareWriter.uploadMacros(currentProfile,io:io,transactionURL:url,beforeChanging:{try journal.begin(url,lock:lock)})
            }.value
            try finalizeUpload(record,url:url,lock:lock);try refreshUploadRecovery()
            status=restoring ? "Previous macros restored and verified" : "Macro upload complete; readback verified"
            note(restoring ? "Restored prior macro slots; full readback verified." : "Uploaded changed macro slots; full readback verified. Macro contents omitted from diagnostics.")
        } catch {
            status="Macro upload stopped; no automatic retry"
            do {try refreshUploadRecovery()} catch {uploadRecoveryBlocked=true;note("Recovery index needs inspection: \(error.localizedDescription)")}
            fail(error)
        }
    }
    func verifyPendingUpload() async {
        guard !busy,let url=pendingTransactionURL else {return}
        busy=true;defer {busy=false}
        status="Verifying previous upload; no device write…"
        do {
            let journal=UploadJournal(directory:try privateDirectory())
            let lock=try journal.acquireTransactionLock();defer {lock.release()}
            guard try journal.pendingURL() == url else {throw ConfiguratorError("Upload recovery state changed. Refresh before continuing.")}
            let saved=try UploadJournal.readRecord(url)
            let record:HardwareTransaction
            if saved.stage == .verified {record=saved}
            else {
                guard saved.stage == .normalObserved else {throw ConfiguratorError("This upload stopped before a confirmed normal-mode return. Inspect its recovery record; do not resend it.")}
                record=try await Task.detached(priority:.userInitiated) {
                    let io=NativeConfigurationIO(expectedLocation:saved.original.locationID)
                    return try HardwareWriter.reverifyReadback(io:io,transactionURL:url)
                }.value
            }
            try finalizeUpload(record,url:url,lock:lock)
            try refreshUploadRecovery()
            status="Previous upload readback verified"
            note("Finalized previous upload without sending another configuration page.")
        } catch {status="Verification incomplete; no device write";fail(error)}
    }
    func cancelPreparedUpload() {
        guard !busy,pendingStage == .prepared else {return}
        do {
            try UploadJournal(directory:privateDirectory()).cancelPrepared()
            try refreshUploadRecovery()
            note("Canceled prepared upload recovery state; no device commands had started.")
        } catch {fail(error)}
    }
    func revealUploadRecord() {
        if let url=pendingTransactionURL ?? lastVerifiedUploadURL {NSWorkspace.shared.activateFileViewerSelecting([url])}
    }
    func monitor() async {
        do {try refreshUploadRecovery(finalizeVerified:true)} catch {uploadRecoveryBlocked=true;fail(error)}
        if profile == nil {
            do {
                let directory=try privateDirectory()
                if let recovered=try DraftStore(url:directory.appendingPathComponent("working-draft.json")).recover() {
                    profile=recovered;source="Recovered private draft from this Mac"
                    note("Recovered local draft. Hardware unchanged.")
                }
            } catch { fail(error) }
        }
        while !Task.isCancelled {
            if !busy {
                do {
                    let found=try await Task.detached(priority:.utility) { try HIDTransport.connectedIdentity() }.value
                    if found != identity || connection.error != nil {
                        connection.discovered(found)
                        if found == nil { status="Keypad disconnected";note("Keypad disconnected; drafts retained.") }
                        else {
                            status="Keypad connected";note("Matched 20A0:422D vendor interface.")
                            if profile == nil { await readDevice() }
                            else if !source.hasPrefix("Recovered") { source="Previous snapshot or profile; read keypad to refresh" }
                        }
                    }
                } catch { connection.failed(error.localizedDescription);status="Connection unavailable";if log.last?.contains(error.localizedDescription) != true { note(error.localizedDescription) } }
            }
            try? await Task.sleep(nanoseconds:2_000_000_000)
        }
    }
    func readDevice() async {
        guard !busy else { return };busy=true;defer { busy=false }
        status="Reading keymaps and stored macros…"
        do {
            let expected=identity
            let snapshot=try await Task.detached(priority:.userInitiated) { try HIDTransport.readSnapshot(expected:expected) }.value
            let captured=Profile(snapshot:snapshot,draftLayers:snapshot.layers,draftMacros:snapshot.macros)
            let directory=try privateDirectory()
            let url=directory.appendingPathComponent("snapshot-\(UUID().uuidString).json")
            try PrivateFiles.save(try captured.encoded(),to:url)
            try persistDraft(captured)
            profile=captured;backupURL=url
            source="Read from connected keypad";status="Connected · firmware \(snapshot.firmware)"
            note("Read four keymaps and twelve macros. Macro contents omitted from diagnostics.")
            note("Private snapshot saved in this Mac’s Application Support folder.")
        } catch { status="Read or backup failed; previous draft retained";fail(error) }
    }
    func assign(_ code:UInt8) {
        guard !busy,selectedLayer==0,var p=profile else { return }
        p.draftLayers[0][selectedOffset]=code
        do { try p.validate();try persistDraft(p);profile=p } catch { fail(error) }
    }
    func revertSelected() {
        guard let p=profile,selectedLayer==0 else { return }
        assign(p.snapshot.layers[0][selectedOffset])
    }
    func setMacroActions(_ actions:[MacroAction]) {
        guard !busy,var p=profile else{return}
        do {p.draftMacros[selectedMacro]=try MacroCodec.encode(actions,allowHeldKeys:true);try p.validate();try persistDraft(p);profile=p}
        catch {fail(error)}
    }
    func appendMacroText(_ text:String) {
        do {setMacroActions(selectedMacroActions + (try MacroCodec.actions(forText:text)))} catch {fail(error)}
    }
    func revertSelectedMacro() {
        guard var p=profile else{return}
        p.draftMacros[selectedMacro]=p.snapshot.macros[selectedMacro]
        do {try p.validate();try persistDraft(p);profile=p} catch {fail(error)}
    }
    func clearSelectedMacro() {setMacroActions([])}
    func saveProfile() {
        guard let profile else { return }
        do {
            try checkStorage()
            let panel=NSSavePanel();panel.title="Save private keypad profile";panel.nameFieldStringValue="Keypad Profile.json"
            panel.allowedContentTypes=[.json];panel.directoryURL=applicationSupportRoot
            panel.message="Includes the captured stored macros, which may contain private text. Saving does not change the keypad."
            guard panel.runModal() == .OK,let url=panel.url else { return }
            try PrivateFiles.save(try profile.encoded(),to:url,replaceExisting:true)
            note("Profile saved. Hardware unchanged.")
        } catch { fail(error) }
    }
    func loadProfile() {
        do {
            try checkStorage()
            let panel=NSOpenPanel();panel.title="Load keypad profile";panel.allowedContentTypes=[.json];panel.directoryURL=applicationSupportRoot;panel.allowsMultipleSelection=false
            guard panel.runModal() == .OK,let url=panel.url else { return }
            let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size<=256*1024 else { throw ConfiguratorError("Profile exceeds the 256 KB limit.") }
            let loaded=try Profile.decode(Data(contentsOf:url))
            try persistDraft(loaded)
            profile=loaded;source="Profile file: \(url.lastPathComponent)";backupURL=nil
            selectedLayer=0;note("Profile loaded into local editor. Hardware unchanged.")
        } catch { fail(error) }
    }
    func exportPlan() {
        guard let profile else { return }
        do {
            try checkStorage()
            let keymap=profile.draftLayers == profile.snapshot.layers ? nil : try PagePlan(snapshot:profile.snapshot,draftLayers:profile.draftLayers)
            let macros=profile.draftMacros == profile.snapshot.macros ? nil : try MacroPagePlan(snapshot:profile.snapshot,draftMacros:profile.draftMacros)
            let panel=NSSavePanel();panel.title="Export offline configuration plan";panel.nameFieldStringValue="Configuration Review.json";panel.allowedContentTypes=[.json];panel.directoryURL=applicationSupportRoot
            panel.message="Review only. If macro drafts are present, this file contains their encoded key events and may include private text. It does not program the keypad."
            guard panel.runModal() == .OK,let url=panel.url else { return }
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try PrivateFiles.save(try encoder.encode(OfflineDraftReview(keymap:keymap,macros:macros)),to:url,replaceExisting:true)
            note("Offline plan exported; no USB write performed.")
        } catch { fail(error) }
    }
    func revealBackup() { if let backupURL { NSWorkspace.shared.activateFileViewerSelecting([backupURL]) } }
    func copyDiagnostics() {
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(log.joined(separator:"\n"),forType:.string)
    }
}
