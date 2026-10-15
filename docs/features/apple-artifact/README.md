# The Tree's Fruit, the Kalash and the Blue Spell

The fruit hanging on the floating island's tree. The player picks a fruit and it comes close. They open it
and a **glowing orb** rises out of it. They drag the orb into their **kalash**, the spell container that
waits by their right hip. With three orbs inside, they look at the kalash, pinch and **twist their fingers**:
the orbs fuse into a **blue spell**. The spell flies to the dragon and soothes it. The dragon comes to the
player and the untangling puzzle starts ([Untangle the Dragon](../untangle-dragon/README.md)).

Origins:
- The apple and pomegranate come from Isadora's AppleSpiral prototype: a spiral-cut apple deformed by a Metal shader, with worms.
- The banana and pineapple come from the fruit lab prototype (`fruit_test_2`).

Status: playable with placeholder orbs (golden), a procedural kalash and a procedural blue spell, until the 3D
assets arrive.

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

4. Pinch the orb that rises out and drag it to the kalash by your right hip. Let go over its mouth.
5. With 3 orbs in, **tap the kalash**. On a headset you can instead look at it, pinch thumb and index, and twist
   your wrist (45° or more within 1.5 s) like turning a key. The kalash's label shows a bar filling up while you
   twist.

## What the player sees

| Moment | Behaviour |
|---|---|
| On the tree | 3 apples, 1 pomegranate, 1 banana and 1 pineapple hang on the canopy, swaying gently, turning and bobbing with the island. Looking at a fruit highlights it |
| Tap a fruit | It flies from its branch to ~50 cm in front of the player, a little below the eyes, and grows. A small panel under it says what to do. **Focus mode**: the island, the tree, the other fruit and the dragon fade to 25% while it is close |
| Open it | Apple: the spiral slices lift (Metal compute shader) and 3 worms guard the orb. Pomegranate: the halves open like a book and 40 seeds burst out. Banana: each strip turns on its hinge and hangs down. Pineapple: the halves fall open towards the player and the crown tips away |
| Orb freed | The orb rises out of the fruit, glowing and pulsing. Pinch it and carry it |
| Orb near the kalash | The kalash's rim lights up. Let go: the orb drops into a slot above its mouth and the fruit goes back to its branch. Let go elsewhere: the orb glides back above its fruit |
| Kalash | Placed once by the right hip, at pocket height, when the world appears. Drag it anywhere: it stays where it is dropped. A small label beside it counts the orbs |
| Kalash full | The rim pulses. Tap it, or look at it, pinch and twist (a bar in its label fills while you twist): the 3 orbs spiral up and fuse into the blue spell, which floats above the kalash for a moment |
| Blue spell | It flies to the dragon's head. The scene comes back from focus mode, the dragon is soothed and comes to the player. If the dragon has already left the island (debug **Call It Now**), the spell stays above the kalash |
| Empty fruit | A fruit whose orb is already in the kalash: once opened, the panel says "No orb left in this one" and **Back to the Tree** becomes the prominent button. The fruit never leaves by itself |
| Back to the Tree / Close It Again | The fruit flies back to its branch, closing gently on the way / closes it again |

Every fruit holds one orb, so no choice is wrong: any 3 of the 6 fruits make the spell.

## Code layout

