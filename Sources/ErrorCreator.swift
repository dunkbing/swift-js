import JavaScriptCore
import Foundation

/// Protocol that defines error creation capability for JavaScript modules
protocol ErrorCreator {
    /// JavaScript context to use for error creation
    var context: JSContext { get }

    /// Creates a JavaScript Error object with the given message
    /// - Parameters:
    ///   - message: The error message
    ///   - name: Optional error type name (defaults to "Error")
    /// - Returns: A JSValue representing a JavaScript Error
    func createError(message: String, name: String) -> JSValue
}

extension ErrorCreator {
    /// Default implementation with optional name parameter
    func createError(message: String, name: String = "Error") -> JSValue {
        if let errorConstructor = context.evaluateScript("Error") {
            let error = errorConstructor.construct(withArguments: [message])!

            // Set the name property if it's not the default "Error"
            if name != "Error" {
                error.setObject(name, forKeyedSubscript: "name" as NSString)
            }

            return error
        } else {
            // Fallback if Error constructor is not available
            let errorObj = JSValue(object: [:], in: context)!
            errorObj.setObject(message, forKeyedSubscript: "message" as NSString)
            errorObj.setObject(name, forKeyedSubscript: "name" as NSString)
            return errorObj
        }
    }

    /// Helper method to create a JavaScript null value
    func jsNull() -> JSValue {
        return context.evaluateScript("null")!
    }
}
