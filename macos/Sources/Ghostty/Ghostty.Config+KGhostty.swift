import GhosttyKit

// kghostty: accessors for fork-specific configuration options. These live in
// a separate file to keep merges with upstream's Ghostty.Config.swift simple.
extension Ghostty.Config {
    var quickTerminalNormalWindow: Bool {
        guard let config = self.config else { return false }
        var v = false
        let key = "quick-terminal-normal-window"
        _ = ghostty_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
        return v
    }

    var quickTerminalTabs: Bool {
        guard let config = self.config else { return false }
        var v = false
        let key = "quick-terminal-tabs"
        _ = ghostty_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
        return v
    }
}
