import Foundation
import JavaScriptCore

class Console {
    private let context: JSContext
    private weak var runtime: Runtime?

    init(context: JSContext, runtime: Runtime? = nil) {
        self.context = context
        self.runtime = runtime
        setupConsole()
    }

    private func setupConsole() {
        let console = JSValue(object: [:], in: context)

        let consoleLog: @convention(block) () -> Void = { [self] in
            if let args = JSContext.currentArguments() as? [JSValue] {
                self.formatAndPrint(args: args)
            }
        }

        let consoleError: @convention(block) () -> Void = { [self] in
            if let args = JSContext.currentArguments() as? [JSValue] {
                self.formatAndPrint(args: args, prefix: nil, isError: true)
            }
        }

        let consoleWarn: @convention(block) () -> Void = { [self] in
            if let args = JSContext.currentArguments() as? [JSValue] {
                self.formatAndPrint(args: args, prefix: "WARNING")
            }
        }

        let consoleInfo: @convention(block) () -> Void = { [self] in
            if let args = JSContext.currentArguments() as? [JSValue] {
                self.formatAndPrint(args: args, prefix: "INFO")
            }
        }

        let consoleDebug: @convention(block) () -> Void = { [self] in
            if let args = JSContext.currentArguments() as? [JSValue] {
                self.formatAndPrint(args: args, prefix: "DEBUG")
            }
        }

        let consoleClear: @convention(block) () -> Void = {
            print("\u{001B}[2J\u{001B}[H", terminator: "")
        }

        let timers = JSValue(object: [:], in: context)
        context.setObject(timers, forKeyedSubscript: "__consoleTimers" as NSString)

        let consoleTime: @convention(block) (String) -> Void = { label in
            let timer = Date().timeIntervalSince1970
            timers?.setObject(timer, forKeyedSubscript: label as NSString)
            print("Timer '\(label)' started")
        }

        let consoleTimeEnd: @convention(block) (String) -> Void = { label in
            if let startTime = timers?.objectForKeyedSubscript(label)?.toDouble() {
                let endTime = Date().timeIntervalSince1970
                let duration = (endTime - startTime) * 1000 // ms
                print("Timer '\(label)': \(String(format: "%.3f", duration))ms")
                timers?.deleteProperty(label)
            } else {
                print("Timer '\(label)' does not exist")
            }
        }

        let consoleAssert: @convention(block) () -> Void = { [self] in
            if let args = JSContext.currentArguments() as? [JSValue], args.count > 0 {
                let condition = args[0].toBool()
                if !condition {
                    print("Assertion failed: ", terminator: "")
                    if args.count > 1 {
                        var remainingArgs = [JSValue]()
                        for i in 1..<args.count {
                            remainingArgs.append(args[i])
                        }
                        self.formatAndPrint(args: remainingArgs)
                    }
                }
            }
        }

        console?.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        console?.setObject(consoleError, forKeyedSubscript: "error" as NSString)
        console?.setObject(consoleWarn, forKeyedSubscript: "warn" as NSString)
        console?.setObject(consoleInfo, forKeyedSubscript: "info" as NSString)
        console?.setObject(consoleDebug, forKeyedSubscript: "debug" as NSString)
        console?.setObject(consoleClear, forKeyedSubscript: "clear" as NSString)
        console?.setObject(consoleTime, forKeyedSubscript: "time" as NSString)
        console?.setObject(consoleTimeEnd, forKeyedSubscript: "timeEnd" as NSString)
        console?.setObject(consoleAssert, forKeyedSubscript: "assert" as NSString)

        // add console to global
        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    private func formatAndPrint(args: [JSValue], prefix: String? = nil, isError: Bool = false) {
        var messages: [String] = []

        for arg in args {
            if isError && arg.isObject && self.isErrorObject(arg) {
                let formattedError = self.formatErrorObject(arg)
                messages.append(formattedError)
            } else if arg.isObject {
                if let jsonData = try? JSONSerialization.data(withJSONObject: arg.toObject() ?? [:], options: [.prettyPrinted]),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    messages.append(jsonString)
                } else {
                    messages.append(arg.toString() ?? UNDEFINED)
                }
            } else {
                messages.append(arg.toString() ?? UNDEFINED)
            }
        }

        if let prefix = prefix {
            print("\(prefix):", messages.joined(separator: " "))
        } else {
            print(messages.joined(separator: " "))
        }
    }

