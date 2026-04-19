import SwiftUI

@main
struct GoPro360StitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup("GoPro 360 Stitcher") {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run any initial setup if needed.
    }
    
    // Enable closing the last window to quit the app, to avoid ghost background processes
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
