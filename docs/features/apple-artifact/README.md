# The Tree's Fruit, the Ingredients and the Elixir

The fruit hanging on the floating island's tree. The player picks a fruit and it comes close. They open it
and a **glowing orb**, an **ingredient** of the elixir, rises out of it. A moment later it flies off and joins
a small **elliptic orbit in front of the player**, just below their eyes. With three ingredients in orbit, the player
**snaps their fingers**: the ingredients spiral in and fuse into the **elixir**. The elixir flies to the dragon
and soothes it. The dragon comes to the player and the untangling puzzle starts
([Untangle the Dragon](../untangle-dragon/README.md)).

Origins:
- The apple and pomegranate come from Isadora's AppleSpiral prototype: a spiral-cut apple deformed by a Metal shader, with worms.
- The banana and pineapple come from the fruit lab prototype (`fruit_test_2`).

Status: playable with placeholder ingredients (RealityKit spheres in three colours) and a procedural blue elixir,
until the 3D assets arrive. The kalash (the spell container by the hip) is gone: the orbit replaces it.

## How to try it

1. Install Xcode's Metal Toolchain once: `xcodebuild -downloadComponent MetalToolchain`. It's needed to compile
   `AppleSpiral.metal`.
2. Run the app and choose **Open the Island**. Look at a fruit on the tree and pinch.
3. Open the fruit:

   | Fruit | How to open it |
   |---|---|
   | Apple | Pull the stem up (pinch and drag upwards), then tap the worms |
   | Pomegranate | Pull it apart with both hands (in the simulator hold Option) |
   | Banana | Pinch each of the 4 strips of peel and pull it outwards and down |
   | Pineapple | Chop down through it with the edge of your hand, or tap it |

4. The orb rises out of the fruit and, after a moment, flies into the orbit in front of you (tap it to send it at
   once). The fruit goes back to its branch.
5. With 3 ingredients in orbit, **snap your fingers**: press the thumb on the middle finger's pad (the label
   then says "Now snap!") and snap, either hand. The dragon panel's debug shows what the detector reads
   (**Snap** row). Without hand
   tracking (simulator) tap one of the orbiting ingredients, or press **Brew the Elixir** on the label under
   the orbit.

## What the player sees

| Moment | Behaviour |
|---|---|
| On the tree | 3 apples, 1 pomegranate, 1 banana and 1 pineapple hang on the canopy, swaying gently, turning and bobbing with the island. Looking at a fruit highlights it |
| Tap a fruit | It flies from its branch to ~50 cm in front of the player, a little below the eyes, and grows. A small panel under it says what to do. **Focus mode**: the island, the tree, the other fruit and the dragon fade to 25% while it is close |
| Open it | Apple: the spiral slices lift (Metal compute shader) and 3 worms guard the orb. Pomegranate: the halves open like a book and 40 seeds burst out. Banana: each strip turns on its hinge and hangs down. Pineapple: the halves fall open towards the player and the crown tips away |
| Ingredient found | The orb rises out of the fruit (1.2 s), glowing and pulsing, and floats there for 0.6 s (or until tapped) |
| Into the orbit | It takes its ingredient's colour (pomegranate red, saffron gold, pistachio green), lifts and arcs into its slot on the orbit (1.4 s), leaving a trail of sparks. The fruit goes back to its branch |
| In orbit | The ingredients go round a small ellipse (48 × 28 cm) 60 cm in front of the player, a little below their eyes, its far side tilted up so they see it whole; evenly spaced (120°), one turn every 9 s. The orbit follows the player as they walk and turns with them only when they really turn (not when they glance at a fruit). While a fruit is close it rises above it and its panel, then comes back down. A small label under the orbit counts them |
| Orbit complete | The label says "Press your thumb on your middle finger and snap to brew the elixir.", and "Now snap!" while the thumb is pressed |
| Snap | The ingredients spiral into the orbit's centre, whirling faster, shrinking, while the elixir grows there (2.2 s). It pops to its full size with a flash of sparks and floats there for 1.2 s |
| The elixir flies | An arc rising above the straight line, landing on the dragon's head even as it moves. The scene comes back from focus mode, the dragon is soothed and comes to the player. If the dragon has already left the island (debug **Call It Now**), the elixir keeps floating in front of the player |
| Empty fruit | A fruit whose ingredient already orbits: once opened, the panel says "No ingredient left in this one" and **Back to the Tree** becomes the prominent button. The fruit never leaves by itself |
| A 4th ingredient | With 3 already in orbit the orb stays above its fruit: "Three ingredients already orbit you: brew the elixir first." |
| Back to the Tree / Close It Again | The fruit flies back to its branch, closing gently on the way / closes it again. An ingredient already freed still joins the orbit from the branch |

