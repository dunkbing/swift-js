import JavaScriptCore
import NIO
import Foundation

class FS {
    private let context: JSContext
    private let moduleValue: JSValue
    private let eventLoop: EventLoop
    private let threadPool: NIOThreadPool

    init(context: JSContext, eventLoop: EventLoop) {
        self.context = context
        self.moduleValue = JSValue(object: [:], in: context)
        self.eventLoop = eventLoop

        // thread pool for file operations
        self.threadPool = NIOThreadPool(numberOfThreads: 4)
        self.threadPool.start()

        setupModule()
    }

    deinit {
        try? threadPool.syncShutdownGracefully()
    }

    private func setupModule() {
        let readFileSync: @convention(block) (String, JSValue?) -> Any? = { [weak self] path, encodingValue in
            guard let self = self else { return nil }

            let encoding = encodingValue?.toString()
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                if encoding == "utf8" || encoding == nil {
                    return String(data: data, encoding: .utf8)
                } else {
                    return data
                }
            } catch {
                let errorObj = self.createError("Error reading file: \(error.localizedDescription)")
                return context.evaluateScript("throw \(errorObj)")
            }
        }
        moduleValue.setObject(readFileSync, forKeyedSubscript: "readFileSync" as NSString)

        let readFile: @convention(block) (String, JSValue?, JSValue?) -> Void = { [weak self] path, options, callback in
            guard let self = self else { return }

            var encoding: String? = nil
            if let optionsObj = options {
                if optionsObj.isString {
                    encoding = optionsObj.toString()
                } else if !optionsObj.isUndefined && !optionsObj.isNull {
                    encoding = optionsObj.objectForKeyedSubscript("encoding")?.toString()
                }
            }

            var actualCallback = callback
            if actualCallback == nil && options != nil && !options!.isObject && !options!.isString {
                actualCallback = options
            }

            guard let actualCallback = actualCallback else {
                print("Warning: No callback provided for readFile")
                return
            }

            self.context.objectForKeyedSubscript("__incrementPendingOps")?.call(withArguments: [])

            let _ = self.eventLoop.execute {
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: path))

