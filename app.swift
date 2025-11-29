import Cocoa
import Carbon

func hotKeyHandler(nextHandler: EventHandlerCallRef?, theEvent: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async {
        AppDelegate.shared?.commitPush()
    }
    return noErr
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var overlayWindow: NSWindow?
    var fadeTimer: Timer?
    var eventMonitor: Any?
    var hotKeyRef: EventHotKeyRef?
    
    static var shared: AppDelegate!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
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

        // Register Carbon hotkey for Control + Option + Command + E
        let hotKeyID = EventHotKeyID(signature: OSType(0x68747323), id: 1) // "hts#1"
        let keyCode: UInt32 = 14 // E key
        let keyModifiers: UInt32 = UInt32(cmdKey | controlKey | optionKey)
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        var hotKeyRef: EventHotKeyRef?
        
        let status = RegisterEventHotKey(
            keyCode,
            keyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        self.hotKeyRef = hotKeyRef
        
        if status == noErr {
            // Install event handler using global function
            InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, nil, nil)
        }

    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
    
    @objc func commitPush() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
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
                let status = task.terminationStatus
                
                DispatchQueue.main.async {
                    self?.showOverlay(output: output, status: status)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showOverlay(output: "Error: \(error)", status: 1)
                }
            }
        }
    }
    
    func showOverlay(output: String, status: Int32) {
        // Clean up existing
        fadeTimer?.invalidate()
        fadeTimer = nil
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        
        let padding: CGFloat = 16
        let maxWidth: CGFloat = 450
        
        // Determine if success or failure
        let isSuccess = status == 0
        let symbol = isSuccess ? "✓" : "⚠"
        let symbolColor = isSuccess ? NSColor.systemGreen : NSColor.systemYellow
        
        let displayMessage = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: maxWidth, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.hasShadow = true
        
        // Container with rounded corners
        let container = NSView(frame: NSRect(x: 0, y: 0, width: maxWidth, height: 100))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        container.layer?.cornerRadius = 12
        window.contentView = container
        
        // Symbol label
        let symbolLabel = NSTextField(labelWithString: symbol)
        symbolLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        symbolLabel.textColor = symbolColor
        symbolLabel.frame = NSRect(x: padding, y: 0, width: 30, height: 100)
        container.addSubview(symbolLabel)
        
        // Message label
        let messageLabel = NSTextField(labelWithString: displayMessage)
        messageLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        messageLabel.textColor = .labelColor
        messageLabel.alignment = .left
        messageLabel.maximumNumberOfLines = 6
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.preferredMaxLayoutWidth = maxWidth - padding * 2 - 40
        messageLabel.frame = NSRect(x: padding + 34, y: padding, width: maxWidth - padding * 2 - 40, height: 0)
        messageLabel.sizeToFit()
        container.addSubview(messageLabel)
        
        // Resize window to fit content
        let windowHeight = messageLabel.frame.height + padding * 2
        let windowWidth = messageLabel.frame.width + padding * 2 + 40
        
        guard let screen = NSScreen.main else { return }
        let windowX = (screen.frame.width - windowWidth) / 2
        let windowY = screen.frame.height - windowHeight - 60
        
        window.setFrame(NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight), display: false)
        container.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        symbolLabel.frame = NSRect(x: padding, y: (windowHeight - 24) / 2, width: 30, height: 24)
        messageLabel.frame = NSRect(x: padding + 34, y: (windowHeight - messageLabel.frame.height) / 2, width: messageLabel.frame.width, height: messageLabel.frame.height)
        
        overlayWindow = window
        
        // Show with fade in
        window.alphaValue = 0
        window.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        }
        
        // Schedule fade out
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self, let window = self.overlayWindow else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                window.animator().alphaValue = 0
            }, completionHandler: {
                self.overlayWindow?.orderOut(nil)
                self.overlayWindow = nil
            })
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()