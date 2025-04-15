import Foundation
import JavaScriptCore

class JSConsole {
    private let context: JSContext

    init(context: JSContext) {
        self.context = context
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
                self.formatAndPrint(args: args, prefix: "ERROR")
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

    private func formatAndPrint(args: [JSValue], prefix: String? = nil) {
        var messages: [String] = []

        for arg in args {
            if arg.isObject {
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
}
