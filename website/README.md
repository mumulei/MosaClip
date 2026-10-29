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

The acquisition dialog links directly to the explicitly authorized 0.5.0 ad-hoc
test DMG, with a test-build label, concise installation guidance and a release-notes link. A production
DMG still requires the Developer ID/notarization pipeline. Fonts load from Xiaomi's MiSans CDN;
other website artwork and UI icons are local assets. No clipboard access or analytics.

## Standalone Vercel deployment

Use the repository's `website` directory as the Vercel project root.
`vercel.json` selects Vite, `npm run build`, and the `dist/client` output.
Leave `VITE_BASE_PATH` unset (or `/`) for a standalone root-domain deployment.
The existing portfolio URL remains live until the new production URL has been
verified; update canonical/product links and the portfolio redirect afterward.
