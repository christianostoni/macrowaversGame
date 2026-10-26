# Untangle the Dragon (AR126-100)

A mixed-reality chapter of the Persian fairy tale: a floating island with a tree at its centre appears in the
room, and a dragon is coiled around the tree. The player taps the dragon, which flies to them and settles in
the air in front of them, tangled in a knot. The player grabs the body with their hands and untangles it.
Once free, the dragon thanks the player and flies away into the sky.

Status: on `main`, playable with the design team's **stone dragon** (see [The stone dragon](#the-stone-dragon)):
a head and a chain of separate stones, each of which the player grabs to untangle it. The code-generated
placeholder is used when it is not in the bundle.

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
5. Pick fruit on the tree and open them: each frees an **ingredient** that joins a small orbit on your right (see
   [The tree's fruit](../apple-artifact/README.md)). With three in orbit, snap your fingers (or tap one): they
   dive one by one into the flask in the orbit's middle and brew the **elixir**; the flask flies to the dragon and
   pours the elixir over its head (`callDragon()`): it flies to you, stops to look at you and settles tangled in
   front of you.
6. Pinch and drag the dragon's stones or its head (one per hand), lift them to pass them over or under the
   others. Each stone lights up when you look at it; the head stays where you leave it.

Two-handed grabbing and the dragon looking at you need a real device; the simulator only does one hand and
uses a seated eye height of 1.15 m.

## What the player sees

| Moment | Behaviour |
|---|---|
| Start | Floating island with the dragon coiled around its tree, circling slowly; island and floating rocks bob gently. The island is at its real size (~2.5 m wide, tree top ~2.45 m), the grass at 0.6 m; the rock's roots sink into the real floor (the part below it is hidden). Looking at the dragon highlights it. The island turns like a turntable (drag the rock, two-handed rotate or the island panel's buttons): its side facing you follows your hand, and the dragon turns with it |
| Tap the dragon | For ~3 s it gets angry (`DragonPhase.alerted`): circles faster, glares at you, growls and snorts smoke, then calms down and keeps circling |
| The flask pours the elixir over it | It flies to ~1 m from your eyes and hovers looking at you then settles in the air in front of you (no visible platform), tracing the knot with its body |
| Puzzle | Dragon tied in a trefoil knot (3 crossings), blue pulsing spheres on every crossing, crossings left in the island panel. **Focus mode**: from the landing until it is free the island, the tree and the fruit fade to 25% and only the dragon stays at full strength |
| Grab | The stone (or the head) you look at glows; pinch to grab, one per hand: left and right hand hold and drag two parts independently; a part can pass from one hand to the other without being dropped. The body follows the hand smoothly, without snapping after it, and slides through the knot instead of sticking to the hand; pulled taut, it stops stretching but the other hand can still move its part. Two held parts push each other away instead of passing through. The dragon turns to your hand, bares its teeth and tugs its head slowly if pulled hard. The head can be held too: it follows the hand and stays where it is let go, settling onto the plane |
| No progress (8 s, shorter each time, min 5 s) | 2 s warning: it stares at you, smoke from the nostrils (the placeholder's eyes turn red). Then a fit: it **turns around**, rears up and roars with a burst of fire, lashes its tail and coils, **always adding at least one new crossing** |
| Solved (0 crossings, body released for 0.6 s) | Raises its head towards you, lifts its head (the placeholder also spreads its wings and turns gold) and **speaks**: the room darkens, the island fades back and its words float above it (two "Thank you" pages, the second ending "Are you ready?"). When you answer **I'm Ready** (at least 1.5 s after the win) it **takes off** away from you, sweeps once from side to side **in front of you** (1.2–1.6 m away, 1.0–1.8 m high, never behind you), **hovers 1.35 m straight in front of your eyes** (wherever you look) roaring its thanks with its snout up, and **flies away**, fading out within ~2 m, before the room's walls or ceiling. **Restart Game** in the island panel starts over |
| Play area | Invisible: the knot floats at knee/table height in front of the player, placed for a seated player (`PlayAreaPlacement.seated`). There are no controls to move it: the dragon panel that rotated and tilted it was removed |

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
│   ├── TangleSimulation.swift          Rope physics of the body (PBD/Verlet): grabs with a leash and per-grab
│   │                                     tension, friction, flatten, crossing count (drawn and simulated)
│   ├── TangleShapes.swift              Initial knots from parametric curves (trefoil, figure-eight, loop)
│   ├── DragonBehavior.swift            Difficulty: idle timer → fit (choreography of DragonAction), DragonMood
│   ├── DragonFlight.swift              Flights (orbit, approach, landing, farewell) with a "follow the leader" body
│   ├── DragonFlightSettings.swift      Manoeuvres and flight tuning (default and `.farewell`)
│   ├── DragonPhase.swift               Story chapters (captive ⇄ alerted → approaching → landing → untangling → free → gone)
│   ├── HandGrabs.swift                 Which hand holds which node, from the manipulation events
│   ├── IslandPlacement.swift           Island position + OrbitPath (the curve around the tree)
│   ├── PlayAreaPlacement.swift         Play area position, rotation, tilt
│   └── UntangleViewModel.swift         @Observable @MainActor view model shared by the island panel and the space
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
        ├── DragonCurve.swift             The stone dragon's curve: spline, point at a distance, neck
        ├── StoneDragonRig.swift          Rig for the design team's stone dragon, used when it is in the bundle
        └── ProceduralDragonRig.swift     Placeholder dragon built from primitives
Sources/Macrowavers/Model/Untangle/StoneDragonLayout.swift        Where each stone sits on the body, which node holds it
Sources/Macrowavers/Resources/StoneDragon.usdz                    The design team's stone dragon (Git LFS)
Sources/Macrowavers/Resources/FloatingIsland.usdz                 Floating island with the tree (Git LFS)
Assets/Blender/floating-island/       The island's source and make_island_asset.py (not in the app)
Assets/Blender/stone-dragon/          The stone dragon's source and make_stone_dragon_asset.py (not in the app)
Tests/MacrowaversTests/UntangleTests.swift, SceneFocusTests.swift, StoneDragonTests.swift
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
5. `rig.update(DragonFrame)` draws the dragon; `CrossingMarkers` moves the blue spheres.

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
  in the room when the dragon arrives looked out of place. The play area cannot be dragged by hand, and since the
  dragon panel was removed it is not rotated or tilted from a panel either: it stays at `PlayAreaPlacement.seated`
  (`UntangleViewModel.setTilt` remains for code and tests).
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
  The head is anchored only while nobody holds it: the player can grab it like the stones (`grab(0)`), it follows
  the hand, and let go it stays where it was put, anchored again there (settling back onto the plane in ~0.2 s if
  it was let go in the air; the dragon never looks at its own head when the player holds it).
- **The untangling physics, retuned (October 2026).** Measured headless (the Model at 90 Hz on the trefoil knot,
  before → after): hand-to-stone gap pulling the tail at 0.5 m/s 0.73 → 0.17 m, direction reversals 14 → 0, a
  stone let go 20 cm up falls at 7.0 → 0.88 m/s, two held parts pushed together 4.1 → 8.0 cm apart, phantom
  crossings between near segments 77 → 0, the untouched knot keeps its 3 crossings for 18 → 60+ s, a taut body
  under a shaky hand moves 0.04 → 0.23 mm per frame.
  - *Friction once per sub-step, Coulomb-like* (`applyFriction`): it ran in all 10 solver iterations, taking
    ~97 % of the sliding away per sub-step, so the knot stuck to the hand that pulled it, which juddered. Now a
    contact holds a slip back by at most `selfFriction` × its depth, and a contact barely touching holds nothing
    (a fixed minimum made a taut body stick and slip).
  - *Tension per grab, directional* (`grabTensions`): the single most stretched segment of the whole body (4 %,
    1.5 mm) used to hold back every grab at once. Now each grab looks at the mean stretch of the `tensionReach`
    (8) segments on each side, and only the part of its move that stretches a taut side stops: sideways it still
    follows its hand slowly (15 % per sub-step), back towards that side freely. So one hand pulling the body
    taut does not lock the other (it can still lift its part; test), and the pulling one gives way.
  - *A leash on the hand* (`grabLeash`, 8 cm): the collider follows the hand however far the body is held back;
    the node then rushed after it like a rubber band. The target stays within 8 cm of the node.
  - *Held parts collide*: two held nodes (or a held node and the anchored head) have infinite mass, so the
    constraint moved neither and they passed through each other; now each gives way by half.
  - *The pull towards the plane builds up no speed* (`previous` moves with it) and is half as strong
    (`flattenStrength` 0.02): stones let go in the air no longer slam down. At 0.04 with that change the resting
    knot loosened by itself.
  - *Crossings of near segments are ignored* (`crossingSkip`, 8 segments): small kinks showed phantom markers
    and blocked the win. The markers sit on the body as it is drawn (`drawnCrossings`, interpolated), not on the
    60 Hz simulation.
- **Grabs are filtered, the tension limit is soft.** The hand drives the node through a 60 ms low-pass filter
  (`grabSmoothing`), so tracking noise does not shake the body; near `maxTension` the stretching part of the move
  slows down gradually (`tensionSoftness`) and the node gives way in proportion to the overstretch. The old hard stop made a taut
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
  every `WillEnd`). The head is grabbable with its own sphere (half the gap to the first stone: it used to have
  no collider at all, so its 9 cm tap sphere would not sit over the neck and swallow pinches), the grab spheres are 1.2× the body radius instead of 1.5× (neighbouring
  spheres overlap less, so two hands close together pick two nodes instead of sharing one), and colliders have
  no shape while the dragon flies. One hand pulling the body taut does not lock the other: tension is measured
  per grab and only holds back the move that stretches the taut side, so the other node keeps following its hand
  and the pulling one gives way (test).
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

`Sources/Macrowavers/Resources/FloatingIsland.usdz` comes from the design team's `ilha_RCP_v2.usdz`
(`Assets/Blender/floating-island/ilha_rcp.usdz`): the island with its tree, prepared in Reality Composer Pro, with
its materials. It is prepared headless with USD's Python API (`pxr`, which ships with Blender; Blender itself is
not used):

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    -P Assets/Blender/floating-island/make_island_asset.py -- \
    Assets/Blender/floating-island/ilha_rcp.usdz <output folder>
