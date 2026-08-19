import AppKit
import CoreGraphics

enum CaptureError: LocalizedError {
    case chromeNotFrontmost, chromeWindowNotFound, captureFailed
    var errorDescription: String? {
        switch self { case .chromeNotFrontmost: "Make Chrome the active app, then try again."
        case .chromeWindowNotFound: "No visible Chrome window was found."
        case .captureFailed: "Chart capture failed. Check Screen Recording permission." }
    }
}

struct ChromeCaptureService {
    func captureActiveChromeChart() throws -> NSImage {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome" else { throw CaptureError.chromeNotFrontmost }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
              let window = info.first(where: { ($0[kCGWindowOwnerName as String] as? String) == "Google Chrome" && (($0[kCGWindowLayer as String] as? Int) ?? 1) == 0 }),
              let id = window[kCGWindowNumber as String] as? CGWindowID,
              let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]) else { throw CaptureError.chromeWindowNotFound }
        let cropped = ChartCropper.crop(image)
        return NSImage(cgImage: cropped, size: .init(width: cropped.width, height: cropped.height))
    }
}

enum ChartCropper {
    static func crop(_ image: CGImage) -> CGImage {
        // Removes Chrome's tab/address strip and a narrow price-scale/sidebar edge.
        let top = Int(Double(image.height) * 0.12)
        let right = Int(Double(image.width) * 0.06)
        let rect = CGRect(x: 0, y: 0, width: max(1, image.width - right), height: max(1, image.height - top))
        return image.cropping(to: rect) ?? image
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation, let rep = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
