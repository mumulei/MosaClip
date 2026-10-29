# Distribution

Source release: 0.5.0. Requires macOS 14 or later.

Public source availability and production binary certification are separate.
Developer ID/notarization credentials are not configured for this release, so
0.5.0 publishes source and build instructions; no public production DMG is offered.
The maintainer has explicitly authorized a separately labelled ad-hoc 0.5.0 test
DMG on the prerelease page. It is not Developer ID signed or notarized and may be
blocked by macOS. This specific test distribution does not relax production gates.

## Local QA

```sh
make package VERSION=0.5.0 ARCH=arm64 SIGNING_MODE=adhoc \
  DIST_DIR="dist/qa/<source-sha>-<candidate>"
```

Keep exact App/DMG, SHA-256 checksums, source provenance and test logs together.
Never overwrite an accepted candidate or rebuild it to promote different bytes.
Ad-hoc artifacts are for local QA by default and are not notarized production
packages. The explicit 0.5.0 test-prerelease exception above retains that distinction.

## Production pipeline

The existing `.github/scripts/ci-build-dmg.sh` and manually dispatched
`.github/workflows/build-sign.yml` implement fail-closed production validation:

1. Genuine Developer ID Application identity and Team ID validation.
2. App/helper signing with hardened runtime, secure timestamp and safe entitlements.
3. DMG creation and signature validation.
4. Apple notarytool submission; only Accepted may proceed.
5. Stapling and validation.
6. Gatekeeper and quarantine assessment, then final artifact checksums.

Configure the secret names documented in build-sign.yml only through repository
secret storage. Never commit certificates, private keys, passwords or API tokens.
Do not replace missing credentials with self-signed identities, remove quarantine,
disable Gatekeeper or weaken pipeline gates.

Optional launch smoke is restricted to GitHub-hosted runners. Foundation storage
paths resolve against the actual user home; changing HOME does not isolate user
data. Never run an allegedly isolated smoke on local or self-hosted machines.

The pipeline does not publish a Release or enable the online updater. Updates stay
disabled until certified production delivery and authenticated update metadata
are implemented and validated separately.
