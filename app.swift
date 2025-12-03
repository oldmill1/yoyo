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
        
        let displayMessage = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Get screen dimensions
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        
        // Toast dimensions and position (top-right corner)
        let toastWidth: CGFloat = 250
        let toastHeight: CGFloat = 60
        let margin: CGFloat = 20
        let toastX = screenFrame.width - toastWidth - margin
        let toastY = screenFrame.height - toastHeight - margin
        
        // Create small window for toast
        let window = NSWindow(
            contentRect: NSRect(x: toastX, y: toastY, width: toastWidth, height: toastHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.ignoresMouseEvents = true
        
        // Retro toast background
        let toastView = NSView(frame: NSRect(x: 0, y: 0, width: toastWidth, height: toastHeight))
        toastView.wantsLayer = true
        toastView.layer?.backgroundColor = NSColor.black.cgColor
        toastView.layer?.cornerRadius = 8
        toastView.layer?.borderWidth = 2
        toastView.layer?.borderColor = NSColor.white.cgColor
        window.contentView = toastView
        
        // Retro text label
        let messageLabel = NSTextField(labelWithString: displayMessage)
        messageLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        messageLabel.textColor = NSColor.green
        messageLabel.alignment = .center
        messageLabel.backgroundColor = .clear
        messageLabel.isBordered = false
        messageLabel.isEditable = false
        messageLabel.isSelectable = false
        messageLabel.cell?.wraps = true
        messageLabel.cell?.isScrollable = false
        messageLabel.maximumNumberOfLines = 3
        messageLabel.lineBreakMode = .byTruncatingTail
        
        // Center text in toast
        messageLabel.frame = NSRect(x: 10, y: 10, width: toastWidth - 20, height: toastHeight - 20)
        
        toastView.addSubview(messageLabel)
        
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