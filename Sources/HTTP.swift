import JavaScriptCore
import NIO
import Foundation

class HTTP {
    private let context: JSContext
    private let moduleValue: JSValue
    private let eventLoop: EventLoop

    init(context: JSContext, eventLoop: EventLoop) {
        self.context = context
        self.moduleValue = JSValue(object: [:], in: context)
        self.eventLoop = eventLoop

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

            // Use Foundation's URLSession for HTTP requests
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
                        // If not UTF8, provide as base64
                        let base64 = data.base64EncodedString()
                        responseObj.setObject(base64, forKeyedSubscript: "bodyBase64" as NSString)
                    }
                }

                callback?.call(withArguments: [self.jsNull(), responseObj])
            }

            task.resume()
        }
        moduleValue.setObject(get, forKeyedSubscript: "get" as NSString)

        // HTTP request with options
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

        // Setup a simple HTTP server using Foundation's networking
        setupServerModule()
    }

    private func setupServerModule() {
        // Create a simple HTTP server
        let createServer: @convention(block) (JSValue?) -> JSValue = { [weak self] callback in
            guard let self = self else { return JSValue(nullIn: self!.context) }

            let serverObj = JSValue(object: [:], in: self.context)!

            // Store the callback to be called with (request, response) objects
            let requestHandler = callback

            // Listen method to start the server
            let listen: @convention(block) (Int, String?, JSValue?) -> Void = { [weak self, weak serverObj] port, host, callback in
                guard let self = self, let serverObj = serverObj else { return }

                let hostname = host ?? "localhost"

                // Create a server socket
                do {
                    // Create a simple TCP server using NIO directly
                    let serverHandler = SimpleHTTPServer(
                        context: self.context,
                        requestCallback: requestHandler
                    )

                    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
                    let bootstrap = ServerBootstrap(group: group)
                        .serverChannelOption(ChannelOptions.backlog, value: 256)
                        .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                        .childChannelInitializer { channel in
                            channel.pipeline.addHandler(serverHandler)
                        }
                        .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

                    let serverChannel = try bootstrap.bind(host: hostname, port: port).wait()
                    print("Server started and listening on \(hostname):\(port)")

                    // Store server details
                    serverObj.setObject(serverChannel, forKeyedSubscript: "__channel" as NSString)
                    serverObj.setObject(group, forKeyedSubscript: "__group" as NSString)

                    // Call the callback if provided
                    callback?.call(withArguments: [])
                } catch {
                    print("Failed to start server: \(error)")
                    callback?.call(withArguments: [self.createError(message: "Failed to start server: \(error)")])
                }
            }

            serverObj.setObject(listen, forKeyedSubscript: "listen" as NSString)

            // Close method to stop the server
            let close: @convention(block) (JSValue?) -> Void = { [weak serverObj] callback in
                guard let serverObj = serverObj else { return }

                if let channel = serverObj.objectForKeyedSubscript("__channel")?.toObject() as? Channel,
                   let group = serverObj.objectForKeyedSubscript("__group")?.toObject() as? EventLoopGroup {
                    do {
                        try channel.close().wait()
                        try group.syncShutdownGracefully()
                        print("Server stopped")
                        callback?.call(withArguments: [])
                    } catch {
                        print("Error stopping server: \(error)")
                    }
                } else {
                    print("Server was not properly initialized")
                }
            }

            serverObj.setObject(close, forKeyedSubscript: "close" as NSString)

            return serverObj
        }

        moduleValue.setObject(createServer, forKeyedSubscript: "createServer" as NSString)
    }

    // Create JS Error objects
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

