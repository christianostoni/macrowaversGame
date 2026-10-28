# Source assets

Working files that are not loaded by the app directly. Binary formats here are stored in Git LFS.

| Folder | What | Naming |
|---|---|---|
| `Blender/` | One folder per model: the design team's sources (`.usdc`, or `.usdz` from Reality Composer Pro) and the scripts, run headless through Blender's Python (`pxr`), that prepare them for `Sources/Macrowavers/Resources/` (`apple/` only measures the apple for the spiral cut; `loading-dragon/` renders the loading animation from the game's dragon) | `elixir-flask/elixir_flask.usdc`, `make_flask_asset.py` (snake_case) |
| `Scroll/` | The story's scroll: the paper and the painting (made with ChatGPT in the game's style, no text), `make_scroll_page.swift`, which sets the Persian story on them into `Sources/Macrowavers/Resources/ScrollPage.jpg`, and the design team's Blender scroll whose roll the app reproduces (see `docs/features/storytelling/README.md`) | `paper.png`, `make_scroll_page.swift` |
| `SnapHint/` | `make_snap_hint_hand.sh` (with `make_snap_hint_hand.swift`), which bakes the hologram hand's meshes into `Sources/Macrowavers/Resources/SnapHintHand.bin` (see `docs/features/apple-artifact/README.md`) | `make_snap_hint_hand.swift` |
| `Icon/` | The app icons' Icon Composer documents (`AppIcon.icon`, the default; `AppIconRedDragon.icon`, `AppIconBlackDragon.icon`, alternates) and `make_visionos_icon.swift`, which renders each into the visionOS layers of the `.solidimagestack` of the same name (usage in the script's header; see `docs/features/storytelling/README.md`) | `AppIconRedDragon.icon` |
| `Textures/` | Source textures, HDRIs | `bark_albedo_2k.png`, `sky_hdri_4k.exr` |
| `Audio/` | Sound effects and music as generated or downloaded, before conversion to the mono `.m4a`/`.wav`/`.caf` the app loads from `Sources/Macrowavers/Resources/` (PascalCase) | `dragon_roar.mp3` → `DragonRoar.m4a` |

How to run each script, and what it produces, is in the feature docs under `docs/features/`. `Textures/` does not
exist yet: create it with the first file.

Guidelines: keep single files under 25 MB, textures at 2K unless a close-up needs 4K, and share materials between
entities. Many unique materials and large textures are the most common frame-rate killers on Vision Pro.
