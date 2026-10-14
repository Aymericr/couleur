# Spatial palette analysis

Couleur serves both design screenshots and photographs. Quantization answers which colors occur together; it cannot establish their use or whether neighboring shades form a gradient. The existing OKLab palette remains available alongside suggestions based on spatial evidence.

## References considered

- [Google Material Color Utilities](https://github.com/material-foundation/material-color-utilities/blob/main/dev_guide/extracting_colors.md) separates image quantization from scoring suitable theme seeds and includes Swift implementations. Its theme generation does not reconstruct the original UI roles or gradients.
- [Android Palette](https://developer.android.com/develop/ui/views/graphics/palette-colors) selects light/dark and vibrant/muted swatches. Those are useful color characteristics, rather than evidence of background or foreground usage.
- [colorlip](https://github.com/na-zu-nya/colorlip) adds composition-aware center/border and edge weighting to dominant/accent extraction. It is a useful conceptual reference for considering position as well as population.

The implementation is original Swift, using the existing quantizer; no upstream source was copied or package installed. A new quantizer alone would not solve the missing spatial evidence.

## Roles

The color-managed image is sampled at a bounded size. Analysis uses at most 160 pixels along its longest side, retains aspect ratio, and ignores pixels that are not nearly opaque. Each sample is assigned to a perceptually nearest palette swatch.

- Background requires a substantial connected flat region and meaningful coverage of the outer image edges.
- Surface requires a second coherent flat area with relatively gentle background contrast.
- Foreground is a contrasting neutral in a predominantly flat image. It is deliberately not labeled text, because no OCR or object recognition is performed.
- Main color uses the largest broad group when there is no convincing flat background or detected gradient. Textured images may also suggest substantial shadow and highlight groups.
- Accents combine chroma, area, position, and (for flat designs) connected region evidence. Accents must have a distinct hue from a chromatic background/main color and from each other. Perceptually close accents are merged. Colors primarily belonging to a detected gradient do not become a row of spurious accents.

Textured images do not receive surface/foreground labels. There is no requirement to fill every role. Suggested roles are persisted as optional metadata; old libraries remain readable, and user-edited names are preserved.

## Gradients

Smooth connected regions provide candidate rectangles. A color derivative structure tensor estimates the dominant spatial direction. Robust color bins along that direction are snapped to observed pixels; a piecewise linear approximation simplifies the resulting stops. An estimate is accepted only when at least 94% of opaque samples fit within a small RGB error and the clipped RMS error is also low. Up to three distinct regions are returned.

Hard boundaries, shuffled color ramps, texture, and radial shading are regression cases: they must not be reported as a linear gradient. A source-region preview lets users inspect the evidence. Copied CSS includes the estimated angle and stops; stop colors can be copied and kept independently.

These are appearance-based estimates, not recovery of original CSS. Screenshots do not preserve original stops, interpolation color space, opacity layers, or vector geometry. Radial/mesh gradients and heavily occluded or very subtle linear gradients can be omitted. Photo lighting that truly resembles a smooth linear ramp may still be suggested; “Estimated” is always visible.

## Validation

Core fixtures cover light/dark interface layouts, a small coherent accent, monochrome and transparency, horizontal/diagonal/multi-stop gradients, region localization, copyable CSS, textured images, same-hue photo tones, shuffled ramps, hard boundaries, and radial shading. Existing color-format, palette, image-coordinate, metadata, and persistence tests remain in place. Native interaction checks use the isolated preview so synthetic colors never enter the real library. They cover role copying and collection persistence, gradient CSS and stop copying, source-region inspection, both appearances, and a photograph of a rocket against a blue sky. These checks establish the intended behavior on the fixtures, not general semantic accuracy across all images.
