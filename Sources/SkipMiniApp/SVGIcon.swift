// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import SwiftUI

#if os(iOS) || SKIP

/// Renders an SVG file as an icon image.
///
/// On iOS, parses the SVG's `<path>` elements and renders them as a SwiftUI `Path`,
/// then uses `ImageRenderer` to snapshot the result into an `Image` when `render` is true.
/// On Android (SKIP), loads the SVG data via `UIImage(data:)` which has native SVG support.
///
/// - Parameters:
///   - url: File URL to the SVG file.
///   - size: The point size to render at (default 24).
///   - render: When true (iOS only), snapshots the path rendering into a static `Image`
///     via `ImageRenderer`. Required for contexts like `TabView` tab items where
///     SwiftUI expects an `Image`, not an arbitrary view.
public struct SVGIcon: View {
    let url: URL
    let size: CGFloat
    let render: Bool

    public init(url: URL, size: CGFloat = 24, render: Bool = false) {
        self.url = url
        self.size = size
        self.render = render
    }

    public var body: some View {
        #if SKIP
        // Android: UIImage(data:) supports SVG natively
        androidSVGImage
        #else
        // iOS: parse SVG paths and render via SwiftUI Path
        if render {
            renderedImage
        } else {
            SVGPathView(url: url, size: size)
                .frame(width: size, height: size)
        }
        #endif
    }

    #if SKIP
    @ViewBuilder
    private var androidSVGImage: some View {
        if let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .renderingMode(.template)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "questionmark.circle")
                .frame(width: size, height: size)
        }
    }
    #else
    /// Snapshot the SVG path rendering into a static Image via ImageRenderer.
    @ViewBuilder
    private var renderedImage: some View {
        let pathView = SVGPathView(url: url, size: size)
            .frame(width: size, height: size)
        if let uiImage = renderToUIImage(content: pathView) {
            Image(uiImage: uiImage)
                .renderingMode(.template)
        } else {
            SVGPathView(url: url, size: size)
                .frame(width: size, height: size)
        }
    }

    @MainActor
    private func renderToUIImage<V: View>(content: V) -> UIImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
    #endif
}

// MARK: - iOS SVG Path Renderer

#if !SKIP
/// Parses SVG `<path>` elements and renders them as a filled SwiftUI `Path`.
///
/// Supports SVG path commands: M/m, L/l, H/h, V/v, C/c, S/s, Q/q, Z/z.
/// Designed for simple monochrome icons such as Material Symbols from fonts.google.com/icons.
struct SVGPathView: View {
    let url: URL
    let size: CGFloat

    @State private var combinedPath: Path = Path()

    var body: some View {
        combinedPath
            .fill()
            .onAppear { loadSVG() }
    }

    private func loadSVG() {
        guard let data = try? Data(contentsOf: url),
              let svgString = String(data: data, encoding: .utf8) else { return }
        let viewBox = SVGParser.parseViewBox(svgString)
        let paths = SVGParser.parsePaths(svgString)

        let scale = min(size / viewBox.width, size / viewBox.height)
        let offsetX = (size - viewBox.width * scale) / 2.0 - viewBox.origin.x * scale
        let offsetY = (size - viewBox.height * scale) / 2.0 - viewBox.origin.y * scale
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: offsetX / scale, y: offsetY / scale)

        var combined = Path()
        for p in paths {
            combined.addPath(p.applying(transform))
        }
        combinedPath = combined
    }
}

/// SVG parsing utilities for extracting viewBox and path data.
enum SVGParser {
    static func parseViewBox(_ svg: String) -> CGRect {
        guard let range = svg.range(of: "viewBox=\"") else {
            let w = parseAttribute("width", from: svg) ?? 24
            let h = parseAttribute("height", from: svg) ?? 24
            return CGRect(x: 0, y: 0, width: w, height: h)
        }
        let start = range.upperBound
        guard let end = svg[start...].firstIndex(of: "\"") else {
            return CGRect(x: 0, y: 0, width: 24, height: 24)
        }
        let parts = svg[start..<end].split(separator: " ").compactMap { Double($0) }
        if parts.count >= 4 {
            return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        }
        return CGRect(x: 0, y: 0, width: 24, height: 24)
    }

    static func parseAttribute(_ name: String, from svg: String) -> Double? {
        let pattern = name + "=\""
        guard let range = svg.range(of: pattern) else { return nil }
        let start = range.upperBound
        guard let end = svg[start...].firstIndex(of: "\"") else { return nil }
        return Double(svg[start..<end])
    }

    static func parsePaths(_ svg: String) -> [Path] {
        var results: [Path] = []
        for marker in [" d=\"", "\"d=\"", "\td=\""] {
            var searchStart = svg.startIndex
            while let range = svg.range(of: marker, range: searchStart..<svg.endIndex) {
                let start = range.upperBound
                guard let end = svg[start...].firstIndex(of: "\"") else { break }
                let d = String(svg[start..<end])
                if let path = parseSVGPath(d) {
                    results.append(path)
                }
                searchStart = end
            }
        }
        return results
    }

