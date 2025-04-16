import JavaScriptCore
import Foundation

class Path: ErrorAwareJSModule {
    let context: JSContext
    let moduleValue: JSValue

    init(context: JSContext) {
        self.context = context
        self.moduleValue = JSValue(object: [:], in: context)

        setupModule()
    }

    func setupModule() {
        // join: Joins path segments together
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
        moduleValue.setObject(join, forKeyedSubscript: "join" as NSString)

        // basename: Returns the last portion of a path
        let basename: @convention(block) (String, String?) -> String = { path, ext in
            let lastComponent = URL(fileURLWithPath: path).lastPathComponent

            if let ext = ext, !ext.isEmpty, lastComponent.hasSuffix(ext) {
                let endIndex = lastComponent.index(lastComponent.endIndex, offsetBy: -ext.count)
                return String(lastComponent[..<endIndex])
            }

            return lastComponent
        }
        moduleValue.setObject(basename, forKeyedSubscript: "basename" as NSString)

        // dirname: Returns the directory name of a path
        let dirname: @convention(block) (String) -> String = { path in
            return URL(fileURLWithPath: path).deletingLastPathComponent().path
        }
        moduleValue.setObject(dirname, forKeyedSubscript: "dirname" as NSString)

        // extname: Returns the extension of the path
        let extname: @convention(block) (String) -> String = { path in
            let ext = URL(fileURLWithPath: path).pathExtension
            return ext.isEmpty ? "" : ".\(ext)"
        }
        moduleValue.setObject(extname, forKeyedSubscript: "extname" as NSString)

        // resolve: Resolves a sequence of paths or path segments into an absolute path
        let resolve: @convention(block) (JSValue) -> String = { argsValue in
            var result = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

            if let args = argsValue.toArray() {
                for arg in args {
                    if let component = arg as? String {
                        // Handle absolute paths
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
        moduleValue.setObject(resolve, forKeyedSubscript: "resolve" as NSString)

        // normalize: Normalizes a path, resolving '..' and '.' segments
        let normalize: @convention(block) (String) -> String = { path in
            return URL(fileURLWithPath: path).standardized.path
        }
        moduleValue.setObject(normalize, forKeyedSubscript: "normalize" as NSString)

        // isAbsolute: Determines if path is an absolute path
        let isAbsolute: @convention(block) (String) -> Bool = { path in
            return path.starts(with: "/")
        }
        moduleValue.setObject(isAbsolute, forKeyedSubscript: "isAbsolute" as NSString)

        // relative: Returns the relative path from from to to
        let relative: @convention(block) (String, String) -> String = { from, to in
            let fromURL = URL(fileURLWithPath: from)
            let toURL = URL(fileURLWithPath: to)

            // Get standardized absolute paths
            let standardizedFrom = fromURL.standardized
            let standardizedTo = toURL.standardized

            // Split the paths into components
            let fromComponents = standardizedFrom.pathComponents
            let toComponents = standardizedTo.pathComponents

            // Find common prefix
            var i = 0
            while i < min(fromComponents.count, toComponents.count) && fromComponents[i] == toComponents[i] {
                i += 1
            }

            // Build the relative path
            var relPath = ""

            // Add "../" for each remaining component in fromPath
            for _ in i..<fromComponents.count {
                relPath += "../"
            }

            // Add the remaining components from toPath
            for j in i..<toComponents.count {
                relPath += toComponents[j]
                if j < toComponents.count - 1 {
                    relPath += "/"
                }
            }

            return relPath
        }
        moduleValue.setObject(relative, forKeyedSubscript: "relative" as NSString)

        // parse: Returns an object with path components
        let parse: @convention(block) (String) -> JSValue = { [weak self] path in
            guard let self = self else { return JSValue(nullIn: self!.context) }

            let url = URL(fileURLWithPath: path)
            let result = JSValue(object: [:], in: self.context)!

            result.setObject(url.path, forKeyedSubscript: "path" as NSString)
            result.setObject(url.lastPathComponent, forKeyedSubscript: "base" as NSString)

            // Get the path extension
            let ext = url.pathExtension
            result.setObject(ext.isEmpty ? "" : ".\(ext)", forKeyedSubscript: "ext" as NSString)

            // Get the filename without extension
            var name = url.lastPathComponent
            if !ext.isEmpty {
                let endIndex = name.index(name.endIndex, offsetBy: -(ext.count + 1))
                name = String(name[..<endIndex])
            }
            result.setObject(name, forKeyedSubscript: "name" as NSString)

            // Get the directory
            result.setObject(url.deletingLastPathComponent().path, forKeyedSubscript: "dir" as NSString)

            // Add the root (on Unix/macOS this is "/")
            result.setObject("/", forKeyedSubscript: "root" as NSString)

            return result
        }
        moduleValue.setObject(parse, forKeyedSubscript: "parse" as NSString)

        // format: Returns a path string from an object
        let format: @convention(block) (JSValue) -> String = { pathObject in
            var path = ""

            if let dir = pathObject.objectForKeyedSubscript("dir")?.toString(), !dir.isEmpty {
                path += dir
                // Only add a separator if the dir doesn't already end with one
                if !dir.hasSuffix("/") {
                    path += "/"
                }
            }

            if let name = pathObject.objectForKeyedSubscript("name")?.toString(), !name.isEmpty {
                path += name
            }

            if let ext = pathObject.objectForKeyedSubscript("ext")?.toString(), !ext.isEmpty {
                // Add a dot if the extension doesn't already start with one
                if !ext.starts(with: ".") {
                    path += "."
                }
                path += ext
            }

            return path
        }
        moduleValue.setObject(format, forKeyedSubscript: "format" as NSString)

        // Set path separator based on platform
        moduleValue.setObject(String(FileManager.default.pathSeparator), forKeyedSubscript: "sep" as NSString)

        // Add delimiter (same as separator on Unix, ";" on Windows)
        #if os(Windows)
        moduleValue.setObject(";", forKeyedSubscript: "delimiter" as NSString)
        #else
        moduleValue.setObject(":", forKeyedSubscript: "delimiter" as NSString)
        #endif
    }

    func module() -> JSValue {
        return moduleValue
    }
}
