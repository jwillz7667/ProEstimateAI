# ProEstimate AI — five-panel App Store campaign

This revision keeps the **original charcoal and curved orange-ribbon panorama**. It expands the sequence to **five panels per device family** and accounts for the visible space between cards.

The first three headline themes remain “See the vision. Before you build.”, “Every job. One clear view.” and “Clear quotes. Confident next steps.” The fourth panel covers materials/pricing, and the fifth covers project organization. The obsolete dashboard illustration is replaced with an illustration of the new project-first Home hierarchy.

## Exact exports

| Folder | Portrait RGB PNG dimensions | Panels |
| --- | --- | --- |
| `iphone-dynamic-island-medium` | 1206 × 2622 | 01–05 |
| `iphone-dynamic-island-large` | 1320 × 2868 | 01–05 |
| `iphone-face-id-large` | 1284 × 2778 | 01–05 |
| `ipad-13` | 2064 × 2752 | 01–05 |
| `ipad-12-9` | 2048 × 2732 | 01–05 |
| `ipad-11` | 1668 × 2420 | 01–05 |

These are **30 full-size sRGB RGB PNGs without alpha**, verified against [Apple’s accepted screenshot dimensions](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) on November 3, 2026. Five images per bucket is the requested campaign size; it is not an Apple minimum. Apple accepts up to ten images per device size.

`ListingScreenshots.prepare` selects five ordered files in each of five upload buckets for en-US, en-GB, en-AU, es-MX and es-ES: **125 staged images**. Captions in this campaign remain English in every locale. The optional 2048 × 2732 exports are provided for manual use but are not staged with the 2064 × 2752 exports because those formats occupy the same Apple bucket.

## The gap correction

The measured reference is the public App Store iPhone gallery at a 1200 CSS-pixel browser viewport:

- Card width: **273.328125 CSS px**.
- Inter-card gutter: **20 CSS px**.
- Reference gap ratio: `20 / 273.328125`.

For a panel width `W`, the renderer creates one full ribbon panorama with virtual gutter width `G = round(W × referenceGapRatio)` and width `5W + 4G`. Panel `i` is extracted at **`x = i × (W + G)`**, not `i × W`. The hidden strips carry the background that would otherwise be incorrectly omitted when Apple inserts a gutter. Foreground artwork uses the same offsets.

`gallery-geometry.json` records this calibration. The same iPhone ratio is applied to iPad exports as a reference calibration; **no native iPad gallery measurement is claimed**. Other storefront widths, orientation and scaling can change the gutter/card ratio. The package therefore includes reference and alternate views instead of claiming exact alignment at every possible width.

- `iphone-gallery-viewport-1200.png`: gallery-only 1200 px reference, 273.328125 px cards and 20 px gaps.
- `ipad-gallery-viewport-1200.png`: iPad reference calibration using that ratio.
- `*-gallery-viewport-390.png`: compact illustrative alternative, 260 px cards and 16 px gaps, showing expected variation.
- `*-gallery-gap-*.png`: all five panels visible at the reference ratio and alternative 8 / 16 / 28 px preview gutters.
- `iphone-editable-panorama.svg`, `ipad-editable-panorama.svg`: editable complete panoramas including the virtual gaps. These are not App Store upload files.
- `gallery-preview.html`: interactive gallery review with device-family, card-width and gutter controls. It is a layout review tool, not an App Store screenshot or runtime app capture.

## Source accuracy

The user’s latest instruction was **keep simulators closed**. No simulator was opened, booted, relaunched or captured for this revision.

| Panel | Foreground source |
| --- | --- |
| 01 | Actual preserved job-site photo and completed app generation, with an illustrative comparison control/device frame. |
| 02 | Code-derived illustration of the new Home hierarchy, with fictional sample account/projects and the repository’s sample summary totals. It is **not a fresh runtime screenshot**. |
| 03 | Previously selected generated iPhone device artwork. The iPad proposal is a code-native illustration with example values. |
| 04 | Actual historic iPhone materials-list crop; an illustrative iPad estimate layout with example values. |
| 05 | Actual historic project-list/metadata capture crops. Old navigation bars and the QA-only description are excluded by cropping. The iPad metadata/photo composition and device frames are illustrative. |

`sources.json` identifies originals and SHA-256 hashes. The new Home and proposal illustrations are not represented as verified pixel captures. No customer data, API keys, authentication tokens or Apple reviewer password are embedded in this package.

## Regeneration and validation

```sh
node scripts/render-app-store-listing.cjs
node scripts/verify-app-store-listing.cjs
/opt/homebrew/opt/ruby/bin/ruby fastlane/tests/listing_screenshots_test.rb
```

The renderer uses the existing backend `sharp` dependency. It preserves the original gradient stops and normalized curve profile, renders a single virtual panorama, then exports exact crops. Update `gallery-geometry.json` to calibrate a different measured reference; `--gap-ratio=NUMBER` overrides the reference ratio. Staging rejects a three-panel regression, missing/duplicate order, incorrect dimensions, alpha and paths escaping the campaign.

This package contains artwork and staging changes. It does not itself upload assets, change a live listing, withdraw an App Review submission or publish a release.
