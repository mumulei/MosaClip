# MosaClip website

Bilingual product site for MosaClip 0.5.0, published at
https://mosaclip.vercel.app/ on Vercel. Portfolio-2 links to this standalone site.

```sh
npm ci
npm run dev -- --host 127.0.0.1
npm run build
npm run test:sites
```

The static client build produces `dist/client` for Vercel.
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
The old portfolio `/mosaclip/` address redirects to the standalone site.
