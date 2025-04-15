import Foundation

let VERSION = "0.0.1"

struct SwiftJSVersion {
    static let version = VERSION

    static var components: (major: Int, minor: Int, patch: Int) {
        let parts = VERSION.split(separator: ".")
                          .compactMap { Int($0) }

        return (
            major: parts.count > 0 ? parts[0] : 0,
            minor: parts.count > 1 ? parts[1] : 0,
            patch: parts.count > 2 ? parts[2] : 0
        )
    }
}