```
Sources/Macrowavers/
├── Model/Orchard/                       Pure logic (Foundation + simd), unit-tested
│   ├── AppleShape.swift                   Spiral-cut apple maths, shared with the shader (CPU fallback too)
│   ├── WormSwarm.swift                    Worm behaviour: crawl, burrow, speed up, hide when closed
│   ├── Kalash.swift                       The spell: orbs stored, cast, forming → formed → flying → delivered
│   ├── HandGestures.swift                 HandSample, ChopDetector (pineapple), TwistDetector (kalash)
│   └── OrchardViewModel.swift             @Observable: fruit focus, openings, worms, one orb per fruit, kalash
└── Views/Orchard/
    ├── FruitPanelView.swift               Panel under the focused fruit (RealityView attachment, not a window)
    ├── KalashPanelView.swift              Label beside the kalash: orbs inside, how to cast
    ├── OrchardInteractions.swift          Gestures (tap fruit/worm/pineapple, pull stem, peel, open
    │                                      pomegranate, drag seeds/orbs/kalash) and the link spell → dragon
    └── RealityKit/
        ├── OrchardScene.swift               Components, OrchardSystem, FocusSystem, builder, per-fruit drawing
        ├── OrbScene.swift                   The orbs: placeholder template, where each orb is every frame
        ├── KalashScene.swift                The kalash (procedural or Kalash.usdz), its glow, the blue spell
        ├── HandTracker.swift                ARKit hand tracking → HandSample
        ├── AppleRig.swift                   LowLevelMesh + Metal compute pipeline, stem, worms
        ├── AppleSpiral.metal                `deformApple` kernel (one thread per vertex)
        ├── PomegranateRig.swift             Halves, crown, seed burst
        ├── BananaRig.swift                  Banana.usdz, peel strips on hinges
        └── PineappleRig.swift               Pineapple.usdz, halves and crown opening
```

The fruit hangs from the island's root at the points `fruit_01` … `fruit_12` stored in `FloatingIsland.usdz`
(see the island section of the dragon docs).

### One frame

`OrchardSystem.update` (every frame) does these steps in order:
1. **Model.** `orchard.update(deltaTime:)` advances the worms of the focused apple, the orbs' rise and the kalash's spell.
2. **Focus.** When the focused fruit changes, it moves the fruit between its branch and the **stage** in front of the
   player (`setParent(_:preservingWorldTransform:)` + `FocusComponent` easing), and switches tap targets.
3. **Openings.** It applies each fruit's opening. `AppleRig.apply(opening:)` re-runs the Metal kernel only when the value changes.
4. **Chop.** With hand tracking, it feeds `ChopDetector` with the hands near the focused pineapple.
5. **Orbs.** It moves each orb: sealed, rising above its fruit, held (the drag moves it), in a kalash slot, or spiralling into the spell.
6. **Kalash.** It places the kalash once and lights its rim. It feeds `TwistDetector` (hands plus "looking at the kalash") and flies the spell.
   On arrival it calls `orchard.spellDelivered()`. `OrchardInteractions` sees `.delivered` and calls `untangle.callDragon()`.

## Design decisions (and why)

- **No new window.** Everything lives in the existing immersive space. The instructions are RealityView
  attachments under the fruit and beside the kalash.
- **Every gesture targets its own component.** The components are `FruitTapTargetComponent`, `AppleStemComponent`, `WormComponent`,
  `PomegranateBodyComponent`, `SeedComponent`, `BananaPeelComponent`, `PineappleBodyComponent`, `OrbComponent`
  and `KalashComponent`. `.targetedToAnyEntity()` would steal the pinch from the dragon's tap and grabs, and from spinning the island.
- **Two view models, connected by the view.** `OrchardViewModel` knows nothing about the dragon. The immersive
  view tells it whether the dragon is still on the island (`isDragonOnIsland`). The spell only flies then, and the
  kalash only takes the pinch then: during the untangling its collider would steal the grabs on the knot. The view calls
  `callDragon()` when the spell arrives.
- **The chop and the twist use ARKit hand tracking, the rest are SwiftUI gestures.** SwiftUI has no "fast hand
  coming down" or "pinch and roll the wrist". The detectors are pure structs fed with `HandSample`s, so they are unit-tested.
  - **The twist measures roll, not bend.** The palm's normal is projected onto the plane perpendicular to the wrist→knuckle axis.
  - **"Looking at" uses the head's direction.** It must point within 45° of the kalash; visionOS does not expose the eyes.
  - **Taps always work too:** a tap opens the pineapple, a tap on the full kalash casts the spell. Without hand
    tracking (simulator, permission denied) they are the only way.
- **The pineapple opens with an eased animation, not physics.** The prototype launched the halves as dynamic bodies.
  There is no floor in front of the player, and the fruit must close again when it goes back to the tree.
