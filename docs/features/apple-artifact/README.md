# The Tree's Fruit, the Ingredients and the Elixir

The fruit hanging on the floating island's tree. The player picks a fruit and it comes close. They open it
and a **glowing orb**, an **ingredient** of the elixir, rises out of it. A moment later it flies off and joins
a small **elliptic orbit to the player's right**, just below their eyes, clear of the fruit in front of them. With three ingredients in orbit, the player
**snaps their fingers**: the ingredients dive one by one into the **flask** waiting in the middle of the orbit and
brew the **elixir**. The flask flies to the dragon and pours the elixir over its head, which soothes it. The dragon comes to the player and the untangling puzzle starts
([Untangle the Dragon](../untangle-dragon/README.md)).

Origins:
- The apple and the pomegranate's gestures come from Isadora's AppleSpiral prototype: a spiral-cut apple deformed by a Metal shader, with worms. The pomegranate itself is now the design team's model (`Pomegranate.usdz`).
  The prototype's own Xcode project was removed once ported; it is still in the git history.
- The banana and pineapple were first shaped in the fruit lab prototype (`fruit_test_2`, a separate project that
  is not in this repo); the design team then gave them the same airbrush materials as the island, the dragon and
  the pomegranate (`Banana.usdz`, `Pineapple.usdz`).
- The orange is generated in code (`OrangeRig`): no asset.

Status: playable with the design team's ingredient gem (`IngredientGem.usdz`, in three colours) and flask
(`ElixirFlask.usdz`).

## How to try it

1. Install Xcode's Metal Toolchain once: `xcodebuild -downloadComponent MetalToolchain`. It's needed to compile
   `AppleSpiral.metal`.
2. Run the app and choose **Start**. Tap through the narrator's pages ("What are you searching for?", "Chapter I"):
   the island fades in. Look at a fruit on the tree and pinch (fruit can be picked while the dragon is still on
   the island).
3. Open the fruit:

   | Fruit | How to open it |
   |---|---|
   | Apple | Pull the stem up (pinch and drag upwards), then tap the worms |
   | Pomegranate | Pull it apart with both hands (in the simulator hold Option) |
   | Banana | Pinch each of the 4 strips of peel and pull it outwards and down |
   | Orange | Pull it apart with both hands (in the simulator hold Option): it splits into two halves, then falls open into 8 wedges |
   | Pineapple | Chop down through it with the edge of your hand, or tap it |

4. The orb rises out of the fruit and, after a moment, flies into the orbit on your right (tap it to send it at
   once). The fruit goes back to its branch.
5. With 3 ingredients in orbit, **snap your fingers**: press the thumb on the middle finger's pad (the label
   then says "Now snap!") and snap, either hand. Without hand
   tracking (simulator) tap one of the orbiting ingredients, or press **Brew the Elixir** on the label under
   the orbit.

## What the player sees

