import Foundation
import Darwin

/// The hidden About page describes this process's host. Classic application
/// heap/AppleTalk values have no modern counterpart and are labeled N/A.
enum OriginalHostInformation {
    static var lines: [String] {
        OriginalAboutRules.systemInformation(
            machineType: systemString("hw.model") ?? "Unknown",
            processor: systemString("machdep.cpu.brand_string") ?? architecture,
            systemVersion: operatingSystemVersion)
    }

    private static var architecture: String {
        #if arch(arm64)
        "ARM64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "Unknown"
        #endif
    }

    private static var operatingSystemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private static func systemString(_ name: String) -> String? {
        var count = 0
        guard sysctlbyname(name, nil, &count, nil, 0) == 0, count > 1, count < 4096 else { return nil }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname(name, &bytes, &count, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }
}