Every fruit holds one ingredient, so no choice is wrong: any 3 of the 6 fruits make the elixir.

## The orbit

`ElixirOrbit` (pure maths) keeps the orbit; the `OrchardSystem` feeds it the player's head every frame.

**Where it is.** Not around the player (they would only ever see part of it, and a wide ellipse runs through
their body and arms) but around a centre `O` close in front of them, small enough to be seen whole. It lives in
the frame of the player's body: `forward` and `right` come from a yaw `ψ` (`forward = (−sin ψ, 0, −cos ψ)`,
`right = (cos ψ, 0, −sin ψ)`), never from the head's pitch, so looking down at it does not move it.

```
O     = eyes + forward · distance + up · (lift − drop)
depth = forward · cos β + up · sin β              the plane tilted by β, far side up: it faces the eyes
φ     = θ + 2π k / 3                              slot k, evenly spaced; φ = 0 on the far side
P     = O + right · a sin φ + depth · b cos φ
θ(t + Δt) = θ(t) + ω · spin · Δt,   ω = 2π / period
```

| Symbol | Value | Why |
|---|---|---|
| `distance` | 0.60 m | within the comfortable focus range (0.5–1 m), beyond the hands snapping in front of the chest |
| `drop` | 0.18 m | centre ~17° below the line of sight: the comfortable band for looking down without bending the neck |
| `a` | 0.24 m | ±22° to the sides: the whole orbit in the central field of view, no head turn needed |
| `b` | 0.14 m | half-depth in the tilted plane: the near side stays ~0.49 m from the eyes, ~0.3 m in front of the chest |
| `β` | 35° | seen from ~17° above, a flat orbit would look like a line; tilted it reads as an open ellipse (≈ 2 : 1) |
| `period` | 9 s | ~0.13 m/s along the ellipse: calm, alive |
| `lift` | 0, or 0.28 m while a fruit is close | the focused fruit (0.5 m, just below the eyes) and its panel sit where the orbit is: the orbit rises above them and comes back down (`1 − e^(−4 Δt)`) |

Over a whole turn every ingredient stays ≥ 0.45 m in front of the eyes, within 25° to the sides and 5–35° below
the eyes (test `thePlayerSeesAllOfItClearOfTheirBody`). Three ingredients on a ~1.2 m perimeter are ~40 cm apart:
the 7.6 cm halos never touch.

**Lazy follow (comfort).** Content locked to the head moves with every glance and tires the player; content
locked to the world is left behind when they walk. The orbit is in between:
- `eyes ← eyes + (head − eyes) · (1 − e^(−3 Δt))`: it follows the player smoothly (walking, sitting down).
- The yaw `ψ` stays put while the head looks within 30° of the orbit's front (glancing at an ingredient, at a
  fruit). Past that the player has turned: `ψ` eases towards the head's yaw (`1 − e^(−2 Δt)` per frame) until
  within 5°.

**Fusion.** With `u` the fusion's progress (0…1) and `e = smootherstep(u) = u³(6u² − 15u + 10)` (no visible
start or stop), the ellipse shrinks to its centre while spinning faster:

```
P_fusion(k) = O + (1 − e) · (right · a sin φ + depth · b cos φ)
spin = 1 + 3 e
ingredient scale = 1 − 0.7 e,  elixir scale = 0.6 · smoothstep(0.55, 1, u)
```

so the ingredients leave the orbit with no jump, spiral inwards and meet at `O` exactly when the elixir has
grown out of them. Brewed, the elixir pops from 0.6 to 1 with `easeOutBack` (~10 % overshoot, 0.45 s) and a burst
of 160 sparks.

**Flight.** A quadratic Bézier `B(t) = (1 − t)² P₀ + 2(1 − t)t P₁ + t² P₂`, with `P₀` where it was brewed, `P₂` the
dragon's head (read every frame: it moves) and `P₁` the midpoint lifted by `0.25 + 0.1 · |P₂ − P₀|`. `t` is the
flight time over `duration = max(|P₂ − P₀| / 1.1 m/s, 0.9 s)`, eased in and out: it always lands on time.

