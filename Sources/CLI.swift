import Foundation
import JavaScriptCore

class CLI {
    private let runtime: JSRuntime

    init() {
        self.runtime = JSRuntime()
        setupEnvironment()
    }

    private func setupEnvironment() {
        // node's `process` object
        let process = JSValue(object: [:], in: runtime.context)

        // argv array
        let args = CommandLine.arguments
        let jsArgs = args.map { $0 as Any }
        process?.setObject(jsArgs, forKeyedSubscript: "argv" as NSString)

        // simple versions of other process properties
        process?.setObject(FileManager.default.currentDirectoryPath, forKeyedSubscript: "cwd" as NSString)
        process?.setObject(ProcessInfo.processInfo.environment, forKeyedSubscript: "env" as NSString)

        let processExit: @convention(block) (Int32) -> Void = { code in
            print("Exiting with code: \(code)")
            exit(code)
        }
        process?.setObject(processExit, forKeyedSubscript: "exit" as NSString)

        runtime.context.setObject(process, forKeyedSubscript: "process" as NSString)

        // basic module
        setupFSModule()
        setupPathModule()
    }

    private func setupFSModule() {
        let fs = JSValue(object: [:], in: runtime.context)

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
        fs?.setObject(readFileSync, forKeyedSubscript: "readFileSync" as NSString)

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
        fs?.setObject(writeFileSync, forKeyedSubscript: "writeFileSync" as NSString)

        let existsSync: @convention(block) (String) -> Bool = { path in
            return FileManager.default.fileExists(atPath: path)
        }
        fs?.setObject(existsSync, forKeyedSubscript: "existsSync" as NSString)

        // add to runtime
        runtime.moduleCache.setObject(fs, forKeyedSubscript: "fs" as NSString)
    }

    private func setupPathModule() {
        let path = JSValue(object: [:], in: runtime.context)

        let join: @convention(block) (JSValue) -> String = { argsValue in
            var components: [String] = []
            if let args = argsValue.toArray() {
                for arg in args {
                    if let component = arg as? String {
                        components.append(component)
                    }
                }
            }

            return components.joined(separator: "/")
        }
        path?.setObject(join, forKeyedSubscript: "join" as NSString)

        let basename: @convention(block) (String) -> String = { path in
            return URL(fileURLWithPath: path).lastPathComponent
        }
        path?.setObject(basename, forKeyedSubscript: "basename" as NSString)

        let dirname: @convention(block) (String) -> String = { path in
            return URL(fileURLWithPath: path).deletingLastPathComponent().path
        }
        path?.setObject(dirname, forKeyedSubscript: "dirname" as NSString)

        runtime.moduleCache.setObject(path, forKeyedSubscript: "path" as NSString)
    }

    func executeFile(path: String) {
        do {
            let script = try String(contentsOfFile: path, encoding: .utf8)

            let fileURL = URL(fileURLWithPath: path)
            let filename = fileURL.path
            let dirname = fileURL.deletingLastPathComponent().path

            runtime.context.setObject(filename, forKeyedSubscript: "__filename" as NSString)
            runtime.context.setObject(dirname, forKeyedSubscript: "__dirname" as NSString)
            runtime.execute(script, filename: path)
        } catch {
            print("Error reading JavaScript file: \(error)")
        }
    }

    func executeString(script: String) {
        if let result = runtime.execute(script, filename: "repl") {
            if !result.isUndefined && !result.isNull {
                print("Result: \(result.toString() ?? "undefined")")
            }
        }
    }

    func startREPL() {
        print("SwiftJS REPL v0.1")
        print("Type .exit to exit, .help for more commands")

        var running = true

        while running {
            print("> ", terminator: "")
            if let input = readLine() {
                switch input {
                case ".exit":
                    running = false
                case ".help":
                    print("Available commands:")
                    print("  .exit    Exit the REPL")
                    print("  .help    Show this help")
                default:
                    executeString(script: input)
                }
            }
        }
    }
}
