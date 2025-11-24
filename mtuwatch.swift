// SPDX-License-Identifier: WTFPL

import Cocoa
import Foundation

class ClickableMenuItemView: NSView {
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTrackingArea()
    }

    private func setupTrackingArea() {
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isHovered {
            // Use the proper menu selection color with inset and rounded corners
            let insetRect = bounds.insetBy(dx: 5, dy: 1)
            let path = NSBezierPath(roundedRect: insetRect, xRadius: 7, yRadius: 7)
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.8).setFill()
            path.fill()
        }
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
        menu?.cancelTracking()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?
    var isDaemonRunning = false
    let socketPath = "/tmp/mtuprotect.sock"
    let defaults = UserDefaults.standard
    let vpnInterfaceKey = "vpnInterface"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item with fixed length
        statusItem = NSStatusBar.system.statusItem(withLength: 28)

        // Set initial button state
        if let button = statusItem.button {
            button.title = "?"
            button.imagePosition = .imageLeft
        }

        // Create menu
        setupMenu()

        // Initial update
        updateStatus()

        // Start checking daemon status
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    func setupMenu() {
        menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: "Status: Checking...", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let interfacesItem = NSMenuItem(title: "Interfaces", action: nil, keyEquivalent: "")
        interfacesItem.tag = 200
        menu.addItem(interfacesItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    func updateStatusIcon() {
        if let button = statusItem.button {
            button.title = isDaemonRunning ? "✓" : "✗"
        }
    }

    func updateStatus() {
        isDaemonRunning = checkDaemonStatus()
        updateStatusIcon()

        // Update status menu item
        if let statusMenuItem = menu.item(withTag: 100) {
            statusMenuItem.title = isDaemonRunning ? "Status: Running" : "Status: Not Running"
        }

        // Update interfaces list
        if isDaemonRunning {
            updateInterfacesList()
        } else {
            clearInterfacesList()
        }
    }

    func checkDaemonStatus() -> Bool {
        let sockfd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sockfd >= 0 else { return false }
        defer { close(sockfd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = socketPath.withCString { cString in
                strncpy(ptr, cString, sunPathSize)
            }
        }

        let connected = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(sockfd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size)) >= 0
            }
        }

        guard connected else { return false }

        // Send STATUS command
        let command = "STATUS\n"
        _ = command.withCString { cString in
            write(sockfd, cString, strlen(cString))
        }

        // Read response
        var buffer = [UInt8](repeating: 0, count: 1024)
        let bytesRead = read(sockfd, &buffer, buffer.count)

        if bytesRead > 0 {
            let response = String(bytes: buffer[0..<bytesRead], encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return response == "OK"
        }

        return false
    }

    func sendCommand(_ command: String) -> String? {
        let sockfd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sockfd >= 0 else { return nil }
        defer { close(sockfd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = socketPath.withCString { cString in
                strncpy(ptr, cString, sunPathSize)
            }
        }

        let connected = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(sockfd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size)) >= 0
            }
        }

        guard connected else { return nil }

        // Send command
        let fullCommand = command + "\n"
        _ = fullCommand.withCString { cString in
            write(sockfd, cString, strlen(cString))
        }

        // Read response
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(sockfd, &buffer, buffer.count)

        if bytesRead > 0 {
            return String(bytes: buffer[0..<bytesRead], encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    func updateInterfacesList() {
        guard let response = sendCommand("LIST") else {
            clearInterfacesList()
            return
        }

        // Remove old interface items
        clearInterfacesList()

        let vpnInterface = defaults.string(forKey: vpnInterfaceKey) ?? "utun4"
        let interfaces = response.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: ":")
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        }

        // Find the interfaces item and add submenu items after it
        if let interfacesIndex = menu.items.firstIndex(where: { $0.tag == 200 }) {
            for (index, (name, mtu)) in interfaces.enumerated() {
                let isVPN = name == vpnInterface
                let vpnMarker = isVPN ? " ✓" : ""

                let item = NSMenuItem()
                item.representedObject = name
                item.tag = 300 + index

                // Create custom clickable view for proper right-alignment
                let containerView = ClickableMenuItemView(frame: NSRect(x: 0, y: 0, width: 250, height: 26))
                containerView.onClick = { [weak self] in
                    self?.handleInterfaceClickForName(name)
                }
                containerView.wantsLayer = true

                let leftLabel = NSTextField()
                leftLabel.isEditable = false
                leftLabel.isBordered = false
                leftLabel.drawsBackground = false
                leftLabel.isSelectable = false
                leftLabel.allowsEditingTextAttributes = false
                leftLabel.translatesAutoresizingMaskIntoConstraints = false

                // Create attributed string with colored star
                let leftAttrString = NSMutableAttributedString()
                leftAttrString.append(NSAttributedString(string: name, attributes: [
                    .font: NSFont.menuFont(ofSize: 14)
                ]))
                if !vpnMarker.isEmpty {
                    leftAttrString.append(NSAttributedString(string: vpnMarker, attributes: [
                        .font: NSFont.menuFont(ofSize: 14),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]))
                }
                leftLabel.attributedStringValue = leftAttrString
                containerView.addSubview(leftLabel)

                let rightLabel = NSTextField(labelWithString: "\(mtu) MTU")
                rightLabel.font = NSFont.menuFont(ofSize: 14)
                rightLabel.textColor = .secondaryLabelColor
                rightLabel.isEditable = false
                rightLabel.isBordered = false
                rightLabel.drawsBackground = false
                rightLabel.isSelectable = false
                rightLabel.allowsEditingTextAttributes = false
                rightLabel.translatesAutoresizingMaskIntoConstraints = false
                containerView.addSubview(rightLabel)

                NSLayoutConstraint.activate([
                    leftLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
                    leftLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                    rightLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
                    rightLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
                ])

                item.view = containerView
                menu.insertItem(item, at: interfacesIndex + 1 + index)
            }
        }
    }

    func clearInterfacesList() {
        menu.items.removeAll { $0.tag >= 300 && $0.tag < 400 }
    }

    func handleInterfaceClickForName(_ interface: String) {
        // Check if command key is pressed
        if NSEvent.modifierFlags.contains(.command) {
            setAsVPNInterface(interface)
        } else {
            setInterfaceMTU(interface)
        }
    }

    @objc func handleInterfaceClick(_ sender: NSMenuItem) {
        guard let interface = sender.representedObject as? String else { return }
        handleInterfaceClickForName(interface)
    }

    func setAsVPNInterface(_ interface: String) {
        defaults.set(interface, forKey: vpnInterfaceKey)

        let alert = NSAlert()
        alert.messageText = "VPN Interface Set"
        alert.informativeText = "\(interface) is now set as your GlobalProtect VPN interface."
        alert.addButton(withTitle: "OK")
        alert.runModal()

        // Refresh the list to show the star
        updateInterfacesList()
    }

    func setInterfaceMTU(_ interface: String) {

        let alert = NSAlert()
        alert.messageText = "Set MTU for \(interface)"
        alert.informativeText = "The daemon will set the MTU to 1280."
        alert.addButton(withTitle: "Set to 1280")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let response = sendCommand("SET:\(interface):1280") {
                if response.hasPrefix("OK") {
                    let successAlert = NSAlert()
                    successAlert.messageText = "Success"
                    successAlert.informativeText = "MTU set to 1280 for \(interface)"
                    successAlert.runModal()

                    // Refresh the list
                    updateInterfacesList()
                } else {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Error"
                    errorAlert.informativeText = "Failed to set MTU: \(response)"
                    errorAlert.runModal()
                }
            }
        }
    }

}// Main entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Run as menu bar app only
app.run()
