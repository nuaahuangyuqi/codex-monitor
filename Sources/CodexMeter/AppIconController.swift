import AppKit

@MainActor
final class AppIconController {
    static let shared = AppIconController()
    private var appearanceObservation: NSKeyValueObservation?

    func start() {
        // macOS 26 会从 bundle 图标自动生成 Dark/Clear/Tinted 外观。
        // 不在运行时覆盖 applicationIconImage，以免阻断系统外观。
        if #available(macOS 26.0, *) { return }
        guard appearanceObservation == nil else { return }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { _, _ in
            Task { @MainActor in AppIconController.shared.updateIcon() }
        }
    }

    private func updateIcon() {
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
        NSApp.applicationIconImage = image
    }
}

final class CodexMeterAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIconController.shared.start()
    }
}
