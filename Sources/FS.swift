import Foundation
import JavaScriptCore

class FS {
    private let context: JSContext
    private let moduleValue: JSValue

    init(context: JSContext) {
        self.context = context
        self.moduleValue = JSValue(object: [:], in: context)

        setupModule()
    }

    private func setupModule() {
        let readFileSync: @convention(block) (String, JSValue?) -> Any? = { path, encodingValue in
            let encoding = encodingValue?.toString()
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                if encoding == "utf8" || encoding == nil {
                    return String(data: data, encoding: .utf8)
                } else {
                    return data
                }
            } catch {
                print("Error reading file: \(error)")
                return nil
            }
        }
        moduleValue.setObject(readFileSync, forKeyedSubscript: "readFileSync" as NSString)

        let writeFileSync: @convention(block) (String, Any, JSValue?) -> Bool = { path, data, options in
            do {
                if let stringData = data as? String {
                    try stringData.write(toFile: path, atomically: true, encoding: .utf8)
                } else if let binaryData = data as? Data {
                    try binaryData.write(to: URL(fileURLWithPath: path))
                }
                return true
            } catch {
                print("Error writing file: \(error)")
                return false
            }
        }
        moduleValue.setObject(writeFileSync, forKeyedSubscript: "writeFileSync" as NSString)
    }

    func module() -> JSValue {
        return moduleValue
    }
}
