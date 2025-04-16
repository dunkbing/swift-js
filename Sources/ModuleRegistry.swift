import JavaScriptCore
import Foundation

/// Registry for managing JavaScript modules
class ModuleRegistry {
    private let context: JSContext
    private let moduleCache: JSValue

    init(context: JSContext) {
        self.context = context
        self.moduleCache = JSValue(object: [:], in: context)
        context.setObject(self.moduleCache, forKeyedSubscript: "moduleCache" as NSString)
    }

    /// Register a module with the given name
    /// - Parameters:
    ///   - module: The module instance to register
    ///   - name: The name to use when requiring the module
    func registerModule(_ module: JSModule, name: String) {
        moduleCache.setObject(module.module(), forKeyedSubscript: name as NSString)
    }

    /// Register a built-in module with the given name
    /// - Parameters:
    ///   - moduleObject: The JavaScript object to use as the module
    ///   - name: The name to use when requiring the module
    func registerBuiltinModule(_ moduleObject: JSValue, name: String) {
        moduleCache.setObject(moduleObject, forKeyedSubscript: name as NSString)
    }

    /// Set up the require function in the JavaScript context
    /// - Parameter runtime: The runtime that owns this registry
    func setupRequire(runtime: Runtime) {
        // require implementation
        let require: @convention(block) (String) -> JSValue? = { [weak runtime, weak self] moduleName in
            guard let runtime = runtime, let self = self else { return nil }

            if let cachedModule = self.moduleCache.objectForKeyedSubscript(moduleName),
               !cachedModule.isUndefined {
                return cachedModule
            }

            print("Loading module: \(moduleName)")

            let possiblePaths = [
                "\(moduleName).js",
                "\(moduleName)/index.js"
            ]

            for path in possiblePaths {
                if FileManager.default.fileExists(atPath: path) {
                    do {
                        let moduleScript = try String(contentsOfFile: path, encoding: .utf8)
                        let oldScriptPath = runtime.getCurrentScriptPath()
                        let oldScriptSource = runtime.getCurrentScriptSource()

                        // current script details for error handling
                        runtime.setCurrentScript(path: path, source: moduleScript)

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

                            // restore previous script details
                            runtime.setCurrentScript(path: oldScriptPath, source: oldScriptSource)

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
}
