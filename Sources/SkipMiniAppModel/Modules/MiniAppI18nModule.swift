// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import Foundation
import SkipScript
// SKIP NOWARN

extension MiniAppModuleType {
    /// Internationalization module.
    public static let i18n = MiniAppModuleType(MiniAppI18nModule())
}

/// MiniApp module providing internationalization (i18n) support.
///
/// Loads translation files from the MiniApp's `i18n/` directory, resolves the active
/// locale via fallback chain (device → manifest.lang → "en"), and exposes:
/// - `skip.i18n.t(key, params?)` — translate with parameter substitution
/// - `skip.i18n.n(number, options?)` — format number via Intl.NumberFormat
/// - `skip.i18n.d(date, options?)` — format date via Intl.DateTimeFormat
/// - `skip.i18n.plural(count, forms)` — select plural form via Intl.PluralRules
/// - `skip.i18n.locale` — current active locale string
public final class MiniAppI18nModule: MiniAppModule {
    /// The active locale resolved for this runtime instance.
    public var activeLocale: String = "en"

    /// The loaded translations for the active locale.
    public var translations: [String: String] = [:]

    /// Fallback translations (from the manifest's default locale).
    public var fallbackTranslations: [String: String] = [:]

    public override init() {
        super.init()
    }

    override public func registerInRuntime(_ runtime: MiniAppRuntime) {
        let context = runtime.jsContext
        guard let namespace = runtime.namespaceObject else { return }

        // Resolve locale and load translations
        loadTranslations(runtime: runtime)

        // Register the i18n namespace object
        let i18nObj = JSValue(newObjectIn: context)

        // Inject translations as a JS object for the t() function
        let allTranslations = mergedTranslations()
        if let jsonData = try? JSONSerialization.data(withJSONObject: allTranslations),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            context.evaluateScript("var __i18nMessages = JSON.parse('\(Self.escapeJS(jsonStr))')")
        } else {
            context.evaluateScript("var __i18nMessages = {}")
        }
        context.evaluateScript("var __i18nLocale = '\(Self.escapeJS(activeLocale))'")

        // skip.i18n.t(key, params?) — translate with parameter substitution
        context.evaluateScript("""
        function __i18nTranslate(key, params) {
            var msg = __i18nMessages[key] || key;
            if (params) {
                var keys = Object.keys(params);
                for (var i = 0; i < keys.length; i++) {
                    var k = keys[i];
                    msg = msg.split('{' + k + '}').join(String(params[k]));
                }
            }
            return msg;
        }
        """)

