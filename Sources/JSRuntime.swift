import Foundation
import JavaScriptCore

class JSRuntime {
    let context: JSContext
    let moduleCache: JSValue
    private var console: JSConsole?

    init() {
        guard let context = JSContext() else {
            fatalError("Failed to create JavaScript context")
        }

        self.context = context

        // init module system
        self.moduleCache = JSValue(object: [:], in: context)
        context.setObject(self.moduleCache, forKeyedSubscript: "moduleCache" as NSString)

        self.context.exceptionHandler = { context, exception in
            if let exception = exception {
                print("JS Error: \(exception.toString() ?? "Unknown error")")

                if let stack = exception.objectForKeyedSubscript("stack")?.toString() {
                    print("Stack trace: \(stack)")
                }
            }
        }

        self.console = JSConsole(context: context)
        setupTimers()
        setupRequire()
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

        // clearTimeout
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
    func execute(_ script: String) -> JSValue? {
        return context.evaluateScript(script)
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
