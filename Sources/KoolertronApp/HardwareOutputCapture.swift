import AppKit
import SwiftUI

@MainActor
final class HardwareOutputCapture: ObservableObject {
    @Published private(set) var armed=false
    @Published private(set) var result="Capture stopped"
    @Published private(set) var presses=0
    private var unexpected=false
    private var monitor:Any?
    func start() {
        stop();presses=0;unexpected=false;result="Waiting for the designated test key";armed=true
        monitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.flagsChanged]) { [weak self] event in
            guard let self,self.armed,NSApp.isActive,event.window?.identifier?.rawValue == "main" else { return event }
            let modifiers=event.modifierFlags.intersection([.command,.control,.option,.shift])
            if event.type == .flagsChanged {
                if !modifiers.isEmpty { self.unexpected=true;self.result="Unexpected modifier event; contents hidden" }
            } else {
                self.presses+=1
                if self.presses == 1,event.keyCode == 0,modifiers.isEmpty,!self.unexpected,!event.isARepeat {
                    self.result="A key event received (one press)"
                } else {
                    self.unexpected=true;self.result="Unexpected or multiple key events; contents hidden"
                }
            }
            return nil
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor);self.monitor=nil }
        armed=false
    }
}
