import AppKit
import CoreGraphics
import Foundation

enum ScreenshotError: LocalizedError {
    case missingScreenCapturePermission
    case couldNotCaptureDisplay
    case couldNotEncodePNG

    var errorDescription: String? {
        switch self {
        case .missingScreenCapturePermission:
            "Screen Recording permission is required before NeekShot can capture the screen."
        case .couldNotCaptureDisplay:
            "The main display could not be captured."
        case .couldNotEncodePNG:
            "The screenshot could not be encoded as a PNG."
        }
    }
}

struct ScreenshotResult: @unchecked Sendable {
    let fileURL: URL
    let image: CGImage
    let capturedAt: Date

    var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }
}

final class ScreenshotService: @unchecked Sendable {
    private let fileManager: FileManager
    private let outputDirectory: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let picturesDirectory = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
        outputDirectory = (picturesDirectory ?? fileManager.homeDirectoryForCurrentUser)
            .appendingPathComponent("NeekShot", isDirectory: true)
    }

    func captureMainDisplay() throws -> ScreenshotResult {
        guard ScreenPermissionService.hasScreenCaptureAccess else {
            throw ScreenshotError.missingScreenCapturePermission
        }

        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
            throw ScreenshotError.couldNotCaptureDisplay
        }

        let capturedAt = Date()
        let bitmap = NSBitmapImageRep(cgImage: image)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.couldNotEncodePNG
        }

        try fileManager.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let fileURL = outputDirectory.appendingPathComponent(Self.fileName(for: capturedAt))
        try pngData.write(to: fileURL, options: .atomic)

        return ScreenshotResult(fileURL: fileURL, image: image, capturedAt: capturedAt)
    }

    @MainActor
    func copyToClipboard(_ image: CGImage) {
        let pasteboardImage = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([pasteboardImage])
    }

    private static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        return "NeekShot \(formatter.string(from: date)).png"
    }
}