## The snap

ARKit hand tracking (`HandTracker`) gives each hand's wrist, middle knuckle, the thumb and index tips, and the
middle finger's last joint (DIP) and tip. Joints flagged "not tracked" are kept with ARKit's estimate: in a fast
movement the fingertips lose tracking for a frame, exactly when the snap happens.

A snap lasts a few hundredths of a second (one to three readings), so `SnapDetector` does not follow the finger:
it compares the two poses on either side of it, each against the player's own hand.
1. **Loaded:** the thumb tip within 3 cm of the middle finger's **last phalanx** (the segment DIP → tip,
   `thumbToMiddlePad`), not pinching the index (thumb–index ≥ 2 cm: that is the system's tap). Measured tip to
   tip it would fail: pressing the pad, the two tip joints stay 2–4 cm apart.
2. **Released**, at most 0.3 s after the last loaded reading (a late frame or two), compared with it:
   - thumb and middle tips at least **3 cm farther apart**, opened at **0.5 m/s** or more (a snap: 1 m/s or more);
   - the middle tip at least **1.2 cm closer to the wrist**: it flexed into the palm. Simply opening the fingers
     stretches it instead, so it never counts.

Each hand on its own, with a 0.6 s cooldown; repeated readings (the frame is faster than the tracking) count once.
The snap is read only while the orbit is complete. A tap on an orbiting ingredient does the same, so the game also
works without hand tracking.

**Tuning on the headset.** The dragon panel's debug has a **Snap** row: `pad` is the closest thumb–pad distance
now (it must go under 3 cm when the thumb presses), `last +sep/curl cm speed m/s ✓/✗` what the latest release
measured. A missed snap shows which threshold it failed.

## Code layout

```
Sources/Macrowavers/
├── Model/Orchard/                       Pure logic (Foundation + simd), unit-tested
│   ├── AppleShape.swift                   Spiral-cut apple maths, shared with the shader (CPU fallback too)
│   ├── WormSwarm.swift                    Worm behaviour: crawl, burrow, speed up, hide when closed
│   ├── Elixir.swift                       Ingredients in orbit, brew, fusing → brewed → flying → delivered, curves
│   ├── ElixirOrbit.swift                  The ellipse in front of the player, lazy follow, fusion spiral, ElixirFlight
│   ├── HandGestures.swift                 HandSample, ChopDetector (pineapple), SnapDetector (elixir)
│   └── OrchardViewModel.swift             @Observable: fruit focus, openings, worms, one ingredient per fruit, elixir
└── Views/Orchard/
    ├── FruitPanelView.swift               Panel under the focused fruit (RealityView attachment, not a window)
    ├── ElixirPanelView.swift              Label under the orbit: ingredients in orbit, how to brew
    ├── OrchardInteractions.swift          Gestures (tap fruit/worm/pineapple/ingredient, pull stem, peel, open
    │                                      pomegranate, drag seeds) and the link elixir → dragon
    └── RealityKit/
        ├── OrchardScene.swift               Components, OrchardSystem, FocusSystem, builder, per-fruit drawing
        ├── OrbScene.swift                   The ingredients: sphere template, colours, trail, where each one is every frame
        ├── ElixirScene.swift                The elixir and its flash; orbit, snap and flight in the system
        ├── HandTracker.swift                ARKit hand tracking → HandSample
        ├── AppleRig.swift                   LowLevelMesh + Metal compute pipeline, stem, worms
        ├── AppleSpiral.metal                `deformApple` kernel (one thread per vertex)
        ├── PomegranateRig.swift             Halves, crown, seed burst
        ├── BananaRig.swift                  Banana.usdz, peel strips on hinges
        └── PineappleRig.swift               Pineapple.usdz, halves and crown opening
```

The fruit hangs from the island's root at the points `fruit_01` … `fruit_12` stored in `FloatingIsland.usdz`
(see the island section of the dragon docs).

### State

```
OrbState:     sealed ──open──▶ revealed ──1.8 s or tap──▶ orbiting(slot) ──fused──▶ spent
ElixirState:  gathering ──3rd ingredient──▶ ready ──snap──▶ fusing ──2.2 s──▶ brewed ──1.2 s, dragon on the island──▶ flying ──arrived──▶ delivered
```

The view model owns both (`orbs`, `elixir`); the RealityKit layer only draws them and keeps what is purely visual:
the orbit (`OrchardComponent.orbit`), each ingredient's flight into the orbit and its colour (`OrbComponent`), the
elixir's flight (`OrchardComponent.flight`).

### One frame

`OrchardSystem.update` (every frame) does these steps in order:
1. **Model.** `orchard.update(deltaTime:)` advances the worms of the focused apple, the orbs' rise (sending the
   risen ones into orbit) and the elixir.
