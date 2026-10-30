# ProEstimate AI App Store campaign

The orange ribbon and charcoal base are drawn once across three panels, then sliced. Upload each family in filename order **01, 02, 03** to retain the side-by-side flow. The icon and wordmark share a dark, high-contrast badge on every panel.

## Deliverables

| Folder | Portrait PNG dimensions | Use |
| --- | --- | --- |
| `iphone-dynamic-island-medium` | 1206 × 2622 | Required iPhone family under Apple's current specifications |
| `iphone-dynamic-island-large` | 1320 × 2868 | Additional large iPhone family |
| `iphone-face-id-large` | 1284 × 2778 | Additional compatible large iPhone family |
| `ipad-13` | 2064 × 2752 | Required for this iPad-supporting app |
| `ipad-12-9` | 2048 × 2732 | Additional iPad family |
| `ipad-11` | 1668 × 2420 | Additional iPad family |

Each completed family contains three sRGB RGB PNGs with no alpha channel. `manifest.json` records the actual exported files and validation. Required dimensions were checked against [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) on October 30, 2026. App Store Connect can scale required screenshots to smaller compatible displays; separate landscape exports are not required for a portrait listing. iPhone Duo requirements start in April 2027 for builds using the iOS 27.1 SDK or later; this app currently targets the iOS 26.4 SDK.

`iphone-side-by-side.png` and `ipad-side-by-side.png` are review sheets, not upload files. The editable panorama SVGs contain the typography, branding, continuous background, and embedded device art. They can be opened in a vector editor. The original transparent assets and image-generation prompts are included.

These are marketing concepts for designing the new listing. The iPhone foregrounds were generated with the built-in image_gen tool from the earlier approved concepts, then extracted with the same tool. They contain illustrative app UI and example data. Replace them with final release captures before submission. Tablet capture sources are recorded in `sources.json` when available. No screenshots have been uploaded or submitted to App Store Connect.

To regenerate exact layouts after replacing the device artwork:

```sh
node scripts/render-app-store-listing.cjs
```

The script uses the existing backend `sharp` dependency for deterministic SVG rendering/export and validates each PNG's dimensions and absence of alpha. Raster cutouts preserve their original files; layout is code-native SVG.