// Simple HTTP Server using NIO but without NIOHTTP1 dependency
fileprivate class SimpleHTTPServer: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let context: JSContext
    private let requestCallback: JSValue?

    init(context: JSContext, requestCallback: JSValue?) {
        self.context = context
        self.requestCallback = requestCallback
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = self.unwrapInboundIn(data)

        // Very basic HTTP parsing
        if let requestString = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes),
           let requestCallback = self.requestCallback {

            // Parse the request
            let lines = requestString.components(separatedBy: "\r\n")
            if lines.isEmpty {
                sendResponse(context: context, status: 400, body: "Bad Request")
                return
            }

            // Parse the request line
            let requestLine = lines[0].components(separatedBy: " ")
            if requestLine.count < 3 {
                sendResponse(context: context, status: 400, body: "Bad Request")
                return
            }

            let method = requestLine[0]
            let path = requestLine[1]

            // Parse headers
            var headers: [String: String] = [:]
            var i = 1
            while i < lines.count && !lines[i].isEmpty {
                let headerLine = lines[i]
                if let colonIndex = headerLine.firstIndex(of: ":") {
                    let name = headerLine[..<colonIndex].trimmingCharacters(in: .whitespaces)
                    let value = headerLine[headerLine.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
                    headers[name] = value
                }
                i += 1
            }

            // Find body if any
            var body = ""
            if i < lines.count - 1 {
                body = lines[(i+1)...].joined(separator: "\r\n")
            }

            // Create request object for JavaScript
            let jsRequest = JSValue(object: [:], in: self.context)!
            jsRequest.setObject(method, forKeyedSubscript: "method" as NSString)
            jsRequest.setObject(path, forKeyedSubscript: "url" as NSString)

            // Add headers
            let jsHeaders = JSValue(object: [:], in: self.context)!
            for (name, value) in headers {
                jsHeaders.setObject(value, forKeyedSubscript: name as NSString)
            }
            jsRequest.setObject(jsHeaders, forKeyedSubscript: "headers" as NSString)

            // Add body if any
            if !body.isEmpty {
                jsRequest.setObject(body, forKeyedSubscript: "body" as NSString)
            }

            // Create response object for JavaScript
            let jsResponse = JSValue(object: [:], in: self.context)!

            // Add status code property with default 200
            jsResponse.setObject(200, forKeyedSubscript: "statusCode" as NSString)

            // Add response headers object
            let responseHeaders = JSValue(object: [:], in: self.context)!
            jsResponse.setObject(responseHeaders, forKeyedSubscript: "headers" as NSString)

            // Add write method to response
            let write: @convention(block) (Any) -> Void = { [weak jsResponse] data in
                guard let jsResponse = jsResponse else { return }

                if let dataString = data as? String {
                    jsResponse.setObject(dataString, forKeyedSubscript: "_body" as NSString)
                }
            }
            jsResponse.setObject(write, forKeyedSubscript: "write" as NSString)

            // Add end method to response
            let end: @convention(block) (Any?) -> Void = { [weak self, weak jsResponse, weak context] data in
                guard let self = self, let jsResponse = jsResponse, let context = context else { return }

                var responseBody = ""

                // Handle data passed to end
                if let dataString = data as? String {
                    responseBody = dataString
                } else if let body = jsResponse.objectForKeyedSubscript("_body")?.toString() {
                    responseBody = body
                }

                // Get status code from response object
                let statusCode = jsResponse.objectForKeyedSubscript("statusCode").toInt32()

                // Get headers from response object
                var responseHeadersDict: [String: String] = [:]
                if let headerObj = jsResponse.objectForKeyedSubscript("headers").toObject() as? [String: String] {
                    responseHeadersDict = headerObj
                }

                // Send the response
                self.sendResponse(context: context,
                                  status: Int(statusCode),
                                  headers: responseHeadersDict,
                                  body: responseBody)
            }
            jsResponse.setObject(end, forKeyedSubscript: "end" as NSString)

            // Call the JavaScript request handler
            requestCallback.call(withArguments: [jsRequest, jsResponse])
        } else {
            sendResponse(context: context, status: 400, body: "Bad Request")
        }
    }

    private func sendResponse(context: ChannelHandlerContext,
                             status: Int,
                             headers: [String: String] = [:],
                             body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 201: statusText = "Created"
        case 204: statusText = "No Content"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        // Create response
        let responseData = body.data(using: .utf8) ?? Data()

        // Build response headers
        var responseHeaders = [
            "Content-Length": "\(responseData.count)",
            "Content-Type": "text/plain; charset=utf-8",
            "Connection": "close"
        ]

        // Add custom headers
        for (key, value) in headers {
            responseHeaders[key] = value
        }

        // Create response string
        var responseString = "HTTP/1.1 \(status) \(statusText)\r\n"

        // Add headers
        for (key, value) in responseHeaders {
            responseString += "\(key): \(value)\r\n"
        }

        // Add empty line to separate headers from body
        responseString += "\r\n"

        // Add body
        responseString += body

        // Convert to buffer and send
        var buffer = context.channel.allocator.buffer(capacity: responseString.utf8.count)
        buffer.writeString(responseString)

        // Write and flush
        _ = context.writeAndFlush(self.wrapOutboundOut(buffer))
            .always { _ in
                // Close the connection after sending the response
                _ = context.close()
            }
    }
}
