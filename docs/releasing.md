# Releasing Couleur

Couleur is free, with public MIT-licensed source. The native app and releases live in `Aymericr/couleur`. The website lives in the separate `Aymericr/aymeric` repository, deployed by Vercel at **https://aymeric.dev/couleur** behind the existing Cloudflare DNS. No DNS migration is needed.

## What is automated

`scripts/package-release.sh` tests the app, builds both Apple silicon and Intel, embeds Sparkle, signs nested code inside-out with Developer ID and hardened runtime, notarizes and staples the app, creates the update ZIP and drag-to-Applications DMG, notarizes and staples the DMG, then generates the signed appcast, Homebrew cask, and SHA-256 checksums. It verifies the update signature against the **public key embedded in the app**. Any signing or notarization failure stops the pipeline.

`scripts/publish-release.sh VERSION` creates a **draft**, uploads the verified artifacts, downloads them again, and checks their hashes. Add `--publish` to make that draft public. An already-published version cannot be overwritten. The GitHub **Release** workflow combines these steps; leave its Publish checkbox off to review a draft first. Publishing also updates `Casks/couleur.rb` on main.

The website checks public GitHub release metadata every five minutes. It displays a download only when the DMG, update ZIP, appcast, cask, and checksums are present. The Homebrew tap uses the committed cask. Before a complete release is available, the page links to source and says the downloadable release is being prepared. The repositories do not need shared deployment credentials.

## One-time credentials

This checkout has a dedicated Sparkle key in the macOS Keychain under account `com.aymeric.couleur`. Its public half is checked into `Resources/Info.plist`. **Keep and back up the private key. Never regenerate it for an update.** Generating a replacement without a key migration breaks updates from existing installations.

For local releases, install a **Developer ID Application** certificate with its private key, then configure a `notarytool` Keychain profile using your Apple notarization credentials. For example, with an App Store Connect API key that has notarization access:

```sh
xcrun notarytool store-credentials Couleur \
  --key /secure/path/AuthKey.p8 --key-id YOUR_KEY_ID --issuer YOUR_ISSUER_ID
COULEUR_NOTARY_PROFILE=Couleur ./scripts/package-release.sh
```

Do not put Apple passwords, P8/P12 files, or the Sparkle private key in the repository. Distribution never falls back to ad-hoc signing. Ordinary `scripts/build.sh` builds remain usable for local development and do not enable the public updater.

### Personal Apple account

The personal release certificate is **Developer ID Application: Aymeric Rabot (BU849QPYLP)**. Signing and notarization are separate: this certificate signs the app, while a login for the same personal team submits it to Apple. Selecting a certificate does not switch the account used for notarization.

To configure personal notarization without an API key, create an app-specific password at [Apple Account](https://account.apple.com/), then run this in your own Terminal with the Apple ID for your personal developer membership:

```sh
xcrun notarytool store-credentials Couleur \
  --apple-id YOUR_PERSONAL_APPLE_ID --team-id BU849QPYLP
```

Enter the app-specific password at the secure prompt. Do not put it in the command, chat, or shell history. The command validates and saves it in the local Keychain. Then the release pipeline can run:

```sh
COULEUR_SIGN_IDENTITY='Developer ID Application: Aymeric Rabot (BU849QPYLP)' \
COULEUR_NOTARY_PROFILE=Couleur ./scripts/package-release.sh
```

A failed credentials preflight does not reserve the release output directory. This local flow needs no credential export to GitHub. The hosted workflow requires the separate environment setup below.

For hosted releases, create the GitHub Actions **release** environment and add these secrets there:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 export of the Developer ID Application certificate **and its private key** |
| `DEVELOPER_ID_P12_PASSWORD` | Password protecting that export |
| `NOTARY_KEY_P8` | Contents of the Apple notarization API private key |
| `NOTARY_KEY_ID` | Its key ID |
| `NOTARY_ISSUER_ID` | Its issuer ID |
| `SPARKLE_PRIVATE_KEY` | Export of the **existing** Couleur update signing key |

These credentials grant release-signing authority. Transferring them to GitHub is a separate setup step; they are not automatically exported by any repository script. Limit the environment to reviewed releases. The workflow imports Apple signing material into a temporary Keychain and removes that Keychain and temporary key files even on failure.

To export the existing Sparkle key securely for a backup or the GitHub secret, after `swift package resolve`:

```sh
umask 077
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.aymeric.couleur -x /secure/path/couleur-sparkle-key.txt
```

## Each release

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist`. The build number must be greater than every previous public build, including prereleases.
2. Run the regular checks and verify the isolated preview in light/dark appearances. On a release candidate, verify browser provenance under hardened runtime, screen capture, and quit/reopen.
3. Commit and push the reviewed source, then create and push its matching version tag, for example `v1.0.0`. Packaging and publishing require a clean checkout; publication requires HEAD to match the tag.
4. Run the **Release** workflow for that tag. First use a draft. Inspect Apple’s Accepted reports and artifacts. Keep the version’s bytes immutable once published.
5. Publish with the workflow checkbox, or locally use `scripts/publish-release.sh 1.0.0 --publish` on the verified artifacts. A local publication also needs the generated `couleur.rb` copied to `Casks/couleur.rb`, committed and pushed.
6. Verify the website, DMG install on a clean Mac, the custom tap, and a real Sparkle upgrade from the previous public build. CI validates package integrity; it cannot prove an interactive installation or upgrade path.

Artifacts live in `build/releases/VERSION/` (ignored by Git). Notarization reports live in `build/notarization/`. Failed partial output is retained for diagnosis; move it aside before rebuilding. A draft produced on a different CI runner can be rebuilt/replaced while still a draft. Published artifacts cannot.

## Homebrew

The app repository itself is a small custom tap. After the first public release has generated its cask:

```sh
brew tap Aymericr/couleur https://github.com/Aymericr/couleur
brew install --cask Aymericr/couleur/couleur
```

This needs no additional repository, personal access token, or admission to the central Homebrew Cask catalog. The URL, version, and checksum are generated from the final notarized DMG. Normal uninstall preserves the user's color library. No `zap` stanza deletes personal data.

## Updates and privacy

Public distribution builds use Sparkle 2.10.0. The native **Check for Updates…** menu is available; Sparkle asks whether to check automatically using its standard consent flow. Preview and development builds do not start the updater. The feed is `https://github.com/Aymericr/couleur/releases/latest/download/appcast.xml`, independent of the website domain. Sparkle profile reporting is disabled. Screenshots, colors, names, notes, and provenance are never sent to the update service.

## References

- [Sparkle integration](https://sparkle-project.org/documentation/programmatic-setup/) and [publishing](https://sparkle-project.org/documentation/publishing/)
- [Apple notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Homebrew taps](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