    private func isErrorObject(_ value: JSValue) -> Bool {
        let hasMessage = !value.objectForKeyedSubscript("message").isUndefined
        let hasName = !value.objectForKeyedSubscript("name").isUndefined
        let hasStack = !value.objectForKeyedSubscript("stack").isUndefined

        let isInstanceOfError = context.evaluateScript("(function(obj) { return obj instanceof Error; })")?.call(withArguments: [value]).toBool() ?? false

        return isInstanceOfError || (hasMessage && (hasName || hasStack))
    }

    private func formatErrorObject(_ errorValue: JSValue) -> String {
        let errorName = errorValue.objectForKeyedSubscript("name")?.toString() ?? "Error"
        let message = errorValue.objectForKeyedSubscript("message")?.toString() ?? ""
        let lineNumber = errorValue.objectForKeyedSubscript("line")?.toInt32() ?? 0
        let column = errorValue.objectForKeyedSubscript("column")?.toInt32() ?? 0
        let stack = errorValue.objectForKeyedSubscript("stack")?.toString() ?? ""

        // stack location
        let filePath = runtime?.getCurrentScriptPath() ?? "script"
        var extractedLineNumber = lineNumber
        var extractedColumn = column

        if lineNumber == 0 && !stack.isEmpty {
            let stackLines = stack.components(separatedBy: .newlines)
            for line in stackLines {
                if let match = line.range(of: ":(\\d+):(\\d+)", options: .regularExpression) {
                    let matchedText = line[match]
                    let components = String(matchedText).components(separatedBy: ":")
                    if components.count >= 3 {
                        if let line = Int32(components[1]) {
                            extractedLineNumber = line
                        }
                        if let col = Int32(components[2]) {
                            extractedColumn = col
                        }
                        break
                    }
                }
            }
        }

        if let runtime = runtime, extractedLineNumber > 0, let scriptSource = runtime.getCurrentScriptSource() {
            let lines = scriptSource.components(separatedBy: .newlines)
            let startLine = max(0, Int(extractedLineNumber) - 2)
            let endLine = min(lines.count - 1, Int(extractedLineNumber) + 1)

            var result = "Caught explicitly:"

            for i in startLine...endLine {
                let lineNum = i + 1
                let formattedLineNum = String(format: "%d", lineNum)

                if lineNum == extractedLineNumber {
                    result += "\n\(formattedLineNum) | \(lines[i])"

                    let pointerIndent = " ".repeated(formattedLineNum.count + 3 + Int(extractedColumn) - 1)
                    result += "\n\(pointerIndent)^"

                    result += "\n\(errorName): \(message)"
                } else {
                    result += "\n\(formattedLineNum) | \(lines[i])"
                }
            }

            result += "\n      at \(filePath):\(extractedLineNumber):\(extractedColumn)"

            if !stack.isEmpty {
                let stackLines = stack.components(separatedBy: .newlines)
                for stackLine in stackLines.dropFirst() {
                    let trimmedLine = stackLine.trimmingCharacters(in: .whitespaces)
                    if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("global code") {
                        result += "\n      \(trimmedLine)"
                    }
                }
            }

            return result
        } else {
            var formattedError = "\(errorName): \(message)"

            if !stack.isEmpty {
                formattedError = "\(formattedError)\n      at \(filePath):\(extractedLineNumber):\(extractedColumn)"

                let stackLines = stack.components(separatedBy: .newlines)
                for stackLine in stackLines.dropFirst() {
                    let trimmedLine = stackLine.trimmingCharacters(in: .whitespaces)
                    if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("global code") {
                        formattedError += "\n      \(trimmedLine)"
                    }
                }
            } else {
                if extractedLineNumber > 0 {
                    formattedError += "\n      at \(filePath):\(extractedLineNumber):\(extractedColumn)"
                }
            }

            return formattedError
        }
    }
}
