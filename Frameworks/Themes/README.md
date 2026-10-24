# Themes

Themes reads, validates, saves, and resolves theme packs, and exports default templates. The provisional format supports semantic colors and bundled images.

## Package structure

A `.xtheme` pack is a directory containing `manifest.json` and optional images under `Assets/`. Files presents the package as one document.

```text
Example.xtheme/
├── manifest.json
└── Assets/
    └── background.png
```

## Manifest

| Field | Requirement |
| --- | --- |
| `version` | Required integer. Format version: `1`. |
| `id` | Required UUID string. Keep it when updating or renaming a theme. |
| `name` | Required, nonempty display name. |
| `tokens` | Optional appearance overrides. Omitted settings use app defaults. |
| `assets` | Optional mapping of asset names to relative paths inside `Assets/`. |

```json
{
  "version": 1,
  "id": "a416c5bc-e1f3-4614-929a-cef0b40af7d0",
  "name": "Example",
  "tokens": {
    "colors": {
      "light": {
        "accent": { "srgb": "#26643E" }
      }
    }
  },
  "assets": {
    "background": "Assets/background.png"
  }
}
```

Use a new UUID for each new theme.

## Appearance values

- Color roles: `background`, `surface`, `primaryText`, `secondaryText`, `separator`, `accent`, and `onAccent`.
- Colors use exactly one representation: a [supported system color](Sources/Colors/Color.swift) such as `{ "system": "systemBackground" }`, or an opaque sRGB color such as `{ "srgb": "#26643E" }`.
- Appearance keys under `tokens.colors`: `light`, `dark`, `lightIncreasedContrast`, and `darkIncreasedContrast`. Missing values use that appearance's defaults; dark palettes are not generated from light palettes.
- Only color tokens are supported. Typography, spacing, shapes, motion, and layout tokens are not accepted.

## Assets

- Use PNG or JPEG. PNG supports transparency.
- Paths must remain inside `Assets/`. External URLs, absolute paths, and symbolic links are unsupported.
- Every declared image must exist and be readable. Declaring an asset does not assign it to a component.
- Limits: 1 MiB per manifest (including room for complete export values), 16 MiB per image file, 64 MiB of unique image files per pack, and 16,777,216 pixels per image. Asset names referencing the same path share one retained buffer and count once toward the byte budget.

## Import and export

- Author packs externally and import through Files. Installed packs stay local.
- Omit settings to use defaults. Explicit `null`, unknown settings, incorrect types, unsupported values or versions, and invalid assets cause import errors.
- Validation checks structure and safe asset loading, not aesthetics or HIG conformance.
- Default-template exports contain all defaults and a new UUID. System color references remain symbolic. Imported themes are not re-exported.

## Example Usage

Inject `PackServicing`, implemented by the stateless `PackService`. Supply `Colors` with a complete `Palette` for each appearance; the framework defines no default palette.

```swift
let service: any PackServicing = PackService()
let pack = try await service.read(from: sourceURL)
let colors = service.resolve(pack, defaults: defaults)
try await service.save(pack, to: installedURL)
try await service.exportTemplate(named: "My Theme", defaults: defaults, to: templateURL)
```

Reads retain independent asset bytes. File access waits asynchronously; loading, validation, serialization, and writing run serially at user-initiated priority on a shared queue outside the main actor and Swift's shared executor. Cancellation interrupts pending coordination and is checked during loading and before committing an atomic export; a write already underway finishes normally.

Use `save(_:to:)` for an installed copy that preserves identity, assets, and omitted settings. Saving an installation does not freeze its inherited defaults.

Resolve colors when the selected pack or defaults change. Resolved palettes contain stored values; accessing a color performs no I/O or decoding.

The app owns Files presentation, destination/replacement approval, installation, preferences, and rendering. Invalid packages throw `ValidationError`; file-access and cancellation errors propagate to the caller.
