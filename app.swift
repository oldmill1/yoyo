import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var overlayWindow: NSWindow?
    
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
        let pipe = Pipe()
        
        task.currentDirectoryURL = URL(fileURLWithPath: "/Users/ataxali/dev/manuscriptos")
        task.executableURL = URL(fileURLWithPath: "/Users/ataxali/bin/cmtmsg")
        task.arguments = ["--confirm"]
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "No output"
            let message = "\(output.trimmingCharacters(in: .whitespacesAndNewlines))\nStatus: \(task.terminationStatus)"
            
            showOverlay(message: message)
        } catch {
            showOverlay(message: "Error: \(error)")
        }
    }
    
    func showOverlay(message: String) {
        // Close existing overlay if any
        overlayWindow?.close()
        
        let padding: CGFloat = 20
        let maxWidth: CGFloat = 500
        
        // Create text field to measure size
        let textField = NSTextField(labelWithString: message)
        textField.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textField.textColor = .white
        textField.alignment = .center
        textField.maximumNumberOfLines = 10
        textField.preferredMaxLayoutWidth = maxWidth - (padding * 2)
        
        let textSize = textField.fittingSize
        let windowWidth = min(textSize.width + (padding * 2), maxWidth)
        let windowHeight = textSize.height + (padding * 2)
        
        // Position at top center of screen
        let screenFrame = NSScreen.main?.frame ?? .zero
        let windowX = (screenFrame.width - windowWidth) / 2
        let windowY = screenFrame.height - windowHeight - 50
        
        let window = NSWindow(
            contentRect: NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        window.isOpaque = false
        window.level = .floating
        window.contentView?.wantsLayer = true
        
        textField.frame = NSRect(x: padding, y: padding, width: windowWidth - (padding * 2), height: textSize.height)
        window.contentView?.addSubview(textField)
        
        overlayWindow = window
        window.orderFront(nil)
        
        // Auto-dismiss after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.overlayWindow?.close()
            self?.overlayWindow = nil
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()