| Moment | Behaviour |
|---|---|
| On the tree | 3 apples, 1 pomegranate, 1 banana, 1 orange and 1 pineapple hang on the canopy, swaying gently, turning and bobbing with the island. Looking at a fruit highlights it |
| Tap a fruit | It flies from its branch to ~50 cm in front of the player, a little below the eyes, and grows. A small panel under it says what to do. **Focus mode**: the island, the tree, the other fruit and the dragon fade to 25% while it is close |
| Turn it | With hand tracking, cup a hand next to the close fruit (all four fingers curled like a bowl, the thumb off the index, the palm within ~16 cm) and turn the hand: the fruit turns with it, in every direction, about its centre. Open the hand and it stays as it is; back on the tree it eases to its home pose, and it comes close upright again. The panel says so under the hint. Not in the simulator |
| Open it | Apple: the design team's apple gives way to its spiral-cut copy, whose slices lift (Metal compute shader) while the stem and the leaf rise with the top one, and 3 worms guard the orb. Pomegranate: the halves open like a book and its 40 seeds burst out. Banana: each strip turns on its hinge and hangs down. Orange: the halves move apart and turn their cut faces to the player, then the 8 wedges fall open into a ring around the orb, showing their flesh and white rind. Pineapple: the halves fall open towards the player and the crown tips away |
| Ingredient found | The orb rises out of the fruit (1.2 s), glowing and pulsing, and floats there for 0.6 s (or until tapped) |
| Into the orbit | It takes its ingredient's colour (pomegranate red, saffron gold, pistachio green), lifts and arcs into its slot on the orbit (1.4 s), leaving a trail of sparks. The fruit goes back to its branch |
| In orbit | The ingredients go round a small ellipse (26 × 28 cm) 60 cm away, 30° to the player's right and a little below their eyes, facing them, its far side tilted up so they see it whole: always between ~18° and ~42° to the right, never in the middle of the view where the fruit comes close; evenly spaced (120°), one turn every 9 s. The orbit follows the player as they walk and turns with them only when they really turn (not when they glance at a fruit). A small label under the orbit counts them |
| Hold an ingredient | Pinch an ingredient in orbit and move it (before the brew): it follows the hand and turns with the wrist, while the others keep going round. With two hands (in the simulator: hold Option) move them apart or together to make it bigger or smaller (0.5×–3×), turn them around it to turn it about any axis. Let go (the last hand), it flies back to its slot in the same arc it came in from its fruit (1.4 s), turns upright again and takes back its own size. A pinch that does not move stays a tap. Looking at it or taking it draws no highlight |
| Orbit complete | The label says "Press your thumb on your middle finger and snap to brew the elixir.", and "Now snap!" while the thumb is pressed |
| The flask | With the first ingredient found, an empty, corked glass flask appears in the middle of the orbit (0.6 s) and turns slowly there; the ingredients go round it. Each time one reaches the orbit the flask wobbles and its glass glows in that ingredient's colour |
| Snap (3.6 s) | The cork pops out and tumbles above the neck (0.4 s). The ingredients dive in **one at a time** (0.75 s each): each leaves its place in an arc up above the neck, drops down into the flask, shrinking, and lands with a burst of bubbles; the liquid rises by a third, sloshes and takes its colour (red, then mixed with gold, then with green). The cork goes back on (2.7–3.2 s) and the liquid swirls into the elixir's glowing blue (3.2–3.6 s) |
| Brewed (1.2 s) | The flask swells a little with a flash of sparks and floats there, throbbing; bubbles rise, and its glow lights the player's hands |
| The elixir flies | The flask flies in an arc rising above the straight line, landing on the dragon's head even as it moves. The scene comes back from focus mode. If the dragon has already left the island (debug **Call It Now**), the flask keeps floating in front of the player |
| Poured (1.6 s) | Above the dragon's head the cork pops, the flask tips over (its neck down) and a sparkling blue stream pours out while the liquid drains; then the flask fades. The dragon, soothed, comes to the player |
| Empty fruit | A fruit whose ingredient already orbits: once opened, the panel says "No ingredient left in this one" and **Back to the Tree** becomes the prominent button. The fruit never leaves by itself |
| A 4th ingredient | With 3 already in orbit the orb stays above its fruit: "Three ingredients already orbit you: brew the elixir first." |
| Back to the Tree / Close It Again | The fruit flies back to its branch, closing gently on the way / closes it again. An ingredient already freed still joins the orbit from the branch |

Every fruit holds one ingredient, so no choice is wrong: any 3 of the 7 fruits make the elixir.

## The orbit

`ElixirOrbit` (pure maths) keeps the orbit; the `OrchardSystem` feeds it the player's head every frame.

**Where it is.** Not around the player (they would only ever see part of it, and a wide ellipse runs through
their body and arms) but around a centre `O` close to them, small enough to be seen whole, and **to the side**:
the middle of the view belongs to the fruit the player picks (it comes 0.5 m from the eyes in the direction of
the fruit, within ~±10°, plus its own size and its panel): an orbit in front ran through them. It lives in the
frame of the player's body: `forward` and `right` come from a yaw `ψ` (`forward = (−sin ψ, 0, −cos ψ)`,
`right = (cos ψ, 0, −sin ψ)`), never from the head's pitch, so looking down at it does not move it. `towards`
and `across` turn them by the bearing `α`, so the ellipse faces the eyes instead of being seen at an angle.

```
towards = forward · cos α + right · sin α           from the eyes to the orbit, seen from above
across  = right · cos α − forward · sin α           side to side, as the player sees the orbit
O       = eyes + towards · distance − up · drop
depth   = towards · cos β + up · sin β              the plane tilted by β, far side up: it faces the eyes
φ       = θ + 2π k / 3                              slot k, evenly spaced; φ = 0 on the far side
P       = O + across · a sin φ + depth · b cos φ
θ(t + Δt) = θ(t) + ω · spin · Δt,   ω = 2π / period
```

| Symbol | Value | Why |
|---|---|---|
| `α` (`bearing`) | 30° to the right | clear of the fruit in front of the player and of the island panel (50° to the left) |
| `distance` | 0.60 m | within the comfortable focus range (0.5–1 m), beyond the hands snapping in front of the chest |
| `drop` | 0.18 m | centre ~17° below the line of sight: the comfortable band for looking down without bending the neck |
| `a` | 0.13 m | ±12° around `α`: the whole orbit between ~18° and ~42° to the right, inside the field of view with no head turn; the flask (~15 cm wide, in the middle) still fits between the two sides |
| `b` | 0.14 m | half-depth in the tilted plane: the near side stays ~0.49 m from the eyes, ~0.3 m in front of the chest |
| `β` | 35° | seen from ~17° above, a flat orbit would look like a line; tilted it reads as an open ellipse (≈ 2 : 1) |
| `period` | 9 s | ~0.13 m/s along the ellipse: calm, alive |

