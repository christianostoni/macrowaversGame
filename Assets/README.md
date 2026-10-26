# Source assets

Working files that are not loaded by the app directly. Binary formats here are stored in Git LFS.

| Folder | What | Naming |
|---|---|---|
| `Blender/` | One folder per feature: model sources (`.usdc`, `.blend`) and the headless Blender scripts that export them to `Sources/Macrowavers/Resources/` | `elixir-flask/elixir_flask.usdc`, `make_flask_asset.py` (snake_case) |
| `Icon/` | The app icons' Icon Composer documents (`AppIcon.icon`, the default; `AppIconRedDragon.icon`, `AppIconBlackDragon.icon`, alternates) and `make_visionos_icon.swift`, which renders each into the visionOS layers of the `.solidimagestack` of the same name (usage in the script's header; see `docs/features/storytelling/README.md`) | `AppIconRedDragon.icon` |
| `Textures/` | Source textures, HDRIs | `bark_albedo_2k.png`, `sky_hdri_4k.exr` |
| `Audio/` | Source audio before conversion | `dragon_roar.wav` |

How to run each script, and what it produces, is in the feature docs under `docs/features/`. `Textures/` and
`Audio/` do not exist yet: create them with the first file.

Guidelines: keep single files under 25 MB, textures at 2K unless a close-up needs 4K, and share materials between
entities. Many unique materials and large textures are the most common frame-rate killers on Vision Pro.
