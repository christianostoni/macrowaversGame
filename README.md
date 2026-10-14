# Macrowavers

A native visionOS game for Apple Vision Pro inspired by a Persian fairy tale, built in 40 days by a team of five
for the Arte-1 challenge.

Stack: Swift 6, SwiftUI, RealityKit, Reality Composer Pro 3. Target: visionOS 26.5 (deployment target, matching the team's test devices).

## Features

### Untangle the Dragon

Branch `feature/AR126-100-untangle-dragon` · Jira AR126-100 · full docs in
[docs/features/untangle-dragon/README.md](docs/features/untangle-dragon/README.md)

A mixed-reality chapter of the tale. A floating island appears in the room with a dragon bound to the tree at its
centre. The player spins the island, finds the artifact hidden in an apple to soothe the dragon, and it settles in front
of them with its long body tied in a knot. The player has to set it free:

- **Untangle it with your hands.** Pinch and drag any part of the body, even two parts at once (one per hand), and
  lift them to pass them over or under the rest. The part you look at glows; red pulsing spheres mark every
  crossing and the panel counts how many are left.
- **The dragon fights back.** If you stop making progress it warns you (it stares at you, growls, smoke rises
  from its nostrils), then it has a fit: it turns around, rears up and roars with a burst of fire, lashes its tail
  and coils. Every fit adds at least one new crossing, and fits come sooner each time.
- **Set it free.** At zero crossings the dragon turns gold, celebrates, circles you, roars its thanks and flies
  away into the sky.
- **Two windows only.** The main window opens the island, spins it and restarts the whole game; the dragon panel
  (opened by tapping the dragon) shows its state and debug info and restarts the dragon's scene.

### The Tree's Fruit

Full docs in [docs/features/apple-artifact/README.md](docs/features/apple-artifact/README.md). Apples and a
pomegranate hang on the island's tree. Pick one and it comes close: pull the apple's stem to open its spiral cut
(a Metal shader), catch the worms that crawl and burrow between the slices, and the artifact rises out. Tapped,
it flies to the dragon and soothes it. The pomegranate bursts into seeds you can play with.

Open it from the main window with **Open the Island**. It uses a placeholder dragon built in code until the
design team's asset (`DragonBody` / `DragonHead`) is added; the asset specification is in the feature docs.

## Requirements

- macOS 26 or later, Xcode 27 with a visionOS 26.5 (or later) simulator runtime
- Xcode's Metal Toolchain: `xcodebuild -downloadComponent MetalToolchain` (for the apple's shader)
- Reality Composer Pro 3 (separate beta download from Apple)
- Homebrew (for `brew bundle`: GitHub CLI, Git LFS, SwiftLint)
- Vision Pro in Developer Mode, paired in Xcode's Device Hub, for anything with hands, room sensing or comfort

## Quick start

```bash
git clone <repo-url> game && cd game
brew bundle                                   # gh, git-lfs, swiftlint
git lfs install && git lfs pull               # binary assets
git config core.hooksPath .githooks           # commit message, LFS and SwiftLint checks
git config pull.rebase true && git config fetch.prune true && git config push.autoSetupRemote true
cp Configs/Local.xcconfig.example Configs/Local.xcconfig   # then set DEVELOPMENT_TEAM for device builds
open Macrowavers.xcodeproj
```

Then: Cmd-U runs the unit tests on the simulator and `swiftlint lint --strict` runs SwiftLint like CI does.
New files under `Sources/` and `Tests/` join the targets automatically (synced folders, see `docs/decisions/0004`).

## How we work

Feature branches merged into `main` through reviewed PRs, one tagged release per sprint.
**Read [CONTRIBUTING.md](CONTRIBUTING.md) before your first branch.** In short:

```
main      ──●──────●──────●──────●──●──   always builds; tag v0.1.0, v0.2.0 ... v1.0.0 at each sprint end
             \    /        \    /
feature/      ●──●          ●──●           feature/AR126-12-orbit-gesture or fix/..., squash-merged
```

- Branch from `main`: `git switch main && git pull && git switch -c feature/AR126-12-orbit-gesture`
- Open a PR into `main`. CI must be green and one teammate approves. Squash merge.
- Sprint end: bump the version in a small PR, then tag `main` (`v0.2.0`).
- Tracker: Jira project AR126. GitHub Issues are off on purpose.

## Layout

| Path | What |
|---|---|
| `Macrowavers.xcodeproj` | Committed Xcode project; `Sources/Macrowavers` and `Tests/` are synced folders |
| `Sources/Macrowavers/` | App code: `App/`, `Model/` (testable game rules), `Views/`, `Resources/` (`.reality` exports, asset catalogs) |
| `Tests/` | Unit tests (Swift Testing) |
| `RealityComposerPro/` | RCP 3 projects, one owner per scene at a time, stored in Git LFS |
| `Assets/` | Blender, texture and audio sources, stored in Git LFS |
| `Configs/` | `Local.xcconfig.example`: copy holds your signing team, gitignored |
| `.github/` | CI, release automation, PR template, CODEOWNERS, `rulesets/` (branch protection definitions) |
| `docs/` | `ci.md` (runner setup), `decisions/` (why we work this way), `features/` (one README per feature) |
