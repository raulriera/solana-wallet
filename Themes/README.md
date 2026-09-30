# Themes

Theme packs customize app appearance through semantic tokens and bundled images. The format is provisional.

## Package structure

A pack is a directory containing `manifest.json` and optional images under `Assets/`. Files presents it as one document. The package extension is not yet defined.

```text
Example/
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
- Colors use exactly one representation: a supported system color such as `{ "system": "systemBackground" }`, or an opaque sRGB color such as `{ "srgb": "#26643E" }`.
- Themes follow system light, dark, and increased-contrast appearance. Missing values use the corresponding defaults; dark palettes are not generated from light palettes.
- Typography uses iOS system text styles with default, rounded, serif, or monospaced designs and standard Dynamic Type. Custom fonts are unsupported; control icons remain app-owned SF Symbols.

## Assets

- Use PNG or JPEG. PNG supports transparency.
- Paths must remain inside `Assets/`. External URLs, absolute paths, and symbolic links are unsupported.
- Every declared image must exist and be readable. Declaring an asset does not assign it to a component.

## Import and export

- Author packs externally and import through Files. Installed packs stay local.
- Omit settings to use defaults. Explicit `null`, unknown settings, incorrect types, unsupported values or versions, and invalid assets cause import errors. Field errors identify the affected path.
- Failed imports leave installed themes and preferences unchanged. Replacing a custom theme with the same ID requires confirmation; built-in themes remain available.
- Validation checks structure and safe asset loading, not aesthetics or HIG conformance.
- Default-template exports contain all defaults and a new UUID. Custom-theme exports preserve the UUID and include resolved settings and assets. System color references remain symbolic.
