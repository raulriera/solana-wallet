# Themes

Themes is the planned framework for theme-pack data and package operations, included in the app alongside its other frameworks. This README defines the agreed pre-release contract for theme authors and agents. The framework target, public Swift API, and production import/export implementation are not yet present.

The framework owns manifest models, package reading and writing, structural validation, and resolving overrides against a complete baseline supplied by the app. The app owns the Files picker, installed-pack catalog, appearance preferences, wallet overrides, recovery controls, and rendering. See [UI architecture](../references/ui.md) for those responsibilities.

## Package structure

A theme pack is a directory containing `manifest.json` and optional images under `Assets/`. The registered package type lets Files present the directory as one document. The final extension is undecided; it must be independent of the app's name.

```text
Example/
├── manifest.json
└── Assets/
    └── background.png
```

The name `Example/` illustrates the contents; it does not establish an extension. Creating a package requires ordinary folders, a JSON editor, and any bundled images. A ZIP archive is not the package format. Cross-platform sharing workflows remain unverified.

## Manifest

| Field | Requirement |
| --- | --- |
| `version` | Required integer; initially `1`. Identifies the format, not a revision of the theme. |
| `id` | Required UUID string. Identifies the theme independently of its display name or filename. |
| `name` | Required, nonempty display name. |
| `tokens` | Optional object containing appearance overrides. Omitted settings inherit the corresponding baseline values. |
| `assets` | Optional object mapping asset names to relative paths inside `Assets/`. |

The smallest manifest uses the entire baseline:

```json
{
  "version": 1,
  "id": "a416c5bc-e1f3-4614-929a-cef0b40af7d0",
  "name": "Example"
}
```

The UUID above is an example. Use a new UUID for a new theme; retain its UUID when editing or renaming that same theme.

## Appearance values

Tokens describe semantic purposes independently of screens. Color roles are `background`, `surface`, `primaryText`, `secondaryText`, `separator`, `accent`, and `onAccent`.

Each color supplies exactly one representation:

```json
{ "system": "systemBackground" }
```

```json
{ "srgb": "#26643E" }
```

System values refer to supported iOS colors and remain symbolic during export. sRGB values are opaque six-digit `#RRGGBB` colors. Supplying both representations is invalid.

Follow system light and dark appearance and increased contrast, with an increased-contrast variant for each appearance. Missing values inherit the baseline for the corresponding appearance; a custom light palette does not automatically generate a dark palette.

Typography uses iOS system text styles with default, rounded, serif, or monospaced designs. Custom font files are unsupported, and control icons remain app-owned SF Symbols. Standard Dynamic Type has no custom cap.

Spacing, shapes, decorative motion, component-specific asset usage, and layout choices remain provisional until the consuming components are designed. The complete token catalog and default values are not finalized. Do not treat illustrative appearance values as an approved built-in theme.

## Assets

An asset declaration names a bundled file, for example:

```json
{
  "assets": {
    "background": "Assets/background.png"
  }
}
```

This fragment declares an asset; it does not define which component displays it. Component-specific bindings require an agreed component contract.

- Support PNG artwork and textures, including transparency, and JPEG photographic backgrounds.
- Paths must stay inside the package's `Assets/` directory. Absolute paths, paths escaping the package, external URLs, and symbolic links are unsupported.
- A declared asset must exist and be readable in a supported image format.

## Import rules

| Input | Behavior |
| --- | --- |
| Omitted appearance setting | Use its complete app-owned baseline value. |
| Explicit `null`, wrong type, unknown setting, or unsupported supplied value | Reject with the field path and a clear explanation. |
| Unsupported `version` | Explain that the app cannot read that format version. |
| Color containing both `system` and `srgb` | Reject the ambiguous color. |
| Missing, unreadable, or unsupported declared image | Reject the import. |
| Existing custom theme ID | Require explicit replacement. Built-in themes remain available. |
| Any import failure | Leave installed themes and appearance preferences unchanged. |

For example: `tokens.colors.light.accent: expected either “system” or “srgb”, but received both.`

Validation covers structure, supported settings and image formats, and safe asset loading. It does not reject or rewrite a custom theme for contrast, aesthetic choices, or HIG conformance. Navigation behavior, action meanings, accessibility semantics, and transaction approval requirements remain app-owned.

## Authoring and export

Themes are authored externally and imported through the system Files picker. Installed copies are local; there is no in-app theme editor or app-managed cloud synchronization.

Once production export is implemented:

1. Export the default template to start a new theme. It includes every supported appearance setting with its default value and a new custom theme UUID.
2. Edit `manifest.json` and add any PNG or JPEG assets. Settings may be omitted to inherit the baseline; use omission rather than `null`.
3. Import the package. Keep the same UUID when updating that theme and explicitly confirm replacement when it already exists.

Exporting an existing custom theme preserves its UUID and includes complete resolved settings and its bundled assets. System color references remain symbolic. The complete default template is not available until the baseline and supported token catalog are defined.

## Versioning and agent guidance

- The pre-release format may change as production UI exercises it. Do not build migrations for development packs. Stabilize version 1 alongside the first production UI before shipping.
- After shipping, preserve compatibility for existing packs. New optional settings inherit defaults; removal or changes in type or meaning require deliberate format versioning.
- Keep the manifest and package extension independent of app branding.
- Resolve defaults centrally before rendering. Views receive complete values and do not repeat fallback or decoding logic.
- Keep framework contracts narrow and protocol-based; hide serialization and asset-loading helpers behind the services that need them.
- Keep wallet identity, window state, user selection, and presentation workflows in the app. Do not make theme data depend on wallet or transaction frameworks.
- Agree on additional tokens and component behavior before implementing them. Disposable mockups do not approve production UI.
- Update this contract when approved format decisions change. Keep examples consistent with it.
