// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import Foundation
import SkipScript
// SKIP NOWARN
import Observation

/// Navigation action types matching WeChat's 5 navigation APIs.
public enum MiniAppNavAction: Equatable {
    /// Push a new page onto the current tab's navigation stack.
    case navigateTo(url: String, query: String)
    /// Pop `delta` pages from the current tab's stack.
    case navigateBack(delta: Int)
    /// Replace the current page in the stack (no new entry).
    case redirectTo(url: String)
    /// Clear ALL stacks and reset to a single page.
    case reLaunch(url: String)
    /// Switch to the tab whose root page matches `url`.
    case switchTab(url: String)
}

/// Route for NavigationStack path (must be Hashable for SwiftUI).
public struct MiniAppPageRoute: Hashable {
    public let path: String
    public let query: String

    public init(path: String, query: String = "") {
        self.path = path
        self.query = query
    }
}

extension MiniAppModuleType {
    /// Navigation module providing WeChat-compatible navigation APIs.
    public static let navigation = MiniAppModuleType(MiniAppNavigationModule())
}

/// MiniApp module providing WeChat-compatible navigation APIs in the Logic Layer.
///
/// Manages per-tab navigation stacks and dispatches navigation actions to the host view.
/// Implements: navigateTo, navigateBack, redirectTo, reLaunch, switchTab.
@Observable public final class MiniAppNavigationModule: MiniAppModule {
    /// Maximum navigation depth per tab stack (WeChat convention).
    public let maxDepth = 10

    /// The pending navigation action for the host view to observe and process.
    public var pendingAction: MiniAppNavAction?

    /// Tab bar configuration from the manifest.
    public var tabBarConfig: MiniAppTabBar?

    /// Per-tab navigation stacks. Index matches tab index.
    /// Each stack is an array of page paths (the root page is always at index 0).
    public var tabStacks: [[String]] = []

    /// Currently active tab index.
    public var activeTabIndex: Int = 0

    public override init() {
        super.init()
    }

    /// Initialize tab stacks from the manifest's tabBar configuration.
    public func configure(manifest: MiniAppManifest) {
        tabBarConfig = manifest.tabBar
        if let tabBar = manifest.tabBar {
            tabStacks = tabBar.tabs.map { [$0.page] }
            activeTabIndex = 0
        } else {
            // No tab bar: single stack with the first page
            if let firstPage = manifest.pages.first {
                tabStacks = [[firstPage]]
            }
        }
    }

    /// The current tab's navigation stack.
    public var currentStack: [String] {
        guard activeTabIndex < tabStacks.count else { return [] }
        return tabStacks[activeTabIndex]
    }

    /// The current page (top of the active tab's stack).
    public var currentPage: String? {
        return currentStack.last
    }

    override public func registerInRuntime(_ runtime: MiniAppRuntime) {
        let context = runtime.jsContext
        guard let namespace = runtime.namespaceObject else { return }
        let navModule = self

        // Configure from manifest
        configure(manifest: runtime.manifest)

        // skip.navigateTo({ url, query })
        let navigateToFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard let options = args.first, options.isObject else { return JSValue(undefinedIn: ctx) }
            let urlVal = options.objectForKeyedSubscript("url")
            let queryVal = options.objectForKeyedSubscript("query")
            let url = urlVal.isUndefined ? "" : (urlVal.toString() ?? "")
            let query = queryVal.isUndefined ? "" : (queryVal.toString() ?? "")

            // Check max depth
            if navModule.currentStack.count >= navModule.maxDepth {
                return JSValue(undefinedIn: ctx)
            }
            navModule.pendingAction = .navigateTo(url: url, query: query)
            return JSValue(undefinedIn: ctx)
        }
        namespace.setObject(navigateToFn, forKeyedSubscript: "navigateTo")