Over a whole turn every ingredient stays 0.55–0.72 m from the eyes, 17.6°–42.4° to the right and 8°–28° below
the eyes; the flask is at 30° to the right, 17° below (test `thePlayerSeesAllOfItToTheSideClearOfTheFruitAndTheirBody`:
≥ 0.45 m away, 17°–45° to the right, 5°–35° below). Three ingredients on a ~0.85 m perimeter are ~28 cm apart: the
12 cm glows never touch. The orbit used to sit 60 cm straight ahead and rose 28 cm above a close fruit; to the
side it no longer needs to.

**Lazy follow (comfort).** Content locked to the head moves with every glance and tires the player; content
locked to the world is left behind when they walk. The orbit is in between:
- `eyes ← eyes + (head − eyes) · (1 − e^(−3 Δt))`: it follows the player smoothly (walking, sitting down).
- The yaw `ψ` stays put while the head looks anywhere from 30° to the left of the orbit's front to 30° past the
  orbit on the right (`bearing + turnDeadZone`, 60°): glancing at a fruit, at the flask, at an ingredient. Past
  that the player has turned: `ψ` eases towards the head's yaw (`1 − e^(−2 Δt)` per frame) until within 5°, and the
  orbit settles 30° to the right of where they now face. The dead zone is asymmetric because the orbit is to the
  right: with ±30° around the front, turning the head to look at the orbit (30° right) crossed it, the orbit
  moved further right, and the player chased it out of view (test `lookingAtTheOrbitDoesNotPushItAway`).

**The brew** (`Elixir.Timeline`, seconds from the snap). The flask sits at `O`; its neck runs from `neck_base` to
`neck_top` (the cork's two ends, axis `n`, tilted 20°).

| Time | What |
|---|---|
| 0–0.4 | The cork pops: `corkOut = easeOutBack(t / 0.4)` (~10 % overshoot), along `n` by 10 cm and 4 cm aside, tumbling |
| 0.4 + 0.77 k … + 0.75 | Ingredient `k` dives (`diveProgress`); dives never overlap |
| landing + 0…0.35 | The liquid rises by a third (`smoothstep`), sloshes (`0.2 · e^(−t/0.45) · sin(2π · 2.2 t)` rad) and bubbles burst |
| 2.7–3.2 | The cork goes back on |
| 3.2–3.6 | The liquid swirls into the elixir's blue; its glow goes from 0.35 to 1 |

The dive (`ElixirOrbit.divePosition`), with `P` the ingredient's place on the orbit (still turning) and
`A = neck_top + n · 0.08` above the open neck:

```
first 60 %:  B(t) = (1 − t)² P + 2 (1 − t) t C + t² A,   C = (P + A) / 2 + up · 0.06,   t = smootherstep
last 40 %:   from A down to neck_base − n · 0.03, accelerating (d²)
ingredient scale = 1 − smoothstep(0.55, 1, dive)
```

so each ingredient leaves the orbit with no jump and always ends inside the flask. The liquid's colour is the
ingredients' colours weighted by their share of the liquid, mixed into the blue as it swirls. Brewed, the flask
swells by 8 % and back (`sin`, 0.45 s) with a burst of 160 sparks. The ingredients still waiting whirl up to 2.5×
faster (`fusionSpin` 1.5).

**Pour.** Delivered, the flask stays 12 cm above the dragon's head: the cork pops (0–0.4 s), the flask tips by
2.2 rad around the axis across its neck (0.15–0.6 s), the stream pours (0.45–1.25 s) while the liquid drains
(0.45–1.2 s), and the flask fades (1.25–1.6 s).

**Flight.** A quadratic Bézier `B(t) = (1 − t)² P₀ + 2(1 − t)t P₁ + t² P₂`, with `P₀` where it was brewed, `P₂` the
dragon's head (read every frame: it moves) and `P₁` the midpoint lifted by `0.25 + 0.1 · |P₂ − P₀|`. `t` is the
flight time over `duration = max(|P₂ − P₀| / 1.1 m/s, 0.9 s)`, eased in and out: it always lands on time.

## The snap

ARKit hand tracking (`HandTracker`) gives each hand's wrist, the four knuckles, the thumb, index, ring and little
tips, and the middle finger's last joint (DIP) and tip (the snap reads the thumb, index and middle finger; the
cupped hand that turns the fruit reads the others too). Joints flagged "not tracked" are kept with ARKit's estimate: in a fast
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

**Tuning on the headset.** `SnapDetector` keeps what it reads: `closestContact` is the closest thumb–pad distance
in the current frame (it must go under 3 cm when the thumb presses) and `lastAttempt` the separation, curl and
speed the latest release measured, and whether it counted as a snap. Log them while tuning: a missed snap shows
which threshold it failed.

## Code layout

