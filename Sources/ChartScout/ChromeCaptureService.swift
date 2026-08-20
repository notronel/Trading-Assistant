import AppKit
import CoreGraphics
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case chromeNotFrontmost, chromeWindowNotFound, captureFailed
    var errorDescription: String? {
        switch self { case .chromeNotFrontmost: "Make Chrome the active app, then try again."
        case .chromeWindowNotFound: "No visible Chrome window was found."
        case .captureFailed: "Chart capture failed. Check Screen Recording permission." }
    }
}

struct ChromeCaptureService {
    func captureActiveChromeChart() async throws -> NSImage {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome" else {
            throw CaptureError.chromeNotFrontmost
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
        } catch {
            throw CaptureError.captureFailed
        }

        guard let window = content.windows.first(where: {
            $0.owningApplication?.bundleIdentifier == "com.google.Chrome" && $0.windowLayer == 0
        }) else {
            throw CaptureError.chromeWindowNotFound
        }

        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * 2))
        configuration.height = max(1, Int(window.frame.height * 2))
        configuration.showsCursor = false

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw CaptureError.captureFailed
        }

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