2. **Focus.** When the focused fruit changes, it moves the fruit between its branch and the **stage** in front of the
   player (`setParent(_:preservingWorldTransform:)` + `FocusComponent` easing), and switches tap targets.
3. **Openings.** It applies each fruit's opening. `AppleRig.apply(opening:)` re-runs the Metal kernel only when the value changes.
4. **Chop.** With hand tracking, it feeds `ChopDetector` with the hands near the focused pineapple.
5. **Orbit.** `ElixirOrbit.follow` with the head's pose (faster spin while fusing); the label's anchor follows it.
6. **Snap.** With the orbit complete, it feeds `SnapDetector` with both hands; a snap calls `orchard.brewElixir()`.
7. **Orbs.** It moves each orb: sealed, rising above its fruit, flying into its slot, orbiting, spiralling into the elixir.
8. **Elixir.** It grows it, flashes it, flies it. On arrival it calls `orchard.elixirDelivered()`.
   `OrchardInteractions` sees `.delivered` and calls `untangle.callDragon()`.

## Design decisions (and why)

- **No new window.** Everything lives in the existing immersive space. The instructions are RealityView
  attachments under the fruit and under the orbit (hidden in SwiftUI while a fruit is close: the fruit's panel
  speaks then).
- **No container to carry.** The kalash asked the player to drag every orb to their hip. The orbit keeps what they
  found in sight, around them, without a gesture: finding an ingredient is the reward, not carrying it.
- **Every gesture targets its own component.** The components are `FruitTapTargetComponent`, `AppleStemComponent`, `WormComponent`,
  `PomegranateBodyComponent`, `SeedComponent`, `BananaPeelComponent`, `PineappleBodyComponent` and `OrbComponent`.
  `.targetedToAnyEntity()` would steal the pinch from the dragon's tap and grabs, and from spinning the island.
- **Two view models, connected by the view.** `OrchardViewModel` knows nothing about the dragon. The immersive
  view tells it whether the dragon is still on the island (`isDragonOnIsland`). The elixir only flies then, and the
  orbiting ingredients only take the pinch then (and never while a fruit is close): during the untangling they
  would steal the grabs on the knot. The view calls `callDragon()` when the elixir arrives.
