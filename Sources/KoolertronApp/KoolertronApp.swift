import AppKit
import SwiftUI

@main
struct KoolertronApp: App {
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene {
        Window("Koolertron Configurator",id:"main") { ContentView().onAppear { NSApp.activate(ignoringOtherApps:true) } }
            .defaultSize(width:870,height:710)
    }
}
