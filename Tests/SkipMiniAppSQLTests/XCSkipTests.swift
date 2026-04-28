// Copyright 2025-2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import Foundation
#if os(macOS) || os(Linux)
import SkipTest

@available(macOS 13, macCatalyst 16, *)
final class XCSkipTests: XCTestCase, XCGradleHarness {
    public func testSkipModule() async throws {
        try await runGradleTests()
    }
}
#endif
#endif
