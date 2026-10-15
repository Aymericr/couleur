# Image palettes and color exploration

Captured images are editable color studies. A bounded scan locates representative pixels for an initial palette; each marker stores its exact full-resolution position and sampled sRGB value. Clicking adds a point, dragging refines it with a pixel loupe, and releasing commits one undoable edit. Keyboard arrows move one pixel, Shift moves ten, and Escape cancels an in-progress drag. The limit is twelve points. An intentionally empty palette stays empty after reopening.

The canvas and its palette share selection. Clicking a palette swatch keeps and copies it; editing points alone does not create color-history entries or alter the clipboard. A palette can be copied in the user's selected format or saved to a named collection. Palette edits, normal library writes, and exports preserve image files; portable exports include images and point metadata. Library version 3 reads earlier versions and protects point data from older writers.

Imported images are oriented before sampling and archived as PNG. Canvas geometry excludes letterboxing and clamps drags to actual pixels. Dragging an existing marker preserves the grab offset. Images and swatches are rendered without material overlays; glass is confined to control surfaces. macOS 26 uses native glass, with material and accessibility fallbacks. Both compact and expanded views follow the app appearance.

Rounded surfaces use continuous corners, with outer radii following the inner radius plus padding. The craft skill's shadow-border recipe is translated into native points: a fine neutral edge with small contact and ambient shadows in light mode, and a subtle white edge in dark mode. Increase Contrast strengthens the edge. Geist, Geist Mono, and Geist Pixel are bundled unchanged from Vercel's release and registered only for the app process. Pixel is limited to the compact wordmark; codes remain legible in Mono.

The expanded window has two destinations: Colors and Captures. Collections and favorites live in the color grid dropdown, details start closed, and image analysis is a disclosure below the editor. Pick color, Capture area, and Open image are direct labeled buttons in both the compact picker and the library toolbar. The inspector sits below the shared toolbar, so opening details never hides these actions. At narrow widths, search collapses to its standard magnifying-glass button and remains available through Command-F. Color families are searchable metadata based on perceptual chroma, hue, and lightness, rather than another navigation tree. They do not move colors out of named collections. New picks get editable suggested names; previously unnamed colors show derived names without changing their saved metadata. Existing personal names win. The vocabulary and family boundaries are editorial approximations, not formal semantic classifications.

Harmonies use OKLCH hue rotations (analogous ±30°, complementary 180°, triadic 120°/240°) or a tonal lightness ramp. Gamut mapping reduces chroma at fixed lightness and hue; it does not clip channels independently. Neutral colors therefore remain neutral. These are starting points to explore, not guarantees that a palette suits a design.

Contrast previews composite translucent colors over the displayed surface and calculate WCAG relative-luminance contrast. AA labels apply to that text/background pair: 4.5:1 for normal text, 3:1 for large text. They do not certify a whole interface.

References:

- [Björn Ottosson's OKLab definition and public-domain conversion matrices](https://bottosson.github.io/posts/oklab/)
- [W3C contrast minimum guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Apple design skill](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md)
- [UI polish skill](https://github.com/jakubkrehel/skills/blob/main/skills/better-ui/SKILL.md) and [color skill](https://github.com/jakubkrehel/skills/blob/main/skills/better-colors/SKILL.md)
- [Shadow-border and surface recipes](https://github.com/jakubkrehel/skills/blob/main/skills/better-ui/surfaces.md)
- [Bundled Geist font source and license](../Resources/Fonts/README.md)
- [Transitions polish reference](https://github.com/Jakubantalik/transitions.dev/blob/main/skills/transitions-polish/SKILL.md)
