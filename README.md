# Macrowavers

A native visionOS game for Apple Vision Pro inspired by a Persian fairy tale, built by a team of six for the
Arte-1 challenge. On the Home View the app is called **Toranj Flying Dragon** (`CFBundleDisplayName` in
`Sources/Macrowavers/Info.plist`); Macrowavers is the project, target and scheme name.

Stack: Swift 6 (strict concurrency), SwiftUI, RealityKit, Metal. Deployment target: visionOS 26.5, matching the
team's devices. Tracker: Jira project AR126.

## The story

The game plays in mixed reality, in the player's room:

1. **Start.** A Start button floats in the room, with a small **App Icon** menu under it (Stone Dragon, Red
   Dragon, Black Dragon). The room dims and a Persian scroll appears: pull it open, drag its paper up to read the
   chapter's story, *The Shah's Tree*, down to its painting, and continue (or skip it). Then "Chapter I": tap the
   text to go on.
2. **The island.** A floating island fades in, with a dragon bound to the tree at its centre, circling it. Tap the
   dragon and it gets angry for a moment.
3. **The fruit.** Apples, a pomegranate, a banana, an orange and a pineapple hang on the tree. Pick one and it
   comes close: cup a hand next to it and turn the hand to turn the fruit; pull the apple's stem to open its spiral cut and catch the worms guarding it, pull the pomegranate
   apart with two hands, peel the banana strip by strip, pull the orange apart into wedges, chop the pineapple.
   Every fruit frees a glowing ingredient that joins a small orbit on your right.
4. **The elixir.** With three ingredients in orbit, snap your fingers: they dive one by one into the flask in the
   middle of the orbit. The flask flies to the dragon, which stops and lifts its head, and pours the elixir over
   it.
5. **Untangle the dragon.** Soothed, the dragon comes to you and settles with its long body tied in a knot. Pinch
   and drag any part of it, even two at once (one per hand), and lift it over or under the rest until no crossing
   is left. Stop making progress and the dragon warns you, then has a fit: it rears up, roars fire, lashes its
   tail and adds new crossings.
6. **Farewell.** Free, the dragon thanks you, offers to take you to safety and flies away into the sky.

No window covers the game: the launch window steps aside when the immersive space opens. Inside the space,
panels are attached to the scene: the island panel (left) rotates the island and restarts the game, a small panel
under the picked fruit says what to do, and a label under the ingredients' orbit says how to brew the elixir.

The dragon, the fruit and the elixir play spatial sound effects. Music follows the story: a setar under the
narrator's pages and the fruit, the puzzle theme from the dragon's flight to the knot, and the farewell theme once
it is free. Tracks crossfade, and the music steps back while the dragon roars.

Full documentation, one README per feature:

| Feature | Docs |
|---|---|
| The floating island and the dragon: orbit, flight, untangling puzzle, farewell | [docs/features/untangle-dragon](docs/features/untangle-dragon/README.md) |
| The tree's fruit, the ingredients' orbit, the flask and the elixir | [docs/features/apple-artifact](docs/features/apple-artifact/README.md) |
| The story screens: Start and the app icon menu, the narrator, the dragon's words, the music | [docs/features/storytelling](docs/features/storytelling/README.md) |

## Requirements

- macOS 26 or later, Xcode 26.6 or later with the visionOS 26.5 (or later) simulator runtime
- Xcode's Metal Toolchain, for the apple's shader: `xcodebuild -downloadComponent MetalToolchain`
- Git LFS and SwiftLint: `brew install git-lfs swiftlint` (the GitHub CLI, `gh`, is optional)
- A Vision Pro in Developer Mode, paired in Xcode, for anything with hands or comfort. The simulator has no hand
  tracking: there hold Option to pull the pomegranate and the orange apart with two hands, a tap chops the
  pineapple, and a tap on an ingredient or **Brew the Elixir** replaces the finger snap; turning a fruit with a
  cupped hand needs the headset

## Quick start

```bash
git clone https://github.com/christianostoni/macrowaversGame.git && cd macrowaversGame
git lfs install && git lfs pull               # binary assets (models, audio, icon images)
git config core.hooksPath .githooks           # commit message, LFS and SwiftLint checks
git config pull.rebase true && git config fetch.prune true && git config push.autoSetupRemote true
cp Configs/Local.xcconfig.example Configs/Local.xcconfig   # then set DEVELOPMENT_TEAM for device builds
open Macrowavers.xcodeproj
```

Then run the `Macrowavers` scheme. Cmd-U runs the unit tests on the simulator and `swiftlint lint --strict` runs
SwiftLint like CI does. New files under `Sources/` and `Tests/` join the targets automatically (synced folders).

## How we work

Feature branches merged into `main` through pull requests. **Read [CONTRIBUTING.md](CONTRIBUTING.md) before your
first branch.** In short:

- Branch from `main`: `git switch main && git pull && git switch -c feature/AR126-12-slug`.
- Open a PR into `main`. A teammate pulls the branch, runs it on their Mac or on a Vision Pro, checks that CI is
  green, approves and squash-merges it.
- CI ([docs/ci.md](docs/ci.md)) checks the PR title and SwiftLint. It does not build: the reviewer builds the app
  and runs the unit tests on their Mac.

## Layout

| Path | What |
|---|---|
| `Macrowavers.xcodeproj` | Committed Xcode project; `Sources/Macrowavers` and `Tests/MacrowaversTests` are synced folders |
| `Sources/Macrowavers/` | App code: `App/`, `Model/` (game rules, no SwiftUI or RealityKit), `Views/` (SwiftUI and RealityKit), `Resources/` (`.usdz` models, `.m4a`/`.wav`/`.caf` audio, `Assets.xcassets` with the three app icons) |
| `Tests/MacrowaversTests/` | Unit tests of the game rules (Swift Testing) |
| `Assets/` | Asset sources, stored in Git LFS: `Blender/` (models and the scripts, run headless through Blender, that prepare them), `Icon/` (the app icons' Icon Composer documents), `Audio/` (sound and music sources) |
| `Configs/` | `Base.xcconfig` and `Local.xcconfig.example`: your copy holds your signing team, gitignored |
| `.github/` | CI and release workflows, PR template |
| `.githooks/` | `commit-msg` and `pre-commit` checks |
| `docs/` | `ci.md` (the CI jobs), `features/` (one README per feature) |
