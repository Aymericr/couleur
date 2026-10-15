# Couleur reference

A tiny, floating color picker for macOS. Pick, copy, keep.

An independent successor to the compact workflow of [Couleurs](https://couleursapp.com/), inspired by its compact form factor. Written from scratch in SwiftUI and AppKit, using native screen capture APIs. No accounts or subscription. Color analysis and your library stay on your Mac. Public builds use Sparkle for signed app updates; no color or capture data is sent.

## Everyday use

The app opens as a **256 × 204 pt floating palette**: a small color well beside a prominent code, six recent colors, and three direct actions: **Pick color**, **Capture area**, and **Open image**. The surface follows your Mac’s light or dark appearance. On macOS 26 and later it uses native Liquid Glass, with a material fallback on older systems and solid surfaces for Reduce Transparency or Increase Contrast. Swatch colors stay unfiltered.

The interface uses **Geist**, color codes use **Geist Mono**, and the compact wordmark uses **Geist Pixel**. The fonts are bundled locally under the [SIL Open Font License](../Resources/Fonts/OFL.txt); no font installation or download is needed at runtime. Continuous corners, fine neutral edges, and soft contact shadows keep surfaces legible in both appearances.

- **Press the color well, hold, drag anywhere on screen, and release** to save and copy the color.
- Alternatively, click **Pick color**, then click a color, or press **⌃⌥C** from any app.
- **Hold Shift when selecting** to keep the sampler open and collect more colors. Release Shift for the final selection, or press **Esc** to finish. Each selected color gets its own history entry; the latest is copied.
- **Click the color code** to copy it again. Click a recent swatch to select and copy it. A checkmark and **Copied** label confirm each action; new picks arrive with a short color transition. Reduce Motion keeps the feedback quiet.
- Hover a recent swatch or library color for its small **×**. Removal is immediate; **⌘Z** restores it with its name, notes, and source. **⌘⇧Z** redoes the removal.
- Use the **format menu** beside the code to change its encoding. **Keep on top** is in the same menu.
- The **expand button in the header** unfolds the same window into the full library. The **Compact Picker** toolbar button (or **⌘2**) folds it back to its original position. Search, selection, and browsing state are preserved. The transition respects **Reduce Motion**.
- **Capture area** (or **⌘⇧A** while Couleur is active) lets you drag a screen area and explore its palette. **Open image** (or **⌘O**) opens an image file. All three actions also appear directly in the expanded library's toolbar, including with details open. Search folds to a magnifying-glass button when space is tight; **⌘F** always opens it.

Automatic copying and keeping the picker on top are enabled initially. The floating window can accompany other apps and full-screen Spaces. Drag the quiet header to move it; the small close button hides it.

## Your color library

Every pick is saved immediately and kept across app restarts, with no history limit. Expand to:

- Give colors names, mark favorites, and organize them into named collections.
- New picks get local, editable name suggestions. Older unnamed colors display a suggested name without rewriting the stored record. Personal names remain unchanged.
- Switch between **Colors** and **Captures** in the top bar. All colors, Favorites, and collections are direct filters above the color catalog; the collection strip scrolls when space is tight. **+** creates a collection; right-click a collection to rename or remove it.
- Arrange the catalog with the visible **Recent / Color family / App / Name** controls. Recent groups by local day, newest first. Color family follows the spectrum with shades from light to dark, then earth tones and neutrals. App groups by provenance with recent colors first; Name keeps a simple alphabetical grid. Family and App use shorter swatches so more groups fit on screen. Arrangement changes move and resize existing tiles with a brief transition and respect Reduce Motion. Filters and search work in every arrangement.
- Each color tile shows its source app. Hover for **Today at 12:27 PM**, the available website, and the source window title. Older picks show their date and local time. Clipboard, imported-image, and harmony colors keep their own source labels.
- Open the **ⓘ** details panel, then **Explore harmonies**, for analogous, complementary, triadic, and tonal palettes. Click a suggestion to copy and keep it, or copy the whole palette. Text previews measure contrast on white and ink surfaces, including alpha compositing.
- Search by name, HEX, app, window title, source URL, collection, or notes.
- Sort by time, name, or hue.
- Click a library swatch once to select and copy it in your chosen format. A small **Copied** checkmark appears on that swatch for two seconds. Arrow keys browse the selection; **⌘C** copies it.
- Use **⌘F** for search. Details start closed; **ⓘ** opens names, collections, and optional harmony tools. **Source & notes** reveals metadata only when needed.
- Adjust a saved color with the native color panel, including opacity.
- See the pick time, source app and bundle ID, display, and screen coordinates.
- Add notes and a source URL by hand.
- Import or export a complete JSON backup through the **File** menu.
- Browse **Captures** for saved images and their palettes. Rename captures, search by website or app, and return to the original page through its source link.

Screen metadata is best effort: the source app is resolved from the normal window under the pointer, or the window containing the captured rectangle. A selection spanning multiple windows has no single attributed source. Window titles are only saved when macOS supplies them, and can be absent without Screen Recording permission. Clipboard imports are labeled as pasted colors. Screen coordinates use the Core Graphics origin at the top-left of the primary display and may be negative on other displays.

**Remember source websites** is enabled initially and can be changed in the **Couleur** app menu or the compact format/options menu. Couleur reads the current tab in the matching window of Safari or supported Chromium browsers (Chrome, Edge, Brave, Chromium, Vivaldi). macOS may ask for **Automation** access to that browser. It checks both window bounds and title before recording a URL, skips Chromium incognito windows, and only stores HTTP(S) links without embedded credentials. It does not read browsing history or execute page JavaScript. A denied request, unsupported browser, or changed tab leaves the website empty; the source link remains editable. Browser lookup runs off the main thread and never delays saving or copying a color.

Screen picking uses a compact circular loupe with a fine grid and an outlined center pixel. It takes a temporary snapshot of each display so the visible pixel and the saved sRGB value agree. Arrow keys refine the selection one source pixel at a time. The snapshots stay in memory and disappear when picking ends. Canceling with Esc never creates an entry or changes the clipboard; previously collected colors remain saved during a Shift session. Without screen access, the native macOS sampler remains available without requiring Accessibility permission.

## Screen palettes

Choose **Capture area** in the compact picker or library toolbar, or **Capture Screen Palette** from the File or menu-bar menu. Drag a rectangle using macOS's screenshot selector; **Esc** cancels. Couleur hides its window during selection, then expands into the result:

- Up to **five dominant colors**, ordered by area, with approximate percentages and a proportion strip.
- **Suggested color roles**: background, surface, foreground, and accents for flat designs; main colors, accents, shadows, and highlights for textured images. Click a role to copy and save its color with an editable name and role metadata.
- **Estimated linear gradients**, including multi-stop gradients within a larger image. Inspect the source region, copy CSS, or keep individual stops. Gradients are inferred from spatial changes, not assembled from unrelated swatches.
- Up to **64 grouped shades**, sortable by area or hue.
- A large image canvas with up to **12 movable color points**. Five representative points are suggested initially. **Click to add**, drag a numbered point to refine it, or use **+ / −** beside Your palette. The small pixel loupe appears during dragging. **Esc** cancels an unfinished drag.
- Arrow keys move a selected point by one original image pixel; **Shift** moves ten. The palette buttons also support keyboard focus and arrow refinement. **⌘Z / ⌘⇧Z** undo and redo palette edits.
- Your palette saves with the image, including exact pixel coordinates. Moving a point updates the palette on release; it does not fill the color history with intermediate samples. Click a palette swatch to copy and keep that color, **Copy palette** for every color in the selected format, or the folder button to create a collection.
- Choose **Open image** (or **File → Open Image…**, **⌘O**) to explore a local photo or design. Image orientation is normalized, and a PNG copy is kept locally.
- Click a shade to **copy and save it** in the current copy format. A checkmark confirms the copy. Repeated clicks on the same color in that capture reuse its history entry.
- Expand **Explore more colors** for suggested roles, gradients, dominant colors, and the full shade catalog. **Save colors…** inside that section saves those groups as a collection. Names and notes on already-picked, unfiled colors are preserved.
- Every successful capture is **saved automatically**, including the original image, all grouped shades, roles, gradients, capture date, and available source metadata. Open it again from **Captures**, including after restarting the app. A capture stays together as one palette; individual colors enter All Colors when you choose to keep them.
- Hover a gallery thumbnail for **×**, or use its context menu, to remove a capture. **⌘Z** restores the capture and image during the session; removed images go to the Mac's Trash. Colors already kept in your library are independent and retain their source metadata.

Extraction uses a bounded image sample and population-weighted OKLab clustering. Representatives are colors found in that sample. Group percentages are estimates, not exact pixel counts; very small accents may be absent from the grouped palette. The image picker reads the original pixels independently, so you can still access every color in the captured area. Both paths convert to sRGB.

Role analysis also considers flat connected regions, image edges, chroma, contrast, and position. It adapts to flat graphics versus textured images, but does not recognize objects or read text. Labels are suggestions, not a recovered design system. Linear gradient estimates must closely match a smooth region; radial/mesh gradients, heavily overlaid gradients, and subtle photographic shading may be omitted. The original CSS interpolation space and exact stops cannot be recovered reliably from a screenshot. Gradient CSS is copied on demand; keep individual stops to retain them in color history. Everything runs locally without an AI service or new dependencies. See [analysis design and references](palette-analysis.md).

Original images are stored locally in the library's `captures` folder. Temporary screenshot files are removed after processing. The catalog stores lightweight palette metadata and loads thumbnails on demand; editing a color does not rewrite screenshots. Capture colors remember the image dimensions and either the group's estimated area or the exact pixel coordinates within the image, alongside the available app and website. Nothing is uploaded.

### Screen access

Area capture and the custom pixel loupe need **Screen Recording** permission; point picking still works without it through the native sampler. **Couleur → Screen Access…** opens the setup guide, also shown before the first area capture. It names the correct app, links directly to the privacy settings, checks access when you return, and provides **Quit & Reopen** if macOS needs a restart. Restart closes the setup window, opens the same app through macOS, and returns to setup with a fresh permission check. The replacement waits for the previous instance to exit before returning to setup. A denied permission and a capture failure have different guidance. This feature does not record audio, capture continuously, or send images anywhere.

Local builds use an available Developer ID or Apple Development signing certificate to keep a stable app identity across updates. You can select one explicitly with `COULEUR_SIGN_IDENTITY`. Without a certificate, builds fall back to ad-hoc signing; macOS may require renewing Screen Recording permission after a rebuild. If an older ad-hoc build remains enabled in Settings, remove that old entry and add the current app. The preview and installed app have separate permissions, labeled **Couleur Preview** and **Couleur**.

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

## Build from source

Requires **macOS 14 or later**, Xcode command-line tools, and a Swift 6 toolchain. Builds for the current Mac's architecture. Sparkle provides updates in distribution builds.

```sh
./scripts/install.sh
```

This builds and signs `Couleur.app`, installs it in `/Applications`, and opens the compact picker. The original `/Applications/Couleurs.app` is a separate app. For a user-only install, run `./scripts/install.sh "$HOME/Applications"`. Quit Couleur before updating.

```sh
swift test                     # Colors, palettes, catalog persistence, deletion, undo, and source attribution
./scripts/build.sh debug        # Build a local .app
open build/Couleur.app          # Compact picker
open build/Couleur.app --args --library
open Package.swift             # Open the package in Xcode
```

For visual and interaction checks alongside the installed app:

```sh
./scripts/preview.sh light      # Or dark; quit the preview before rebuilding
./scripts/preview.sh light /path/to/image.png  # Exercise the palette UI without screen access
open "build/Couleur Preview.app"
```

The debug preview has a separate bundle ID, preferences, and library in `build/preview-data`. It starts with six sample colors and does not register the global shortcut. Its appearance override applies only to the preview, leaving your system appearance and real library alone. The normal app also accepts `--data-directory /path/to/test-library` for an isolated library.

For permission-free visual checks of the loupe, run `./scripts/preview.sh light --loupe /path/to/image.png`, open the preview, and start picking. This debug-only mode samples the fixture image into the isolated preview library.

Local builds are signed for development and do not start the public updater. Public distribution uses a universal, Developer ID signed and notarized DMG, signed Sparkle updates, and a generated Homebrew cask. See [release setup and automation](releasing.md). The first public download is not available until that pipeline has completed.

The app icon uses the gradient artwork and single pearl `#` in [`Resources/AppIcon.icon`](../Resources/AppIcon.icon). The composition fills the system icon shape with the artwork, preserving its color and dithering without an extra background plate. Its compiled asset catalog and ICNS fallback are checked in, so normal builds need no icon tooling. To regenerate them with Xcode 26 or later:

```sh
./scripts/make-icon.sh
```

## Data and recovery

Your data lives outside the repository and app bundle:

```text
~/Library/Application Support/Couleur/library.json
~/Library/Application Support/Couleur/library.backup.json
~/Library/Application Support/Couleur/captures/<capture-id>.png
```

Writes are atomic. Before each successful change, the previous valid catalog is saved as `library.backup.json`. The backup is the previous version, not a full revision archive, and references the images beside it. **Export library** creates a portable JSON archive containing the catalog and every original capture image. Reinstalling the app keeps the library. **Reveal library folder** is available in the **Couleur** app menu.

A damaged or unsupported file opens in read-only recovery mode and is never silently replaced with an empty library. To recover: quit Couleur, keep a copy of the damaged file and capture images, replace `library.json` with the previous catalog backup, and relaunch. Portable exports are restored through **Import library** and merge by UUID, preserving existing records with the same identity. Version 1 and 2 libraries migrate to version 3 without losing colors or metadata; older app builds refuse to overwrite the newer format. Version 3 includes editable image palettes. Removing a collection moves its colors to Unfiled. Color and capture deletions and palette edits support native Undo/Redo until the app quits.

Color names and families are deterministic suggestions from a small curated vocabulary and perceptual color distance, not object recognition or a universal naming standard. Harmonies preserve perceptual lightness and hue relationships, reducing chroma when needed to fit sRGB. See [palette studio implementation notes](palette-studio.md) for behavior and references.

## Structure

`CouleurCore` contains sRGB values, format conversion, parsing, perceptual palette extraction, color-managed image sampling, the versioned data model, and atomic file persistence. `Couleur` contains the shared native window, compact picker, library, region-capture workflow and permission guide, screen-source lookup, global shortcut, and clipboard behavior. Tests exercise the core without requiring display capture, UI permissions, or access to your real library.

GitHub Actions runs the core and catalog tests and builds the app on macOS. Hosted CI results are independent of local validation.

## Acknowledgment

The original [Couleurs by Laurent Baumann](https://couleursapp.com/) inspired the small utility workflow. This is an independent implementation and includes none of its source code or assets. The custom loupe uses [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit); [NSColorSampler](https://developer.apple.com/documentation/appkit/nscolorsampler) provides the fallback when screen access is unavailable.

## License and distribution

[MIT](../LICENSE). Bundled Geist fonts retain their [SIL Open Font License](../Resources/Fonts/OFL.txt); Sparkle retains its own license, included in app builds. The project page is [aymeric.dev/couleur](https://aymeric.dev/couleur). Release packaging, Homebrew, website integration, credential ownership, and update validation are documented in [docs/releasing.md](releasing.md).