- **Metal with a safety net.** If Metal or the apple kernel is missing, the apple is deformed on the CPU with the
  same maths (`AppleShape`).
- **Fruit on the island, focus on a stage.** On the tree the fruit is a child of the island. Focused, it moves to
  a stage ~50 cm from the eyes. The orbs, the kalash and the spell live under the orchard's root, outside the
  faded parts, so they always stay fully visible.
- **A fruit leaves only when the player is done with it.** **Back to the Tree**, an orb dropped into the kalash,
  or the spell flying. The return is eased and the fruit closes gently on the way.

## Tuning

| Where | Parameter | Effect |
|---|---|---|
| `OrchardViewModel.init` | `apples`, `pomegranates`, `bananas`, `pineapples` | how many fruits hang on the tree (up to 12 hang points) |
| `OrchardViewModel` | `peeledStrip`, `burstOpening` | when a banana counts as peeled, when the pomegranate bursts |
| `Kalash` | `capacity`, `formingDuration`, `formedHold` | orbs needed, how long the spell takes to form and waits before flying |
| `ChopDetector.Settings` | `speed`, `cooldown` | how fast the hand must come down |
| `TwistDetector.Settings` | `pinchDistance`, `minimumRoll`, `window` | how much and how fast the wrist must roll |
| `TwistDetector.isLooking` | `maximumAngle` | how precisely the player must look at the kalash |
| `KalashRig.place` | offsets | where the kalash starts (right of and in front of the hip, base 62 cm below the eyes) |
| `OrchardComponent` | `kalashDropRadius`, `spellSpeed` | how close to the mouth an orb drops in, how fast the spell flies |
| `WormSwarm.Settings` | `count`, `crawlSpeed`, `speedUpPerCatch`, `burrowInterval`, `burrowDuration` | worm difficulty |
| `OrchardSceneBuilder` | `…SizeOnTree`, `…SizeFocused` | fruit sizes on the tree and in front of the player |

## Assets

| Asset | Where it comes from |
|---|---|
| `Banana.usdz` | Poly Haven `bananas` (CC0), cut into four peel strips by the fruit lab's `build_fruits.py`. Prims: `peelPivot_N/peel_N`, `peelBase`, `core`; the prototype's `stand` and `item` are removed at load |
| `Pineapple.usdz` | Procedural, from the same script. Prims: `pineapple_1`, `pineapple_2`, `crown`; `item` removed at load |
| Orb (missing) | Put `Artifact.usdz` in `Sources/Macrowavers/Resources/` and it replaces the golden orb automatically. Origin at its centre, about 5 cm wide |
| Kalash (missing) | Put `Kalash.usdz` in `Resources/` and it replaces the procedural brass pot, scaled to 15 cm, base at the origin, open mouth at the top. None of Poly Haven's brass vessels has a kalash's shape, so the pot is drawn in code for now |

Apples and pomegranate are generated in code (the apple must stay procedural: the shader cuts it).

## Tests

- **`Tests/MacrowaversTests/OrchardTests.swift`:**
  - apple maths and Swift/Metal layouts, and the worms
  - every fruit kind opening its own way and freeing its orb
  - leaving a fruit early
  - orbs dropped into the kalash or let go elsewhere
  - empty fruit
  - a full kalash
  - the spell forming, flying, and waiting when the dragon is gone
- **`Tests/MacrowaversTests/HandGestureTests.swift`:** chop speed, zone and cooldown; twist pinch, roll, speed and gaze; the kalash's slots and spell timing.

## Known limits

- **The twist and the chop need a headset.** The simulator has no hand tracking: use the taps.
- **Head direction, not eyes.** "Looking at the kalash" uses the head's direction, so the player has to tilt their head
  down towards it, not just their eyes.
- **Hand height, not the apple.** Pulling the stem uses the hand's height: if the player moves their head a lot while
  pulling, the opening follows the hand.
- **Straight-line flight.** The spell flies in a straight line to the dragon's head; it may pass through the canopy.
