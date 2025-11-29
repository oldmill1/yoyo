import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "☕"
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hello!", action: nil, keyEquivalent: ""))
        
        let commitPushItem = NSMenuItem(title: "Commit Push", action: #selector(commitPush), keyEquivalent: "")
        commitPushItem.target = self
        menu.addItem(commitPushItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    
    @objc func commitPush() {
        let task = Process()
        task.currentDirectoryURL = URL(fileURLWithPath: "/Users/ataxali/dev/manuscriptos")
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "echo 'Hello from manuscriptos!'"]  // placeholder command
        
        do {
            try task.run()
            task.waitUntilExit()
            print("Command finished with status: \(task.terminationStatus)")
        } catch {
            print("Error: \(error)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()