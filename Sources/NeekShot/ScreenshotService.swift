import AppKit
import CoreGraphics
import CryptoKit
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

struct CaptureContext: Codable, Sendable {
    let appName: String
    let bundleIdentifier: String?
    let windowTitle: String?

    static let unknown = CaptureContext(
        appName: "Unknown App",
        bundleIdentifier: nil,
        windowTitle: nil
    )

    var filenameSegment: String {
        var parts = [appName]

        if let windowTitle, !windowTitle.isEmpty {
            parts.append(windowTitle)
        }

        return parts
            .map(Self.sanitizedPathComponent)
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
    }

    var folderName: String {
        let sanitized = Self.sanitizedPathComponent(appName)
        return sanitized.isEmpty ? "Unknown App" : sanitized
    }

    private static func sanitizedPathComponent(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)

        let cleaned = value
            .components(separatedBy: invalidCharacters)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.count > 80 else {
            return cleaned
        }

        return String(cleaned.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ScreenshotResult: @unchecked Sendable {
    let fileURL: URL
    let metadataURL: URL
    let image: CGImage
    let capturedAt: Date
    let context: CaptureContext
    let sha256: String

    var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    var markdownSnippet: String {
        var lines = [
            "## Screenshot",
            "",
            "- App: \(context.appName)",
            "- Captured: \(Self.isoString(for: capturedAt))",
            "- Size: \(image.width)x\(image.height)",
            "- File: `\(fileURL.path)`",
            "- SHA-256: `\(sha256)`"
        ]

        if let windowTitle = context.windowTitle, !windowTitle.isEmpty {
            lines.insert("- Window: \(windowTitle)", at: 4)
        }

        return lines.joined(separator: "\n")
    }

    private static func isoString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private struct CaptureManifest: Encodable {
    let capturedAt: String
    let appName: String
    let bundleIdentifier: String?
    let windowTitle: String?
    let pixelWidth: Int
    let pixelHeight: Int
    let fileName: String
    let metadataFileName: String
    let sha256: String
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

    func captureMainDisplay(context: CaptureContext = .unknown) throws -> ScreenshotResult {
        guard ScreenPermissionService.hasScreenCaptureAccess else {
            throw ScreenshotError.missingScreenCapturePermission
        }

        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
            throw ScreenshotError.couldNotCaptureDisplay
        }

        return try save(image: image, capturedAt: Date(), context: context)
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

    @MainActor
    func copyTextToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func save(
        image: CGImage,
        capturedAt: Date,
        context: CaptureContext
    ) throws -> ScreenshotResult {
        let bitmap = NSBitmapImageRep(cgImage: image)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.couldNotEncodePNG
        }

        let contextDirectory = outputDirectory.appendingPathComponent(
            context.folderName,
            isDirectory: true
        )

        try fileManager.createDirectory(
            at: contextDirectory,
            withIntermediateDirectories: true
        )

        let sha256 = SHA256.hash(data: pngData)
            .map { String(format: "%02x", $0) }
            .joined()
        let fileURL = contextDirectory.appendingPathComponent(
            Self.fileName(for: capturedAt, context: context)
        )
        let metadataURL = fileURL
            .deletingPathExtension()
            .appendingPathExtension("capture.json")

        try pngData.write(to: fileURL, options: .atomic)
        try writeManifest(
            to: metadataURL,
            fileURL: fileURL,
            image: image,
            capturedAt: capturedAt,
            context: context,
            sha256: sha256
        )

        return ScreenshotResult(
            fileURL: fileURL,
            metadataURL: metadataURL,
            image: image,
            capturedAt: capturedAt,
            context: context,
            sha256: sha256
        )
    }

    private func writeManifest(
        to metadataURL: URL,
        fileURL: URL,
        image: CGImage,
        capturedAt: Date,
        context: CaptureContext,
        sha256: String
    ) throws {
        let manifest = CaptureManifest(
            capturedAt: Self.isoString(for: capturedAt),
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            windowTitle: context.windowTitle,
            pixelWidth: image.width,
            pixelHeight: image.height,
            fileName: fileURL.lastPathComponent,
            metadataFileName: metadataURL.lastPathComponent,
            sha256: sha256
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: metadataURL, options: .atomic)
    }

    private static func fileName(for date: Date, context: CaptureContext) -> String {
        let contextSegment = context.filenameSegment
        let suffix = contextSegment.isEmpty ? "" : " \(contextSegment)"
        return "NeekShot \(fileDateString(for: date))\(suffix).png"
    }

    private static func fileDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        return formatter.string(from: date)
    }

    private static func isoString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
