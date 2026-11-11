import Cocoa

/// kghostty: rename user-visible "Ghostty" strings in the main menu to
/// "KGhostty" at runtime. Doing this here instead of editing MainMenu.xib
/// keeps merges with upstream simple.
enum KGhosttyBranding {
    static let name = "KGhostty"

    static func applyToMainMenu() {
        guard let menu = NSApp.mainMenu else { return }
        rename(menu)
    }

    private static func rename(_ menu: NSMenu) {
        menu.title = rebrand(menu.title)
        for item in menu.items {
            item.title = rebrand(item.title)
            if let submenu = item.submenu { rename(submenu) }
        }
    }

    /// Replaces "Ghostty" with "KGhostty", leaving already renamed text alone.
    static func rebrand(_ text: String) -> String {
        text.replacingOccurrences(
            of: "(?<!K)Ghostty",
            with: name,
            options: .regularExpression)
    }
}
