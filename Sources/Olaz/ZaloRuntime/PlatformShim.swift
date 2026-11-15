import Foundation
import SwiftUI
import UserNotifications

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

/// User-visible product name. The package, bundle id and log subsystem still say Olaz until the rename.
enum AppBrand {
    static let name = "Olaz"
}

extension Notification.Name {
    static let olazShareFileRequested = Notification.Name("OlazShareFileRequested")
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

enum PlatformImageCodec {
    static func decode(data: Data) -> PlatformImage? {
        #if os(macOS)
        return NSImage(data: data)
        #else
        if let image = UIImage(data: data) {
            return image
        }
        return decodeSVG(data: data)
        #endif
    }

    static func pngData(from image: PlatformImage) -> Data? {
        #if os(macOS)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #else
        return image.pngData()
        #endif
    }

    static func jpegData(from image: PlatformImage, compressionQuality: CGFloat = 0.85) -> Data? {
        #if os(macOS)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
        #else
        return image.jpegData(compressionQuality: compressionQuality)
        #endif
    }

    static func pixelSize(of image: PlatformImage) -> (width: Int, height: Int)? {
        #if os(macOS)
        if let rep = image.representations.max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }),
           rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return (rep.pixelsWide, rep.pixelsHigh)
        }
        if image.size.width > 0, image.size.height > 0 {
            return (Int(image.size.width.rounded()), Int(image.size.height.rounded()))
        }
        return nil
        #else
        if let cg = image.cgImage {
            return (cg.width, cg.height)
        }
        let w = Int((image.size.width * image.scale).rounded())
        let h = Int((image.size.height * image.scale).rounded())
        return (w > 0 && h > 0) ? (w, h) : nil
        #endif
    }

    #if os(iOS)
    /// Pure-Swift minimal SVG rasterizer for QR codes (`<rect>` and `<path>` M/m/L/l/H/h/V/v/Z/z).
    /// Zalo's web runtime occasionally emits SVG QR codes before canvas rasterization completes.
    static func decodeSVG(data: Data) -> UIImage? {
        guard let raw = String(data: data, encoding: .utf8),
              raw.localizedCaseInsensitiveContains("<svg") else { return nil }

        let viewBox = parseViewBox(in: raw) ?? CGRect(x: 0, y: 0, width: 256, height: 256)
        guard viewBox.width > 0, viewBox.height > 0 else { return nil }

        let targetSize = CGSize(width: 512, height: 512)
        let scaleX = targetSize.width / viewBox.width
        let scaleY = targetSize.height / viewBox.height

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        var drewShape = false
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: targetSize))
            cg.translateBy(x: -viewBox.minX * scaleX, y: -viewBox.minY * scaleY)
            cg.scaleBy(x: scaleX, y: scaleY)

            // Draw <rect .../>
            let rectPattern = #"<rect\b([^>]*)/?>"#
            if let regex = try? NSRegularExpression(pattern: rectPattern, options: [.caseInsensitive]) {
                let ns = raw as NSString
                for match in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
                    let attrs = ns.substring(with: match.range(at: 1))
                    let x = parseAttrNumber("x", in: attrs) ?? 0
                    let y = parseAttrNumber("y", in: attrs) ?? 0
                    let w = parseAttrNumber("width", in: attrs) ?? 0
                    let h = parseAttrNumber("height", in: attrs) ?? 0
                    guard w > 0, h > 0 else { continue }
                    let fill = parseFillColor(in: attrs) ?? UIColor.black
                    cg.setFillColor(fill.cgColor)
                    cg.fill(CGRect(x: x, y: y, width: w, height: h))
                    drewShape = true
                }
            }

            // Draw <path d="..." .../>
            let pathPattern = #"<path\b([^>]*)/?>"#
            if let regex = try? NSRegularExpression(pattern: pathPattern, options: [.caseInsensitive]) {
                let ns = raw as NSString
                for match in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
                    let attrs = ns.substring(with: match.range(at: 1))
                    guard let d = parseAttrString("d", in: attrs),
                          let bezier = parseSVGPath(d) else { continue }
                    let fill = parseFillColor(in: attrs) ?? UIColor.black
                    if fill == UIColor.clear { continue }
                    cg.saveGState()
                    cg.addPath(bezier.cgPath)
                    cg.setFillColor(fill.cgColor)
                    cg.fillPath(using: .evenOdd)
                    cg.restoreGState()
                    drewShape = true
                }
            }
        }
        return drewShape ? image : nil
    }

    private static func parseViewBox(in svg: String) -> CGRect? {
        if let vb = parseAttrString("viewBox", in: svg) {
            let nums = vb.split { $0 == " " || $0 == "," || $0 == "\t" || $0 == "\n" }
                .compactMap { Double($0) }
            if nums.count == 4, nums[2] > 0, nums[3] > 0 {
                return CGRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])
            }
        }
        if let w = parseAttrNumber("width", in: svg),
           let h = parseAttrNumber("height", in: svg), w > 0, h > 0 {
            return CGRect(x: 0, y: 0, width: w, height: h)
        }
        return nil
    }

    private static func parseAttrString(_ name: String, in text: String) -> String? {
        let pattern = #"\b\#(name)\s*=\s*["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func parseAttrNumber(_ name: String, in text: String) -> CGFloat? {
        guard let str = parseAttrString(name, in: text) else { return nil }
        let cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "px", with: "")
        guard let value = Double(cleaned) else { return nil }
        return CGFloat(value)
    }

    private static func parseFillColor(in attrs: String) -> UIColor? {
        guard let fill = parseAttrString("fill", in: attrs)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }
        switch fill {
        case "none", "transparent": return .clear
        case "white", "#fff", "#ffffff": return .white
        case "black", "#000", "#000000": return .black
        default:
            if fill.hasPrefix("#"), fill.count == 7, let hex = UInt32(fill.dropFirst(), radix: 16) {
                return UIColor(
                    red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1
                )
            }
            return .black
        }
    }

    private static func parseSVGPath(_ d: String) -> UIBezierPath? {
        let scannerPattern = #"[MmLlHhVvZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: scannerPattern) else { return nil }
        let ns = d as NSString
        let tokens = regex.matches(in: d, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range)
        }
        guard !tokens.isEmpty else { return nil }

        let path = UIBezierPath()
        var i = 0
        var cmd: Character = "M"
        var cur = CGPoint.zero
        var start = CGPoint.zero

        func nextNum() -> CGFloat? {
            guard i < tokens.count, let v = Double(tokens[i]) else { return nil }
            i += 1
            return CGFloat(v)
        }

        while i < tokens.count {
            let tok = tokens[i]
            if tok.count == 1, let ch = tok.first, "MmLlHhVvZz".contains(ch) {
                cmd = ch
                i += 1
                if cmd == "Z" || cmd == "z" {
                    path.close()
                    cur = start
                }
                continue
            }

            switch cmd {
            case "M", "m":
                guard let x = nextNum(), let y = nextNum() else { break }
                let pt = cmd == "m" ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                path.move(to: pt)
                cur = pt
                start = pt
                cmd = (cmd == "m") ? "l" : "L"
            case "L", "l":
                guard let x = nextNum(), let y = nextNum() else { break }
                let pt = cmd == "l" ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                path.addLine(to: pt)
                cur = pt
            case "H", "h":
                guard let x = nextNum() else { break }
                let pt = CGPoint(x: cmd == "h" ? cur.x + x : x, y: cur.y)
                path.addLine(to: pt)
                cur = pt
            case "V", "v":
                guard let y = nextNum() else { break }
                let pt = CGPoint(x: cur.x, y: cmd == "v" ? cur.y + y : y)
                path.addLine(to: pt)
                cur = pt
            default:
                i += 1
            }
        }
        return path.isEmpty ? nil : path
    }
    #endif
}

