# Changelog

All notable changes to Clipward are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-09

First public release.

### Added

- Clipboard history for every data type: plain and rich text, links, images, files, colors and
  app-specific formats, with every format of every item preserved.
- History popup on <kbd>⌥⌘C</kbd>, with search, keyboard navigation, <kbd>⌘1</kbd>–<kbd>⌘9</kbd>
  quick picks, plain-text paste and per-item delete.
- Customisable global shortcut.
- Paste straight into the active app (needs Accessibility access).
- Clipboard auto-clear for items pasted from the history (default 1 minute).
- AES-256 + HMAC-SHA256 encrypted history on disk, with the key stored in the login Keychain, or
  memory-only mode.
- Concealed and transient content from password managers is never recorded; per-app ignore list;
  Pause Recording.
- History size and retention limits.
- Launch at login.
- Universal app for macOS 10.13 and later, distributed as a DMG.

[1.0.0]: https://github.com/ypankovych/clipward/releases/tag/v1.0.0
