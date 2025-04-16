import JavaScriptCore
import Foundation

/// protocol that defines the standard interface for JavaScript modules
protocol JSModule {
    /// The JavaScript context to use for this module
    var context: JSContext { get }

    /// The JSValue containing the module object to expose to JavaScript
    var moduleValue: JSValue { get }

    /// Set up the module's functions and properties
    func setupModule()

    /// Get the module value to be exposed through the require system
    func module() -> JSValue
}

/// Default implementation for common module functionality
extension JSModule {
    func module() -> JSValue {
        return moduleValue
    }
}

/// Protocol combining JSModule and ErrorCreator functionalities
protocol ErrorAwareJSModule: JSModule, ErrorCreator {}
