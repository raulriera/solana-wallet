# Themes

Theme packs: reading, validating, and saving them, applying their colors and font design over app defaults, and exporting templates to start a new one.

## Usage

```swift
import Themes

let service: any PackServicing = PackService()
let pack = try await service.read(from: packURL)
let tokens = defaults.applying(pack)
try await service.exportTemplate(named: "My Theme", defaults: defaults, to: templateURL)
```

`defaults` is the app's `Tokens`: a complete `Palette` for each appearance and a `FontDesign`. `applying(_:)` keeps every default the pack omits.

## Build a theme pack

A `.xtheme` pack is a folder with `manifest.json` and optional images in `Assets/`. Files shows it as one document.

```text
Example.xtheme/
├── manifest.json
└── Assets/
    └── background.png
```

To start, export a template from the app: it holds every default color, the default font design, and a new ID. Edit it, then import the pack through Files.

### Manifest

| Field | Requirement |
| --- | --- |
| `version` | Required. `1`. |
| `id` | Required UUID string. Use a new one for each theme, and keep it when you update or rename the theme. |
| `name` | Required, nonempty display name. |
| `tokens` | Optional colors and font design. Omitted values use the app's defaults. |
| `assets` | Optional map of asset names to paths inside `Assets/`. |

```json
{
  "version": 1,
  "id": "a416c5bc-e1f3-4614-929a-cef0b40af7d0",
  "name": "Example",
  "tokens": {
    "colors": {
      "light": {
        "primary": { "srgb": "#26643E" }
      }
    },
    "fontDesign": "monospaced"
  },
  "assets": {
    "background": "Assets/background.png"
  }
}
```

### Colors

- Appearances under `tokens.colors`: `light` and `dark`.
- Roles in each appearance: `background`, `surface`, `text`, `secondaryText`, `separator`, `primary`, `onPrimary`, `secondary`, `onSecondary`, `destructive`, `onDestructive`, `border`, and `sidebar`.
- `primary`, `secondary`, and `destructive` fill their buttons. Each `on` role colors the text and symbols on that fill. `primary` also colors links and controls without a fill, and `destructive` colors destructive text without a fill. `border` outlines buttons; use `clear` for none. `sidebar` fills sidebars; use `clear` for the system sidebar.
- Each color is a [system color](Sources/Colors/Color.swift), such as `{ "system": "systemBackground" }`, or an opaque sRGB color, such as `{ "srgb": "#26643E" }`.

### Font design

`tokens.fontDesign` sets the design of the system font: `default`, `rounded`, `serif`, or `monospaced`. Text keeps its sizes and weights. Omitted, it uses the app's default.

### Assets

- PNG or JPEG files inside `Assets/`, with no external URLs, absolute paths, or symbolic links.
- Every declared asset must exist.
- Limits: 1 MiB for the manifest, 16 MiB and 16,777,216 pixels for each image, and 64 MiB of images for each pack.

Import rejects explicit `null` values, unknown settings, wrong types, unsupported values, and invalid assets.
