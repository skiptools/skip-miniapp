// Licensed under the GNU General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import Foundation

/// Global application lifecycle states per the W3C MiniApp Lifecycle specification.
public enum MiniAppGlobalState: String, Hashable {
    case launched
    case shown
    case hidden
    case error
    case unloaded
}

/// Page lifecycle states per the W3C MiniApp Lifecycle specification.
public enum MiniAppPageState: String, Hashable {
    case loaded
    case ready
    case shown
    case hidden
    case unloaded
}

/// Manages global lifecycle state for a MiniApp instance.
public class MiniAppLifecycle {
    public private(set) var globalState: MiniAppGlobalState
    public private(set) var currentError: (any Error)?

    public init() {
        self.globalState = .launched
        self.currentError = nil
    }

    /// Transition to the launched state.
    public func launch() {
        globalState = .launched
        currentError = nil
    }

    /// Transition to the shown (foreground) state.
    public func show() {
        globalState = .shown
    }

    /// Transition to the hidden (background) state.
    public func hide() {
        globalState = .hidden
    }

    /// Transition to the error state.
    public func fail(error: any Error) {
        currentError = error
        globalState = .error
    }

    /// Transition to the unloaded (terminated) state.
    public func unload() {
        globalState = .unloaded
    }
}

/// Manages page lifecycle state for a MiniApp page.
public class MiniAppPageLifecycle {
    public private(set) var pageState: MiniAppPageState

    public init() {
        self.pageState = .loaded
    }

    /// Transition to the loaded state.
    public func load() {
        pageState = .loaded
    }

    /// Transition to the ready state (first render complete).
    public func ready() {
        pageState = .ready
    }

    /// Transition to the shown (foreground) state.
    public func show() {
        pageState = .shown
    }

    /// Transition to the hidden (background) state.
    public func hide() {
        pageState = .hidden
    }

    /// Transition to the unloaded (closed) state.
    public func unload() {
        pageState = .unloaded
    }
}
