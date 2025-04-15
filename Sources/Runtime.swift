import Foundation
import JavaScriptCore

class Runtime {
    let context: JSContext
    let moduleCache: JSValue
    private var console: Console?
    private var currentScriptSource: String?
    private var currentScriptPath: String?

    init() {
        guard let context = JSContext() else {
            fatalError("Failed to create JavaScript context")
        }

        self.context = context

        // init module system
        self.moduleCache = JSValue(object: [:], in: context)
        context.setObject(self.moduleCache, forKeyedSubscript: "moduleCache" as NSString)

        self.context.exceptionHandler = { [weak self] context, exception in
            guard let self = self, let exception = exception else { return }

            let errorMessage = exception.toString() ?? "Unknown error"
            let errorType = exception.objectForKeyedSubscript("name")?.toString() ?? "Error"
            let lineNumber = exception.objectForKeyedSubscript("line")?.toInt32() ?? 0
            let column = exception.objectForKeyedSubscript("column")?.toInt32() ?? 0
            let stack = exception.objectForKeyedSubscript("stack")?.toString() ?? ""

            // format error to show code context
            if let scriptSource = self.currentScriptSource, lineNumber > 0 {
                let lines = scriptSource.components(separatedBy: .newlines)

                let startLine = max(0, Int(lineNumber) - 2)
                let endLine = min(lines.count - 1, Int(lineNumber) + 1)

                print("\nCaught explicitly:", terminator: " ")

                for i in startLine...endLine {
                    let lineNum = i + 1  // Lines are 1-indexed in error messages
                    let formattedLineNum = String(format: "%d", lineNum)

                    if lineNum == lineNumber {
                        print("\(formattedLineNum) | \(lines[i])")

                        let pointerIndent = " ".repeated(formattedLineNum.count + 3 + Int(column) - 1)
                        print("\(pointerIndent)^")

                        print("\(errorType): \(errorMessage)")

                        if let path = self.currentScriptPath {
                            print("      at \(path):\(lineNumber):\(column)")
                        }
                    } else {
                        print("\(formattedLineNum) | \(lines[i])")
                    }
                }

                // Print additional stack trace lines if available
                if !stack.isEmpty {
                    let stackLines = stack.components(separatedBy: .newlines)
                    for stackLine in stackLines.dropFirst() {
                        let trimmedLine = stackLine.trimmingCharacters(in: .whitespaces)
                        if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("global code") {
                            print("      \(trimmedLine)")
                        }
                    }
                }
            } else {
                print("JS Error: \(errorType): \(errorMessage)")
                if !stack.isEmpty {
                    print("Stack trace:\n\(stack)")
                }
            }
        }

        self.console = Console(context: context, runtime: self)
        setupTimers()
        setupRequire()
    }

    // Provide access to the current script source
    func getCurrentScriptSource() -> String? {
        return currentScriptSource
    }

    // Provide access to the current script path
    func getCurrentScriptPath() -> String? {
        return currentScriptPath
    }

    private func setupTimers() {
        // setTimeout
        let setTimeout: @convention(block) (JSValue, Double) -> Int = { callback, delay in
            let id = Int.random(in: 1...10000)

            DispatchQueue.main.asyncAfter(deadline: .now() + delay/1000) {
                callback.call(withArguments: [])
            }

            return id
        }

        context.setObject(setTimeout, forKeyedSubscript: "setTimeout" as NSString)

        let clearTimeout: @convention(block) (Int) -> Void = { _ in }
        context.setObject(clearTimeout, forKeyedSubscript: "clearTimeout" as NSString)
    }

    private func setupRequire() {
        // require implementation
        let require: @convention(block) (String) -> JSValue? = { [weak self] moduleName in
            guard let self = self else { return nil }

            if let cachedModule = self.moduleCache.objectForKeyedSubscript(moduleName),
               !cachedModule.isUndefined {
                return cachedModule
            }

            print("Loading module: \(moduleName)")

            if let builtinModule = self.moduleCache.objectForKeyedSubscript(moduleName),
               !builtinModule.isUndefined {
                return builtinModule
            }

            let possiblePaths = [
                "\(moduleName).js",
                "\(moduleName)/index.js"
            ]

            for path in possiblePaths {
                if FileManager.default.fileExists(atPath: path) {
                    do {
                        let moduleScript = try String(contentsOfFile: path, encoding: .utf8)
                        let oldScriptPath = self.currentScriptPath
                        let oldScriptSource = self.currentScriptSource

                        // current script details for error handling
                        self.currentScriptPath = path
                        self.currentScriptSource = moduleScript

                        let exports = JSValue(object: [:], in: self.context)
                        let module = JSValue(object: [:], in: self.context)
                        module?.setObject(exports, forKeyedSubscript: "exports" as NSString)

                        let wrapper = """
                        (function(exports, require, module, __filename, __dirname) {
                            \(moduleScript)
                        })
                        """

                        if let wrapperFn = self.context.evaluateScript(wrapper) {
                            let fileURL = URL(fileURLWithPath: path)
                            let filename = fileURL.path
                            let dirname = fileURL.deletingLastPathComponent().path

                            wrapperFn.call(withArguments: [
                                exports!,
                                self.context.objectForKeyedSubscript("require")!,
                                module!,
                                filename,
                                dirname
                            ])

                            let moduleExports = module?.objectForKeyedSubscript("exports")

                            self.moduleCache.setObject(moduleExports, forKeyedSubscript: moduleName as NSString)

                            // Restore previous script details
                            self.currentScriptPath = oldScriptPath
                            self.currentScriptSource = oldScriptSource

                            return moduleExports
                        }
                    } catch {
                        print("Error loading module \(moduleName): \(error)")
                    }
                }
            }

            print("Module not found: \(moduleName)")
            return JSValue(undefinedIn: self.context)
        }

        context.setObject(require, forKeyedSubscript: "require" as NSString)
    }

    // execute js code
    func execute(_ script: String, filename: String? = nil) -> JSValue? {
        self.currentScriptSource = script
        self.currentScriptPath = filename

        let result = context.evaluateScript(script)

        self.currentScriptSource = nil
        self.currentScriptPath = nil

        return result
    }

    // register a native Swift function that takes no arguments
    func registerFunction(name: String, function: @escaping () -> Any?) {
        context.setObject(function, forKeyedSubscript: name as NSString)
    }

    // register a native Swift function that takes arguments and returns a value
    func registerFunctionWithArgs(name: String, function: @escaping ([Any]) -> Any?) {
        let wrappedFunction: @convention(block) (JSValue) -> Any? = { args in
            if let argsArray = args.toArray() {
                return function(argsArray)
            }
            return function([])
        }
        context.setObject(wrappedFunction, forKeyedSubscript: name as NSString)
    }
}
