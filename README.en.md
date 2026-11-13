# Golden Palette / Golden 调色

[简体中文](README.md) | [English](README.en.md)

A macOS app for organizing project colors and generating paint-mixing recipes for scale models and art projects.

**Latest version: 1.0.19 (build 20)** · [Release notes and downloads](https://github.com/zeal-odoo/GoldenPalette/releases/latest) · [Download Universal DMG](https://github.com/zeal-odoo/GoldenPalette/releases/download/v1.0.19/GoldenPalette-1.0.19-universal.dmg)

## Features

- Generate base, shadow, and highlight recipes from an RGB value or a color selection using your locally installed Codex CLI.
- Choose either GOLDEN SoFlat 12 colors or Fluid Acrylics 15 colors. Each recipe uses only the selected set. Prepare 200 drops of base color, then take two separate 20-drop portions to make the shadow and highlight by adding small amounts of paint.
- Use Tamiya or Mr.Hobby paint references as target colors, while mixing with the selected GOLDEN paints.
- Combine RGB colors, branded paint references, or both using relative proportions, such as Mr.Hobby H1 at 30% and H2 at 70%. Weights are normalized when their total differs from 100%.
- Save colors and recipes by project, delete individual colors, and reopen or copy complete mixing instructions.
- Configure the model, reasoning effort, and Codex CLI path in the app. Startup checks help diagnose CLI or model connection problems and let you update settings or retry.
- Find a kit's instruction manual or import a PDF, research a painting scheme with online sources, annotate part colors, and export an annotated PDF.

## Installation and requirements

Requires **macOS 12.7 or later**. The Universal DMG supports **Apple silicon and Intel Macs**. The app interface is currently primarily in Simplified Chinese; this repository provides documentation in Chinese and English.

1. Download the DMG from [GitHub Releases](https://github.com/zeal-odoo/GoldenPalette/releases/latest).
2. Quit any running copy of Golden Palette.
3. Open the DMG and drag `Golden调色.app` to `Applications`. Replace the previous app when updating.
4. Eject the disk image and open the app from Applications.

Replacing the application preserves existing projects, recipes, manual studies, and AI settings. Release assets include a SHA-256 checksum and bilingual installation notes. Download the DMG and checksum into the same folder, then verify them from that folder:

```sh
shasum -a 256 -c GoldenPalette-1.0.19-universal.sha256
```

AI features require **Codex CLI to be installed and signed in on this Mac**. In the app, open `系统设置 → AI 配置` (Settings → AI Configuration), choose a model available to your account, and set the CLI path if necessary. The installer does not include Codex CLI or login credentials. The startup check sends a short request to the configured model.

The current application is signed with an **Apple Development** certificate. It is **not Developer ID signed or notarized by Apple**; macOS on another machine may show a verification warning or block it from opening.

AI recipes and screen swatches are starting points. Test a small physical mixture using equal-volume drops and compare it after drying.

## Making shadows and highlights from the base color

Version **1.0.19 (build 20)** uses this workflow:

1. Prepare the 200-drop base recipe and mix thoroughly.
2. Put 20 drops of the mixed base into each of two clean mixing cups.
3. Add the specified paints to one cup for the shadow and to the other for the highlight. The original base mixture has 160 drops remaining.

The 20 drops are taken from the **already mixed base**. Do not divide each ingredient in the original recipe by ten. Each variant starts independently from the base color.

AI is instructed to favor 1–3 added paints totaling 1–8 drops, with a maximum of 20 added drops per variant when necessary. Each variant's final volume is 20 base drops plus its additions. Total paint use for the complete set is 200 base drops plus both sets of additions; the two portions taken from the base are not counted twice. A pure-black base may need no shadow additions, and a pure-white base may need no highlight additions.

The requested result preserves the base hue naturally while making the light/dark contrast somewhat stronger. Guidance covers saturation and warm/cool shifts and discourages muddy, chalky, or mechanically blackened/whitened results. The minimum preview lightness difference increased from 15 to 18 L*, with a preferred range of roughly 20–28. Near black or white, validation accounts for the remaining lightness range. These are screen-target checks, not measurements of mixed paint.

Each saved shadow and highlight includes a complete snapshot of the base recipe. It remains available when viewing or copying that variant independently, even if its original base card has been deleted. Legacy recipes that used three independent 200-drop mixtures retain their original quantities. Regenerating a recipe applies the new addition workflow.

## Mixing multiple target colors

Open `AI 调色 → 多色合成` (AI Mixing → Multi-color Blend) within a project. Each entry can be an RGB color or a branded paint reference. For example, select `郡士 Mr.Hobby → 水性 Hobby Color · H → H1` at 30%, then H2 from the same series at 70%. Paint codes are searchable, and each entry can use its own brand and series.

The AI receives each input's brand, series, code, preview RGB, and weight to propose a combined target. The resulting recipe uses the selected SoFlat 12-color or Fluid 15-color set: a 200-drop base and two 20-drop base portions with additions. Input weights describe the target blend, not the final GOLDEN ingredient quantities.

Saved recipes retain the input references, proportions, and RGB snapshots. Changing an entry's series clears that entry's paint selection; changing inputs clears unsaved results. Older blends created entirely from RGB inputs remain readable.

## Branded paint references

In AI Mixing, choose the mixing paint set, then open `品牌标准色` (Branded Paint Reference), select a brand and series, and search for a code such as Tamiya XF-53 or Mr.Hobby C13. The AI uses that reference as the target and mixes only with the selected GOLDEN set.

Changing the paint set, reference, or input mode clears unsaved results. Changing the paint set also cancels an active generation request. Saved recipes retain their paint set and reference identity; reopening AI Mixing restores the most recently saved selection for the project.

| Brand | Series | Selectable colors |
| --- | --- | --- |
| GOLDEN | Selected SoFlat set | 12 |
| GOLDEN | Fluid mixing set plus five additions | 15 |
| Tamiya | Acrylic X / XF | 101 |
| Tamiya | Enamel X / XF | 79 |
| Tamiya | Lacquer LP | 79 |
| Tamiya | Spray TS, colored references | 98 |
| Tamiya | Aircraft spray AS | 33 |
| Tamiya | Polycarbonate spray PS, including special item 69944 | 60 |
| Mr.Hobby | Mr.Color C | 50 |
| Mr.Hobby | Aqueous Hobby Color H | 38 |
| Mr.Hobby | Acrysion N | 40 |

### Tamiya catalog expansion in 1.0.18

Version 1.0.18 added 239 references, bringing the six Tamiya series to **450 selectable colors**. XF-85 Rubber Black is available in both acrylic and enamel. Searches accept `XF-85`, `xf85`, and Chinese or English names. LP covers colored products within the official LP-85 range; AS and PS are now included. The special-edition PS Dark Blue keeps its actual item number, `69944`.

The official [acrylic](https://www.tamiya.com/english/products/list.html?genre_item=e_504010), [enamel](https://www.tamiya.com/english/products/list.html?genre_item=e_504020), [LP](https://www.tamiya.com/english/products/list.html?genre_item=e_504005), [TS](https://www.tamiya.com/english/products/list.html?genre_item=e_504030), [AS](https://www.tamiya.com/english/products/list.html?genre_item=e_504050), and [PS](https://www.tamiya.com/english/products/list.html?genre_item=e_504060) catalogs were checked on November 13, 2026. Coverage, exclusions, and individual product links are recorded in [the catalog coverage data](docs/tamiya-catalog-coverage.json). Primers, weathering products, panel liners, and paint markers are outside this scope.

The catalog includes colored metallic, pearl, fluorescent, transparent, and iridescent references. GOLDEN recipes approximate their color, not their special finish or substrate behavior. Colorless topcoats, matting additives, and thinners are excluded as target colors. Mr.Hobby coverage remains a selection of common solid colors rather than its complete catalog.

TS includes 98 colored references within TS-1 through TS-102. TS-13, TS-65, TS-79, and TS-80 are colorless finishes and are excluded. TS references are targets only; spray paints are never added to the mixing ingredient sets.

Legacy enamel XF-67, XF-68, and XF-69 references are retained for saved recipes but hidden from new selections because they were not found in the current official enamel catalog. Their acrylic counterparts remain selectable. Existing RGB values and saved identities were preserved during the expansion.

### GOLDEN paint sets and compatibility

The Fluid set contains the [official 0928 ten-color mixing set](https://goldenartistcolors.com/products/fluid-acrylics-mixing-set): 2009, 2008, 2210, 2305, 2260, 2255, 2270, 2275, 2040, and 2380. It adds Pyrrole Orange 2276, Dioxazine Purple 2150, Yellow Ochre 2407, Ultramarine Blue 2400, and Permanent Green Light 2250. Codes and names follow the [GOLDEN Fluid pigment chart](https://goldenartistcolors.com/products/golden-artist-acrylics/fluid/pigment-data).

Version 1.0.14 added Ultramarine Blue and Permanent Green Light, completing the requested six-color selection alongside Benzimidazolone Yellow Medium, Naphthol Red Light, Carbon Black, and Titanium White. The Fluid ingredient set grew from 13 to 15 colors.

SoFlat and Fluid paints retain separate series identities even when their names match. They are not assumed to be interchangeable drop for drop. Recipes from the older SoFlat 12-color, Fluid 13-color, or combined 25-color sets keep their original ingredients and amounts. New recipes use one current set; regenerating from the old combined set defaults to SoFlat, while regenerating from Fluid 13 selects Fluid 15.

## Instruction manuals and painting research

Select a project and open `说明书考证` (Manual Research) in the toolbar.

1. Enter the manufacturer, kit number, scale, subject, and painting requirements such as era, unit, location, or a specific scheme. Use `AI 查找说明书` (Find Manual with AI), review the candidate edition before downloading, or choose `导入 PDF` (Import PDF). The app accepts unlocked PDFs with 1–200 pages up to 30 MB, including scans.
2. Navigate to a useful page, such as the paint chart, then choose `AI 考证配色` (Research Colors with AI). The request includes the cover, the current page image, and up to 32,000 characters of extracted text, with online search enabled. A response without an actual search event is not accepted as a research result.
3. Review color names, standard paint codes, applicable parts, source links, and unresolved questions. Evidence labels distinguish supported, inferred/unconfirmed, and disputed claims. They represent AI judgments, not human certification. A kit manufacturer's suggested hobby paint and a historical subject's actual finish are treated separately.
4. Annotate the current page or continue through remaining pages. Pages are processed individually, so completed work survives cancellation or a later page failure. Unreadable scans and uncertain locations are recorded in page notes. You can add or edit marks manually and reposition them by clicking the PDF.
5. Save the PDF, requirements, research, and annotations within the project. Exported PDFs include color and part tables, sources, and unprocessed page numbers. Marker numbers use `page.mark`; an orange border indicates that a mark has not yet been manually checked. Importing and exporting do not overwrite the original document automatically.

Manual studies are stored separately under `Application Support/Golden调色/ManualStudies`, rather than placing PDFs in UserDefaults. Changing the kit requirements or PDF suspends display and export of old annotations; successful new research clears those annotations. A manual mark does not imply the AI analyzed the entire page.

Researched colors with a defensible RGB approximation can be sent to GOLDEN mixing through `用 GOLDEN 试调此色` (Try This Color with GOLDEN). Saved mixing notes retain the subject, researched color, and sources. Colors without an RGB basis do not generate recipes.

This feature uses the configured Codex model and requires image input and online search support. Page annotation reads the supplied page and existing research; ordinary recipe generation keeps search disabled. AI interpretation of fine part numbers, camouflage areas, and historical sources still requires review.

## Color data and provenance

The app stores verified reference data locally and does not download color charts at runtime. Source URLs, original-file SHA-256 hashes, PDF pages, sampling coordinates, color profiles, and value changes are recorded in [paint-swatch-sources.json](docs/paint-swatch-sources.json).

### Fluid sRGB

The original Fluid 13-color set was checked on October 9, 2026 against the [GOLDEN virtual mixer](https://goldenartistcolors.com/mixer/acrylic?tab=palette-builder) and its [source data](https://assets.goldenartistcolors.com/mixerPaintData/index.json). Values use each entry's `paintColor.srgb` for the unmixed color. The mixer uses 1xxx IDs and `paletteTags` to identify applicable series; the app retains the bottle's Fluid 2xxx code. The two added colors were checked on November 11, 2026. All entries below include the `Fluid` tag.

| Fluid code | Mixer ID | Color | sRGB | HEX |
| --- | --- | --- | --- | --- |
| 2009 | 1009 | Benzimidazolone Yellow Light | 246, 207, 0 | #F6CF00 |
| 2008 | 1008 | Benzimidazolone Yellow Medium | 254, 192, 0 | #FEC000 |
| 2210 | 1210 | Naphthol Red Light | 201, 31, 16 | #C91F10 |
| 2305 | 1305 | Quinacridone Magenta | 91, 23, 45 | #5B172D |
| 2260 | 1260 | Phthalo Blue (Red Shade) | 30, 19, 52 | #1E1334 |
| 2255 | 1255 | Phthalo Blue (Green Shade) | 32, 17, 75 | #20114B |
| 2270 | 1270 | Phthalo Green (Blue Shade) | 1, 40, 51 | #012833 |
| 2275 | 1275 | Phthalo Green (Yellow Shade) | 0, 44, 42 | #002C2A |
| 2040 | 1040 | Carbon Black | 35, 34, 34 | #232222 |
| 2380 | 1380 | Titanium White | 247, 247, 242 | #F7F7F2 |
| 2276 | 1276 | Pyrrole Orange | 243, 60, 0 | #F33C00 |
| 2150 | 1150 | Dioxazine Purple | 40, 31, 29 | #281F1D |
| 2407 | 1407 | Yellow Ochre | 178, 121, 47 | #B2792F |
| 2400 | 1400 | Ultramarine Blue | 25, 18, 62 | #19123E |
| 2250 | 1250 | Permanent Green Light | 0, 118, 57 | #007639 |

Permanent Green Light is also called `Perm Green Light` in the mixer; both names are searchable. Deep colors such as Dioxazine Purple may appear nearly black in their unmixed preview. These values reproduce the source data and do not guarantee identical physical color across paint series.

### Branded references and SoFlat swatches

Version 1.0.12 updated 354 references: 342 Tamiya/Mr.Hobby colors and 12 SoFlat colors. Fluid continued using the mixer data. Previews, RGB/HEX labels, and AI ingredient inputs use the same stored values.

| Original update scope | Count | Source and method |
| --- | --- | --- |
| Tamiya enamel X / XF with unambiguous product matches | 35 | [Encycolorpedia](https://encycolorpedia.jp/paints/tamiya) HEX values matched to 800xx / 803xx enamel product numbers |
| Tamiya acrylic X / XF, LP, TS, and unmatched enamel colors | 179 | Corresponding swatches from the [official 2024 Tamiya chart](https://www.tamiya.com/cms/img/usr/inst/paints/202405_paints.pdf), converted to sRGB |
| Mr.Hobby C / H / N | 128 | Separate series swatches from the [official 2024–2025 charts](https://www.mr-hobby.com/en/record-download/catalog/23) |
| GOLDEN SoFlat | 12 | Official brush-painted images from each 6xxx product page, using their embedded sRGB IEC61966-2.1 profiles |

Encycolorpedia's matched Tamiya codes describe enamel products, so they are not copied across acrylic, LP, or TS references. Unmatched enamel colors X-2, X-7, X-18, XF-1, XF-2, XF-3, and XF-63 use the official chart. Matching X/XF numbers retain separate identities across series.

PDF charts were rendered to sRGB with ICC color management using MuPDF 1.28.2. Each swatch is sampled from a text-free 6×6-point region at 4× resolution, using the median of each channel. Cross-reference codes printed on a chart do not cause RGB values to be reused across series. The 1.0.18 additions use the available official 2024 chart; a 2026 chart link returned 404 and was not used.

The GOLDEN mixer does not provide a dedicated SoFlat palette. SoFlat values instead come from each product's original `swatches-web-1000px` WebP image. After checking product identity and its embedded ICC profile, the image is converted to sRGB using relative colorimetric intent. Sampling uses the 50×40-pixel region `[360, 470, 410, 510]` on paint over white between the first two black opacity-test stripes, taking channel medians. These are image samples, not manufacturer-published paint measurements.

| SoFlat code | Color | sRGB | HEX |
| --- | --- | --- | --- |
| 6755 | Titanium White | 244, 248, 249 | #F4F8F9 |
| 6745 | Black | 31, 36, 31 | #1F241F |
| 6660 | Permanent Green | 1, 114, 64 | #017240 |
| 6610 | Ultramarine Blue | 1, 38, 214 | #0126D6 |
| 6505 | Cadmium Primrose | 255, 241, 22 | #FFF116 |
| 6550 | Naphthol Red Light | 240, 43, 18 | #F02B12 |
| 6645 | Cobalt Teal | 2, 167, 168 | #02A7A8 |
| 6510 | Bismuth Vanadate Yellow | 255, 235, 2 | #FFEB02 |
| 6570 | Naphthol Pink | 239, 65, 80 | #EF4150 |
| 6530 | Cadmium Orange | 254, 102, 13 | #FE660D |
| 6595 | Red Violet | 111, 53, 104 | #6F3568 |
| 6675 | Yellow Green | 174, 232, 52 | #AEE834 |

Printed-chart conversions and digital swatches are screen references, not measurements of dried paint. Metallic, pearlescent, fluorescent, transparent, and iridescent effects cannot be guaranteed by RGB matching.

Saved recipes retain their RGB snapshots. Older references without snapshots, including those from 1.0.7–1.0.8, are restored using their earlier RGB values. Updating the catalog does not recalculate saved targets or ingredient amounts. Newly selected references use the current data.

For a manual UI check, compare Tamiya enamel XF-53 (`#6D787C`), acrylic XF-53 (`#71848E`), and Mr.Hobby C13 (`#74858D`), including their source notes. Hover over SoFlat ingredient rows to inspect sRGB values, and reopen an older recipe to confirm that its preview and quantities are preserved.

## Earlier generation improvements

Version 1.0.13 fixed requests at `max` reasoning effort being stopped by the former four-minute timeout. A recorded test using the then-configured `gpt-6.1-sol · max`, Tamiya TS-8, and Fluid 13 returned three valid independent 200-drop recipes after 241.9 seconds. That describes the workflow at that version; 1.0.19 uses base portions and additions for new shadows and highlights.

The current timeout is 20 minutes for `max` / `ultra`, 10 minutes for `xhigh`, and four minutes for the other options. Actual duration depends on the model and service. The app preserves the selected effort, supports cancellation, and displays the applicable timeout in settings, progress, and error messages. Generation moves to the results area, and failures remain visible in a selectable, scrollable message above the results.

## Development

Open `Golden调色.xcodeproj` in Xcode, select your own development team under Signing & Capabilities, and build or run the `Golden调色` scheme.

`Golden调色 Release` is the shared Release scheme. Select `Any Mac (arm64, x86_64)` when building the universal application.

Unit tests are in `Golden调色Tests`; UI tests are in `Golden调色UITests`. Run them from Xcode. AI integration tests use fixed responses and simulated CLI behavior, so they do not require live model calls. Version 1.0.19 was validated with 88 unit test methods and four UI workflow tests; these checks verify application behavior rather than physical paint accuracy.

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` manage the app version and build number. Increment both for each app iteration. DMGs and checksums are kept in the ignored `dist/` directory and distributed through GitHub Releases.
