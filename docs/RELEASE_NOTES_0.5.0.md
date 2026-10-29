# MosaClip 0.5.0

First public test release of the MosaClip clipboard workspace.

- Public repository and bilingual product website, with MosaClip links and upstream attribution.
- Card/list workspace with contiguous deletion compaction and restored image thumbnails.
- Rendered/raw Markdown and SVG detail, code/color/image previews and local search.
- Adapted storage management, original-image backups, OCR/extraction and automation output destinations.
- Settings branding cleanup and version information in the About header.
- Ten rounded ICNS representations with transparent margins for older macOS icon presentation.

Minimum macOS: 14. Source version: 0.5.0. No storage-schema change from the
0.4.7 MosaClip baseline. Public code is complete and includes tests/build scripts.

An Apple Silicon test DMG is available, explicitly authorized by the maintainer.
It uses ad-hoc signing, without Developer ID signing or Apple notarization. macOS
may block its first launch. It is not a production-certified installer; check the
SHA256SUMS attachment before use. Public binaries keep the standard bundle ID
`com.mumulei.mosaclip` for compatibility with existing installations.

Website refinements include repeatable entrance animation, theme-safe screenshot
clipping, more mobile illustration spacing, direct installer download, and a
new-tab portfolio card. README defaults to Chinese with an English counterpart.

Production certification remains pending. macOS 14 Finder/Dock appearance, cross-app paste, global
hotkeys and system Shortcuts execution still require acceptance on target systems.