- **The chop and the snap use ARKit hand tracking, the rest are SwiftUI gestures.** SwiftUI has no "fast hand
  coming down" or "snap". The detectors are pure structs fed with `HandSample`s, so they are unit-tested.
  - **Two poses, not a trajectory.** See [The snap](#the-snap): robust at the tracking's rate.
  - **Taps always work too:** a tap opens the pineapple, a tap on an orbiting ingredient brews the elixir. Without
    hand tracking (simulator, permission denied) they are the only way, and the label shows **Brew the Elixir**.
- **The orbit is body-locked with lazy follow, not head-locked.** See [The orbit](#the-orbit).
- **Placeholders are RealityKit spheres.** One template (core, halo, trail) cloned per fruit and tinted per slot,
  so the real ingredients can replace it in `OrchardSceneBuilder.makeOrbTemplate()` alone.
- **The pineapple opens with an eased animation, not physics.** The prototype launched the halves as dynamic bodies.
  There is no floor in front of the player, and the fruit must close again when it goes back to the tree.
- **Metal with a safety net.** If Metal or the apple kernel is missing, the apple is deformed on the CPU with the
  same maths (`AppleShape`).
- **Fruit on the island, focus on a stage.** On the tree the fruit is a child of the island. Focused, it moves to
  a stage ~50 cm from the eyes. The ingredients and the elixir live under the orchard's root, outside the faded
  parts, so they always stay fully visible.
- **A fruit leaves only when the player is done with it.** **Back to the Tree**, its ingredient joining the orbit,
  the snap, or the elixir flying. The return is eased and the fruit closes gently on the way.

## Tuning

| Where | Parameter | Effect |
|---|---|---|
| `OrchardViewModel.init` | `apples`, `pomegranates`, `bananas`, `pineapples` | how many fruits hang on the tree (up to 12 hang points) |
| `OrchardViewModel` | `peeledStrip`, `burstOpening` | when a banana counts as peeled, when the pomegranate bursts |
| `OrchardViewModel` | `orbRiseDuration`, `orbOrbitDelay` | how long an ingredient rises, how long it floats before joining the orbit |
| `Elixir` | `ingredientCount`, `fusingDuration`, `brewedHold`, `popDuration` | ingredients needed, how long the fusion takes, how long the elixir waits before flying |
| `ElixirOrbit.Settings` | `distance`, `drop`, `lateralRadius`, `depthRadius`, `tilt`, `period` | where the orbit is, its size, tilt and speed |
| `ElixirOrbit.Settings` | `followResponsiveness`, `turnDeadZone`, `turnResponsiveness` | how the orbit follows the player |
| `ElixirOrbit.Settings` | `roomLift`, `liftResponsiveness`, `fusionSpin`, `hintDrop` | how it makes room for a fruit, how the ingredients whirl, where the label floats |
| `ElixirFlight` | `speed`, `minimumDuration` | how fast the elixir flies |
| `OrbComponent` | `joinDuration` | how long an ingredient takes from its fruit to the orbit |
| `ChopDetector.Settings` | `speed`, `cooldown` | how fast the hand must come down |
| `SnapDetector.Settings` | `contactDistance`, `pinchClearance`, `separation`, `curl`, `window`, `minimumSpeed`, `cooldown` | how strict the snap is |
| `WormSwarm.Settings` | `count`, `crawlSpeed`, `speedUpPerCatch`, `burrowInterval`, `burrowDuration` | worm difficulty |
| `OrchardSceneBuilder` | `…SizeOnTree`, `…SizeFocused`, `ingredientColor` | fruit sizes on the tree and in front of the player, ingredient colours |

## Assets

| Asset | Where it comes from |
|---|---|
| `Banana.usdz` | Poly Haven `bananas` (CC0), cut into four peel strips by the fruit lab's `build_fruits.py`. Prims: `peelPivot_N/peel_N`, `peelBase`, `core`; the prototype's `stand` and `item` are removed at load |
| `Pineapple.usdz` | Procedural, from the same script. Prims: `pineapple_1`, `pineapple_2`, `crown`; `item` removed at load |
| Ingredients (missing) | RealityKit spheres for now (`OrchardSceneBuilder.makeOrbTemplate`): 5 cm core, 7.6 cm halo, origin at the centre |
| Elixir (missing) | A procedural blue orb with sparkles (`ElixirRig`) |

Apples and pomegranate are generated in code (the apple must stay procedural: the shader cuts it).

## Tests

- **`Tests/MacrowaversTests/OrchardTests.swift`:**
  - apple maths and Swift/Metal layouts, and the worms
  - every fruit kind opening its own way and freeing its ingredient
  - leaving a fruit early
  - an ingredient rising, joining the orbit by itself or when tapped, also from a fruit sent back early
  - empty fruit, a complete orbit taking no more
  - the elixir brewing, flying, waiting when the dragon is gone, sending the close fruit back
- **`Tests/MacrowaversTests/HandGestureTests.swift`:** chop speed, zone and cooldown; the snap (fast, slow, late,
  fingers that do not curl, a pinch, repeated readings, cooldown, one hand at a time); the elixir's slots, timing
  and curves; the orbit's shape, period, lazy follow and fusion spiral; the flight's arc and arrival.

## Known limits

- **The snap and the chop need a headset.** The simulator has no hand tracking: use the taps.
- **Snap thresholds come from hand proportions, not from recordings:** tune `SnapDetector.Settings` on device
  with the dragon panel's **Snap** row.
- **Head, not body.** The orbit turns with the head's yaw past 30° (visionOS gives no torso pose): a long look to
  the side turns it too.
- **Hand height, not the apple.** Pulling the stem uses the hand's height: if the player moves their head a lot while
  pulling, the opening follows the hand.
- **The orbit ignores the room.** 0.5–0.75 m in front of the eyes it can sink into a table the player sits at.
- **The flight ignores the canopy.** The elixir's arc rises above the straight line but may still cross the tree.