enum PlatformPasteboard {
    static func setString(_ string: String) {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    static func string() -> String? {
        #if os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return UIPasteboard.general.string
        #endif
    }

    static func setImage(_ image: PlatformImage) {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        #else
        UIPasteboard.general.image = image
        #endif
    }

    static func setPNGData(_ data: Data) {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)
        #else
        if let image = UIImage(data: data) {
            UIPasteboard.general.image = image
        }
        #endif
    }
}

@MainActor
enum PlatformApp {
    static var isActive: Bool {
        #if os(macOS)
        return NSApp.isActive
        #else
        return UIApplication.shared.applicationState == .active
        #endif
    }

    static var willTerminateNotification: Notification.Name {
        #if os(macOS)
        return NSApplication.willTerminateNotification
        #else
        return UIApplication.willTerminateNotification
        #endif
    }

    static var didBecomeActiveNotification: Notification.Name {
        #if os(macOS)
        return NSApplication.didBecomeActiveNotification
        #else
        return UIApplication.didBecomeActiveNotification
        #endif
    }

    static var didReceiveMemoryWarningNotification: Notification.Name? {
        #if os(macOS)
        return nil
        #else
        return UIApplication.didReceiveMemoryWarningNotification
        #endif
    }

    static var systemUsername: String {
        #if os(macOS)
        return NSUserName()
        #else
        return "mobile"
        #endif
    }

    @discardableResult
    static func openURL(_ url: URL) -> Bool {
        #if os(macOS)
        return NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        return true
        #endif
    }

    static func openNotificationSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        #else
        let target = UIApplication.openNotificationSettingsURLString
        if let url = URL(string: target) {
            UIApplication.shared.open(url)
        } else if let settings = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settings)
        }
        #endif
    }

    static func revealFile(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #else
        NotificationCenter.default.post(name: .olazShareFileRequested, object: url)
        #endif
    }

    static func setBadgeCount(_ count: Int) {
        #if os(macOS)
        NSApp.dockTile.badgeLabel = count <= 0 ? nil : (count > 5 ? "5+" : "\(count)")
        #else
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(max(0, count))
        }
        #endif
    }
}