                    if encoding == "utf8" || encoding == nil, let content = String(data: data, encoding: .utf8) {
                        actualCallback.call(withArguments: [self.jsNull(), content])
                    } else {
                        let base64 = data.base64EncodedString()
                        actualCallback.call(withArguments: [self.jsNull(), base64])
                    }
                } catch {
                    let jsError = self.createError("Error reading file: \(error.localizedDescription)")
                    actualCallback.call(withArguments: [jsError, self.jsNull()])
                }

                self.context.objectForKeyedSubscript("__decrementPendingOps")?.call(withArguments: [])
            }.whenFailure { error in
                print("Error executing task: \(error)")
            }
        }
        moduleValue.setObject(readFile, forKeyedSubscript: "readFile" as NSString)

        let writeFileSync: @convention(block) (String, Any, JSValue?) -> Bool = { [weak self] path, data, options in
            guard let self = self else { return false }

            do {
                if let stringData = data as? String {
                    try stringData.write(toFile: path, atomically: true, encoding: .utf8)
                } else if let binaryData = data as? Data {
                    try binaryData.write(to: URL(fileURLWithPath: path))
                }
                return true
            } catch {
                let errorObj = self.createError("Error writing file: \(error.localizedDescription)")
                _ = context.evaluateScript("throw \(errorObj)")
                return false
            }
        }
        moduleValue.setObject(writeFileSync, forKeyedSubscript: "writeFileSync" as NSString)

        let writeFile: @convention(block) (String, Any, JSValue?, JSValue?) -> Void = { [weak self] path, data, options, callback in
            guard let self = self else { return }

            var actualCallback = callback
            if actualCallback == nil && options != nil && !options!.isObject {
                actualCallback = options
            }

            self.context.objectForKeyedSubscript("__incrementPendingOps")?.call(withArguments: [])

            let _ = self.eventLoop.execute {
                do {
                    if let stringData = data as? String {
                        try stringData.write(toFile: path, atomically: true, encoding: .utf8)
                    } else if let binaryData = data as? Data {
                        try binaryData.write(to: URL(fileURLWithPath: path))
                    } else {
                        throw NSError(domain: "FSError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid data type"])
                    }

                    actualCallback?.call(withArguments: [self.jsNull()])
                } catch {
                    let jsError = self.createError("Error writing file: \(error.localizedDescription)")
                    actualCallback?.call(withArguments: [jsError])
                }

                self.context.objectForKeyedSubscript("__decrementPendingOps")?.call(withArguments: [])
            }.whenFailure { error in
                print("Error executing task: \(error)")
            }
        }
        moduleValue.setObject(writeFile, forKeyedSubscript: "writeFile" as NSString)

        let existsSync: @convention(block) (String) -> Bool = { path in
            return FileManager.default.fileExists(atPath: path)
        }
        moduleValue.setObject(existsSync, forKeyedSubscript: "existsSync" as NSString)

        let exists: @convention(block) (String, JSValue?) -> Void = { [weak self] path, callback in
            guard let self = self else { return }

            self.context.objectForKeyedSubscript("__incrementPendingOps")?.call(withArguments: [])

            let _ = self.eventLoop.execute {
                let exists = FileManager.default.fileExists(atPath: path)
                callback?.call(withArguments: [exists])

                self.context.objectForKeyedSubscript("__decrementPendingOps")?.call(withArguments: [])
            }.whenFailure { error in
                print("Error executing task: \(error)")
            }
        }
        moduleValue.setObject(exists, forKeyedSubscript: "exists" as NSString)

        setupDirectoryMethods()
    }

    private func setupDirectoryMethods() {
        let mkdirSync: @convention(block) (String, JSValue?) -> Bool = { [weak self] path, options in
            guard let self = self else { return false }

            do {
                try FileManager.default.createDirectory(
                    atPath: path,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                return true
            } catch {
                let errorObj = self.createError("Error creating directory: \(error.localizedDescription)")
                _ = self.context.evaluateScript("throw \(errorObj)")
                return false
            }
        }
        moduleValue.setObject(mkdirSync, forKeyedSubscript: "mkdirSync" as NSString)

        let mkdir: @convention(block) (String, JSValue?, JSValue?) -> Void = { [weak self] path, options, callback in
            guard let self = self else { return }

            var actualCallback = callback
            if actualCallback == nil && options != nil && !options!.isObject {
                actualCallback = options
            }

            self.context.objectForKeyedSubscript("__incrementPendingOps")?.call(withArguments: [])

            let _ = self.eventLoop.execute {
                do {
                    try FileManager.default.createDirectory(
                        atPath: path,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    actualCallback?.call(withArguments: [self.jsNull()])
                } catch {
                    let jsError = self.createError("Error creating directory: \(error.localizedDescription)")
                    actualCallback?.call(withArguments: [jsError])
                }

                self.context.objectForKeyedSubscript("__decrementPendingOps")?.call(withArguments: [])
            }.whenFailure { error in
                print("Error executing task: \(error)")
            }
        }
        moduleValue.setObject(mkdir, forKeyedSubscript: "mkdir" as NSString)

        let readdirSync: @convention(block) (String) -> Any? = { [weak self] path in
            guard let self = self else { return nil }

            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: path)
                return contents
            } catch {
                let errorObj = self.createError("Error reading directory: \(error.localizedDescription)")
                return self.context.evaluateScript("throw \(errorObj)")
            }
        }
        moduleValue.setObject(readdirSync, forKeyedSubscript: "readdirSync" as NSString)

        let readdir: @convention(block) (String, JSValue?) -> Void = { [weak self] path, callback in
            guard let self = self else { return }

            self.context.objectForKeyedSubscript("__incrementPendingOps")?.call(withArguments: [])

            let _ = self.eventLoop.execute {
                do {
                    let contents = try FileManager.default.contentsOfDirectory(atPath: path)
                    callback?.call(withArguments: [self.jsNull(), contents])
                } catch {
                    let jsError = self.createError("Error reading directory: \(error.localizedDescription)")
                    callback?.call(withArguments: [jsError, self.jsNull()])
                }

                self.context.objectForKeyedSubscript("__decrementPendingOps")?.call(withArguments: [])
            }.whenFailure { error in
                print("Error executing task: \(error)")
            }
        }
        moduleValue.setObject(readdir, forKeyedSubscript: "readdir" as NSString)
    }

    private func createError(_ message: String) -> JSValue {
        if let errorConstructor = context.evaluateScript("Error") {
            return errorConstructor.construct(withArguments: [message])
        } else {
            let error = JSValue(object: [:], in: context)!
            error.setObject(message, forKeyedSubscript: "message" as NSString)
            error.setObject("Error", forKeyedSubscript: "name" as NSString)
            return error
        }
    }

    private func jsNull() -> JSValue {
        return context.evaluateScript("null")!
    }

    func module() -> JSValue {
        return moduleValue
    }
}
