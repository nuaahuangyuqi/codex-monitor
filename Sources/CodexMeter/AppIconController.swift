import AppKit

@MainActor
final class AppIconController {
    static let shared = AppIconController()
    private var appearanceObservation: NSKeyValueObservation?

    func installBundleIconBeforeLaunch() {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else { return }
        image.isTemplate = false
        NSApp.applicationIconImage = image
    }

    func startAppearanceObservation() {
        // macOS 26 由系统根据 bundle 图标生成平台外观；不要在启动后
        // 用单张 PNG 覆盖 Stage Manager 和 Dock 已注册的应用图标。
        if #available(macOS 26.0, *) { return }
        updateLegacyIcon()
        guard appearanceObservation == nil else { return }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            Task { @MainActor in AppIconController.shared.updateLegacyIcon() }
        }
    }

    private func updateLegacyIcon() {
        let match = NSApp.effectiveAppearance.bestMatch(from: [
            .accessibilityHighContrastDarkAqua,
            .accessibilityHighContrastAqua,
            .darkAqua,
            .aqua
        ])
        let resource: String
        switch match {
        case .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua:
            resource = "AppIconMono"
        case .darkAqua:
            resource = "AppIconDark"
        default:
            resource = "AppIconDefault"
        }
        guard let url = Bundle.main.url(
            forResource: resource,
            withExtension: "png",
            subdirectory: "AppIcon"
        ), let image = NSImage(contentsOf: url) else { return }
        image.isTemplate = false
        NSApp.applicationIconImage = image
    }
}

final class CodexMeterAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppIconController.shared.installBundleIconBeforeLaunch()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIconController.shared.startAppearanceObservation()
    }
}
