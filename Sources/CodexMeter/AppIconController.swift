import AppKit

@MainActor
final class AppIconController {
    static let shared = AppIconController()
    private var appearanceObservation: NSKeyValueObservation?

    func start() {
        updateIcon()
        guard appearanceObservation == nil else { return }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
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
        image.isTemplate = false
        NSApp.applicationIconImage = image
    }
}

final class CodexMeterAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIconController.shared.start()
    }
}
