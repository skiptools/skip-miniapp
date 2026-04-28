// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import Foundation
import SkipScript
// SKIP NOWARN

extension MiniAppModuleType {
    /// Network module providing the Fetch API in the Logic Layer.
    public static let network = MiniAppModuleType(MiniAppNetworkModule())
}

/// MiniApp module providing the Fetch API for HTTP requests in the Logic Layer.
///
/// Exposes `fetch(url, options)` which returns a Promise resolving to a Response
/// object with `.ok`, `.status`, `.headers`, `.json()`, and `.text()` methods.
/// Only available to app.js and page.js code (not the WebView).
public final class MiniAppNetworkModule: MiniAppModule {

    public override init() {
        super.init()
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

        // Create skip.net namespace
        let netObj = JSValue(newObjectIn: context)
        if let fetchRef = context.evaluateScript("fetch") {
            netObj.setObject(fetchRef, forKeyedSubscript: "fetch")
        }
        namespace.setObject(netObj, forKeyedSubscript: "net")
    }
}
#endif
