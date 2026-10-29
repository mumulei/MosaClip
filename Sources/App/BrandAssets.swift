import AppKit

enum MenuBarIconState: CaseIterable {
    case normal
    case paused
    case relay
}

@MainActor
enum BrandAssets {
    static let logoResourceName = "logo_icon"

    static var logoIcon: NSImage? {
        loadImage(named: logoResourceName, template: true)
    }

    static func menuBarIcon(for state: MenuBarIconState) -> NSImage? {
        guard let image = loadImage(named: resourceName(for: state), template: true) else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    static func resourceName(for state: MenuBarIconState) -> String {
        switch state {
        case .normal:
            return "menu_normal"
        case .paused:
            return "menu_paused"
        case .relay:
            return "menu_relay"
        }
    }

    private static func loadImage(named name: String, template: Bool) -> NSImage? {
        guard let url = Bundle.pasteMemoResources.url(
            forResource: name,
            withExtension: "pdf",
            subdirectory: "Resources/Brand"
        ), let source = NSImage(contentsOf: url), let image = source.copy() as? NSImage else {
            return nil
        }
        image.isTemplate = template
        return image
    }
}
