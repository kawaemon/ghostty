# kawaemon/ghostty

This is an unofficial personal fork of [Ghostty](https://github.com/ghostty-org/ghostty).
It contains changes that I want, made without coordination with upstream.

- This fork is not affiliated with or endorsed by the Ghostty project.
- Please do not report issues found in this fork to upstream.
- For the original README, see [README.md](../README.md).

## Changes from upstream

- Rename Ghostty to kghostty (app name, bundle ID, and config directory `~/.config/kghostty`) to avoid conflicts with upstream Ghostty.
- Add `quick-terminal-normal-window` to show the quick terminal as a regular movable, resizable window with a titlebar (macOS).
- Add `quick-terminal-tabs` to allow native tabs (`cmd+t`) in that quick terminal window (macOS).
- Allow a per-font `:style=<name>` suffix in `font-family*` and `font-codepoint-map` (e.g. `Hiragino Sans:style=W3`) to override `font-style*` for that font only.
- Honor `quick-terminal-animation-duration` for the normal-window quick terminal as a fade in/out (`0` disables animation).

## License

Ghostty is licensed under the [MIT License](../LICENSE).
Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors.

Changes made in this fork are also provided under the MIT License.
