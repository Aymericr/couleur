<p><img src="docs/images/icon.png" width="80" alt="Couleur app icon"></p>

# Couleur

Pick, copy, and keep the colors you find. Free and open source for macOS.

[Explore Couleur](https://aymeric.dev/couleur) · [Releases](https://github.com/Aymericr/couleur/releases)

<a href="https://aymeric.dev/couleur">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/header-dark.png">
    <img src="docs/images/header.png" alt="Try Couleur’s interactive palette: four colors picked from a Starship launch" width="100%">
  </picture>
</a>

### 1. Pick a color

Press the color well, drag anywhere on your screen, and release. Your color is saved and copied immediately.

Hold **Shift** to keep picking. **Esc** finishes. Click a recent color to copy it again.

<img src="docs/images/picker.png" alt="The compact Couleur picker, showing an apricot color and recent swatches" width="320">

### 2. Make it yours

Choose **HEX, RGB, HSL, OKLCH, or Swift code** from the format menu. Expand the picker to name colors, group them, and find where you picked them. Your library stays on your Mac.

### 3. Turn an image into a palette

Choose **Capture area** or **Open image**. Click the image to add a color, then drag its numbered point to refine it. Click a swatch to copy it, or **Copy palette** to take them all.

<img src="docs/images/palette.png" alt="A saved Starship capture with four numbered color points and a matching palette" width="100%">

### Get started

Requires **macOS 14 or later**. The first signed DMG for Apple silicon and Intel is being prepared. You can [build from source](docs/reference.md#build-from-source) in the meantime.

For screen picking, Couleur guides you to **System Settings → Privacy & Security → Screen Recording**. Turn on Couleur, then return to the app. It never records audio.

| Shortcut | Action |
| --- | --- |
| **⌃⌥C** | Pick a color, from any app |
| **⌘⇧A** | Capture an area |
| **⌘O** | Open an image |
| **⌘1 / ⌘2** | Library / compact picker |
| **⌘Z** | Undo a deletion or palette edit |

[Full guide](docs/reference.md) · [Build & release](docs/releasing.md) · [MIT license](LICENSE)

Made by [Aymeric Rabot](https://aymeric.dev). Inspired by the original [Couleurs](https://couleursapp.com/).