        // skip.navigateBack({ delta })
        let navigateBackFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            var delta = 1
            if let options = args.first, options.isObject {
                let deltaVal = options.objectForKeyedSubscript("delta")
                if !deltaVal.isUndefined {
                    delta = max(1, Int(deltaVal.toDouble()))
                }
            }
            navModule.pendingAction = .navigateBack(delta: delta)
            return JSValue(undefinedIn: ctx)
        }
        namespace.setObject(navigateBackFn, forKeyedSubscript: "navigateBack")

        // skip.redirectTo({ url })
        let redirectToFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard let options = args.first, options.isObject else { return JSValue(undefinedIn: ctx) }
            let urlVal = options.objectForKeyedSubscript("url")
            let url = urlVal.isUndefined ? "" : (urlVal.toString() ?? "")
            navModule.pendingAction = .redirectTo(url: url)
            return JSValue(undefinedIn: ctx)
        }
        namespace.setObject(redirectToFn, forKeyedSubscript: "redirectTo")

        // skip.reLaunch({ url })
        let reLaunchFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard let options = args.first, options.isObject else { return JSValue(undefinedIn: ctx) }
            let urlVal = options.objectForKeyedSubscript("url")
            let url = urlVal.isUndefined ? "" : (urlVal.toString() ?? "")
            navModule.pendingAction = .reLaunch(url: url)
            return JSValue(undefinedIn: ctx)
        }
        namespace.setObject(reLaunchFn, forKeyedSubscript: "reLaunch")

        // skip.switchTab({ url })
        let switchTabFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard let options = args.first, options.isObject else { return JSValue(undefinedIn: ctx) }
            let urlVal = options.objectForKeyedSubscript("url")
            let url = urlVal.isUndefined ? "" : (urlVal.toString() ?? "")
            navModule.pendingAction = .switchTab(url: url)
            return JSValue(undefinedIn: ctx)
        }
        namespace.setObject(switchTabFn, forKeyedSubscript: "switchTab")

        // Store reference on runtime
        runtime.navigationModule = self
    }

    // MARK: - Stack manipulation (called by host view after processing actions)

    /// Push a page onto the current tab's stack.
    public func push(page: String) {
        guard activeTabIndex < tabStacks.count else { return }
        guard tabStacks[activeTabIndex].count < maxDepth else { return }
        tabStacks[activeTabIndex].append(page)
    }

    /// Pop `delta` pages from the current tab's stack (never pops the root).
    public func pop(delta: Int) {
        guard activeTabIndex < tabStacks.count else { return }
        let removeCount = min(delta, tabStacks[activeTabIndex].count - 1)
        if removeCount > 0 {
            tabStacks[activeTabIndex].removeLast(removeCount)
        }
    }

    /// Replace the top page in the current tab's stack.
    public func replace(page: String) {
        guard activeTabIndex < tabStacks.count else { return }
        if tabStacks[activeTabIndex].count > 0 {
            tabStacks[activeTabIndex][tabStacks[activeTabIndex].count - 1] = page
        }
    }

    /// Clear all stacks and reset to a single page.
    public func reLaunch(page: String) {
        for i in 0..<tabStacks.count {
            tabStacks[i] = [tabStacks[i].first ?? page]
        }
        // If the page is a tab root, switch to that tab
        if let tabIndex = tabIndexForPage(page) {
            activeTabIndex = tabIndex
            tabStacks[tabIndex] = [page]
        } else {
            // Non-tab page: put it on the current tab
            tabStacks[activeTabIndex] = [page]
        }
    }

    /// Switch to the tab whose root page matches `url`.
    public func switchToTab(page: String) {
        if let tabIndex = tabIndexForPage(page) {
            activeTabIndex = tabIndex
        }
    }

    /// Find the tab index for a given page URL.
    public func tabIndexForPage(_ page: String) -> Int? {
        guard let tabBar = tabBarConfig else { return nil }
        return tabBar.tabs.firstIndex(where: { $0.page == page })
    }
}
#endif
