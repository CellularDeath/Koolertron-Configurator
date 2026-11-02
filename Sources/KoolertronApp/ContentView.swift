import SwiftUI
import KoolertronCore

struct ContentView: View {
    @StateObject private var model=AppModel()
    @State private var replaceRead=false
    @State private var replaceLoad=false
    @State private var reviewUpload=false
    @State private var reviewRestore=false
    @State private var reviewMacroUpload=false
    @State private var reviewMacroRestore=false
    @State private var macroText=""
    @State private var macroKey:UInt8=4
    @State private var macroDelay=0
    @StateObject private var outputCapture=HardwareOutputCapture()
    private let layers=["Normal","FN","FN2","FN3"]
    var body: some View {
        ScrollView {
        VStack(alignment:.leading,spacing:20) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:5) {
                    Text("Koolertron Configurator · 0.7.0").font(.title2.bold())
                    Label(model.status,systemImage:model.identity == nil ? "cable.connector.slash" : "cable.connector")
                        .foregroundStyle(model.identity == nil ? .secondary : .primary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small).accessibilityLabel("Reading keypad") }
                Button("Read keypad") { if model.hasEdits { replaceRead=true } else { Task { await model.readDevice() } } }
                    .disabled(model.busy || model.identity == nil).keyboardShortcut("r")
            }
            HStack {
                Text("\(model.changeCount) keymap · \(model.macroChangeCount) macro slot\(model.macroChangeCount == 1 ? "" : "s") changed locally").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Load profile…") { if model.profile != nil { replaceLoad=true } else { model.loadProfile() } }.disabled(model.busy)
                Button("Save profile…") { model.saveProfile() }.disabled(model.profile == nil || model.busy).keyboardShortcut("s")
            }
            Divider()
            if let profile=model.profile {
                HStack(alignment:.top,spacing:28) {
                    VStack(alignment:.leading,spacing:14) {
                        Picker("Layer",selection:$model.selectedLayer) {
                            ForEach(0..<4) { Text(layers[$0]).tag($0) }
                        }.pickerStyle(.segmented).frame(width:330)
                        LazyVGrid(columns:Array(repeating:GridItem(.fixed(104),spacing:9),count:3),spacing:9) {
                            ForEach(0..<9) { index in
                                let offset=PagePlan.keyOffsets[index]
                                let code=profile.draftLayers[model.selectedLayer][offset]
                                let changed=code != profile.snapshot.layers[model.selectedLayer][offset]
                                Button { model.selectedKey=index } label: {
                                    VStack(spacing:8) {
                                        Text("Row \(index/3+1) · Col \(index%3+1)").font(.caption).foregroundStyle(.secondary)
                                        Text(KeyChoice.label(code)).font(.headline).multilineTextAlignment(.center).lineLimit(2)
                                        Text(changed ? "Edited locally" : "Captured mapping").font(.caption2).foregroundStyle(.secondary)
                                    }.frame(width:96,height:96)
                                }.buttonStyle(.bordered).tint(model.selectedKey == index ? .accentColor : .secondary)
                                    .overlay(RoundedRectangle(cornerRadius:7).stroke(model.selectedKey == index ? Color.accentColor : Color.clear,lineWidth:2))
                                    .accessibilityLabel("Row \(index/3+1), column \(index%3+1), \(KeyChoice.label(code))\(changed ? ", edited locally" : "")")
                            }
                        }
                        Text("Top-left position verified. Other cells show firmware matrix coordinates.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).frame(width:330,alignment:.leading)
                    }
                    VStack(alignment:.leading,spacing:14) {
                        Text("Row \(model.selectedKey/3+1), column \(model.selectedKey%3+1)").font(.title3.bold())
                        Text("Captured: \(KeyChoice.label(profile.snapshot.layers[model.selectedLayer][model.selectedOffset]))")
                            .foregroundStyle(.secondary)
                        if model.selectedLayer == 0 {
                            Picker("Draft assignment",selection:Binding(get:{model.selectedCode},set:{model.assign($0)})) {
                                if !KeyChoice.all.contains(where:{$0.code == model.selectedCode}) { Text(KeyChoice.label(model.selectedCode)).tag(model.selectedCode) }
                                ForEach(KeyChoice.all) { Text($0.name).tag($0.code) }
                            }.disabled(model.busy)
                            Button("Revert this local edit") { model.revertSelected() }.disabled(model.busy)
                        } else {
                            Text("This layer is available for inspection. This version writes only normal-layer assignments.")
                                .foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        }
                        if model.selectedCode >= 189 && model.selectedCode <= 200 {
                            let slot=Int(model.selectedCode)-189
                            Text("Stored macro \(slot+1): \(profile.snapshot.macros[slot].contains(where:{$0 != 0}) ? "captured" : "empty"). Its 168-byte contents are preserved privately in the profile.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        }
                        Divider()
                        Text("Save assignments to the keypad").font(.headline)
                        Text("Key assignments and macro drafts upload in separate reviewed operations. Each upload keeps the other keymaps, macros, and device options intact, then checks the device readback.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        Button("Upload draft…") {reviewUpload=true}.disabled(!model.canUpload)
                        Button("Restore prior upload…") {reviewRestore=true}.disabled(!model.canRestoreUpload)
                        if model.uploadUnresolved {
                            Text("A previous upload needs verification or inspection. Uploading again is blocked.").font(.callout).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
                            if model.pendingStage == .normalObserved || model.pendingStage == .verified {
                                Button(model.pendingStage == .verified ? "Finish saved upload" : "Verify last upload") {Task {await model.verifyPendingUpload()}}.disabled(model.busy)
                            }
                            if model.pendingStage == .prepared {
                                Button("Cancel prepared upload") {model.cancelPreparedUpload()}.disabled(model.busy)
                            }
                            Button("Show recovery record") {model.revealUploadRecord()}.disabled(model.pendingTransactionURL == nil)
                        }
                        Button("Export review plan…") { model.exportPlan() }.disabled(!model.hasEdits || model.busy)
                        Text("Exports the exact proposed page changes for review. Does not program the keypad.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
                macroEditor(profile)
                Divider()
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:4) {
                        Text(model.source).font(.callout)
                        Text("Captured \(profile.snapshot.capturedAt.formatted()) · 4 keymaps · 12 stored macros").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Show private backup") { model.revealBackup() }.disabled(model.backupURL == nil)
                }
            } else {
                ContentUnavailableView("Connect your keypad",systemImage:"keyboard",description:Text("The supported ps2avrGB keypad is detected automatically. You can also load a saved profile for local editing."))
                    .frame(maxWidth:.infinity,minHeight:330)
            }
            if CommandLine.arguments.contains("--hardware-output-test") {
                Divider()
                Text("Single-key hardware output test").font(.headline)
                Text("Arm capture only after the approved A mapping has been uploaded and read back. Press only the designated keypad key. Mac keyboard input is also counted.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Text(outputCapture.result).font(.headline).accessibilityLabel("Hardware test result: \(outputCapture.result)")
                Text("Key presses received: \(outputCapture.presses). While armed, shortcuts in this window are suppressed; click Stop capture to resume. Unexpected event contents are hidden.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Arm or restart capture") { outputCapture.start() }
                    Button("Stop capture") { outputCapture.stop() }.disabled(!outputCapture.armed)
                }.onDisappear { outputCapture.stop() }
            }
            DisclosureGroup("Diagnostics",isExpanded:$model.showDiagnostics) {
                VStack(alignment:.leading,spacing:8) {
                    ScrollView { Text(model.log.isEmpty ? "No diagnostic events yet." : model.log.joined(separator:"\n")).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.frame(height:110)
                    Button("Copy diagnostics") { model.copyDiagnostics() }
                }.padding(.top,8)
            }
        }.padding(24).frame(maxWidth:.infinity,alignment:.leading)
        }.frame(minWidth:810,minHeight:650)
            .task { await model.monitor() }
            .alert("Configurator",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error=nil}})) { Button("OK") { model.error=nil } } message: { Text(model.error ?? "") }
            .confirmationDialog("Upload \(model.changeCount) normal-layer assignment change\(model.changeCount == 1 ? "" : "s")?",isPresented:$reviewUpload,titleVisibility:.visible) {
                Button("Upload to keypad") {Task {await model.uploadDraft()}}
                Button("Cancel",role:.cancel) {}
            } message: {Text(model.uploadSummary)}
            .confirmationDialog("Restore the prior onboard assignments?",isPresented:$reviewRestore,titleVisibility:.visible) {
                Button("Restore prior assignments") {Task {await model.uploadDraft(restoring:true)}}
                Button("Cancel",role:.cancel) {}
            } message: {Text(model.restoreSummary)}
            .confirmationDialog("Upload \(model.macroChangeCount) changed macro slot\(model.macroChangeCount == 1 ? "" : "s")?",isPresented:$reviewMacroUpload,titleVisibility:.visible) {
                Button("Upload macros to keypad") {Task {await model.uploadMacroDraft()}}
                Button("Cancel",role:.cancel) {}
            } message: {Text(model.macroUploadSummary)}
            .confirmationDialog("Restore the prior onboard macros?",isPresented:$reviewMacroRestore,titleVisibility:.visible) {
                Button("Restore prior macros") {Task {await model.uploadMacroDraft(restoring:true)}}
                Button("Cancel",role:.cancel) {}
            } message: {Text(model.restoreSummary)}
            .confirmationDialog("Replace the local draft with a fresh device read?",isPresented:$replaceRead,titleVisibility:.visible) {
                Button("Read and replace draft",role:.destructive) { Task { await model.readDevice() } }
                Button("Cancel",role:.cancel) {}
            }
            .confirmationDialog("Load a profile in place of this local draft?",isPresented:$replaceLoad,titleVisibility:.visible) {
                Button("Choose profile…") { model.loadProfile() }
                Button("Cancel",role:.cancel) {}
            }
    }

    @ViewBuilder
    private func macroEditor(_ profile:Profile)->some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.firstTextBaseline) {
                Text("Macro workshop").font(.title3.bold())
                Text("Draft first. Upload only after review.").font(.callout).foregroundStyle(.secondary)
            }
            Text("Edit any of the 12 stored slots. A slot holds up to 42 simple keystrokes (84 press/release events); delays are in 0.1-second steps. Macro text and profiles may contain private information.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack(alignment:.top,spacing:20) {
                VStack(alignment:.leading,spacing:10) {
                    Picker("Macro slot",selection:$model.selectedMacro) {
                        ForEach(0..<12,id:\.self) { slot in
                            let edited=profile.snapshot.macros[slot] != profile.draftMacros[slot]
                            Text("Slot \(slot+1)\(edited ? " · edited" : "")").tag(slot)
                        }
                    }.frame(width:210)
                    Text("Captured: \(profile.snapshot.macros[model.selectedMacro].contains(where:{$0 != 0}) ? "has a stored sequence" : "empty")")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Draft: \(profile.draftMacros[model.selectedMacro].contains(where:{$0 != 0}) ? "has a sequence" : "empty") · \(model.selectedMacroActions.count)/84 events")
                        .font(.callout)
                    HStack {
                        Button("Revert slot") {model.revertSelectedMacro()}.disabled(model.busy)
                        Button("Clear slot") {model.clearSelectedMacro()}.disabled(model.busy)
                    }
                }
                VStack(alignment:.leading,spacing:10) {
                    if let problem=model.selectedMacroDecodeError {
                        Label("This stored sequence contains an event this editor cannot safely decode. It is preserved in the private profile. Clear this slot to replace it with a new draft. (\(problem))",systemImage:"exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
                    }
                    HStack {
                        Picker("Key",selection:$macroKey) {ForEach(MacroCodec.keyChoices){Text($0.name).tag($0.code)}}.frame(width:220)
                        Stepper("Delay after event: \(macroDelay / 10).\(macroDelay % 10)s",value:$macroDelay,in:0...50)
                    }.disabled(model.busy || model.selectedMacroDecodeError != nil)
                    HStack {
                        Button("Add tap") {appendTap()}.disabled(model.busy || model.selectedMacroDecodeError != nil || model.selectedMacroActions.count > 82)
                        Button("Hold key") {appendEvent(isDown:true)}
                        Button("Release key") {appendEvent(isDown:false)}
                    }.disabled(model.busy || model.selectedMacroDecodeError != nil || model.selectedMacroActions.count >= 84)
                    HStack {
                        TextField("Text to type with this macro",text:$macroText)
                            .textFieldStyle(.roundedBorder).onSubmit {appendText()}
                        Button("Add text") {appendText()}
                    }.disabled(model.busy || model.selectedMacroDecodeError != nil)
                    if model.selectedMacroActions.isEmpty && model.selectedMacroDecodeError == nil {
                        Text("This slot is empty. Add a text sequence or build it one key at a time.").font(.callout).foregroundStyle(.secondary)
                    } else if model.selectedMacroDecodeError == nil {
                        if let warning=model.selectedMacroUploadError {
                            Label("Draft only: \(warning)",systemImage:"hand.raised.fill").font(.callout).foregroundStyle(.orange)
                        }
                        ScrollView {
                            VStack(alignment:.leading,spacing:5) {
                                ForEach(Array(model.selectedMacroActions.enumerated()),id:\.offset) { index,action in
                                    HStack(spacing:8) {
                                        Text(String(format:"%02d",index+1)).font(.system(.caption,design:.monospaced)).foregroundStyle(.secondary)
                                        Text(MacroCodec.keyChoices.first(where:{$0.code == action.keyIndex})?.name ?? "Unknown key")
                                        Text(action.isDown ? "Press" : "Release").foregroundStyle(.secondary)
                                        if action.delayTicks>0 {Text("+\(Double(action.delayTicks)/10,specifier:"%.1f")s").foregroundStyle(.secondary)}
                                        Spacer(minLength:4)
                                        Button {moveEvent(index,by:-1)} label:{Image(systemName:"arrow.up")}.disabled(index==0)
                                        Button {moveEvent(index,by:1)} label:{Image(systemName:"arrow.down")}.disabled(index==model.selectedMacroActions.count-1)
                                        Button(role:.destructive) {removeEvent(index)} label:{Image(systemName:"trash")}
                                    }.buttonStyle(.borderless)
                                }
                            }.frame(maxWidth:.infinity,alignment:.leading).padding(8)
                        }.frame(height:150).background(.quaternary.opacity(0.45),in:RoundedRectangle(cornerRadius:8))
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            Divider()
            HStack {
                Button("Upload macro drafts…") {reviewMacroUpload=true}.disabled(!model.canUploadMacros)
                Button("Restore prior macro upload…") {reviewMacroRestore=true}.disabled(!model.canRestoreMacroUpload)
                Text("Only changed slots are included. The app saves a private backup and verifies all keymaps, macro slots, and options after upload.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
            .background(.background,in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(.quaternary,lineWidth:1))
    }

    private func appendEvent(isDown:Bool) {
        model.setMacroActions(model.selectedMacroActions + [MacroAction(keyIndex:macroKey,isDown:isDown,delayTicks:UInt8(macroDelay))])
        macroDelay=0
    }
    private func appendTap() {
        let delay=UInt8(macroDelay)
        model.setMacroActions(model.selectedMacroActions + [MacroAction(keyIndex:macroKey,isDown:true),MacroAction(keyIndex:macroKey,isDown:false,delayTicks:delay)])
        macroDelay=0
    }
    private func appendText() {guard !macroText.isEmpty else{return};model.appendMacroText(macroText);macroText=""}
    private func removeEvent(_ index:Int) {
        var actions=model.selectedMacroActions;guard actions.indices.contains(index) else{return};actions.remove(at:index);model.setMacroActions(actions)
    }
    private func moveEvent(_ index:Int,by offset:Int) {
        var actions=model.selectedMacroActions;let target=index+offset
        guard actions.indices.contains(index),actions.indices.contains(target) else{return}
        actions.swapAt(index,target);model.setMacroActions(actions)
    }
}
