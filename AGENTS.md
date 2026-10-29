# MosaClip contributor instructions

MosaClip is a GPL-3.0 macOS clipboard workspace derived from PasteMemo.
Upstream and imported-source provenance are recorded in docs/UPSTREAM.md.

- Inspect Git status/branch/HEAD first. Use a task branch; do not develop on main.
- Preserve raw clipboard payloads. Previews must not change copy/paste semantics.
- Do not rewrite clipboard, storage or OCR core just to support UI changes.
- Keep heavy preview/image/OCR work out of the synchronous capture path.
- Preserve the fixed-height card grid and native list fallback; validate layout
  changes in a running macOS App, not by compilation alone.
- Keep main-window Markdown rendered/raw modes. The long-lived Quick Panel uses
  native/raw text for inline Markdown/OCR; do not mount a persistent MarkdownUI
  hierarchy there. Markdown files keep their normal file preview.
- Markdown/SVG previews must not fetch remote resources automatically.
- Preserve sensitive-content masking, ignored-app policy and local MCP privacy.
- No cloud AI pipeline. No unreviewed dependencies or deployment-target increases.
- Never overwrite unknown user changes or publish local data, credentials, QA
  captures, logs or backup files. Website screenshots must use safe demo content.
- Build/test with SwiftPM; run make check for repository checks. Report exact
  commands/results and distinguish automated checks from runtime/manual acceptance.
- Builds belong in an explicit unused dist/qa/<source-sha>-<candidate> directory
  or /tmp for experiments. Preserve App, DMG, hashes and provenance together.
- Production DMGs require Developer ID, hardened runtime, notarization Accepted,
  stapling and Gatekeeper verification through the existing pipeline. Ad-hoc
  packages are normally local QA only; never bypass Gatekeeper/quarantine to claim a pass.
  The maintainer explicitly authorized a public ad-hoc 0.5.0 test prerelease.
  Keep its uncertified status visible; this does not waive production gates or
  authorize automatic publishing or other ad-hoc releases.
- Online updates and analytics stay disabled. Making the repository public does
  not authorize enabling an updater or bypassing certification.
- Do not merge, push, release, change remotes or migrate storage without task
  authorization. Retain GPL, upstream attribution and third-party notices.

Website: preserve the approved layout, bilingual copy, themes, native screenshots,
keyboard accessibility and reduced-motion behavior. Base-path deployments must
resolve all images, icons and favicons correctly. See website/README.md.
