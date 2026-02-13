// Licensed under the GNU General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

#if !SKIP_BRIDGE
import SwiftUI
import SkipMiniAppModel

#if os(iOS) || SKIP
import SkipWeb

/// A SwiftUI view that loads and displays a MiniApp from a package file.
///
/// Extracts the package contents to a temporary directory, parses the manifest,
/// and displays the start page in a WebView with an optional navigation bar.
public struct MiniAppView: View {
    private let packagePath: String
    @State private var manifest: MiniAppManifest?
    @State private var startPageURL: URL?
    @State private var errorMessage: String?
    @State private var webViewState: WebViewState = WebViewState()

    public init(packagePath: String) {
        self.packagePath = packagePath
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let manifest = manifest {
                if manifest.window?.navigationStyle != "custom" {
                    HStack {
                        Text(manifest.window?.navigationBarTitleText ?? manifest.appName)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }

            if let errorMessage = errorMessage {
                VStack {
                    Text("Error loading MiniApp")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if let url = startPageURL {
                WebView(url: url, state: $webViewState)
            } else {
                ProgressView()
            }
        }
        .task {
            loadMiniApp()
        }
    }

    private func loadMiniApp() {
        do {
            let package = MiniAppPackage(path: packagePath)
            let m = try package.readManifest()

            let extractDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("miniapp")
                .appendingPathComponent(m.appID)

            // Clean and recreate extraction directory
            try? FileManager.default.removeItem(at: extractDir)
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
            try package.extractToDirectory(at: extractDir.path)

            self.manifest = m

            if let firstPage = m.pages.first {
                self.startPageURL = extractDir.appendingPathComponent(firstPage + ".html")
            }
        } catch {
            self.errorMessage = String(describing: error)
        }
    }
}

#endif // os(iOS) || SKIP

#endif // !SKIP_BRIDGE
