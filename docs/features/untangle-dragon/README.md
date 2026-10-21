# Untangle the Dragon (AR126-100)

A mixed-reality chapter of the Persian fairy tale: a floating island with a tree at its centre appears in the
room, and a dragon is coiled around the tree. The player taps the dragon, which flies to them and settles in
the air in front of them, tangled in a knot. The player grabs the body with their hands and untangles it.
Once free, the dragon thanks the player and flies away into the sky.

Status: on `main`, playable with a temporary Sketchfab dragon (see
[Temporary asset](#temporary-asset)); the code-generated placeholder is used when the asset is not in the bundle.

## How to try it

1. Open `Macrowavers.xcodeproj` and run on the visionOS simulator or on a Vision Pro. Run `git lfs pull`
   first if the `.usdz` files under `Sources/Macrowavers/Resources/` are only LFS pointers.
2. Press **Start** (the launch window): an `ImmersiveSpace` in `.mixed` style opens, the room darkens and the
   narrator speaks (two pages, tap to go on; see [Storytelling](../storytelling/README.md)). Then the floating
   island (real size, ~2.5 m wide) fades in ~2.8 m in front of you, its grass at table height (0.6 m), with the
   dragon circling its tree. The launch window closes; the island panel is on your left.
3. Spin the island by dragging its rock (or with both hands, or with the buttons in the island panel): the
   dragon turns with it. The side of the island facing you follows your hand, wherever you look on the rock.
4. Look at the dragon and pinch (tap): it gets angry for ~3 s. It won't come near you until it is soothed.
5. Pick fruit on the tree and open them: each frees an **ingredient** that joins a small orbit in front of you (see
   [The tree's fruit](../apple-artifact/README.md)). With three in orbit, snap your fingers (or tap one): they
   dive one by one into the flask in the orbit's middle and brew the **elixir**; the flask flies to the dragon and
   pours the elixir over its head (`callDragon()`): it flies to you, stops to look at you and settles tangled in
   front of you.
6. Pinch and drag the dragon's body (one part per hand), lift parts to pass them over or under the others.

Two-handed grabbing and the dragon looking at you need a real device; the simulator only does one hand and
uses a seated eye height of 1.15 m.

## What the player sees

| Moment | Behaviour |
|---|---|
| Start | Floating island with the dragon coiled around its tree, circling slowly; island and floating rocks bob gently. The island is at its real size (~2.5 m wide, tree top ~2.45 m), the grass at 0.6 m; the rock's roots sink into the real floor (the part below it is hidden). Looking at the dragon highlights it. The island turns like a turntable (drag the rock, two-handed rotate or the island panel's buttons): its side facing you follows your hand, and the dragon turns with it |
| Tap the dragon | For ~3 s it gets angry (`DragonPhase.alerted`): circles faster, glares at you, growls and snorts smoke, then calms down and keeps circling |
| The flask pours the elixir over it | It flies to ~1 m from your eyes and hovers looking at you then settles in the air in front of you (no visible platform), tracing the knot with its body |
| Puzzle | Dragon tied in a trefoil knot (3 crossings), red pulsing spheres on every crossing, crossings left in the island panel. **Focus mode**: from the landing until it is free the island, the tree and the fruit fade to 25% and only the dragon stays at full strength |
| Grab | The part you look at glows; pinch to grab, one part per hand: left and right hand hold and drag two parts independently; a part can pass from one hand to the other without being dropped. The body follows the hand smoothly (no shaking with a shaky hand, no flicker when pulled taut); the dragon turns to your hand, bares its teeth and tugs its head slowly if pulled hard |
| No progress (8 s, shorter each time, min 5 s) | 2 s warning: it stares at you, smoke from the nostrils (the placeholder's eyes turn red). Then a fit: it **turns around**, rears up and roars with a burst of fire, lashes its tail and coils, **always adding at least one new crossing** |
| Solved (0 crossings, body released for 0.6 s) | Raises its head towards you, spreads its wings (the placeholder also turns gold) and **speaks**: the room darkens, the island fades back and its words float above it (two "Thank you" pages, the second ending "Are you ready?"). When you answer **I'm Ready** (at least 1.5 s after the win) it **takes off** away from you, sweeps once from side to side **in front of you** (1.2–1.6 m away, 1.0–1.8 m high, never behind you), **hovers 1.35 m straight in front of your eyes** (wherever you look) roaring its thanks with its snout up, and **flies away**, fading out within ~2 m, before the room's walls or ceiling. **Restart Game** in the island panel starts over |
| Play area | Invisible: the knot floats at knee/table height in front of the player. Rotate it with the panel buttons, tilt it with the slider, reset it. Default is tuned for a seated player |

Everything is in English: user-facing text, code comments and tooling.

## Code layout

```
Sources/Macrowavers/
├── App/MacrowaversApp.swift          Scenes: launch window, ImmersiveSpace (.mixed)
├── Views/IslandControlsView.swift    Island panel (attachment): status, rotation, Restart Game
├── Views/ContentView.swift           Launch window: the story's Start button
├── Model/Story/, Views/Story/        Storytelling screens (see ../storytelling/README.md)
├── Model/SceneFocus.swift            Focus mode: what fades back (none / fruit / dragon)
├── Model/Untangle/                   Pure game logic: Foundation + simd only, unit-tested
│   ├── TangleSimulation.swift          Rope physics of the body (PBD/Verlet) and crossing count
│   ├── TangleShapes.swift              Initial knots from parametric curves (trefoil, figure-eight, loop)
│   ├── DragonBehavior.swift            Difficulty: idle timer → fit (choreography of DragonAction), DragonMood
│   ├── DragonFlight.swift              Flights (orbit, approach, landing, farewell) with a "follow the leader" body
│   ├── DragonFlightSettings.swift      Manoeuvres and flight tuning (default and `.farewell`)
│   ├── DragonPhase.swift               Story chapters (captive ⇄ alerted → approaching → landing → untangling → free → gone)
│   ├── HandGrabs.swift                 Which hand holds which node, from the manipulation events
│   ├── IslandPlacement.swift           Island position + OrbitPath (the curve around the tree)
│   ├── PlayAreaPlacement.swift         Play area position, rotation, tilt
│   └── UntangleViewModel.swift         @Observable @MainActor view model shared by panel and immersive space
└── Views/Untangle/
    ├── DragonImmersiveView.swift       RealityView, island, island panel, island spin, grab events, tap on the dragon
    └── RealityKit/                     Draws, never decides
        ├── DragonScene.swift             Components, System, scene building, grabbable colliders, crossing markers
        ├── DragonJourney.swift           Story ECS: OrbitComponent, DetanglingStateComponent, DragonTapTargetComponent
        ├── IslandScene.swift             Floating island (asset), tree anchor, floor occluder, FloatingComponent/System,
        │                                 TurntableComponent/System, FocusDimmingComponent/System (applies `SceneFocus`)
        ├── DragonRig.swift               DragonRig protocol, DragonFrame, DragonPose, DragonLifeAnimator
        ├── DragonEffects.swift           Smoke, fire, optional spatial audio, placeholder wings
        ├── ViewerTracker.swift           Player head position and gaze (ARKit world tracking, no permission needed)
        ├── ProceduralDragonRig.swift     Placeholder dragon built from primitives
        └── SkeletalDragonRig.swift       Rig for the real asset, picked automatically when it is in the bundle
Sources/Macrowavers/Resources/DragonBody.usdz, DragonHead.usdz   Temporary dragon asset (Git LFS)
Sources/Macrowavers/Resources/FloatingIsland.usdz                 Floating island with the tree (Git LFS)
Assets/Blender/untangle-dragon/       Blender scripts that generate the assets (not in the app)
Tests/MacrowaversTests/UntangleTests.swift, SceneFocusTests.swift
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

Grab start/end comes from `ManipulationEvents.WillBegin/DidHandOff/WillRelease/WillEnd`, subscribed in
`DragonImmersiveView`.

## Design decisions (and why)

- **One launch window, then panels inside the space.** A window opened over an immersive space sits ~1 m in
  front of the player at eye height: exactly where the island is seen, where the dragon stops to look at the
  player and where the fruit comes close. The 3D content clipped through it and its colliders stole the pinch from
  the window, which became hard to grab. Now:
  - the **launch window** (`ContentView`, plain, the story's **Start** button) only opens the island and then
    dismisses itself;
  - inside the space the controls are **RealityView attachments**, placed where nothing moves: the **island
    panel** (`IslandControlsView`: status, island rotation, **Restart Game**) 50° to the left, 0.9 m away,
    turned towards the player (`BillboardComponent`). The island spans ±20°, the dragon's approach and the knot
    are straight ahead, the farewell stays beyond 0.9 m and within ±55° of the gaze. There is no dragon panel and
    no debug panel: the game shows only what the player needs;
  - panels hide themselves in SwiftUI; their attachment entities are **never disabled** (`isEnabled = false`):
    deactivating an entity that hosts SwiftUI while its content changes makes RealityKit abort with "the new
    parent is currently being removed" (it crashed the app when the elixir reached the dragon);
  - closing the space in any way (Restart Game or Digital Crown) resets the game and reopens the launch window,
    so there is never more than one window and never a window over the game.
- **The captive dragon flies in the tree's space (`AnchoredOrbit`).** `OrbitComponent` passes the tree anchor's
  full transform (position, rotation, scale, bobbing); while the dragon is on the island its flight runs in that
  space (body length divided by the island scale), so when the island turns the whole dragon turns rigidly with it,
  with no trail left behind in scene space (test: 90° turn, error < 1 mm). When the player calls it, the flight is
  converted once to scene space (`DragonFlight.transform(by:)`), with no visible jump.
- **The island spins like a turntable** (`TurntableComponent`/`TurntableSystem`): the view model holds the target
  yaw, the system eases towards it along the shortest arc, so drags, two-handed rotation and the ±22.5° buttons all
  look smooth. The rock collider sits below the ground, so the dragon circling above stays tappable.
- **Dragging the rock turns the side facing the player with the hand (`IslandPlacement.spinAngle`).** The drag
  used to turn the island by the angle the hand drew around the trunk, measured from the point where the pinch
  landed: from the far side of the rock the same hand movement turned the island the other way, and near the
  trunk the angle jumped. Now only the hand's movement across the player's view counts (towards the island or up
  does nothing): 0.4 m (`IslandPlacement.spinDistance`) turns it by one radian, from any side of the island.
  While both hands rotate it, the two-hand rotation drives the island and the drag resumes from there.

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
  hand-made animation, and the simulation restarts when the dragon is called (`callDragon()`), so no fit timer
  runs before the puzzle.

- **The body is a custom rope simulation, not RealityKit physics.** 64 nodes ~3.7 cm apart (2.35 m), 4 cm
  radius; distance, bending, self-collision and friction constraints at a fixed 60 Hz with sub-steps. We need
  exact control over what is over/under and no interpenetration; long jointed rigid-body chains are unstable.
  The simulation is deterministic and testable without a headset. The nodes are the control points of the
  spline the rigs draw: more nodes = rounder curves in the knot and in flight. Self-collision has a broad
  phase (candidate pairs found once per sub-step, not per solver iteration), so 64 nodes cost less than the
  old 48 (~3.5 ms per tick in a debug build, 0.1 ms optimised).
- **Friction, anchored head and a tension limit.** Without friction the knot slipped loose by itself; with
  both ends free a single pull solved the puzzle; without a tension limit a taut body tunnels through itself.
- **Grabs are filtered, the tension limit is soft.** The hand drives the node through a 60 ms low-pass filter
  (`grabSmoothing`), so tracking noise does not shake the body; near `maxTension` the node slows down
  gradually (`tensionSoftness`) and gives way in proportion to the overstretch. The old hard stop made a taut
  node flicker between following the hand and giving way every sub-step (headless: 42 direction reversals in
  3 s of a taut pull, 162 with a shaky hand; now 0). The dragon's reaction is visual and slow: strain is
  filtered (`strainResponsiveness`), no per-vertebra tremble while held (it was a 40 Hz buzz that read as a
  glitch), the head tugs at 0.5 Hz. The pre-fit warning head shake runs at a fixed frequency (it used
  `sin(time × restlessness)`, which sped up wildly as the game time grew).
- **Win = zero crossings seen from above.** Segments are projected on the play area plane and intersections
  are counted. Simple, robust and it matches what the player sees.
- **`ManipulationComponent` for grabbing (visionOS 26+).** A SwiftUI `DragGesture` handles one interaction at
  a time; `ManipulationComponent` gives one grab per hand, so the player can hold a loop up with one hand and
  thread the tail under it with the other. Every node has its own collider, input target and manipulation, so
  each hand drives its own node.
- **Hands are tracked per node (`HandGrabs`).** The events (`WillBegin`, `DidHandOff`, `WillRelease`,
  `WillEnd`, with the hands' chirality) are turned into grabs and releases with explicit rules, because they
  are not a clean begin/end pair per hand: a hand holds one node at a time (a missed release used to leave a
  node frozen in the simulation), a node passes between hands without being dropped, and the end of a released
  grab arriving after a quick re-grab of the same node no longer drops the new grab (the old code released on
  every `WillEnd`). The anchored head has no collider at all during the puzzle (its 9 cm tap sphere used to sit
  over the neck and swallow pinches), the grab spheres are 1.2× the body radius instead of 1.5× (neighbouring
  spheres overlap less, so two hands close together pick two nodes instead of sharing one), and colliders have
  no shape while the dragon flies. One hand pulling the body taut does not lock the other: the pulling node
  gives way between sub-steps, so the other node keeps following its hand (test).
- **Colliders are separate from the visuals.** One invisible collider per node handles input; the visuals are
  a swappable `DragonRig`. When the asset arrives only the rig changes, not the game.
- **Hover highlights the part you look at.** visionOS highlights the children of the looked-at entity, so the
  placeholder rig parents each body segment to its collider.
- **"Alive" animations are visual only** (`DragonLifeAnimator`): breathing, neck, gaze, jaw, wings, smoke,
  fire. They never touch the simulation, so the puzzle stays fair.
- **Fits always add a crossing.** Tail lash and coil aim at a reachable body segment and land just past it;
  after the fit the crossings are compared with the start and the dragon retries (up to 8 times). The turn is
  a rigid rotation: spectacular, but it does not change the puzzle. In headless runs 71 fits out of 73 added
  crossings; the rest were already very dense knots. The lash lifts the tail to `grabLift` (12 cm: clear of the
  4 cm-radius body) and the dragon's own moves skip the hand filter, so they land exactly where they aim.
- **Flight uses "follow the leader".** The head flies to a target that depends on the manoeuvre; each vertebra
  sits on the head's trail at a fixed distance, so the body snakes exactly along the path like an eastern
  dragon. Comfort: never closer than 0.7 m to the player's head, 0.9–2.1 m altitude, within ~2 m horizontally.
- **The free dragon stays in front of the player** (`DragonFlight.Settings.farewell`). Circling the player sent
  it behind them and towards the walls, and the old departure travelled ~8 m before fading. Now the farewell
  cruises in a ±55° arc around where the player looks, a hard-but-eased flight volume keeps it 0.9–1.75 m
  from the eyes and 0.85–1.95 m high, it hovers 1.35 m in front of the gaze (`ViewerTracker.viewerPose()`,
  eased so it does not chase every head turn), and the departure fades by distance (0.4–1.8 m), then ends.
- **Focus mode** (`SceneFocus`, applied by `FocusDimmingComponent`). A small state machine in the Model:
  - **fruit** (a fruit is close): the island root (rock, terrain, tree, floating rocks and every fruit still
    hanging on it) **and the dragon** (the play area, body, head, wings and effects) fade to 25%;
  - **dragon** (landing and untangling, `DragonPhase.focusesOnDragon`, and while the freed dragon speaks,
    `StoryStep.focusesOnDragon`): the island, tree and fruit fade, only the dragon stays at 100%;
  - **none** (exploring, or the elixir flying to the dragon, so the player can follow it): everything at 100%.

  Each part eases in ~0.6 s; at 100% its `OpacityComponent` is removed, so it is drawn opaque again. Opacity
  multiplies down the hierarchy, so the dragon's own fade-in and fade-out keep working under it. The focused
  fruit, its panel, the ingredients and the elixir live under the orchard, outside both parts, and never fade.

## Floating island

`Sources/Macrowavers/Resources/FloatingIsland.usdz` is generated from the design team's latest island export
(`last.ttttttttusdc.usdc`, a raw Blender export of the island with its tree). Compared with the first export
(`Tree_FloatingIsland.usdc`) only two meshes changed: the rock body is a little wider and the grass top was
remodelled (501 vertices instead of 121, a shorter, more regular fringe); the tree, the floating rocks and
everything else are identical:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    -P Assets/Blender/untangle-dragon/make_island_asset.py -- <island source .usdc> <output folder>
```

The source is Z-up and ~14 m wide, with ~90 loose meshes, a camera, a sun and a dome light. The script turns it
into the same asset contract the code has always used, so no Swift code changed with the new island:

- **Three parts, as before:** the meshes are joined into `Island` (grass, rock, roots, stones, bushes, flowers:
  its bounds give the rock's collider), `Tree` (trunk, branch, canopy) and `FloatingRocks` (debris and small
  floating islands, which bob on their own). Camera and lights are dropped: the room lights the island.
- **Plain material colours**, no textures and no vertex colours (nothing to bake): exported as UsdPreviewSurface,
  matte (roughness 0.85); the tree's anonymous materials become `Tree_Bark` and `Tree_Leaves`. 247 KB, validated
  with `usdchecker --arkit`.
- **Inside-out meshes turned the right way:** the source's rock body (`Island_RockBody`) has its faces wound
  inwards (signed volume −564, −586 in the latest export). Blender draws both sides of every face, so it looks fine there; RealityKit culls
  back faces, so the rock looked hollow from the outside, its far inner walls showing through. Every closed mesh
  (≤ 5 % open edges, `MAX_OPEN_EDGES`) with a negative signed volume gets its faces recalculated outwards and its
  normals recomputed; open meshes (petals, grass cards) are left alone, their volume's sign means nothing.
  Stray vertices without faces are deleted first (the latest export has one in the rock: it misled Blender's
  guess of the outside), and if the volume is still negative every face is reversed, so the result never depends on it.
  Ask the design team to check *Face Orientation* (Viewport Overlays: blue outside, red inside) on new assets.
- **Origin moved to the base of the trunk, on the grass:** the code uses the origin as the orbit centre with no
  offsets.
- **Scaled by the tree alone** (`TARGET_TREE_HEIGHT`: 1.8415 m from the bottom of the trunk to the top of the
  canopy; island ~2.5 m wide): `IslandPlacement.standard`, the dragon's orbit (`OrbitPath.aroundTree`: no trunk,
  branch or bush inside it), the fruit and the floor occluder stay as they were. Not the island's width nor the
  grass: the wider rock would have shrunk everything by 0.4 %. With the latest export the tree, the fruit points
  and the floating rocks match the previous asset within 0.001 mm across and 0.5 mm in height (the grass by the
  trunk, where the origin sits, rose by half a millimetre).
- Y-up export with *Convert Orientation* (rotation on the file root, so the code never overwrites the loaded
  entity's transform).
- Six empty objects `fruit_01` … `fruit_06` mark where the fruit hangs: the script casts rays at the canopy from
  outside (the canopy is made of separate blobs, so it looks around each wanted spot when a ray slips between
  them) and puts each point just off the foliage, 1.2–1.35 m above the grass. Move them in Blender to move the
  fruit.
- 3 meshes / 20 materials, ~5.9k triangles. The code adds a collider only below the ground (the rock, to spin
  the island).
- Asset size: island ~2.5 m (floating rocks ~3.6 m), tree 1.84 m, canopy from ~0.97 m above the ground, rock and
  roots 0.91 m deep below the grass. In the scene it is at **real size** (scale 1, `IslandPlacement.standard`),
  2.8 m away, **grass at 0.6 m** (`IslandPlacement.grassHeight`), treetop ~2.45 m. If it is missing, the dragon
  circles an empty spot.
- Scale and height are independent: the origin is on the grass and the transform is translation × rotation ×
  uniform positive scale, so changing the scale grows the island around the grass and never moves it (test).
- At that height the rock's roots end ~0.3 m below the real floor and the lowest floating rocks just above it.
  Passthrough does not hide virtual content under the floor, so `IslandSceneBuilder` adds a floor patch 2 mm
  under y = 0 with `OcclusionMaterial` (`floorOccluder`, sized to the whole model so the floating rocks are
  covered whichever way the island is turned, outside the island so it never turns, bobs or fades): seen from
  above it hides only what is under the floor, and the island seems to rise out of it.

## Asset specification (for the design team)

`SkeletalDragonRig` is used automatically when `DragonBody` is in the app bundle (put exports under
`Sources/Macrowavers/Resources/`); otherwise the placeholder is used.

**`DragonBody`** (required; USDZ loaded from the app bundle)
- One skinned mesh: neck + body + tail.
- Bone chain `spine_00` (neck, near the head) … `spine_NN` (tail tip), each child of the previous one,
  names sortable alphabetically (two digits). 24–64 bones (the temporary asset has 64), straight rest pose,
  equal bone lengths.
- **No animation on the spine bones**: code drives them every frame.
- Any scale: code scales the asset so the spine matches the simulated body (~2.35 m). Body thickness about
  1/40 of its length (3 cm radius at game size, `SkeletalDragonRig.Asset.modelledRadius`): the rig thickens it
  to `TangleConfig.radius` (4 cm) with a uniform scale on `spine_00`, shortening every child bone's offset by
  the same factor, so the skin swells around the spine without the body getting longer. Wings keep their size;
  the head grows with the neck.
- Wings (recommended): joints `wing_L` and `wing_R`, children of a shoulder vertebra (~10% down the spine),
  **folded** in the rest pose. Code opens them around their local Z axis (`SkeletalDragonRig.Asset.wingFlareAxis`).

**`DragonHead`** (recommended)
- Separate head so its animations never fight the spine. Origin at the neck joint, snout towards **+Z**.
- Named animations (an `AnimationLibraryComponent` on the root or named USD clips).
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
    -P Assets/Blender/untangle-dragon/make_dragon_asset.py -- <scene.gltf> <output folder>
```

`make_dragon_asset.py` runs the step scripts `1_prepare_and_remove_legs.py`, `2_detach_head_and_clean.py`,
`3_rename_spine.py` and `4_material.py` in order (each can also be run by hand from Blender's Scripting tab)
plus the steps in between. The script removes the legs and closes the holes with curved patches (the hole border is unrolled on the
body cylinder, triangulated in 2D and wrapped back, so no flat patches), detaches the head, slims the body,
builds a 64-bone spine with smooth weights (skin that bends instead of kinking), adds `nostrils`/`mouth`,
fixes the material and exports `DragonBody.usdz` and `DragonHead.usdz` (validated with `usdchecker`).

Notes: use the glTF download (Sketchfab's USDZ loses the texture and the bone names); the model's "emissive"
texture is not its colour (the body uses a solid red); Blender's export with *Convert Orientation* puts a
rotation on the file's root, which is why the head is wrapped in a container.

## Tuning

| Where | Parameter | Effect |
|---|---|---|
| `TangleConfig` | `selfFriction` | higher = harder knot |
| `TangleConfig` | `anchorHead` | `false` = much easier |
| `TangleConfig` | `maxTension`, `tensionSoftness` | lower = fewer glitches when pulling hard, softer grab |
| `TangleConfig` | `nodeCount`, `segmentLength`, `radius` | spline control points, body length (keep ~2.35 m), body thickness (rigs follow it) |
| `TangleConfig` | `grabSmoothing` | higher = calmer but laggier grab |
| `TangleShape` | `.trefoil` / `.figureEight` / `.loop` | starting knot (3 / 4 / 0 crossings) |
| `UntangleViewModel(farewellWaitsForPlayer:)` | `true` in the app | the free dragon waits for `beginFarewell()` (the story's "I'm Ready") instead of taking off after 1.5 s |
| `DifficultySettings` | delays, `maxExtraTangles` | how often and how hard the dragon fights back |
| `DragonFlight.Settings` | `speed`, `orbitRadius`, `altitude`, `personalSpace` | flight feel and room size |
| `DragonFlight.Settings.farewell` | `frontArc`, `hoverDistance`, `boundsMargin`, `departFade` | where the free dragon flies, where it thanks the player, how far it goes before vanishing |
| `SceneFocus` / `FocusDimmingComponent` | `dimmedOpacity` / `responsiveness` | how much the faded parts fade in focus mode, how fast |
| `PlayAreaPlacement.seated` | default placement | comfort for a seated player |
| `IslandPlacement.standard` | island position, scale, yaw | island distance and size |
| `OrbitPath.aroundTree` | radius, height, swings, speed (asset metres) | how the dragon wraps the tree |
| `DragonFlight.Settings` | `approachDistance`, `landingSpeed` | where it stops in front of the player, landing duration |
| `DetanglingStateComponent` | `tapRadius`, `fadeDuration` | how easy the dragon is to tap, fades |

## Tests

`Tests/MacrowaversTests/UntangleTests.swift` (Swift Testing) covers the Model and the view model: initial
crossings, the knot not untying by itself, rigid turns keeping crossings, the anchored head, two-handed grabs,
one hand pulling taut not locking the other, hand tracking (one node per hand, hand-off, late end after a
re-grab, cancelled grab), left and right hands dragging two parts independently through the view model,
the fit starting with a turn after the delay, the dragon waiting while held, a shaky hand not shaking the body,
a taut pull not flickering, flight keeping its distance from the player, the orbit never crossing itself, the
captive dragon turning rigidly with the island, the landing matching the knot, the farewell ending, the free
dragon staying in front of the player and hovering where they look (two gaze directions), the story flow
(captive, a tap only makes it angry for `alertDuration`, `callDragon()` → puzzle), tilt clamping, restart and
play again.
`SceneFocusTests.swift` covers focus mode (what fades with a fruit close, while untangling, while the
elixir flies, when exploring, only landing and untangling focusing on the dragon) and the island's transform (at least the original size, grass at 0.6 m
whatever the scale, positive uniform scale), the island's spin (the side facing the player follows the hand from
any side of the island, movement towards it or up does not turn it, no jump with the player above the trunk), and
the speaking dragon keeping only itself visible.
`StoryTests.swift` covers the free dragon waiting for the player's answer (and taking off on its own without the
story).

## Known limits

- Pulling very hard can make one part clip through another for a moment (see `maxTension`).
- While rearing up the neck is raised only visually; colliders stay on the play area plane for ~1 s.
- Smoke and fire sizes are eyeballed and need tuning on device.
- The island (2.8 m away, ~2.5 m wide, floating rocks ~3.6 m) does not know the room: reduce
  `IslandPlacement.standard` in small spaces.
- The floor occluder assumes a flat floor at the immersive space's origin (y = 0); on a step or a rug it may
  cut the rock slightly above or below the real floor.
- Faded parts are drawn with transparency: overlapping parts (canopy over trunk, coils of the dragon) may sort
  imperfectly at 25%.
- Two-handed grabbing can only be checked on a device (the simulator has one pointer); the event handling is
  covered headless, with the hands' chirality as `ManipulationEvents` reports it.
- Tapping a moving dragon 2 m away needs testing on device (raise `DetanglingStateComponent.tapRadius` if hard).
- Flight does not know the real walls: in small rooms reduce `DragonFlight.Settings.orbitRadius` (the farewell
  is already kept within ~1.75 m of the player and in front of them) or use `SceneReconstructionProvider` later.
