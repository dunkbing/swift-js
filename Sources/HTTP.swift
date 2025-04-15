import Foundation
import JavaScriptCore

class HTTP {
    private let context: JSContext
    private let moduleValue: JSValue

    init(context: JSContext) {
        self.context = context
        self.moduleValue = JSValue(object: [:], in: context)

        setupModule()
    }

    private func setupModule() {
        let get: @convention(block) (String, JSValue?) -> Void = { [weak self] url, callback in
            guard let self = self else { return }

            guard let url = URL(string: url) else {
                let error = self.createError(message: "Invalid URL", name: "Error")
                callback?.call(withArguments: [error, self.jsNull()])
                return
            }

            self.context.objectForKeyedSubscript("__incrementPendingOps")?.call(withArguments: [])

            let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                guard let self = self else { return }

                defer {
                    self.context.objectForKeyedSubscript("__decrementPendingOps")?.call(withArguments: [])
                }

                if let error = error {
                    let jsError = self.createError(message: error.localizedDescription, name: "Error")
                    callback?.call(withArguments: [jsError, self.jsNull()])
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    let error = self.createError(message: "Invalid response", name: "Error")
                    callback?.call(withArguments: [error, self.jsNull()])
                    return
                }

                let responseObj = JSValue(object: [:], in: self.context)!
                responseObj.setObject(httpResponse.statusCode, forKeyedSubscript: "statusCode" as NSString)

                let headers = JSValue(object: [:], in: self.context)!
                for (key, value) in httpResponse.allHeaderFields {
                    if let keyStr = key as? String, let valueStr = value as? String {
                        headers.setObject(valueStr, forKeyedSubscript: keyStr as NSString)
                    }
                }
                responseObj.setObject(headers, forKeyedSubscript: "headers" as NSString)

                if let data = data {
                    if let bodyString = String(data: data, encoding: .utf8) {
                        responseObj.setObject(bodyString, forKeyedSubscript: "body" as NSString)
                    } else {
                        // if not UTF8, provide as base64
                        let base64 = data.base64EncodedString()
                        responseObj.setObject(base64, forKeyedSubscript: "bodyBase64" as NSString)
                    }
                }

                callback?.call(withArguments: [self.jsNull(), responseObj])
            }

            task.resume()
        }
        moduleValue.setObject(get, forKeyedSubscript: "get" as NSString)

        // HTTP request (with options)
        let request: @convention(block) (JSValue, JSValue?) -> Void = { [weak self] options, callback in
            guard let self = self else { return }

            guard let optionsObj = options.toObject() as? [String: Any] else {
                let error = self.createError(message: "Invalid options", name: "Error")
                callback?.call(withArguments: [error, self.jsNull()])
                return
            }

            guard let urlString = optionsObj["url"] as? String,
                  let url = URL(string: urlString) else {
                let error = self.createError(message: "Invalid URL", name: "Error")
                callback?.call(withArguments: [error, self.jsNull()])
                return
            }

            // track this async operation using the global function
            self.context.objectForKeyedSubscript("__incrementPendingOps")?.call(withArguments: [])

            var request = URLRequest(url: url)

            if let method = optionsObj["method"] as? String {
                request.httpMethod = method
            } else {
                request.httpMethod = "GET"
            }

            if let headers = optionsObj["headers"] as? [String: String] {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }

            if let body = optionsObj["body"] as? String {
                request.httpBody = body.data(using: .utf8)
            }

            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }

                defer {
                    self.context.objectForKeyedSubscript("__decrementPendingOps")?.call(withArguments: [])
                }

                if let error = error {
                    let jsError = self.createError(message: error.localizedDescription, name: "Error")
                    callback?.call(withArguments: [jsError, self.jsNull()])
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    let error = self.createError(message: "Invalid response", name: "Error")
                    callback?.call(withArguments: [error, self.jsNull()])
                    return
                }

                let responseObj = JSValue(object: [:], in: self.context)!
                responseObj.setObject(httpResponse.statusCode, forKeyedSubscript: "statusCode" as NSString)

                let headers = JSValue(object: [:], in: self.context)!
                for (key, value) in httpResponse.allHeaderFields {
                    if let keyStr = key as? String, let valueStr = value as? String {
                        headers.setObject(valueStr, forKeyedSubscript: keyStr as NSString)
                    }
                }
                responseObj.setObject(headers, forKeyedSubscript: "headers" as NSString)

                if let data = data {
                    if let bodyString = String(data: data, encoding: .utf8) {
                        responseObj.setObject(bodyString, forKeyedSubscript: "body" as NSString)
                    } else {
                        let base64 = data.base64EncodedString()
                        responseObj.setObject(base64, forKeyedSubscript: "bodyBase64" as NSString)
                    }
                }

                callback?.call(withArguments: [self.jsNull(), responseObj])
            }

            task.resume()
        }
        moduleValue.setObject(request, forKeyedSubscript: "request" as NSString)
    }

    // create js Error objects
    private func createError(message: String, name: String = "Error") -> JSValue {
        if let errorConstructor = context.evaluateScript("Error") {
            let error = errorConstructor.construct(withArguments: [message])!

            // Set the name property if it's not the default "Error"
            if name != "Error" {
                error.setObject(name, forKeyedSubscript: "name" as NSString)
            }

            return error
        } else {
            let errorObj = JSValue(object: [:], in: context)!
            errorObj.setObject(message, forKeyedSubscript: "message" as NSString)
            errorObj.setObject(name, forKeyedSubscript: "name" as NSString)
            return errorObj
        }
    }

    private func jsNull() -> JSValue {
        return context.evaluateScript("null")!
    }

    func module() -> JSValue {
        return moduleValue
    }
}
