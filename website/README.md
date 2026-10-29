# MosaClip website

Bilingual product site for MosaClip 0.5.0, published at
https://mumulei.dpdns.org/mosaclip/ through Portfolio-2's existing Cloudflare Pages.

```sh
npm ci
npm run dev -- --host 127.0.0.1
VITE_BASE_PATH=/mosaclip/ npm run build
npm run test:sites
```

Use `npx vite build --base=/mosaclip/` for the static client build; it produces
dist/client, which is copied to the hosting repository's public/mosaclip directory.
The existing Sites adapter remains available but is not used for this deployment.

Preserve approved responsive typography, light/dark/system themes, language switch,
native screenshot carousel, reduced motion and keyboard dialog behavior. All app
screenshots use demonstration content; do not publish user clipboard data.

The primary acquisition action explains the source-release status and links to
the public repository. A production DMG will only be linked after the existing
Developer ID/notarization pipeline passes. Fonts load from Xiaomi's MiSans CDN;
other website artwork and UI icons are local assets. No clipboard access or analytics.
