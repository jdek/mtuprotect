// SPDX-License-Identifier: WTFPL

import Foundation
import SystemConfiguration

let vpn = "utun4"
let mtu: UInt32 = 1280
let socketPath = "/tmp/mtuprotect.sock"
let appBundleId = "il.luminati.mtuwatch"
var socketSource: DispatchSourceRead?

setlinebuf(stdout)

func getConsoleUser() -> (uid: uid_t, username: String)? {
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard let username = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String? else {
        return nil
    }
    return (uid, username)
}

func launchAppForUser() {
    guard let user = getConsoleUser() else {
        print("No console user found")
        return
    }

    print("Launching app for user \(user.username) (uid: \(user.uid))")

    // Use launchctl to open the app as the logged-in user
    let process = Process()
    process.launchPath = "/bin/launchctl"
    process.arguments = ["asuser", String(user.uid), "/usr/bin/open", "-b", appBundleId]

    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            print("Successfully launched app")
        }
    } catch {
        print("Failed to launch app: \(error)")
    }
}

guard let store = SCDynamicStoreCreate(nil, "MTUMonitor" as CFString, { _, changed, _ in
    guard let keys = changed as? [String], keys.contains(where: { $0.contains("gpd.pan") }) else { return }
    let current = getMTU(vpn)
    if current != mtu {
        print("Setting \(vpn) MTU to \(mtu) (was \(current)).")
        setMTU(vpn, mtu)
        // Launch the app when VPN connects (if not already running)
        launchAppForUser()
    }
}, nil) else { exit(1) }

SCDynamicStoreSetNotificationKeys(store, nil, ["State:/Network/Service/gpd.pan/IPv4"] as CFArray)
guard let rls = SCDynamicStoreCreateRunLoopSource(nil, store, 0) else { exit(1) }
CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, .defaultMode)

func getMTU(_ interface: String) -> UInt32 {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return 0 }
    defer { freeifaddrs(ifaddr) }

    for ptr in sequence(first: ifaddr, next: { $0?.pointee.ifa_next }) {
        let ifa = ptr!.pointee
        if String(cString: ifa.ifa_name) == interface,
           ifa.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
           let ifadata = ifa.ifa_data {
            return ifadata.assumingMemoryBound(to: if_data.self).pointee.ifi_mtu
        }
    }
    return 0
}

@Sendable func setMTU(_ interface: String, _ mtu: UInt32) {
    let process = Process()
    process.launchPath = "/sbin/ifconfig"
    process.arguments = [interface, "mtu", String(mtu)]
    process.launch()
    process.waitUntilExit()
}

@Sendable func getAllInterfaces() -> [(String, UInt32)] {
    var interfaces: [(String, UInt32)] = []
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return interfaces }
    defer { freeifaddrs(ifaddr) }

    var seen = Set<String>()
    for ptr in sequence(first: ifaddr, next: { $0?.pointee.ifa_next }) {
        guard let ptr = ptr else { continue }
        let ifa = ptr.pointee
        let name = String(cString: ifa.ifa_name)
        if !seen.contains(name), ifa.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
           let ifadata = ifa.ifa_data {
            let mtu = ifadata.assumingMemoryBound(to: if_data.self).pointee.ifi_mtu
            interfaces.append((name, mtu))
            seen.insert(name)
        }
    }
    return interfaces.sorted { $0.0 < $1.0 }
}

func setupUnixSocket() {
    // Remove existing socket file if present
    try? FileManager.default.removeItem(atPath: socketPath)

    let sockfd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard sockfd >= 0 else {
        print("Failed to create socket")
        return
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
    _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
        socketPath.withCString { cString in
            strncpy(ptr, cString, sunPathSize)
        }
    }

    let addrSize = MemoryLayout<sockaddr_un>.size
    let bindResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            bind(sockfd, sockaddrPtr, socklen_t(addrSize))
        }
    }

    guard bindResult >= 0 else {
        print("Failed to bind socket")
        close(sockfd)
        return
    }

    guard listen(sockfd, 5) >= 0 else {
        print("Failed to listen on socket")
        close(sockfd)
        return
    }

    // Set socket permissions so any user can connect
    chmod(socketPath, 0o666)

    // Set socket to non-blocking
    _ = fcntl(sockfd, F_SETFL, O_NONBLOCK)

    // Add socket to run loop
    let source = DispatchSource.makeReadSource(fileDescriptor: sockfd, queue: .main)
    source.setEventHandler {
        var clientAddr = sockaddr_un()
        var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        let clientfd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                accept(sockfd, sockaddrPtr, &clientAddrLen)
            }
        }

        guard clientfd >= 0 else { return }

        DispatchQueue.global().async {
            handleClient(clientfd)
        }
    }
    source.resume()
    socketSource = source  // Keep alive

    print("Unix socket server listening at \(socketPath)")
}

func handleClient(_ clientfd: Int32) {
    defer { close(clientfd) }

    var buffer = [UInt8](repeating: 0, count: 1024)
    let bytesRead = read(clientfd, &buffer, buffer.count)

    guard bytesRead > 0 else { return }

    let message = String(bytes: buffer[0..<bytesRead], encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    var response = ""

    if message == "STATUS" {
        response = "OK\n"
    } else if message == "LIST" {
        let interfaces = getAllInterfaces()
        response = interfaces.map { "\($0.0):\($0.1)" }.joined(separator: "\n") + "\n"
    } else if message.hasPrefix("SET:") {
        let parts = message.dropFirst(4).split(separator: ":")
        if parts.count == 2, let interface = parts.first, let mtuValue = UInt32(parts.last!) {
            setMTU(String(interface), mtuValue)
            response = "OK\n"
        } else {
            response = "ERROR:Invalid SET command\n"
        }
    } else if message == "LAUNCH" {
        launchAppForUser()
        response = "OK\n"
    } else {
        response = "ERROR:Unknown command\n"
    }

    _ = response.withCString { cString in
        write(clientfd, cString, strlen(cString))
    }
}

print("Monitoring GlobalProtect on \(vpn), will set MTU to \(mtu).")
setupUnixSocket()
CFRunLoopRun()