    static func parseSVGPath(_ d: String) -> Path? {
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint? = nil
        var lastCommand: Character = " "

        let tokens = tokenize(d)
        var i = 0

        func nextNum() -> CGFloat {
            guard i < tokens.count, let v = Double(tokens[i]) else { return 0 }
            i += 1
            return CGFloat(v)
        }

        func hasMoreNumbers() -> Bool {
            guard i < tokens.count else { return false }
            return tokens[i].first?.isLetter != true
        }

        while i < tokens.count {
            let token = tokens[i]
            if let cmd = token.first, token.count == 1 && cmd.isLetter {
                i += 1
                lastCommand = cmd
            } else {
                if lastCommand == "M" { lastCommand = "L" }
                else if lastCommand == "m" { lastCommand = "l" }
            }

            switch lastCommand {
            case "M":
                let x = nextNum(); let y = nextNum()
                current = CGPoint(x: x, y: y)
                subpathStart = current
                path.move(to: current)
            case "m":
                let dx = nextNum(); let dy = nextNum()
                current = CGPoint(x: current.x + dx, y: current.y + dy)
                subpathStart = current
                path.move(to: current)
            case "L":
                while hasMoreNumbers() {
                    current = CGPoint(x: nextNum(), y: nextNum())
                    path.addLine(to: current)
                }
                lastControl = nil
            case "l":
                while hasMoreNumbers() {
                    current = CGPoint(x: current.x + nextNum(), y: current.y + nextNum())
                    path.addLine(to: current)
                }
                lastControl = nil
            case "H":
                while hasMoreNumbers() {
                    current = CGPoint(x: nextNum(), y: current.y)
                    path.addLine(to: current)
                }
                lastControl = nil
            case "h":
                while hasMoreNumbers() {
                    current = CGPoint(x: current.x + nextNum(), y: current.y)
                    path.addLine(to: current)
                }
                lastControl = nil
            case "V":
                while hasMoreNumbers() {
                    current = CGPoint(x: current.x, y: nextNum())
                    path.addLine(to: current)
                }
                lastControl = nil
            case "v":
                while hasMoreNumbers() {
                    current = CGPoint(x: current.x, y: current.y + nextNum())
                    path.addLine(to: current)
                }
                lastControl = nil
            case "C":
                while hasMoreNumbers() {
                    let c1 = CGPoint(x: nextNum(), y: nextNum())
                    let c2 = CGPoint(x: nextNum(), y: nextNum())
                    let end = CGPoint(x: nextNum(), y: nextNum())
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end; lastControl = c2
                }
            case "c":
                while hasMoreNumbers() {
                    let c1 = CGPoint(x: current.x + nextNum(), y: current.y + nextNum())
                    let c2 = CGPoint(x: current.x + nextNum(), y: current.y + nextNum())
                    let end = CGPoint(x: current.x + nextNum(), y: current.y + nextNum())
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end; lastControl = c2
                }
            case "S":
                while hasMoreNumbers() {
                    let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                    let c2 = CGPoint(x: nextNum(), y: nextNum())
                    let end = CGPoint(x: nextNum(), y: nextNum())
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end; lastControl = c2
                }
            case "s":
                while hasMoreNumbers() {
                    let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                    let c2 = CGPoint(x: current.x + nextNum(), y: current.y + nextNum())
                    let end = CGPoint(x: current.x + nextNum(), y: current.y + nextNum())
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end; lastControl = c2
                }
            case "Q":
                while hasMoreNumbers() {
                    let c = CGPoint(x: nextNum(), y: nextNum())
                    let end = CGPoint(x: nextNum(), y: nextNum())
                    path.addQuadCurve(to: end, control: c)
                    current = end; lastControl = c
                }
            case "q":
                while hasMoreNumbers() {
                    let c = CGPoint(x: current.x + nextNum(), y: current.y + nextNum())
                    let end = CGPoint(x: current.x + nextNum(), y: current.y + nextNum())
                    path.addQuadCurve(to: end, control: c)
                    current = end; lastControl = c
                }
            case "Z", "z":
                path.closeSubpath()
                current = subpathStart
                lastControl = nil
            default:
                i += 1
                lastControl = nil
            }
        }
        return path
    }

    /// Tokenize an SVG path `d` string into commands and numbers.
    static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in d {
            if ch.isLetter && ch != "e" && ch != "E" {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch == "," || ch == " " || ch == "\n" || ch == "\r" || ch == "\t" {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if ch == "-" && !current.isEmpty && current.last != "e" && current.last != "E" {
                tokens.append(current); current = String(ch)
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
#endif // !SKIP

#endif // os(iOS) || SKIP

#endif // !SKIP_BRIDGE