```
Sources/Macrowavers/
├── Model/Orchard/                       Pure logic (Foundation + simd), unit-tested
│   ├── AppleShape.swift                   Spiral-cut apple maths and the design apple's profile, shared with the shader
│   ├── WormSwarm.swift                    Worm behaviour: crawl, burrow, speed up, hide when closed
│   ├── Elixir.swift                       Ingredients in orbit, brew timeline, fusing → brewed → flying → delivered,
│   │                                      the flask's curves (cork, dives, liquid, colours, slosh, pour)
│   ├── ElixirOrbit.swift                  The ellipse to the player's right, lazy follow, the dive into the neck, ElixirFlight
│   ├── CupTurn.swift                      A cupped hand next to the close fruit turns it
│   ├── HandGestures.swift                 HandSample, ChopDetector (pineapple), SnapDetector (elixir)
│   └── OrchardViewModel.swift             @Observable: fruit focus, openings, worms, one ingredient per fruit, elixir
└── Views/Orchard/
    ├── FruitPanelView.swift               Panel under the focused fruit (RealityView attachment, not a window)
    ├── ElixirPanelView.swift              Label under the orbit: ingredients in orbit, how to brew
    ├── OrchardInteractions.swift          Gestures (tap fruit/worm/pineapple/ingredient, pull stem, peel, open
    │                                      pomegranate, drag seeds) and the link elixir → dragon
    └── RealityKit/
        ├── OrchardScene.swift               Components, OrchardSystem, FocusSystem, builder, per-fruit drawing
        ├── OrbScene.swift                   The ingredients: gem template (shine, glow, glints), colours, trail, where each one is every frame
        ├── ElixirScene.swift                ElixirRig (the flask: glass, liquid, cork, bubbles, stream, glow); orbit,
        │                                    snap, flight and pour in the system
        ├── HandTracker.swift                ARKit hand tracking → HandSample
        ├── AppleRig.swift                   Apple.usdz while closed; LowLevelMesh + Metal pipeline once open; stem, worms
        ├── AppleSpiral.metal                `deformApple` kernel (one thread per vertex)
        ├── PomegranateRig.swift             The design team's pomegranate: halves, seed burst
        ├── BananaRig.swift                  Banana.usdz, peel strips on hinges
        ├── OrangeRig.swift                  Procedural orange: two halves, then 8 wedges
        └── PineappleRig.swift               Pineapple.usdz, halves and crown opening
```

The fruit hangs from the island's root at the points `fruit_01` … `fruit_07` stored in `FloatingIsland.usdz`
(see the island section of the dragon docs). The code reads up to `fruit_12`; with more fruits than points they
share them.

### State