```

The source is Z-up under a root that turns it Y-up, ~14 m wide, with 64 meshes, a sun and a camera. Its 13
materials are Reality Composer Pro shader graphs (unlit "airbrush" colour ramps: grass, rock, trunk, canopy,
stones, flowers), several per mesh through face subsets; Blender cannot read them and re-exporting the meshes
would drop the face subsets. So the script edits the USD directly, leaves every mesh, face subset and material
as it is, and gives the code the same asset contract it has always used (no Swift code changed with the new
island):

- **Three parts:** `Island` (grass, rock, roots, stones, bushes, flowers, and the loose stones on the ground: its
  bounds give the rock's collider), `Tree` (trunk and canopy, the source's `Vert_001`) and `FloatingRocks` (the
  `Island_Debris_*` and `Island_Floater_*` pieces, which bob on their own): 42, 7 and 14 meshes. The sun, the
  camera and an empty mesh are removed: the island's materials are unlit, and the room's light does not change
  them. Their grain lies in each mesh's own coordinates (still: `GrainSpeed` 0), which the script never touches
  (it scales the file's root only), so they need no change. v2 has the same geometry as the first export, with
  these new materials. Each face shines with `EmissionBase + (1 − edge) · EmissionBoost` times its ramp colour (1 on the
  silhouette, the boost added on the faces seen head-on): the source's boost (−1.2) turns those faces black and
  the island looked dark, so the code sets `EmissionBoost` to `IslandSceneBuilder.islandEmissionBoost` (−0.7,
  head-on faces at 30 %) on every material when it loads the island; the asset is unchanged.
- **Origin at the base of the trunk, on the grass, and scaled by the tree alone** (`TARGET_TREE_HEIGHT`: 1.8415 m
  from the bottom of the trunk to the top of the canopy): both on the file's root, after its Z-up → Y-up turn.
  The result matches the previous island: `Island` spans (−1.16, −0.91, −1.15)…(1.32, 0.14, 1.34) m, 2.48 m wide,
  as before, so `IslandPlacement.standard`, the dragon's orbit (`OrbitPath.aroundTree`), the rock's collider and
  the floor occluder are unchanged.
- **Seven empty prims `fruit_01` … `fruit_07`** mark where the fruit hangs: the script casts rays at the canopy
  (the meshes with `Airbrush_Canopy`) from outside, the first six at the same angles and heights as before and the
  seventh (260°, for the banana next to the orange) in the widest gap left (it looks around a
  spot when a ray slips between the canopy's blobs), and puts each point 4.5 cm off the foliage, 1.14–1.36 m
  above the grass.
- No faces to turn: the source's meshes are double-sided (the earlier export's rock was wound inwards and looked
  hollow; this one is drawn from both sides).
- 184 KB, 91 `ShaderGraphMaterial`s once loaded (checked with RealityKit on macOS), validated with `usdchecker`.

In the scene:

- Asset size: island ~2.5 m (floating rocks ~3.7 m), tree 1.84 m, rock and roots 0.91 m deep below the grass.
  It is at **real size** (scale 1, `IslandPlacement.standard`), 2.8 m away, **grass at 0.6 m**
  (`IslandPlacement.grassHeight`), treetop ~2.45 m. If it is missing, the dragon circles an empty spot.
- Scale and height are independent: the origin is on the grass and the transform is translation × rotation ×
  uniform positive scale, so changing the scale grows the island around the grass and never moves it (test).
- At that height the rock's roots end ~0.3 m below the real floor and the lowest floating rocks just above it.
  Passthrough does not hide virtual content under the floor, so `IslandSceneBuilder` adds a floor patch 2 mm
  under y = 0 with `OcclusionMaterial` (`floorOccluder`, sized to the whole model so the floating rocks are
  covered whichever way the island is turned, outside the island so it never turns, bobs or fades): seen from
  above it hides only what is under the floor, and the island seems to rise out of it.

## The stone dragon

`StoneDragon.usdz` comes from the design team's `CartoonDragon12_RCP_v2.usdz` (`Assets/Blender/stone-dragon/`),
prepared headless:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    -P Assets/Blender/stone-dragon/make_stone_dragon_asset.py -- \
    Assets/Blender/stone-dragon/cartoon_dragon_rcp.usdz <output folder>
```

