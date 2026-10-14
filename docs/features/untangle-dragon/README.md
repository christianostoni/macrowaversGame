# Untangle the Dragon (AR126-100)

A mixed-reality chapter of the Persian fairy tale: a floating island with a tree at its centre appears in the
room, and a dragon is coiled around the tree. The player taps the dragon, which flies to them and settles in
the air in front of them, tangled in a knot. The player grabs the body with their hands and untangles it.
Once free, the dragon thanks the player and flies away into the sky.

Branch: `feature/AR126-100-untangle-dragon`. Status: playable with a temporary Sketchfab dragon (see
[Temporary asset](#temporary-asset)); the code-generated placeholder is used when the asset is not in the bundle.

## How to try it

1. Open `Macrowavers.xcodeproj` and run on the visionOS simulator or on a Vision Pro. Run `git lfs pull`
   first if the `.usdz` files under `Sources/Macrowavers/Resources/` are only LFS pointers.
2. The main window (the island window) asks you to **Open the Island**: an `ImmersiveSpace` in `.mixed` style
   opens, with the floating island ~2.8 m in front of you and the dragon circling its tree.
3. Spin the island by dragging its rock (or with both hands, or with the buttons in the island window): the
   dragon turns with it.
4. Look at the dragon and pinch (tap): it gets angry for ~3 s and the **dragon panel** opens next to the main
   window, with its state and debug info. Then it flies to you on its own (or tap **Call It Now** in the panel),
   stops to look at you, and settles tangled in front of you.
5. Pinch and drag the dragon's body (one part per hand), lift parts to pass them over or under the others.

Two-handed grabbing and the dragon looking at you need a real device; the simulator only does one hand and
uses a seated eye height of 1.15 m.

## What the player sees

| Moment | Behaviour |
|---|---|
| Start | Floating island with the dragon coiled around its tree, circling slowly; island and floating rocks bob gently. Looking at the dragon highlights it. The island turns like a turntable (drag the rock, two-handed rotate or window buttons) and the dragon turns with it |
| Tap the dragon | It gets angry: circles faster, glares at you, growls and snorts smoke. The dragon panel opens with "The dragon is getting angry!" and debug info (phase, mood, action, crossings, restlessness, strain) |
| After ~3 s of anger (or **Call It Now** in the panel; the future artifact goes here) | It flies to ~1 m from your eyes and hovers looking at you then settles in the air in front of you (no visible platform), tracing the knot with its body |
| Puzzle | Dragon tied in a trefoil knot (3 crossings), red pulsing spheres on every crossing, crossings left in the panel |
| Grab | The part you look at glows; pinch to grab, up to two parts at once; the dragon turns to your hand and growls if pulled hard |
| No progress (8 s, shorter each time, min 5 s) | 2 s warning: it stares at you, smoke from the nostrils, red eyes. Then a fit: it **turns around**, rears up and roars with a burst of fire, lashes its tail and coils, **always adding at least one new crossing** |
| Solved (0 crossings, body released for 0.6 s) | Turns gold, celebrates for 1.5 s, then **takes off**, circles you once, hovers in front of you roaring its thanks and **flies away into the sky**, fading out before it reaches the real ceiling. **Restart Scene** puts it back on the island |
| Play area | Invisible: the knot floats at knee/table height in front of the player. Rotate it with the panel buttons, tilt it with the slider, reset it. Default is tuned for a seated player |

All user-facing text is in English. Code comments are in Italian.

## Code layout

```
Sources/Macrowavers/
├── App/MacrowaversApp.swift          Scenes: island window, dragon panel (single Window), ImmersiveSpace (.mixed)
├── Views/ContentView.swift           Island window: launch, island rotation, Restart Game
├── Model/Untangle/                   Pure game logic: Foundation + simd only, unit-tested
│   ├── TangleSimulation.swift          Rope physics of the body (PBD/Verlet) and crossing count
│   ├── TangleShapes.swift              Initial knots from parametric curves (trefoil, figure-eight)
│   ├── DragonBehavior.swift            Difficulty: idle timer → fit (choreography of DragonAction), DragonMood
│   ├── DragonFlight.swift              Flights (orbit, approach, landing, farewell) with a "follow the leader" body
│   ├── DragonPhase.swift               Story chapters (captive → approaching → landing → untangling → free → gone)
│   ├── IslandPlacement.swift           Island position + OrbitPath (the curve around the tree)
│   ├── PlayAreaPlacement.swift         Play area position, rotation, tilt
│   └── UntangleViewModel.swift         @Observable @MainActor view model shared by panel and immersive space
└── Views/Untangle/
    ├── DragonPanelView.swift           Dragon panel: state, debug info, Call the Dragon, puzzle controls, Restart Scene
    ├── DragonImmersiveView.swift       RealityView, island, grab events, tap on the dragon
    └── RealityKit/                     Draws, never decides
        ├── DragonScene.swift             Components, System, scene building, grabbable colliders, crossing markers
        ├── DragonJourney.swift           Story ECS: OrbitComponent, DetanglingStateComponent, DragonTapTargetComponent
        ├── IslandScene.swift             Floating island (asset), tree anchor, FloatingComponent/System
        ├── DragonRig.swift               DragonRig protocol, DragonFrame, DragonPose, DragonLifeAnimator
        ├── DragonEffects.swift           Smoke, fire, optional spatial audio, placeholder wings
        ├── ViewerTracker.swift           Player head position (ARKit world tracking, no permission needed)
        ├── ProceduralDragonRig.swift     Placeholder dragon built from primitives
        └── SkeletalDragonRig.swift       Rig for the real asset, picked automatically when it is in the bundle
Sources/Macrowavers/Resources/DragonBody.usdz, DragonHead.usdz   Temporary dragon asset (Git LFS)
Sources/Macrowavers/Resources/FloatingIsland.usdz                 Floating island with the tree (Git LFS)
Assets/Blender/untangle-dragon/       Blender scripts that generate the assets (not in the app)
Tests/MacrowaversTests/UntangleTests.swift
```

MVVM: the Model does not import SwiftUI or RealityKit; the view model does not import RealityKit;
SwiftUI views and the RealityKit layer only read state and forward user actions.

### One frame

`DragonBodySystem.update` (RealityKit, every frame):
1. reads where the hands moved the grabbed colliders and passes them to the view model as targets;
2. `viewModel.update(...)` gets the orbit and the tree's transform from `OrbitComponent` and, depending on the chapter,
   runs the flight or the dragon's behaviour, the physics step, crossings, mood and win;
3. `DetanglingStateComponent` applies the chapter to the entities (only when it changes) and fades the dragon;
4. moves the other colliders to the simulated (or flying) positions;
5. `rig.update(DragonFrame)` draws the dragon; `CrossingMarkers` moves the red spheres.

Grab start/end comes from `ManipulationEvents.WillBegin/WillRelease/WillEnd`, subscribed in `DragonImmersiveView`.

## Design decisions (and why)

- **Windows: one main window, one dragon panel, one immersive space.** Before, the main window opened a control
  panel `WindowGroup` (a new instance on every open) that also owned Start/Close of the immersive space, next to an
  unrelated Start/Pause in the main window: several windows drove the same state and got out of sync. Now:
  - the **island window** (`ContentView`, main `WindowGroup`) is the only owner of the immersive space: it opens
    the island at launch, spins it, and **Restart Game** closes the dragon panel and the immersive space and resets
    everything to the launch screen;
  - the **dragon panel** (`DragonPanelView`) is a single-instance `Window` (`openWindow` brings it to the front
    instead of duplicating it), opened only by tapping the dragon, never at launch or restored from a previous
    session (`.defaultLaunchBehavior(.suppressed)`, `.restorationBehavior(.disabled)`), placed next to the main
    window. It shows the dragon's state and debug info and **Restart Scene** puts the dragon back on the island;
  - closing the immersive space in any way (button or Digital Crown) also closes the dragon panel and resets the
    game, so no orphan window survives.
- **The captive dragon flies in the tree's space (`AnchoredOrbit`).** `OrbitComponent` passes the tree anchor's
  full transform (position, rotation, scale, bobbing); while the dragon is on the island its flight runs in that
  space (body length divided by the island scale), so when the island turns the whole dragon turns rigidly with it,
  with no trail left behind in scene space (test: 90° turn, error < 1 mm). When the player calls it, the flight is
  converted once to scene space (`DragonFlight.transform(by:)`), with no visible jump.
- **The island spins like a turntable** (`TurntableComponent`/`TurntableSystem`): the view model holds the target
  yaw, the system eases towards it along the shortest arc, so drags, two-handed rotation and the ±22.5° buttons all
  look smooth. The rock collider sits below the ground, so the dragon circling above stays tappable.

- **Story chapters (`DragonPhase`) drive the entities through `DetanglingStateComponent`.** RealityKit does not
  observe the view model, so the system compares the chapter with the one already applied and reconfigures
  only on change: *tap* (no `ManipulationComponent`, larger 9 cm colliders tagged `DragonTapTargetComponent`,
  which is what the `SpatialTapGesture` targets, so it never steals the pinch from grabbing), *grab*
  (`ManipulationComponent`, head excluded), *none* while flying.
- **No visible platform.** The knot lies on an invisible plane (`y = 0` of the play area): a floor appearing
  in the room when the dragon arrives looked out of place. The play area can still be rotated, tilted and reset
  from the panel; it cannot be dragged by hand any more.
- **Orbit = a two-turn torus curve around the trunk (`OrbitPath`).** After one turn radius and height swap, so
  the 2.35 m body (more than one turn) wraps the tree without crossing itself (headless: closest gap 14 cm,
  6 cm needed). The head advances at a fixed speed per second (frame-rate independent) and the body follows its
  trail, in the tree anchor's space (see `AnchoredOrbit` above).
- **Landing traces the knot.** After the approach a Bézier takes the head to the knot's tail tip, then the head
  runs along the knot from tail to head; with "follow the leader" the body ends exactly in the puzzle's shape
  (max error ~1 cm, blended into the simulation in 0.5 s). The dragon tangles itself up believably with no
  hand-made animation, and the simulation restarts at the tap, so no fit timer runs before the puzzle.

- **The body is a custom rope simulation, not RealityKit physics.** 48 nodes 5 cm apart, 3 cm radius;
  distance, bending, self-collision and friction constraints at a fixed 60 Hz with sub-steps. We need exact
  control over what is over/under and no interpenetration; long jointed rigid-body chains are unstable.
  The simulation is deterministic and testable without a headset.
- **Friction, anchored head and a tension limit.** Without friction the knot slipped loose by itself; with
  both ends free a single pull solved the puzzle; without a tension limit a taut body tunnels through itself.
- **Win = zero crossings seen from above.** Segments are projected on the play area plane and intersections
  are counted. Simple, robust and it matches what the player sees.
- **`ManipulationComponent` for grabbing (visionOS 26+).** A SwiftUI `DragGesture` handles one interaction at
  a time; `ManipulationComponent` gives one grab per hand, so the player can hold a loop up with one hand and
  thread the tail under it with the other.
- **Colliders are separate from the visuals.** One invisible collider per node handles input; the visuals are
  a swappable `DragonRig`. When the asset arrives only the rig changes, not the game.
- **Hover highlights the part you look at.** visionOS highlights the children of the looked-at entity, so the
  placeholder rig parents each body segment to its collider.
- **"Alive" animations are visual only** (`DragonLifeAnimator`): breathing, neck, gaze, jaw, wings, smoke,
  fire. They never touch the simulation, so the puzzle stays fair.
- **Fits always add a crossing.** Tail lash and coil aim at a reachable body segment and land just past it;
  after the fit the crossings are compared with the start and the dragon retries (up to 8 times). The turn is
  a rigid rotation: spectacular, but it does not change the puzzle. In headless runs 39–40 fits out of 41 added
  crossings; the rest were already very dense knots.
- **Flight uses "follow the leader".** The head flies to a target that depends on the manoeuvre; each vertebra
  sits on the head's trail at a fixed distance, so the body snakes exactly along the path like an eastern
  dragon. Comfort: never closer than 0.7 m to the player's head, 0.9–2.1 m altitude, within ~2 m horizontally.

## Floating island

`Sources/Macrowavers/Resources/FloatingIsland.usdz` is generated from the design team's `FloatingIsland.usdc`:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    -P Assets/Blender/untangle-dragon/crea_asset_isola.py -- <FloatingIsland.usdc> <output folder>
```

- The source file points to external textures (`./textures/*_BaseColor.png`) that were never exported; the
  real colours are vertex colours (`Col`), which RealityKit does not draw. The script bakes them into textures
  on the existing UVs (island 2048, tree 1024, rocks 512), rebuilds a PBR material (roughness 0.9) and drops the
  vertex colours. Textures are embedded in the USDZ (5 MB), validated with `usdchecker --arkit`.
- **Origin moved to the base of the trunk, on the ground** (it was the island centre, with the trunk sunk in):
  the code uses the origin as the orbit centre with no offsets.
- Y-up export with *Convert Orientation* (rotation on the file root, so the code never overwrites the loaded
  entity's transform).
- 3 meshes / 3 materials (3 draw calls), ~24k triangles, no collision (it is not interactive).
- Asset size: island ~2.5 m (floating rocks ~3.6 m), tree 1.4 m, canopy from 0.5 m above the ground. In the
  scene it is scaled 0.8 (`IslandPlacement.standard`), 2.8 m away, ground at 1.12 m. If it is missing, the dragon circles an empty spot.

## Asset specification (for the design team)

`SkeletalDragonRig` is used automatically when `DragonBody` is in the app bundle (put exports under
`Sources/Macrowavers/Resources/`); otherwise the placeholder is used.

**`DragonBody`** (required; USDZ or Reality Composer Pro scene)
- One skinned mesh: neck + body + tail.
- Bone chain `spine_00` (neck, near the head) … `spine_NN` (tail tip), each child of the previous one,
  names sortable alphabetically (two digits). 24–48 bones, straight rest pose, equal bone lengths.
- **No animation on the spine bones**: code drives them every frame.
- Any scale: code scales the asset so the spine matches the simulated body (~2.35 m). Body thickness about
  1/30 of its length.
- Wings (recommended): joints `wing_L` and `wing_R`, children of a shoulder vertebra (~10% down the spine),
  **folded** in the rest pose. Code opens them around their local Z axis (`SkeletalDragonRig.Asset.wingFlareAxis`).

**`DragonHead`** (recommended)
- Separate head so its animations never fight the spine. Origin at the neck joint, snout towards **+Z**.
- Named animations (Reality Composer Pro Animation Library or named USD clips).
  Looping, per mood: `idle`, `annoyed`, `restless`, `wriggle`, `happy`.
  One-shot, per move: `roar` (~1.6 s, mouth wide open between 35% and 75%), `turn`, `lash`, `coil`.
  Missing clips fall back to `idle`.
- Two empty child entities: `nostrils` (smoke) and `mouth` (fire, pointing +Z).

**Sounds** (optional; wav/m4a/mp3/caf in the bundle): `DragonGrowl`, `DragonRoar`, `DragonRumble`,
`DragonWhoosh`. Played as spatial audio from the head.

**General**: PBR materials (they pick up the real room light), moderate polygon count (passthrough is on).
Per-part hover on a single skinned mesh needs a ShaderGraph material using the hover input.

On the code side the spine follows a Catmull-Rom spline through the simulated nodes (not the polyline, which
showed corners), and the first stretch of neck (`SkeletalDragonRig.Asset.neckBlendLength`) leaves the back of
the head in the head's direction, so the rigid head and the neck do not show a seam when the head turns (when
it looks up the neck is lifted a little so it does not sink below the knot plane). The head sits inside a
container entity: the code moves the container and never overwrites the transform of the asset's root.

### Temporary asset

Until the design team's dragon is ready, `Sources/Macrowavers/Resources/DragonBody.usdz` and `DragonHead.usdz`
come from **"Chinese dragon" by MAXDESIGN-3D on Sketchfab, licensed CC BY 4.0: it must be credited in the
app credits.** Remove both files to go back to the placeholder dragon.

They are generated without opening Blender by the scripts in `Assets/Blender/untangle-dragon/`:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    -P Assets/Blender/untangle-dragon/crea_asset_drago.py -- <scene.gltf> <output folder>
```

The script removes the legs and closes the holes with curved patches (the hole border is unrolled on the
body cylinder, triangulated in 2D and wrapped back, so no flat patches), detaches the head, slims the body,
builds a 64-bone spine with smooth weights (skin that bends instead of kinking), adds `nostrils`/`mouth`,
fixes the material and exports (USDZ validated with `usdchecker`).

Notes: use the glTF download (Sketchfab's USDZ loses the texture and the bone names); the model's "emissive"
texture is not its colour (the body uses a solid red); Blender's export with *Convert Orientation* puts a
rotation on the file's root, which is why the head is wrapped in a container.

## Tuning

| Where | Parameter | Effect |
|---|---|---|
| `TangleConfig` | `selfFriction` | higher = harder knot |
| `TangleConfig` | `anchorHead` | `false` = much easier |
| `TangleConfig` | `maxTension` | lower = fewer glitches when pulling hard, softer grab |
| `TangleShape` | `.trefoil` / `.figureEight` | starting knot (3 / 4 crossings) |
| `DifficultySettings` | delays, `maxExtraTangles` | how often and how hard the dragon fights back |
| `DragonFlight.Settings` | `speed`, `orbitRadius`, `altitude`, `personalSpace` | flight feel and room size |
| `PlayAreaPlacement.seated` | default placement | comfort for a seated player |
| `IslandPlacement.standard` | island position, scale, yaw | island distance and size |
| `OrbitPath.aroundTree` | radius, height, swings, speed (asset metres) | how the dragon wraps the tree |
| `DragonFlight.Settings` | `approachDistance`, `landingSpeed` | where it stops in front of the player, landing duration |
| `DetanglingStateComponent` | `tapRadius`, `fadeDuration` | how easy the dragon is to tap, fades |

## Tests

`Tests/MacrowaversTests/UntangleTests.swift` (Swift Testing) covers the Model and the view model: initial
crossings, the knot not untying by itself, rigid turns keeping crossings, the anchored head, two-handed grabs,
the fit starting with a turn after the delay, the dragon waiting while held, flight keeping its distance from
the player, the orbit never crossing itself, the landing matching the knot, the farewell ending, the story
flow (tap → puzzle), tilt clamping, restart and play again.

## Known limits

- Pulling very hard can make one part clip through another for a moment (see `maxTension`).
- While rearing up the neck is raised only visually; colliders stay on the play area plane for ~1 s.
- Smoke and fire sizes are eyeballed and need tuning on device.
- The island (2.8 m away, ~2 m wide in the scene, floating rocks ~2.9 m) does not know the room: reduce
  `IslandPlacement.standard` in small spaces.
- Tapping a moving dragon 2 m away needs testing on device (raise `DetanglingStateComponent.tapRadius` if hard).
- Flight does not know the real walls: in small rooms reduce `DragonFlight.Settings.orbitRadius`
  (or use `SceneReconstructionProvider` later).
