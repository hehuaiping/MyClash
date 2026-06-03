# MyClash Packaging

This directory contains the minimal metadata used by `scripts/package-myclash.sh` to assemble a distributable macOS app bundle from the Swift Package executables.

## Local package

```sh
scripts/package-myclash.sh
```

The default build creates `dist/MyClash.app`, applies ad-hoc signing, verifies the signature, and writes a zip archive under `dist/`.

To create a DMG installer with a drag-to-Applications layout:

```sh
scripts/package-dmg.sh
```

## Developer ID package

```sh
MYCLASH_SIGN_IDENTITY="Developer ID Application: Example Team (TEAMID)" \
MYCLASH_NOTARIZE=1 \
MYCLASH_NOTARY_PROFILE="notarytool-profile" \
scripts/package-myclash.sh
```

`MYCLASH_NOTARY_PROFILE` must already exist in the local keychain through `xcrun notarytool store-credentials`.

## Useful variables

- `MYCLASH_VERSION`: app marketing version, default `0.3.0`.
- `MYCLASH_BUILD_NUMBER`: build number, default UTC-like timestamp from the local machine.
- `MYCLASH_BUNDLE_ID`: bundle identifier, default `com.myclash.desktop`.
- `MYCLASH_SIGN_IDENTITY`: Developer ID signing identity. Empty means ad-hoc signing unless disabled.
- `MYCLASH_AD_HOC_SIGN`: set to `0` to skip ad-hoc signing when no identity is present.
- `MYCLASH_NOTARIZE`: set to `1` to submit the zip to Apple notarization.
- `MYCLASH_NOTARY_PROFILE`: notarytool keychain profile name.
- `MYCLASH_DMG_CUSTOMIZE_FINDER`: set to `0` to skip Finder window customization for headless CI runners.
