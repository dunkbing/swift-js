import JavaScriptCore
import NIO
import Foundation

class FS: ErrorAwareJSModule {
    let context: JSContext
    let moduleValue: JSValue
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

    func setupModule() {
        let readFileSync: @convention(block) (String, JSValue?) -> Any? = { [self] path, encodingValue in
            let encoding = encodingValue?.toString()
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                if encoding == "utf8" || encoding == nil {
                    return String(data: data, encoding: .utf8)
                } else {
                    return data
                }
            } catch {
                let errorObj = self.createError(message: "Error reading file: \(error.localizedDescription)")
                return context.evaluateScript("throw \(errorObj)")
            }
        }
        moduleValue.setObject(readFileSync, forKeyedSubscript: "readFileSync" as NSString)

        let readFile: @convention(block) (String, JSValue?, JSValue?) -> Void = { [self] path, options, callback in
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
                    let jsError = self.createError(message: "Error reading file: \(error.localizedDescription)")
                    actualCallback.call(withArguments: [jsError, self.jsNull()])
                }

                self.context.objectForKeyedSubscript("__decrementPendingOps")?.call(withArguments: [])
            }.whenFailure { error in
                print("Error executing task: \(error)")
            }
        }
        moduleValue.setObject(readFile, forKeyedSubscript: "readFile" as NSString)

        let writeFileSync: @convention(block) (String, Any, JSValue?) -> Bool = { [self] path, data, options in
            do {
                if let stringData = data as? String {
                    try stringData.write(toFile: path, atomically: true, encoding: .utf8)
                } else if let binaryData = data as? Data {
                    try binaryData.write(to: URL(fileURLWithPath: path))
                }
                return true
            } catch {
                let errorObj = self.createError(message: "Error writing file: \(error.localizedDescription)")
                _ = context.evaluateScript("throw \(errorObj)")
                return false
            }
        }
        moduleValue.setObject(writeFileSync, forKeyedSubscript: "writeFileSync" as NSString)

        let writeFile: @convention(block) (String, Any, JSValue?, JSValue?) -> Void = { [self] path, data, options, callback in
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
                    let jsError = self.createError(message: "Error writing file: \(error.localizedDescription)")
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

        let exists: @convention(block) (String, JSValue?) -> Void = { [self] path, callback in
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
        let mkdirSync: @convention(block) (String, JSValue?) -> Bool = { [self] path, options in
            var recursive = true

            if let optionsObj = options, optionsObj.isObject {
                if let recursiveOption = optionsObj.objectForKeyedSubscript("recursive")?.toBool() {
                    recursive = recursiveOption
                }
            }

            do {
                let url = URL(fileURLWithPath: path)

                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: recursive,
                    attributes: nil
                )

                print("Successfully created directory at \(path)")
                return true
            } catch let error as NSError {
                let errorMessage: String

                switch error.code {
                case NSFileWriteNoPermissionError:
                    errorMessage = "Permission denied: No permission to create directory at \(path)"
                case NSFileWriteInvalidFileNameError:
                    errorMessage = "Invalid filename: The path contains invalid characters"
                case NSFileNoSuchFileError where !recursive:
                    errorMessage = "Parent directory does not exist and recursive option is false"
                default:
                    errorMessage = "Error creating directory: \(error.localizedDescription)"
                }

                print("mkdirSync error: \(errorMessage)")
                let errorObj = self.createError(message: errorMessage, name: "Error")
                _ = self.context.evaluateScript("throw \(errorObj)")
                return false
            }
        }
        moduleValue.setObject(mkdirSync, forKeyedSubscript: "mkdirSync" as NSString)

        let mkdir: @convention(block) (String, JSValue?, JSValue?) -> Void = { [self] path, options, callback in
            var actualCallback = callback
            var recursive = true // Default to true for compatibility

            if let optionsObj = options, optionsObj.isObject {
                if let recursiveOption = optionsObj.objectForKeyedSubscript("recursive")?.toBool() {
                    recursive = recursiveOption
                }
            } else if options != nil && !options!.isObject {
                actualCallback = options
            }

            self.context.objectForKeyedSubscript("__incrementPendingOps")?.call(withArguments: [])

            let _ = self.eventLoop.execute {
                do {
                    let url = URL(fileURLWithPath: path)

                    try FileManager.default.createDirectory(
                        at: url,
                        withIntermediateDirectories: recursive,
                        attributes: nil
                    )

                    print("Successfully created directory at \(path)")
                    actualCallback?.call(withArguments: [self.jsNull()])
                } catch let error as NSError {
                    let errorMessage: String

                    switch error.code {
                    case NSFileWriteNoPermissionError:
                        errorMessage = "Permission denied: No permission to create directory at \(path)"
                    case NSFileWriteInvalidFileNameError:
                        errorMessage = "Invalid filename: The path contains invalid characters"
                    case NSFileNoSuchFileError where !recursive:
                        errorMessage = "Parent directory does not exist and recursive option is false"
                    default:
                        errorMessage = "Error creating directory: \(error.localizedDescription)"
                    }

                    print("mkdir error: \(errorMessage)")
                    let jsError = self.createError(message: errorMessage)
                    actualCallback?.call(withArguments: [jsError])
                }

                self.context.objectForKeyedSubscript("__decrementPendingOps")?.call(withArguments: [])
            }.whenFailure { error in
                print("Error executing task: \(error)")
            }
        }
        moduleValue.setObject(mkdir, forKeyedSubscript: "mkdir" as NSString)

        let readdirSync: @convention(block) (String) -> Any? = { [self] path in
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: path)
                return contents
            } catch {
                let errorObj = self.createError(message: "Error reading directory: \(error.localizedDescription)")
                return self.context.evaluateScript("throw \(errorObj)")
            }
        }
        moduleValue.setObject(readdirSync, forKeyedSubscript: "readdirSync" as NSString)

        let readdir: @convention(block) (String, JSValue?) -> Void = { [self] path, callback in
            self.context.objectForKeyedSubscript("__incrementPendingOps")?.call(withArguments: [])

            let _ = self.eventLoop.execute {
                do {
                    let contents = try FileManager.default.contentsOfDirectory(atPath: path)
                    callback?.call(withArguments: [self.jsNull(), contents])
                } catch {
                    let jsError = self.createError(message: "Error reading directory: \(error.localizedDescription)")
                    callback?.call(withArguments: [jsError, self.jsNull()])
                }

                self.context.objectForKeyedSubscript("__decrementPendingOps")?.call(withArguments: [])
            }.whenFailure { error in
                print("Error executing task: \(error)")
            }
        }
        moduleValue.setObject(readdir, forKeyedSubscript: "readdir" as NSString)

        let rmdirSync: @convention(block) (String, JSValue?) -> Bool = { [self] path, options in
            do {
                let recursive = options?.objectForKeyedSubscript("recursive")?.toBool() ?? false

                if recursive {
                    try FileManager.default.removeItem(atPath: path)
                } else {
                    let contents = try FileManager.default.contentsOfDirectory(atPath: path)
                    if !contents.isEmpty {
                        let errorMsg = "Directory not empty: \(path)"
                        let errorObj = self.createError(message: errorMsg, name: "Error")
                        _ = self.context.evaluateScript("throw \(errorObj)")
                        return false
                    }
                    try FileManager.default.removeItem(atPath: path)
                }
                return true
            } catch {
                let errorObj = self.createError(message: "Error removing directory: \(error.localizedDescription)")
                _ = self.context.evaluateScript("throw \(errorObj)")
                return false
            }
        }
        moduleValue.setObject(rmdirSync, forKeyedSubscript: "rmdirSync" as NSString)

        setupStatMethods()
    }

    private func setupStatMethods() {
        let statSync: @convention(block) (String) -> JSValue? = { [self] path in
            do {
                let fileManager = FileManager.default
                let attributes = try fileManager.attributesOfItem(atPath: path)

                let stat = JSValue(object: [:], in: self.context)!

                // Set common attributes from FileManager's attribute dictionary
                if let size = attributes[.size] as? NSNumber {
                    stat.setObject(size.int64Value, forKeyedSubscript: "size" as NSString)
                }

                if let modificationDate = attributes[.modificationDate] as? Date {
                    stat.setObject(Int64(modificationDate.timeIntervalSince1970 * 1000), forKeyedSubscript: "mtime" as NSString)
                }

                if let creationDate = attributes[.creationDate] as? Date {
                    stat.setObject(Int64(creationDate.timeIntervalSince1970 * 1000), forKeyedSubscript: "birthtime" as NSString)
                }

                // Set up file type checking methods
                let fileType = attributes[.type] as? String
                let isDirectory = fileType == FileAttributeType.typeDirectory.rawValue
                let isFile = fileType == FileAttributeType.typeRegular.rawValue

                // Method-based interface like Node.js
                let isDirectoryFn: @convention(block) () -> Bool = {
                    return isDirectory
                }
                stat.setObject(isDirectoryFn, forKeyedSubscript: "isDirectory" as NSString)

                let isFileFn: @convention(block) () -> Bool = {
                    return isFile
                }
                stat.setObject(isFileFn, forKeyedSubscript: "isFile" as NSString)

                return stat
            } catch {
                let errorObj = self.createError(message: "Error getting file stats: \(error.localizedDescription)")
                _ = self.context.evaluateScript("throw \(errorObj)")
                return nil
            }
        }
        moduleValue.setObject(statSync, forKeyedSubscript: "statSync" as NSString)

        let stat: @convention(block) (String, JSValue?) -> Void = { [self] path, callback in
            self.context.objectForKeyedSubscript("__incrementPendingOps")?.call(withArguments: [])

            let _ = self.eventLoop.execute {
                do {
                    let fileManager = FileManager.default
                    let attributes = try fileManager.attributesOfItem(atPath: path)

                    let stat = JSValue(object: [:], in: self.context)!

                    // Set common attributes from FileManager's attribute dictionary
                    if let size = attributes[.size] as? NSNumber {
                        stat.setObject(size.int64Value, forKeyedSubscript: "size" as NSString)
                    }

                    if let modificationDate = attributes[.modificationDate] as? Date {
                        stat.setObject(Int64(modificationDate.timeIntervalSince1970 * 1000), forKeyedSubscript: "mtime" as NSString)
                    }

                    if let creationDate = attributes[.creationDate] as? Date {
                        stat.setObject(Int64(creationDate.timeIntervalSince1970 * 1000), forKeyedSubscript: "birthtime" as NSString)
                    }

                    // Set up file type checking methods
                    let fileType = attributes[.type] as? String
                    let isDirectory = fileType == FileAttributeType.typeDirectory.rawValue
                    let isFile = fileType == FileAttributeType.typeRegular.rawValue

                    // Method-based interface like Node.js
                    let isDirectoryFn: @convention(block) () -> Bool = {
                        return isDirectory
                    }
                    stat.setObject(isDirectoryFn, forKeyedSubscript: "isDirectory" as NSString)

                    let isFileFn: @convention(block) () -> Bool = {
                        return isFile
                    }
                    stat.setObject(isFileFn, forKeyedSubscript: "isFile" as NSString)

                    callback?.call(withArguments: [self.jsNull(), stat])
                } catch {
                    let jsError = self.createError(message: "Error getting file stats: \(error.localizedDescription)")
                    callback?.call(withArguments: [jsError, self.jsNull()])
                }

                self.context.objectForKeyedSubscript("__decrementPendingOps")?.call(withArguments: [])
            }.whenFailure { error in
                print("Error executing task: \(error)")
            }
        }
        moduleValue.setObject(stat, forKeyedSubscript: "stat" as NSString)
    }

    func module() -> JSValue {
        return moduleValue
    }
}
