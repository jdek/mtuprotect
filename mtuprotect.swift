// SPDX-License-Identifier: WTFPL

import Foundation
import SystemConfiguration

let vpn = "utun4"
let mtu: UInt32 = 1280

setlinebuf(stdout)

guard let store = SCDynamicStoreCreate(nil, "MTUMonitor" as CFString, { _, changed, _ in
    guard let keys = changed as? [String], keys.contains(where: { $0.contains("gpd.pan") }) else { return }
    let current = getMTU(vpn)
    if current != mtu {
        print("Setting \(vpn) MTU to \(mtu) (was \(current)).")
        setMTU(vpn, mtu)
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

func setMTU(_ interface: String, _ mtu: UInt32) {
    let process = Process()
    process.launchPath = "/sbin/ifconfig"
    process.arguments = [interface, "mtu", String(mtu)]
    process.launch()
    process.waitUntilExit()
}

print("Monitoring GlobalProtect on \(vpn), will set MTU to \(mtu).")
CFRunLoopRun()
