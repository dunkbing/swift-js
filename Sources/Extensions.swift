import Foundation

extension String {
    func repeated(_ count: Int) -> String {
        return String(repeating: self, count: count)
    }
}

extension FileManager {
    var pathSeparator: Character {
        #if os(Windows)
        return "\\"
        #else
        return "/"
        #endif
    }
}