```
OrbState:     sealed ──open──▶ revealed ──1.8 s or tap──▶ orbiting(slot) ──fused──▶ spent
ElixirState:  gathering ──3rd ingredient──▶ ready ──snap──▶ fusing ──3.6 s──▶ brewed ──1.2 s, dragon on the island──▶ flying ──arrived──▶ delivered
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
3. **Openings.** It eases each fruit's drawing towards its opening (`ease(towards:)`; a fruit sent back closes
   gently). `AppleRig.apply(opening:)` re-runs the Metal kernel only when the value changes.
4. **Chop.** With hand tracking, it feeds `ChopDetector` with the hands near the focused pineapple.
   **Cup.** Once the close fruit has arrived, it feeds `CupTurn` with both hands and turns the fruit's holder by
   the cupped palm's turn since the last reading (scene space).
5. **Orbit.** `ElixirOrbit.follow` with the head's pose (faster spin while brewing); the label's anchor follows it.
6. **Snap.** With the orbit complete, it feeds `SnapDetector` with both hands; a snap calls `orchard.brewElixir()`.
7. **Orbs.** It moves each orb: sealed, rising above its fruit, flying into its slot, orbiting, diving into the flask.
8. **Elixir.** `ElixirRig.apply` draws the flask from `Elixir`'s curves (size, wobble, cork, liquid level, colour,
   glow and slosh, glass glow, bubbles, stream, light), splashes for each landing, flashes it, flies it. On arrival
   it calls `orchard.elixirDelivered()`; `OrchardInteractions` sees `.delivered` and calls `untangle.callDragon()`
   while the flask pours over the dragon's head.

## Design decisions (and why)

- **No new window.** Everything lives in the existing immersive space. The instructions are RealityView
  attachments under the fruit and under the orbit (hidden in SwiftUI while a fruit is close: the fruit's panel
  speaks then).
- **No container to carry.** The player never drags an ingredient anywhere. The orbit keeps what they found in
  sight, beside them, without a gesture: finding an ingredient is the reward, not carrying it.
- **Every gesture targets its own component.** The components are `FruitTapTargetComponent`, `AppleStemComponent`, `WormComponent`,
  `PomegranateBodyComponent`, `SeedComponent`, `BananaPeelComponent`, `OrangeBodyComponent`, `PineappleBodyComponent` and `OrbComponent`.
  `.targetedToAnyEntity()` would steal the pinch from the dragon's tap and grabs, and from spinning the island.
- **Two view models, connected by the view.** `OrchardViewModel` knows nothing about the dragon. The immersive
  view tells it whether the dragon is still on the island (`isDragonOnIsland`). The elixir only flies then, and the
  orbiting ingredients only take the pinch then (and never while a fruit is close): during the untangling they
  would steal the grabs on the knot. The view calls `callDragon()` when the elixir arrives.
- **The chop, the snap and the cupped hand use ARKit hand tracking, the rest are SwiftUI gestures.** SwiftUI has no
  "fast hand coming down", "snap" or "cupped hand". The detectors are pure structs fed with `HandSample`s, so they are unit-tested.
  - **Two poses, not a trajectory.** See [The snap](#the-snap): robust at the tracking's rate.
  - **A cup is never a pinch.** `CupTurn` ignores a hand whose thumb touches its index, so pulling the stem,
    peeling the banana or pulling a fruit apart never turns it. The turn is the palm's frame built from the
    joints (wrist → middle knuckle, little → index knuckle), followed with a little smoothing; it lives on the
    fruit's holder, so `FocusComponent` takes it back to the home pose for free. The stem is pulled along the
    apple's own up axis, so a turned apple still opens.
  - **Taps always work too:** a tap opens the pineapple, a tap on an orbiting ingredient brews the elixir. Without
    hand tracking (simulator, permission denied) they are the only way, and the label shows **Brew the Elixir**.
- **The orbit is body-locked with lazy follow, not head-locked.** See [The orbit](#the-orbit).
- **Every ingredient is the design team's gem, tinted per slot.** One template, cloned per fruit
  (`OrchardSceneBuilder.makeOrbTemplate()`): the crystal, spinning slowly around its long axis (one turn every 5 s,
  `gemSpinSpeed`, each orb at its own angle) so its flat facets catch the light one by one; a soft glow behind it
  that always faces the player; glints sparkling around it; and the trail while it flies and orbits. Its colour is
  warm white while it is still in its fruit, then its slot's (`Elixir.ingredientColors`: pomegranate red, saffron
  gold, pistachio green) once it joins the orbit:
  - **the gem look** comes from its flat facets, each lit differently as it spins. The design team's material has
    no texture; it is 20 % opaque and double-sided, but see-through the tinted gem looked washed out in the room
    and could sort wrongly against the flask's glass, so `gemMaterial` is opaque (roughness 0.15). RealityKit has
    no refraction, so the source's IOR (1.7) would have no effect anyway;
  - **shine:** full specular and a clear coat draw the room's highlights on the facets;
  - **glow:** the gem glows only a little in its colour (0.5: a strong emission would light every facet the same
    and flatten it into a coloured blob), and a 12 cm billboard quad behind it carries a radial
    gradient (white at the centre, fading out; made once in code, `makeGlowTexture`) tinted in the same colour.
    The glow writes no depth: its corners are invisible, but writing depth there they hid the flask's glass
    behind them (a see-through square crossing the flask). A sort group draws the glow first, then the gem;
  - **glints:** a particle emitter around the gem (7 per second, 4 mm, quick fade in and out, additive), in its
    colour;
  - **no hover effect:** visionOS highlights every mesh under the looked-at entity, so the glow's square quad lit
    up too, a box around the gem when it was looked at or pinched. The glow and the gestures are feedback enough.
  Without the asset a sphere stands in for the gem, with the same glow.
- **The pineapple opens with an eased animation, not physics.** The prototype launched the halves as dynamic bodies.
  There is no floor in front of the player, and the fruit must close again when it goes back to the tree.
- **Metal with a safety net.** If Metal or the apple kernel is missing, the apple is deformed on the CPU with the
  same maths (`AppleShape`).
- **The design team's apple, cut by the code.** A modelled apple cannot be cut along a helix as it is (its
  triangles would stretch across the cut, with no flesh in the gaps). So `AppleRig` shows `Apple.usdz` while the
  apple is closed (on the tree, and in front of the player until the stem moves) and, as soon as it opens, the
  spiral the shader deforms, built as a body of revolution on the asset's silhouette (`AppleShape.designProfile`,
  the skin's outer radius every 1/24 of its height, both poles kept small) and drawn in the asset's own airbrush
  materials (`Skin` on the wall, `Flesh` on the slices' faces, both sides). The asset's `Stem` and `Leaf` ride
  on the stem the player pulls. The two match in size (0.192 m tall, 0.241 m wide) and colours; what changes at
  the swap is what a body of revolution cannot hold: the slight lobes (±5 mm) and the dimples at the poles. The
  apple is sized by its width (`AppleShape.width`), as wide as the earlier procedural one. Without the asset the
  spiral is drawn closed too, in plain materials, with a stick for a stem.
- **Fruit on the island, focus on a stage.** On the tree the fruit is a child of the island. Focused, it moves to
  a stage ~50 cm from the eyes. The ingredients and the elixir live under the orchard's root, outside the faded
  parts, so they always stay fully visible.
- **A fruit leaves only when the player is done with it.** **Back to the Tree**, its ingredient joining the orbit,
  the snap, or the elixir flying. The return is eased and the fruit closes gently on the way.

## Tuning

| Where | Parameter | Effect |
|---|---|---|
| `OrchardViewModel.init` | `apples`, `pomegranates`, `bananas`, `oranges`, `pineapples` | how many fruits hang on the tree (the island has 7 hang points; more fruits share them) |
| `OrchardViewModel` | `peeledStrip`, `wedgesOpening`, `burstOpening` | when a banana counts as peeled, when the orange's wedges count as open, when the pomegranate bursts |
| `OrangeRig` | `halfShift`, `halfTurn`, `wedgeOut`, `wedgeTilt` | how far the halves move and turn, how far the wedges fall open |
| `OrchardViewModel` | `orbRiseDuration`, `orbOrbitDelay` | how long an ingredient rises, how long it floats before joining the orbit |
| `Elixir` | `ingredientCount`, `brewedHold`, `popDuration`, `appearDuration`, `pourDuration` | ingredients needed, how long the elixir waits before flying, the flask's pop, appearance and pour |
| `Elixir.Timeline` | `corkPop`, `firstDive`, `diveSpacing`, `diveDuration`, `rise`, `recorkStart`, `recorkEnd`, `swirlEnd` | the brew's rhythm (`fusingDuration` = `swirlEnd`) |
| `Elixir` | `ingredientColors`, `elixirColor`, `dampedWave` | ingredient and elixir colours, how the liquid sloshes and the flask wobbles |
| `ElixirOrbit` | `diveArc`, `diveClearance`, `diveLift`, `diveDepth` | the dive's shape |
| `ElixirRig` | `flaskScale`, `pourAngle`, `corkRise`, `corkSide`, `pourHeight` | the flask's size in the orbit, how it pours, how far the cork flies |
| `ElixirOrbit.Settings` | `bearing`, `distance`, `drop`, `lateralRadius`, `depthRadius`, `tilt`, `period` | where the orbit is (side, distance, height), its size, tilt and speed |
| `ElixirOrbit.Settings` | `followResponsiveness`, `turnDeadZone`, `turnSettled`, `turnResponsiveness` | how the orbit follows the player |
| `ElixirOrbit.Settings` | `fusionSpin`, `hintDrop` | how the ingredients whirl, where the label floats |
| `ElixirFlight` | `speed`, `minimumDuration` | how fast the elixir flies |
| `Elixir` | `joinDuration` | how long an ingredient takes from its fruit to the orbit (`OrbComponent` uses it) |
| `OrbComponent` | `heldScaleRange` | how small and how big two hands can make an ingredient |
| `ChopDetector.Settings` | `speed`, `cooldown` | how fast the hand must come down |
| `CupTurn.Settings` | `bend`, `keepMargin`, `pinchClearance`, `reach`, `keepReach`, `grace`, `smoothing` | how curled the fingers must be, how close to the fruit, how forgiving once holding, how smooth the turn is |
| `SnapDetector.Settings` | `contactDistance`, `pinchClearance`, `separation`, `curl`, `window`, `minimumSpeed`, `cooldown` | how strict the snap is |
| `WormSwarm.Settings` | `count`, `crawlSpeed`, `speedUpPerCatch`, `burrowInterval`, `burrowDuration` | worm difficulty |
| `OrchardSceneBuilder` | `…SizeOnTree`, `…SizeFocused` | fruit sizes on the tree and in front of the player (the apple's is its width) |
| `AppleShape` | `turns`, `gapPerTurn` | how many slices the apple opens into, how far apart |

## Assets

| Asset | Where it comes from |
|---|---|
| `Banana.usdz` | The design team's `banana_RCP.usdz` as it is (no pipeline: its layout is the one the code reads). The fruit lab's banana (Poly Haven `bananas`, CC0, cut into four peel strips) with Reality Composer Pro airbrush materials. Prims: `peelPivot_N/peel_N` (each strip a `skin` and a `pith`), `peelBase`, `flesh` (the orb rises from its centre); its golden `gem` is removed at load (the orchard has its own orb) |
| `Pineapple.usdz` | The design team's `pineaple_RCP.usdz` as it is. Prims: `pineapple_1`, `pineapple_2` (each a `rind` and a `flesh`), `leaves` (the crown that tips away); its golden `gem` is removed at load |
| `IngredientGem.usdz` | The design team's gem, `Assets/Blender/ingredient-gem/ingredient_gem.usdc`, prepared headless by `make_gem_asset.py` (below). Prim: `Gem` (26 flat faces, 6 cm tall, ~3.5 cm wide, origin at its centre, long axis up). The code colours it |
| `Pomegranate.usdz` | The design team's pomegranate, `Assets/Blender/pomegranate/pomegranate_rcp.usdz`, prepared headless by `make_pomegranate_asset.py` (below). Prims: `RightHalf` (skin, flesh, crown), `LeftHalf` (skin, flesh), `Seed_00` … `Seed_39` (origin at each seed's centre); real size, 16 cm wide, centred, cut along x = 0. Without it there is no pomegranate on the tree |
| `ElixirFlask.usdz` | The design team's flask, `Assets/Blender/elixir-flask/elixir_flask.usdc`, prepared headless by `make_flask_asset.py` (below). Prims: `Glass`, `Liquid` (origin at its bottom), `Cork` (origin at its centre), `neck_top`, `neck_base`. Without it a glowing blue orb stands in and the brew still plays |

`Apple.usdz` is the design team's `apple_RCP.usdz` as it is: `Skin`, `Flesh` (just inside the skin), `Stem`,
`Leaf`, real size (0.192 m tall, 0.241 m wide), airbrush materials. Closed, the apple is drawn from it; open, from the
spiral (see the design decisions). If the asset changes, measure its profile again and paste the output into
`AppleShape` (`designHeight`, `designProfile`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    -P Assets/Blender/apple/measure_apple_profile.py -- Sources/Macrowavers/Resources/Apple.usdz
```

