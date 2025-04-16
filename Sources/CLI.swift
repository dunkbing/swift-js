import JavaScriptCore
import NIO
import Foundation

class CLI {
    private let runtime: Runtime

    init() {
        self.runtime = Runtime()
        setupEnvironment()
    }

    deinit {
        let _ = runtime.waitForPendingOperations(timeout: 5.0)
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

        setupModules()
    }

    private func setupModules() {
        let fsModule = FS(context: runtime.context, eventLoop: runtime.eventLoop)
        runtime.moduleCache.setObject(fsModule.module(), forKeyedSubscript: "fs" as NSString)

        let httpModule = HTTP(context: runtime.context, eventLoop: runtime.eventLoop)
        runtime.moduleCache.setObject(httpModule.module(), forKeyedSubscript: "http" as NSString)

        setupPathModule()
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

            let url = components.reduce(URL(fileURLWithPath: "")) { (result, component) in
                return result.appendingPathComponent(component)
            }
            return url.path
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

        let extname: @convention(block) (String) -> String = { path in
            let ext = URL(fileURLWithPath: path).pathExtension
            return ext.isEmpty ? "" : ".\(ext)"
        }
        path?.setObject(extname, forKeyedSubscript: "extname" as NSString)

        let resolve: @convention(block) (JSValue) -> String = { argsValue in
            var result = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

            if let args = argsValue.toArray() {
                for arg in args {
                    if let component = arg as? String {
                        // absolute paths
                        if component.starts(with: "/") {
                            result = URL(fileURLWithPath: component)
                        } else {
                            result = result.appendingPathComponent(component)
                        }
                    }
                }
            }

            return result.standardized.path
        }
        path?.setObject(resolve, forKeyedSubscript: "resolve" as NSString)
        path?.setObject(String(FileManager.default.pathSeparator), forKeyedSubscript: "sep" as NSString)

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

            let _ = runtime.execute(script, filename: path)

            if !runtime.waitForPendingOperations(timeout: 60.0) {
                print("Warning: Some asynchronous operations did not complete within the timeout period")
            }
        } catch {
            print("Error reading JavaScript file: \(error)")
        }
    }

    func executeString(script: String) {
        if let result = runtime.execute(script, filename: "repl") {
            if !result.isUndefined && !result.isNull {
                print("Result: \(result.toString() ?? "undefined")")
            }

            if !runtime.waitForPendingOperations(timeout: 5.0) {
                print("Warning: Some asynchronous operations are still pending")
            }
        }
    }

    func startREPL() {
        print("SwiftJS REPL v\(SwiftJSVersion.version)")
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
                    print("  .clear   Clear the screen")
                    print("  .load    Load a JavaScript file")
                case ".clear":
                    print("\u{1B}[2J\u{1B}[H", terminator: "")
                case let cmd where cmd.starts(with: ".load "):
                    let filePath = String(cmd.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    if FileManager.default.fileExists(atPath: filePath) {
                        executeFile(path: filePath)
                    } else {
                        print("Error: File not found: \(filePath)")
                    }
                default:
                    executeString(script: input)
                }
            }
        }
    }

    func showVersion() {
        print("SwiftJSRuntime v\(SwiftJSVersion.version)")
    }

    func showHelp() {
        print("SwiftJSRuntime v\(SwiftJSVersion.version) - A JavaScript runtime written in Swift")
        print("")
        print("Usage: SwiftJSRuntime [options] [script.js] [arguments]")
        print("")
        print("Options:")
        print("  --version, -v     Print the version")
        print("  --help, -h        Print this help message")
        print("  repl              Start the REPL environment")
        print("")
        print("Examples:")
        print("  SwiftJSRuntime                        Show this help")
        print("  SwiftJSRuntime repl                   Start REPL mode")
        print("  SwiftJSRuntime script.js              Run a script")
        print("  SwiftJSRuntime script.js arg1 arg2    Run a script with arguments")
    }

    func parseCommandLineArguments() {
        let args = CommandLine.arguments

        if args.count <= 1 {
            showHelp()
            return
        }

        let firstArg = args[1]

        switch firstArg {
        case "--version", "-v":
            showVersion()
        case "--help", "-h":
            showHelp()
        case "repl":
            startREPL()
        default:
            if FileManager.default.fileExists(atPath: firstArg) {
                executeFile(path: firstArg)
            } else {
                print("Error: File '\(firstArg)' not found.")
                exit(1)
            }
        }
    }
}
