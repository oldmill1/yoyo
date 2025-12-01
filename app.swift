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
        
        let displayMessage = output.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // Get screen dimensions for full-screen overlay
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        
        // Create full-screen window
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.hasShadow = false
        window.ignoresMouseEvents = true
        
        // Main container view
        let container = NSView(frame: screenFrame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = container
        
        // Semi-transparent slate background for text area
        let backgroundHeight = screenFrame.height * 0.6
        let backgroundY = screenFrame.height * 0.75 - (backgroundHeight / 2) // Position at 75% of screen height
        let backgroundView = NSView(frame: NSRect(x: 0, y: backgroundY, width: screenFrame.width, height: backgroundHeight))
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        backgroundView.layer?.cornerRadius = 0
        backgroundView.layer?.borderWidth = 0
        container.addSubview(backgroundView)
        
        // Modern sans-serif text label
        let messageLabel = NSTextField(labelWithString: displayMessage)
        messageLabel.font = NSFont.systemFont(ofSize: 60, weight: .light)
        messageLabel.textColor = NSColor.white
        messageLabel.alignment = .center
        messageLabel.backgroundColor = .clear
        messageLabel.isBordered = false
        messageLabel.isEditable = false
        messageLabel.isSelectable = false
        messageLabel.cell?.wraps = true
        messageLabel.cell?.isScrollable = false
        messageLabel.maximumNumberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        
        // Calculate text size with wrapping
        let maxTextWidth = screenFrame.width * 0.8
        let maxTextHeight = screenFrame.height * 0.5
        let textSize = messageLabel.sizeThatFits(NSSize(width: maxTextWidth, height: maxTextHeight))
        
        // Adjust font size if text is too large
        var fontSize: CGFloat = 60
        var adjustedSize = textSize
        while (adjustedSize.width > maxTextWidth || adjustedSize.height > maxTextHeight) && fontSize > 20 {
            fontSize -= 5
            messageLabel.font = NSFont.systemFont(ofSize: fontSize, weight: .light)
            adjustedSize = messageLabel.sizeThatFits(NSSize(width: maxTextWidth, height: maxTextHeight))
        }
        
        // Center the text on screen
        let finalTextSize = messageLabel.sizeThatFits(NSSize(width: maxTextWidth, height: maxTextHeight))
        let textX = (screenFrame.width - finalTextSize.width) / 2
        let textY = screenFrame.height * 0.75 - (finalTextSize.height / 2) // Position at 75% of screen height
        messageLabel.frame = NSRect(x: textX, y: textY, width: finalTextSize.width, height: finalTextSize.height)
        
        // Remove shadow for cleaner modal look
        messageLabel.shadow = nil
        
        container.addSubview(messageLabel)
        
        overlayWindow = window
        
        // Show with fade in
        window.alphaValue = 0
        window.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 1
        }
        
        // Schedule fade out
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self = self, let window = self.overlayWindow else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5
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