The source (Y-up, ~13 m long, a Sketchfab model prepared in Reality Composer Pro) is a head (face, horns, upper
teeth; the face skinned to a two-bone skeleton `JawRig`, `Root` and `Jaw`) and 19 separate stones with dorsal
spikes (`Block12` meshes), the last a flat tail (`Block12_Tail`), each with an idle animation, and a jaw
animation. The script:

- reads the rest pose and drops the animation and the skeleton (the stones' transform caches, the face's
  armature);
- orders the stones from the head to the tail (each the closest to the previous one) as `Stone_00` … `Stone_18`,
  origin at the centre, +Z along the body towards the tail, +Y up;
- scales the chain, from the head's centre to the tail stone's, to 2.35 m (the simulated body);
- builds `Head` (origin at the face's centre, snout +Z): the face's vertices skinned to the `Jaw` bone (68 of
  398, weight 1) become the lower jaw, `Jaw`, under `JawHinge` at the head of that bone; the upper teeth stay on the
  head; `mouth` and `nostrils` mark where fire and smoke come out. Fitted against the source's jaw animation, the
  jaw turns around exactly that point and the head's sideways axis (within 4 mm), at most 0.489 rad: the rig opens
  it as far (`StoneDragonRig.Asset.jawAngle` 0.49);
- keeps the design team's materials: `AirbrushGrain_00` (head, horns, teeth, jaw) and `AirbrushGrain_01` …
  `AirbrushGrain_19` (one per stone, from behind the head to the tail), Reality Composer Pro shader graphs: unlit,
  a colour ramp driven by the facing angle (each stone also shifted along a body gradient, `BodyT`) plus a fine
  grain drifting slowly over the surface (`GrainSpeed` 0.15). Blender cannot read them, so Blender exports the
  geometry only and notes each mesh's material by name; USD (`pxr`, bundled with Blender) copies
  `/Dragon/Materials` from the source and binds each mesh to its own, as in the source. RealityKit loads them as
  `ShaderGraphMaterial` (checked on macOS);
- resizes the grain with the mesh: the grain is laid out in the mesh's own coordinates (object space), and the
  bake and the chain's scale resize those coordinates (the stones by ×0.043, from 2.6 source units to ~11 cm), so
  each material's `GrainScale` is divided by its meshes' resize (`AirbrushGrain_01` 506 → 11 841 per metre): every
  stone keeps the ~1 300 grain cells across it that the design team set, instead of a grain 23 times coarser.

The v2 source is the design team's fix for the head, parts of which did not show: the geometry is the same as in
the first export, only the materials changed (the first ones used a world-space grain re-rolled 24 times a second,
`GrainFPS`).

The asset is 192 KB (the Sketchfab dragon it replaces, `DragonBody` + `DragonHead`, was 11.6 MB). Earlier exports:
`CartoonDragon_airbrush.usdc` had no usable material (Blender's MaterialX graph, which RealityKit does not render,
with the grain frozen at one position: flat grey boxes); `CartoonDragon_RCP.usdz` had one material for the whole
dragon and opened the mouth in a mesh animation of the face (the script then took the face's pieces that move in
it as the jaw).

**`StoneDragonRig`** (picked first by `DragonRigLoader`):

- `StoneDragonLayout` (Model, tested) keeps each stone's distance from the head along the body, scaled to the
  simulated length, and gives it the closest node: increasing, one per stone, never the head's node 0.
- Every frame each stone sits on the smoothed body (`DragonCurve`) at its distance, turned along it (+Y as close
  to world up as the body allows), breathing with its node and floating 3 mm on its own; the head follows node 0
  like the other rigs (look, neck lift, jaw turning 0.49 rad when wide open, smoke and fire).
- One scale for stones and head: the design's proportions along the simulated body, at 0.9
  (`Asset.stoneScale`): a thin gap between the stones (1–2 cm; at 1 they nearly touch, as modelled), the widest
  stone ~13 cm, the head ~25 cm long. The simulated body is 8 cm thick, so where the dragon crosses itself the
  stones may touch a little.
- **Every stone is grabbable.** Each stone hangs from the collider of the node that holds it, so looking at it
  lights it up and pinching it grabs that node. In the mini-game only those 19 nodes and the head (node 0, whose
  collider carries the head) are grabbable (`DragonRig.grabTargets`), with a sphere 0.95 × half the distance to
  the closest neighbour (~6 cm for a stone, ~9 cm for the head; the stones are ~12 cm apart), so neighbouring
  spheres barely touch and two hands take two different pieces. The nodes in between carry no grab;
  the simulation moves them with their neighbours. While the dragon circles the tree every node is still a tap
  target, as before.
- No wings and no separate eyes: the pose's wing and blink values are not drawn.

## Asset specification (for the design team)

`StoneDragonRig` uses `StoneDragon.usdz` when it is in the bundle (made by `make_stone_dragon_asset.py` from the
design team's file, see [The stone dragon](#the-stone-dragon)); without it the procedural placeholder is used.
What the rig expects:

- **`Stone_00` … `Stone_NN`** (two digits, from behind the head to the tail): one rigid piece each, origin at its
  centre, +Z along the body towards the tail, +Y up. Any number of stones (one node each, up to the node count);
  their rest distances from the head set where they sit on the body. No animation: the code places them.
- **`Head`**: origin at the head's centre, snout towards **+Z**, +Y up, with `JawHinge` (the lower jaw hangs from
  it; the code turns it around its +X to open the mouth) and two empty children, `nostrils` (smoke) and `mouth`
  (fire, pointing +Z).
- Materials: anything RealityKit renders (the design team's are Reality Composer Pro shader graphs). The code
  does not replace them.
- Sounds (optional; wav/m4a/mp3/caf in the bundle): `DragonGrowl`, `DragonRoar`, `DragonRumble`,
  `DragonWhoosh`, played as spatial audio from the head.

The stones follow a Catmull-Rom spline through the simulated nodes (`DragonCurve`), and the first stretch of
neck (`StoneDragonRig.Asset.neckBlendLength`) leaves the back of the head in the head's direction, so the rigid
head and the stones behind it do not show a seam when the head turns. The head sits inside a container entity:
the code moves the container and never overwrites the asset's own transforms.

The source is a Sketchfab model ("Cartoon Dragon"): check its licence and credit it in the app if it asks to.

## Tuning

| Where | Parameter | Effect |
|---|---|---|
| `TangleConfig` | `selfFriction` | higher = harder knot |
| `TangleConfig` | `anchorHead` | `false` = much easier (the head drifts when the tail is pulled) |
| `TangleConfig` | `maxTension`, `tensionSoftness`, `tensionReach` | lower = fewer glitches when pulling hard, softer grab; how much body around a grab counts |
| `TangleConfig` | `grabLeash` | how far ahead of its node a hand may pull (lower = no rubber band, more lag) |
| `TangleConfig` | `flattenStrength` | how fast the body settles onto the plane (higher loosens the resting knot) |
| `TangleConfig` | `crossingSkip` | segments this close never count as crossings |
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
| `IslandSceneBuilder` | `islandEmissionBoost` | how bright the island is (towards 0 = brighter, flatter; the asset's −1.2 = darkest) |
| `OrbitPath.aroundTree` | radius, height, swings, speed (asset metres) | how the dragon wraps the tree |
| `DragonFlight.Settings` | `approachDistance`, `landingSpeed` | where it stops in front of the player, landing duration |
| `DetanglingStateComponent` | `tapRadius`, `fadeDuration` | how easy the dragon is to tap, fades |

## Tests

`Tests/MacrowaversTests/UntangleTests.swift` (Swift Testing) covers the Model and the view model: initial
crossings, the knot not untying by itself, rigid turns keeping crossings, the head staying put unless held,
following the hand when held (even in the air) and staying where it is left, settling onto the plane, two-handed
grabs,
one hand pulling taut not locking the other (the knot slides first, so the test pulls 1.6 m), hand tracking (one node per hand, hand-off, late end after a
re-grab, cancelled grab), left and right hands dragging two parts independently through the view model,
the fit starting with a turn after the delay, the dragon waiting while held, a shaky hand not shaking the body,
a taut pull not flickering (pulled 1.5 m apart, so it ends up taut), flight keeping its distance from the player, the orbit never crossing itself, the
captive dragon turning rigidly with the island, the landing matching the knot, the farewell ending, the free
dragon staying in front of the player and hovering where they look (two gaze directions), the story flow
(captive, a tap only makes it angry for `alertDuration`, `callDragon()` → puzzle), tilt clamping, restart and
play again.
`SceneFocusTests.swift` covers focus mode (what fades with a fruit close, while untangling, while the
elixir flies, when exploring, only landing and untangling focusing on the dragon) and the island's transform (at least the original size, grass at 0.6 m
whatever the scale, positive uniform scale), the island's spin (the side facing the player follows the hand from
any side of the island, movement towards it or up does not turn it, no jump with the player above the trunk), and
the speaking dragon keeping only itself visible.
`StoneDragonTests.swift` covers the stone dragon's layout (stones along the whole body in the asset's
proportions, each held by its own node next to it, increasing and never the head, even when crowded).
`StoryTests.swift` covers the free dragon waiting for the player's answer (and taking off on its own without the
story).

## Known limits

- Pulling very hard can make one part clip through another for a moment (see `maxTension`).
- The stone dragon's look (thickness, gaps between the stones) and its grab spheres are first guesses: check them
  on device (`StoneDragonRig.Asset`). The stones are ~13 cm wide but the simulated body is 8 cm thick
  (`TangleConfig.radius`), so where the dragon crosses itself the stones may touch or slightly overlap. A thicker
  body (radius 5–5.5 cm, with a retuned starting knot) or smaller stones (`stoneScale` ~0.7) would fix it, at the
  cost of changing the puzzle's difficulty.
- The physics was retuned headless; how it feels in the hand (the leash, the sideways give of a taut grab, the
  friction) needs checking on device. A taut grab may stretch one segment by up to ~9 % for a moment.
- Damping, ground friction, the pull towards the plane and the friction are per sub-step: changing `substeps`
  silently changes them too (they should become per-second values).
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