The orange is generated in code (`OrangeRig`), no asset.

### The pomegranate's pipeline

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    -P Assets/Blender/pomegranate/make_pomegranate_asset.py -- \
    Assets/Blender/pomegranate/pomegranate_rcp.usdz <output folder>
```

The source (`roma_RCP.usdz`, prepared in Reality Composer Pro) is at real size, centred and already cut in
two along x = 0: `RightSkin`/`RightFlesh`, `LeftSkin`/`LeftFlesh` (the flesh is the cut face), a `Crown` and `Seeds`,
one mesh holding 40 seeds (and 40 stray vertices without faces, which the script drops: kept, they were 40 empty
seeds, invisible but grabbable). Its three materials (`Airbrush_Skin`, `Airbrush_Flesh`, `Airbrush_Seeds`) are Reality
Composer Pro shader graphs, which Blender cannot read. The script groups `RightHalf` (with the crown) and
`LeftHalf`, splits the seeds into `Seed_00` … `Seed_39` (one object each, origin at its centre, numbered from the
top down), exports the geometry (Y-up) and copies the materials from the source unchanged with USD (`pxr`),
binding each mesh to its own. 564 KB.

**Airbrush materials (fruit, island, dragon).** Unlit: a colour ramp driven by the facing angle (`EdgePower`), a
brightness from `EmissionBase` on the silhouette to `EmissionBase + EmissionBoost` on the faces seen head-on, and a
grain (`GrainAmount`, `GrainScale`, `GrainSpeed`) laid out in each mesh's own coordinates (object space) that drifts
over time when `GrainSpeed` is above 0: the shimmer. On the pomegranate the seeds have it too. Because the grain
follows the mesh's coordinates, a pipeline that resizes a mesh must resize `GrainScale` the other way (the
dragon's does); the pomegranate's only moves the seeds (no resize), so its materials stay as they are.

In the game `PomegranateRig` hangs each half from a pivot it moves and turns (the halves keep their own transforms,
which carry the file's Z-up → Y-up turn): the right half turns by +72° and the left one, its mirror image, by −72°,
so both cut faces turn to the player (checked with RealityKit on macOS). The seeds burst out of the open fruit and
fly back in to their packed places when it closes. It replaces the pomegranate the code used to build (two
generated half-spheres, a crown of boxes and 40 seed spheres).

### The gem's pipeline

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    -P Assets/Blender/ingredient-gem/make_gem_asset.py -- Assets/Blender/ingredient-gem/ingredient_gem.usdc <output folder>
```

