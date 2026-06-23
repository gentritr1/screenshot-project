import AppKit
import CoreGraphics
import Foundation

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let screenshotService: ScreenshotService
    private let hotKeyController: HotKeyController

    private let captureItem = NSMenuItem()
    private let statusItemText = NSMenuItem()
    private let lastCaptureItem = NSMenuItem()
    private let revealLastItem = NSMenuItem()
    private let copyLastPathItem = NSMenuItem()
    private let copyLastMarkdownItem = NSMenuItem()
    private var isCapturing = false
    private var lastScreenshot: ScreenshotResult?
    private var resetStatusWorkItem: DispatchWorkItem?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        screenshotService = ScreenshotService()
        hotKeyController = HotKeyController()

        super.init()

        configureStatusItem()
        configureMenu()
        registerHotKey()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(
            systemSymbolName: "camera.viewfinder",
            accessibilityDescription: "NeekShot"
        )
        button.toolTip = "NeekShot"
    }

    private func configureMenu() {
        let menu = NSMenu()

        captureItem.title = "Capture Now"
        captureItem.target = self
        captureItem.action = #selector(captureNowFromMenu)
        captureItem.keyEquivalent = ""
        menu.addItem(captureItem)

        let shortcutItem = NSMenuItem(
            title: "Hotkey: \(HotKeyController.defaultShortcutDescription)",
            action: nil,
            keyEquivalent: ""
        )
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)

        statusItemText.title = "Ready"
        statusItemText.isEnabled = false
        menu.addItem(statusItemText)

        menu.addItem(.separator())

        lastCaptureItem.title = "Last: None"
        lastCaptureItem.isEnabled = false
        menu.addItem(lastCaptureItem)

        revealLastItem.title = "Reveal Last Capture"
        revealLastItem.target = self
        revealLastItem.action = #selector(revealLastCapture)
        revealLastItem.keyEquivalent = ""
        revealLastItem.isEnabled = false
        menu.addItem(revealLastItem)

        copyLastPathItem.title = "Copy Last Path"
        copyLastPathItem.target = self
        copyLastPathItem.action = #selector(copyLastPath)
        copyLastPathItem.keyEquivalent = ""
        copyLastPathItem.isEnabled = false
        menu.addItem(copyLastPathItem)

        copyLastMarkdownItem.title = "Copy Bug Report Markdown"
        copyLastMarkdownItem.target = self
        copyLastMarkdownItem.action = #selector(copyLastMarkdown)
        copyLastMarkdownItem.keyEquivalent = ""
        copyLastMarkdownItem.isEnabled = false
        menu.addItem(copyLastMarkdownItem)

        menu.addItem(.separator())

        let openFolderItem = NSMenuItem(
            title: "Open Screenshots Folder",
            action: #selector(openScreenshotsFolder),
            keyEquivalent: ""
        )
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        let permissionItem = NSMenuItem(
            title: "Request Screen Recording Permission",
            action: #selector(requestScreenCapturePermission),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)

        let settingsItem = NSMenuItem(
            title: "Open Screen Recording Settings",
            action: #selector(openScreenCaptureSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit NeekShot",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func registerHotKey() {
        do {
            try hotKeyController.registerDefault { [weak self] in
                DispatchQueue.main.async {
                    self?.captureNow(reason: "hotkey")
                }
            }
        } catch {
            setStatus("Hotkey unavailable")
            NSLog("NeekShot hotkey registration failed: \(error.localizedDescription)")
        }
    }

    @objc private func captureNowFromMenu() {
        captureNow(reason: "menu")
    }

    private func captureNow(reason: String) {
        guard !isCapturing else {
            setStatus("Capture already running")
            return
        }

        guard ScreenPermissionService.hasScreenCaptureAccess else {
            setStatus("Permission required")
            ScreenPermissionService.requestScreenCaptureAccess()
            return
        }

        isCapturing = true
        captureItem.isEnabled = false
        setStatus("Capturing...")

        let context = currentCaptureContext()

        DispatchQueue.global(qos: .userInitiated).async { [screenshotService] in
            let result = Result {
                try screenshotService.captureMainDisplay(context: context)
            }

            DispatchQueue.main.async { [weak self] in
                self?.finishCapture(result)
            }
        }
    }

    private func finishCapture(_ result: Result<ScreenshotResult, Error>) {
        isCapturing = false
        captureItem.isEnabled = true

        switch result {
        case .success(let screenshot):
            Task { @MainActor in
                lastScreenshot = screenshot
                updateLastCaptureItems()
                screenshotService.copyToClipboard(screenshot.image)
                setStatus("Saved \(screenshot.context.appName) and copied")
            }
        case .failure(let error):
            setStatus("Capture failed")
            NSLog("NeekShot capture failed: \(error.localizedDescription)")
        }
    }

    private func setStatus(_ text: String) {
        resetStatusWorkItem?.cancel()
        statusItemText.title = text
        statusItem.button?.toolTip = "NeekShot - \(text)"

        guard text != "Ready" else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.statusItemText.title = "Ready"
            self?.statusItem.button?.toolTip = "NeekShot"
        }

        resetStatusWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    private func currentCaptureContext() -> CaptureContext {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .unknown
        }

        let appName = app.localizedName ?? "Unknown App"

        return CaptureContext(
            appName: appName,
            bundleIdentifier: app.bundleIdentifier,
            windowTitle: frontWindowTitle(for: app.processIdentifier)
        )
    }

    private func frontWindowTitle(for processIdentifier: pid_t) -> String? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard
                let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                ownerPID == Int(processIdentifier),
                let layer = window[kCGWindowLayer as String] as? Int,
                layer == 0
            else {
                continue
            }

            let title = window[kCGWindowName as String] as? String
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
        }

        return nil
    }

    private func updateLastCaptureItems() {
        guard let screenshot = lastScreenshot else {
            lastCaptureItem.title = "Last: None"
            revealLastItem.isEnabled = false
            copyLastPathItem.isEnabled = false
            copyLastMarkdownItem.isEnabled = false
            return
        }

        lastCaptureItem.title = "Last: \(screenshot.context.appName) · \(screenshot.pixelSizeDescription)"
        revealLastItem.isEnabled = true
        copyLastPathItem.isEnabled = true
        copyLastMarkdownItem.isEnabled = true
    }

    @objc private func openScreenshotsFolder() {
        let folder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NeekShot", isDirectory: true)
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("NeekShot", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(folder)
    }

    @objc private func revealLastCapture() {
        guard let lastScreenshot else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([lastScreenshot.fileURL])
    }

    @objc private func copyLastPath() {
        guard let lastScreenshot else {
            return
        }

        screenshotService.copyTextToClipboard(lastScreenshot.fileURL.path)
        setStatus("Copied last path")
    }

    @objc private func copyLastMarkdown() {
        guard let lastScreenshot else {
            return
        }

        screenshotService.copyTextToClipboard(lastScreenshot.markdownSnippet)
        setStatus("Copied bug report Markdown")
    }

    @objc private func requestScreenCapturePermission() {
        ScreenPermissionService.requestScreenCaptureAccess()
    }

    @objc private func openScreenCaptureSettings() {
        ScreenPermissionService.openScreenCaptureSettings()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private extension ScreenshotResult {
    var pixelSizeDescription: String {
        "\(image.width)x\(image.height)"
    }
}
