// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import Foundation
import SkipScript

extension MiniAppModuleType {
    /// Network module providing the Fetch API.
    public static let network = MiniAppModuleType(MiniAppNetworkModule())
}

/// MiniApp module providing the Fetch API for HTTP requests.
///
/// Exposes `fetch(url, options)` which returns a Promise resolving to a Response
/// object with `.ok`, `.status`, `.headers`, `.json()`, and `.text()` methods.
public final class MiniAppNetworkModule: MiniAppModule {

    public override init() {
        super.init()
    }

    override public func bridgeScript() -> String {
        return """
            // --- Fetch API: _api.fetch(url, options) -> Promise<Response> ---
            _api.fetch = function(url, options) {
                return new Promise(function(resolve, reject) {
                    sendMessage('fetch', {
                        url: url,
                        method: (options && options.method) || 'GET',
                        headers: (options && options.headers) || {},
                        body: (options && options.body) || null
                    }, function(success, responseData) {
                        if (success && responseData) {
                            resolve({
                                ok: responseData.status >= 200 && responseData.status < 300,
                                status: responseData.status,
                                headers: responseData.headers || {},
                                body: responseData.body || '',
                                json: function() { return Promise.resolve(JSON.parse(this.body)); },
                                text: function() { return Promise.resolve(this.body); }
                            });
                        } else {
                            reject(new Error((responseData && responseData.message) || 'Network error'));
                        }
                    });
                });
            };
        """
    }

    override public func registerInRuntime(_ runtime: MiniAppRuntime) {
        let context = runtime.jsContext
        guard let namespace = runtime.namespaceObject else { return }
        // Register native fetch helper that receives resolve/reject from a Promise
        let nativeFetchFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard args.count >= 6 else { return JSValue(undefinedIn: ctx) }
            let urlString = args[0].toString() ?? ""
            let method = args[1].toString() ?? "GET"
            let headersVal = args[2]
            let bodyVal = args[3]
            let resolveCb = args[4]
            let rejectCb = args[5]

            guard let url = URL(string: urlString) else {
                let _ = try? rejectCb.call(withArguments: [JSValue(string: "Invalid URL: \(urlString)", in: ctx)])
                return JSValue(undefinedIn: ctx)
            }

            var request = URLRequest(url: url)
            request.httpMethod = method

            if headersVal.isObject {
                // SKIP NOWARN
                if let headerDict = headersVal.toObject() as? [String: Any] {
                    for (key, value) in headerDict {
                        request.setValue(String(describing: value), forHTTPHeaderField: key)
                    }
                }
            }
            if bodyVal.isString {
                request.httpBody = (bodyVal.toString() ?? "").data(using: .utf8)
            }

            nonisolated(unsafe) let safeResolve = resolveCb
            nonisolated(unsafe) let safeReject = rejectCb
            nonisolated(unsafe) let safeCtx = ctx
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        let _ = try? safeReject.call(withArguments: [JSValue(string: error.localizedDescription, in: safeCtx)])
                        return
                    }
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
                    let bodyString = data.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""

                    let responseObj = safeCtx.evaluateScript("""
                    (function(body, status) {
                        return {
                            ok: status >= 200 && status < 300,
                            status: status,
                            headers: {},
                            body: body,
                            json: function() { return Promise.resolve(JSON.parse(this.body)); },
                            text: function() { return Promise.resolve(this.body); }
                        };
                    })
                    """)
                    let result = try? responseObj?.call(withArguments: [JSValue(string: bodyString, in: safeCtx), JSValue(double: Double(statusCode), in: safeCtx)])
                    let _ = try? safeResolve.call(withArguments: [result ?? JSValue(undefinedIn: safeCtx)])
                }
            }.resume()

            return JSValue(undefinedIn: ctx)
        }
        context.setObject(nativeFetchFn, forKeyedSubscript: "__nativeFetch")

        // JavaScript wrapper that creates a Promise
        context.evaluateScript("""
        function fetch(url, options) {
            var method = (options && options.method) || 'GET';
            var headers = (options && options.headers) || {};
            var body = (options && options.body) || null;
            return new Promise(function(resolve, reject) {
                __nativeFetch(url, method, headers, body, resolve, reject);
            });
        }
        """)

        if let fetchRef = context.evaluateScript("fetch") {
            namespace.setObject(fetchRef, forKeyedSubscript: "fetch")
        }
    }

    override public func handleBridgeMessage(action: String, data: [String: Any], callId: Int, runtime: MiniAppRuntime, respond: @escaping (Int, Bool, [String: Any]) -> Void) -> Bool {
        guard action == "fetch" else { return false }

        let urlString = data["url"] as? String ?? ""
        let method = data["method"] as? String ?? "GET"
        // SKIP NOWARN
        let headers = data["headers"] as? [String: Any] ?? [:]
        let body = data["body"] as? String

        guard let url = URL(string: urlString) else {
            respond(callId, false, ["message": "Invalid URL: \(urlString)"])
            return true
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        for (key, value) in headers {
            request.setValue(String(describing: value), forHTTPHeaderField: key)
        }
        if let body = body {
            request.httpBody = body.data(using: .utf8)
        }

        nonisolated(unsafe) let safeRespond = respond
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    safeRespond(callId, false, ["message": error.localizedDescription])
                } else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
                    let bodyString = data.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""
                    safeRespond(callId, true, ["status": statusCode, "body": bodyString, "headers": [String: String]()])
                }
            }
        }.resume()

        return true
    }
}
#endif