The source (`GEMF.usdc` from the design team, Z-up) is a faceted crystal: a stretched icosphere with 26 flat faces,
~1.9 × 1.8 × 3.3 units, a pale 20 % opaque material, a camera, two area lights and a dome light pointing to an
.exr that is not shipped. The script keeps only the crystal (`Gem`), drops the object's framing rotation so its
long axis is vertical (it spins around it in the game), centres it, scales it to 6 cm tall, keeps its faces flat
and keeps the design team's `CRYSTAL` material, double-sided (the app tints it per ingredient in code, keeping its
transparency). It exports a Y-up USDZ.

### The flask's pipeline

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    -P Assets/Blender/elixir-flask/make_flask_asset.py -- Assets/Blender/elixir-flask/elixir_flask.usdc <output folder>
```

The source (Z-up, real size: ~21 cm wide, ~30 cm tall with the cork, tilted 20°) needed work before RealityKit:

- **Empty or invisible materials.** The glass (and a bubble) used Blender glass nodes, which do not export to USD:
  empty materials. The liquid was fully transparent (opacity 0). The cork's texture (`corkboard3b-albedo.png`) is
  not shipped. The script gives all three plain placeholder materials (cork: a plain cork colour); the app replaces
  the glass and the liquid ones in code (`ElixirRig`): clear glass (roughness 0.04, clear coat, ~22 % opaque) and a
  glowing, 85 % opaque liquid whose colour follows the brew.
- **Subdivision applied.** Glass and liquid are Catmull-Clark surfaces: USD only flags them and RealityKit draws the
  control cage, so the round flask would look faceted. One level is applied (6.2k and 2.8k faces).
- **Cork decimated** (5.9k → 1.4k faces) for a 6 cm cork.
- **Dropped:** the camera, the dome light (it points to a 4K .exr not shipped) and a stray bubble 69 cm away.
- **Origins** for the animations: the liquid's at its bottom (scaling it along its vertical axis raises its
  level), the cork's at its centre (it tumbles on itself); the flask's at the centre of its round body.
- **Neck markers** `neck_top` and `neck_base` (the cork's ends, along the tilted neck): the ingredients dive along
  that axis and the pour tips the flask across it.
- In the game the flask is scaled to 0.7 (`ElixirRig.flaskScale`, ~15 cm wide) so it fits in the orbit (28 cm deep)
  without touching the ingredients. Liquid and glass are drawn in a fixed order (`ModelSortGroupComponent`: liquid,
  then glass), so the transparent layers never swap.

## Tests

- **`Tests/MacrowaversTests/OrchardTests.swift`:**
  - apple maths and Swift/Metal layouts, and the worms
  - every fruit kind opening its own way and freeing its ingredient
  - leaving a fruit early
  - an ingredient rising, joining the orbit by itself or when tapped, also from a fruit sent back early
  - empty fruit, a complete orbit taking no more
  - the elixir brewing, flying, waiting when the dragon is gone, sending the close fruit back
- **`Tests/MacrowaversTests/CupTurnTests.swift`:** a cupped hand turning about any axis turns the fruit by as
  much; a flat hand, a fist, a pinch or a far hand do not; a wobbly or briefly lost cup keeps holding, a longer
  one lets go; no jump after a tracking gap or on a repeated reading; one hand at a time; the palm frame and the
  bends follow the joints.
- **`Tests/MacrowaversTests/HandGestureTests.swift`:** chop speed, zone and cooldown; the snap (fast, slow, late,
  fingers that do not curl, a pinch, repeated readings, cooldown, one hand at a time); the elixir's slots and
  timing; the flask appearing and wobbling when an ingredient arrives, the cork popping before the first dive and
  going back on after the last, the dives one at a time in order, the liquid rising by thirds and turning blue,
  the slosh dying down, no jumps between states, the pour and the fade; the orbit's place to the right and its
  shape (always seen whole, to the side, clear of the fruit), period, lazy follow and the dive into the neck; the
  flight's arc and arrival.

## Known limits

- **The snap, the chop and the cupped-hand turn need a headset.** The simulator has no hand tracking: use the taps.
- **Snap thresholds come from hand proportions, not from recordings:** tune `SnapDetector.Settings` on device
  with `SnapDetector.closestContact` and `lastAttempt`. The same goes for `CupTurn.Settings` (finger bends).
- **A turned pineapple is chopped as if upright.** `PineappleRig.chopTarget` ignores the fruit's turn; its zone
  is generous, so a chop still lands, but on a fruit turned on its side the zone is off.
- **Head, not body.** The orbit turns with the head's yaw past 30° (visionOS gives no torso pose): a long look to
  the side turns it too.
- **Hand height, not the apple.** Pulling the stem uses the hand's height: if the player moves their head a lot while
  pulling, the opening follows the hand.
- **The orbit ignores the room.** 0.55–0.72 m from the eyes, to the right, it can sink into a table the player sits
  at or into a wall on their right.
- **Right side only.** The orbit is always on the right (`bearing`); a left-handed setting would flip its sign.
- **The flight ignores the canopy.** The elixir's arc rises above the straight line but may still cross the tree.
- **Transparent glass in mixed reality.** Glass, liquid and the gems' glows are all transparent: the fixed
  order keeps liquid and glass right, but an ingredient diving through the neck may sort oddly for a frame.
- **Eyeballed values.** The flask's glow light (1800 at full), the glass and liquid opacity, bubble rates and the
  stream need checking on device.
- **The liquid level scales the liquid's shape** (from its bottom): low levels look like a flattened pool, not a
  true fill of the round body.
