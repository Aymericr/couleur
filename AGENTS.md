# Couleur design and development

Couleur is a native macOS utility. Keep the everyday picker compact and immediate; the library is an expansion of the same window.

For interface and motion work, consult the relevant skills from these sources and apply their principles to SwiftUI and AppKit:

- [Emil Kowalski](https://github.com/emilkowalski/skills): animation purpose, frequency, timing, interruption, and Apple design.
- [transitions.dev](https://github.com/Jakubantalik/transitions.dev/tree/main/skills): consistent motion values and surface transitions.
- [Jakub Krehel](https://github.com/jakubkrehel/skills): hierarchy, typography, optical alignment, states, and visual polish.

Use native controls, SF Symbols, and AppKit window behavior. Use bundled Geist for interface text, Geist Mono for color codes, and Geist Pixel sparingly for the compact wordmark; system menus and dialogs keep native typography. Translate web-specific recipes into native equivalents; adding a web stack or motion dependency is unnecessary.

Copying is a frequent action: perform it immediately, then confirm it on the affected color with a brief, restrained static cue. Keep layout stable. Use motion for spatial continuity and useful feedback, respect Reduce Motion, and avoid decorative bounce or animation on keyboard navigation.

Validate the rendered app in light and dark appearances with `scripts/preview.sh`. The preview has separate data and preferences. Preserve the user's real library; keep synthetic colors in the preview. Check clipboard results and window interactions through the actual native UI, alongside the existing core tests.
