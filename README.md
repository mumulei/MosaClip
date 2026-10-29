# MosaClip

<img src="docs/assets/mosaclip-app-icon.png" width="88" height="88" alt="MosaClip app icon">

**A local clipboard workspace for macOS.**

Keep copied text, images, links and files together. Find a fragment in the card grid,
read it in the detail pane, then copy, paste or transform it while preserving the original.

[简体中文](README_zh.md) · [Downloads](https://github.com/mumulei/MosaClip/releases) · [Report an issue](https://github.com/mumulei/MosaClip/issues)

![MosaClip card workspace with Markdown preview](docs/assets/mosaclip-workspace.png)

## From history to a workspace

MosaClip is a macOS clipboard manager derived from PasteMemo. It keeps the original
clipboard, search, OCR and paste foundation, and adds a workspace for reviewing and
working with saved content.

| Area | What you can do |
| --- | --- |
| History | Capture text, images, files and rich text; search history; filter by content type or source app; pin frequently used items. |
| Workspace | Switch between a compact card grid and native list, select multiple items, and inspect content alongside history. Deletion compacts the grid. |
| Previews | Read Markdown in rendered or raw form, inspect SVG and source, highlight code, view color swatches, zoom images and preview supported media/files. |
| Quick Panel | Open history with a global shortcut, search and paste with the keyboard, or use quick actions. |
| Relay | Queue several items, split text into a queue and paste entries in sequence. |
| OCR & extraction | Recognize text in images, paste recognized text, and extract links or verification codes from supported content. |
| Automation | Run rules automatically or manually; clean URLs, transform text, set metadata and choose output destinations such as a new history item, folder or configured Webhook. |
| Storage | Review usage by source/type/time, clean stored history, convert TIFF originals to PNG losslessly, and import/export backups with original images. |
| Privacy | Ignore selected apps, mask sensitive items, configure history retention and sensitive-item expiry, and pause capture. |
| Integrations | Opt into a local MCP bridge for compatible agent clients, or use the packaged macOS App Intents. |

### Read the content, keep the original

The main-window detail pane supports Markdown rendering, code highlighting and SVG
inspection. Previews do not replace the raw clipboard payload used by copy/paste.
Markdown and SVG previews do not automatically fetch remote resources.

![MosaClip code detail](docs/assets/mosaclip-code.png)

![MosaClip SVG detail](docs/assets/mosaclip-svg.png)

These are MosaClip desktop captures using demonstration content. Quick Panel uses
native/raw text for inline Markdown and OCR; rendered/raw Markdown is in the main window.

## Get started

1. Open MosaClip and choose whether to capture clipboard changes. Review ignored apps
   and retention in Settings before using it with sensitive material.
2. Copy something, then open the workspace to browse cards or switch to the list.
3. Use **⌘⇧V** to open Quick Panel. Search, select an entry and press **Return** to paste.
4. Grant Accessibility access for pasting into other applications. An overwrite
   installation may require renewing that authorization.

### Keyboard basics

These shortcuts apply to Quick Panel unless noted. The global shortcut is configurable.

| Shortcut | Action |
| --- | --- |
| ⌘⇧V | Open/close Quick Panel |
| ↑ / ↓, Ctrl+P / Ctrl+N | Navigate history |
| ⌘1 … ⌘9 | Paste the corresponding item |
| Return | Paste the selected item |
| ⇧Return | Paste and press Return |
| ⌘K | Open quick actions |
| ⌘F | Focus search |
| Esc | Close the panel |

## Source release 0.5.0

[Product website](https://mumulei.dpdns.org/mosaclip/) · [Source release](https://github.com/mumulei/MosaClip/releases/tag/v0.5.0)

Complete source, tests and build instructions are public under GPL-3.0.
Requires macOS 14 or later. Production DMG downloads await Developer ID signing
and Apple notarization. Online updates and anonymous usage statistics remain off.
Back up local history before installing a build. No storage-schema change from
MosaClip 0.4.7. See [release notes](docs/RELEASE_NOTES_0.5.0.md).

## Local data and optional connections

History is stored locally. MosaClip does not bundle a cloud AI provider or automatically
send history to an LLM. **AI Agents** configures the optional local MCP bridge, which is
disabled by default and excludes sensitive items by default. Connected external clients
have their own data handling policies.

Local storage does not mean every feature is offline: webpage previews, links you open,
and Webhook rules you configure can contact their destinations. Review these features
before using them with private content.

## Build & contribute

Use macOS with a Swift 6 compatible toolchain and the macOS SDK. The complete buildable source is public.

```bash
git clone https://github.com/mumulei/MosaClip.git
cd MosaClip
swift build
swift test
make check
```

`make dev` rebuilds and restarts the app after source changes. Create a dedicated topic
branch and follow [AGENTS.md](AGENTS.md).

Package a local QA candidate into an explicit, unused archive directory:

```bash
make package VERSION=0.5.0 ARCH=arm64 SIGNING_MODE=adhoc \
  DIST_DIR="dist/qa/<source-sha>-<candidate-id>"
```

Keep the App, DMG, checksums and provenance together. Do not overwrite an accepted
archive or promote it to root `dist/` by rebuilding. Production distribution requires
the Developer ID, notarization and Gatekeeper workflow in
[MOSACLIP_DISTRIBUTION.md](docs/MOSACLIP_DISTRIBUTION.md).

Further reading: [upstream provenance](docs/UPSTREAM.md),
[third-party notices](THIRD_PARTY_NOTICES.md).

## Thanks to PasteMemo

MosaClip builds on **[PasteMemo by lifedever](https://github.com/lifedever/PasteMemo-app)**.
Thank you to the original author and upstream contributors for making the project open
source and providing its clipboard, persistence, OCR and paste foundation.
MosaClip is an independently maintained derivative.

Licensed under **[GPL-3.0](LICENSE)**. Original copyright and third-party notices are
preserved in the source and app bundle.

© 2026 lifedever and MosaClip contributors.
