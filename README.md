# Couleur

A tiny, floating color picker for macOS. Pick, copy, keep.

A personal replacement for [Couleurs](https://couleursapp.com/), inspired by its compact form factor. Written from scratch in SwiftUI and AppKit, using Apple's native screen sampler. No dependencies, accounts, servers, or network requests.

## Everyday use

The app opens as a **256 × 158 pt floating palette**: a small color well beside a prominent code, with six recent colors below. The surface follows your Mac’s light or dark appearance.

- **Press the color well, hold, drag anywhere on screen, and release** to save and copy the color.
- Alternatively, click the eyedropper, then click a color, or press **⌃⌥C** from any app.
- **Hold Shift when selecting** to keep the sampler open and collect more colors. Release Shift for the final selection, or press **Esc** to finish. Each selected color gets its own history entry; the latest is copied.
- **Click the color code** to copy it again. Click a recent swatch to select and copy it.
- Use the **format menu** beside the code to change its encoding. **Keep on top** is in the same menu.
- The **expand button at the bottom right** unfolds the same window into the full library. The **Compact Picker** toolbar button (or **⌘2**) folds it back to its original position. Search, selection, and sidebar state are preserved. The transition respects **Reduce Motion**.

Automatic copying and keeping the picker on top are enabled initially. The floating window can accompany other apps and full-screen Spaces. Drag the quiet header to move it; the small close button hides it.

## Your color library

Every pick is saved immediately and kept across app restarts, with no history limit. Expand to:

- Give colors names, mark favorites, and organize them into named collections.
- Search by name, HEX, app, window title, source URL, collection, or notes.
- Sort by time, name, or hue.
- Click a library swatch once to select and copy it in your chosen format. A small **Copied** checkmark appears on that swatch for two seconds. Arrow keys browse the selection; **⌘C** copies it.
- Use **⌘F** for toolbar search. Resize or hide the native sidebar and inspector to make more room for colors.
- Adjust a saved color with the native color panel, including opacity.
- See the pick time, source app and bundle ID, display, and screen coordinates.
- Add notes and a source URL by hand.
- Import or export a complete JSON backup through **Library options** or the File menu.

Screen metadata is best effort: the source app is resolved from the frontmost normal window under the pointer. Window titles are only saved when macOS supplies them, and can be absent without Screen Recording permission. Browser URLs are not read automatically. Clipboard imports are labeled as pasted colors. Screen coordinates use the Core Graphics origin at the top-left of the primary display and may be negative on other displays.

The native sampler does not require this app to request Screen Recording or Accessibility access. It displays macOS's magnifying loupe. Canceling with Esc never creates an entry or changes the clipboard. During a Shift session, previously collected colors remain saved when you cancel.

## Copy formats

The chosen format is remembered and used for automatic copying, the main color-code button, recent swatches, and ⌘C when a text field is not editing.

| Format | Example |
| --- | --- |
| HEX | `#E87B65` |
| CSS RGB | `rgb(232 123 101)` |
| CSS HSL | `hsl(10.1 74.0% 65.3%)` |
| CSS OKLCH | `oklch(…% … …)` |
| SwiftUI | `Color(.sRGB, red: …, green: …, blue: …, opacity: …)` |
| AppKit | `NSColor(srgbRed: …, green: …, blue: …, alpha: …)` |
| UIKit | `UIColor(red: …, green: …, blue: …, alpha: …)` |

Colors are converted to standard **sRGB** before storage. Alpha is preserved; HEX includes the final alpha byte for translucent colors. CSS uses modern space-separated syntax. Wide-gamut/HDR colors outside sRGB are clipped to its range. OKLCH output is derived from linearized sRGB through OKLab.

Paste a HEX (3/4/6/8 digits), RGB/RGBA, or HSL/HSLA value through **Paste color from clipboard** or **⌘⇧V**. This is a focused parser for those formats; arbitrary CSS expressions, named colors, and OKLCH input are not supported.

## Install and develop

Requires **macOS 14 or later**, Xcode command-line tools, and a Swift 6 toolchain. Builds for the current Mac's architecture. No package dependencies.

```sh
./scripts/install.sh
```

This builds and ad-hoc signs `Couleur.app`, installs it in `/Applications`, and opens the compact picker. The original `/Applications/Couleurs.app` is a separate app. For a user-only install, run `./scripts/install.sh "$HOME/Applications"`. Quit Couleur before updating.

```sh
swift test                     # Conversion, parsing, persistence, and recovery checks
./scripts/build.sh debug        # Build a local .app
open build/Couleur.app          # Compact picker
open build/Couleur.app --args --library
open Package.swift             # Open the package in Xcode
```

For visual and interaction checks alongside the installed app:

```sh
./scripts/preview.sh light      # Or dark; quit the preview before rebuilding
open "build/Couleur Preview.app"
```

The debug preview has a separate bundle ID, preferences, and library in `build/preview-data`. It starts with six sample colors and does not register the global shortcut. Its appearance override applies only to the preview, leaving your system appearance and real library alone. The normal app also accepts `--data-directory /path/to/test-library` for an isolated library.

The app is signed for local personal use, not notarized for distribution. Rebuilding does not need an Apple Developer account. The checked-in icon is generated by `scripts/make-icon.swift`; regenerate it with:

```sh
swift scripts/make-icon.swift
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
```

## Data and recovery

Your data lives outside the repository and app bundle:

```text
~/Library/Application Support/Couleur/library.json
~/Library/Application Support/Couleur/library.backup.json
```

Writes are atomic. Before each successful change, the previous valid file is saved as `library.backup.json`. The backup is the previous version, not a full revision archive; export the library for independent backups. Reinstalling the app keeps the library. **Reveal library folder** is available in the app and library menus.

A damaged or unsupported file opens in read-only recovery mode and is never silently replaced with an empty library. To recover: quit Couleur, keep a copy of the damaged file, replace `library.json` with a valid export or the backup, and relaunch. Imports merge by UUID, preserving existing records with the same identity. Removing a collection moves its colors to Unfiled; deleting a color requires confirmation.

## Structure

`CouleurCore` contains sRGB values, format conversion, parsing, the versioned data model, and atomic file persistence. `Couleur` contains the shared native window, compact picker, library, screen-source lookup, global shortcut, and clipboard behavior. Tests exercise the core without requiring display capture, UI permissions, or access to your real library.

GitHub Actions runs the core tests and builds the app on macOS. Hosted CI results are independent of local validation.

## Acknowledgment

The original [Couleurs by Laurent Baumann](https://couleursapp.com/) inspired the small utility workflow. This is an independent implementation and includes none of its source code or assets. The app uses Apple's [NSColorSampler](https://developer.apple.com/documentation/appkit/nscolorsampler) for screen picking.