        let tFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let key = args.count > 0 ? (args[0].toString() ?? "") : ""
            let params = args.count > 1 ? args[1] : nil
            if let params = params, params.isObject {
                // Store params in a temp variable so we can pass the object to JS
                ctx.setObject(params, forKeyedSubscript: "__tmpParams")
                let result = ctx.evaluateScript("__i18nTranslate('\(Self.escapeJS(key))', __tmpParams)")
                return result ?? JSValue(string: key, in: ctx)
            } else {
                let result = ctx.evaluateScript("__i18nTranslate('\(Self.escapeJS(key))')")
                return result ?? JSValue(string: key, in: ctx)
            }
        }
        i18nObj.setObject(tFn, forKeyedSubscript: "t")

        // skip.i18n.locale — current locale string
        i18nObj.setObject(JSValue(string: activeLocale, in: context), forKeyedSubscript: "locale")

        // skip.i18n.n(number, options?) — Intl.NumberFormat
        let nFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let num = args.count > 0 ? args[0].toDouble() : 0.0
            let opts = args.count > 1 && args[1].isObject ? args[1].toString() ?? "{}" : "{}"
            let result = ctx.evaluateScript("new Intl.NumberFormat(__i18nLocale, \(opts)).format(\(num))")
            return result ?? JSValue(string: String(num), in: ctx)
        }
        i18nObj.setObject(nFn, forKeyedSubscript: "n")

        // skip.i18n.d(date, options?) — Intl.DateTimeFormat
        let dFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let dateVal = args.count > 0 ? args[0] : JSValue(undefinedIn: ctx)
            let opts = args.count > 1 && args[1].isObject ? args[1].toString() ?? "{}" : "{}"
            // Store date temporarily
            ctx.setObject(dateVal, forKeyedSubscript: "__tmpDate")
            let result = ctx.evaluateScript("new Intl.DateTimeFormat(__i18nLocale, \(opts)).format(__tmpDate)")
            return result ?? JSValue(string: "", in: ctx)
        }
        i18nObj.setObject(dFn, forKeyedSubscript: "d")

        // skip.i18n.plural(count, forms) — Intl.PluralRules
        // forms: { one: "item", other: "items" }
        let pluralFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let count = args.count > 0 ? args[0].toDouble() : 0.0
            let forms = args.count > 1 ? args[1] : nil
            guard let forms = forms, forms.isObject else {
                return JSValue(string: "", in: ctx)
            }
            ctx.setObject(forms, forKeyedSubscript: "__tmpForms")
            let result = ctx.evaluateScript("""
            (function() {
                var rule = new Intl.PluralRules(__i18nLocale).select(\(count));
                var f = __tmpForms;
                return (f[rule] || f['other'] || '').replace('#', String(\(Int(count))));
            })()
            """)
            return result ?? JSValue(string: "", in: ctx)
        }
        i18nObj.setObject(pluralFn, forKeyedSubscript: "plural")

        namespace.setObject(i18nObj, forKeyedSubscript: "i18n")

        // Store reference for the view layer
        runtime.i18nModule = self
    }

    // MARK: - Translation Loading

    private func loadTranslations(runtime: MiniAppRuntime) {
        let manifestLang = runtime.manifest.lang ?? "en"
        let deviceLocale = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")

        // Try loading locale files via the file system or package
        let localesToTry = [deviceLocale, manifestLang, "en"]
        var loaded = false

        for locale in localesToTry {
            if let data = try? runtime.package.readEntry(at: "i18n/\(locale).json"),
               let dict = parseTranslations(data: data) {
                translations = dict
                activeLocale = locale
                loaded = true
                break
            }
            // Also try without region (e.g., "zh" from "zh-Hans")
            let shortLocale = String(locale.split(separator: "-").first ?? "")
            if shortLocale != locale {
                if let data = try? runtime.package.readEntry(at: "i18n/\(shortLocale).json"),
                   let dict = parseTranslations(data: data) {
                    translations = dict
                    activeLocale = shortLocale
                    loaded = true
                    break
                }
            }
        }

        if !loaded {
            activeLocale = manifestLang
        }

        // Load fallback (manifest lang) if different from active
        if activeLocale != manifestLang {
            if let data = try? runtime.package.readEntry(at: "i18n/\(manifestLang).json"),
               let dict = parseTranslations(data: data) {
                fallbackTranslations = dict
            }
        }

        // Load "en" as ultimate fallback if not already loaded
        if activeLocale != "en" && fallbackTranslations.isEmpty {
            if let data = try? runtime.package.readEntry(at: "i18n/en.json"),
               let dict = parseTranslations(data: data) {
                fallbackTranslations = dict
            }
        }
    }

    private func parseTranslations(data: Data) -> [String: String]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return obj
    }

    /// Merge active + fallback translations (active takes precedence).
    private func mergedTranslations() -> [String: String] {
        var merged = fallbackTranslations
        for (key, value) in translations {
            merged[key] = value
        }
        return merged
    }

    /// Get the translations as a JSON string for injection into the view layer.
    public func translationsJSON() -> String {
        let merged = mergedTranslations()
        if let data = try? JSONSerialization.data(withJSONObject: merged),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }

    // MARK: - Helpers

    private static func escapeJS(_ str: String) -> String {
        return str.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\n", with: "\\n")
    }
}

#endif
