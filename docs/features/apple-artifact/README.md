# The Tree's Fruit and the Artifact

The fruit hanging on the floating island's tree. The player picks a fruit, it comes close, they open it and,
in an apple, catch the worms to free the **artifact**: tapped, it flies to the dragon and soothes it, so the
dragon comes to the player and the untangling puzzle starts
([Untangle the Dragon](../untangle-dragon/README.md)).

Based on Isadora's AppleSpiral prototype (spiral-cut apple deformed by a Metal shader, worms, pomegranate),
moved into the Macrowavers app and wired to the island and the dragon.

Branch: `feature/apple-artifact`. Status: playable with a placeholder artifact (golden orb) until the 3D asset
arrives.

## How to try it

1. Install Xcode's Metal Toolchain once: `xcodebuild -downloadComponent MetalToolchain` (needed to compile
   `AppleSpiral.metal`).
2. Run the app, **Open the Island**, then look at a fruit on the tree and pinch.
3. Apple: pull the stem up (pinch and drag upwards) to open it, then tap the worms. When the last worm is caught
   the artifact rises out of the apple: tap it.
4. Pomegranate: pull it apart with both hands (in the simulator hold Option); the seeds burst out and can be
   dragged around. It is a bonus fruit: no artifact inside.

## What the player sees

| Moment | Behaviour |
|---|---|
| On the tree | 3 apples and 1 pomegranate hang on the canopy, swaying gently, turning and bobbing with the island. Looking at a fruit highlights it |
| Tap a fruit | It flies from its branch to ~50 cm in front of the player, a little below the eyes, and grows to ~20 cm. A small panel under it says what to do. **Focus mode**: the island, the tree, the other fruit and the dragon fade to 25% while it is close, and come back when it returns to the tree (or as soon as the artifact flies to the dragon) |
| Open the apple | Dragging the stem up lifts the spiral slices apart (Metal compute shader on the mesh) |
| Worms | 3 worms crawl along the slices. Every few seconds one **burrows** for about a second (it cannot be caught then), they **speed up** after each catch, and they hide while the apple is almost closed |
| Last worm caught | The artifact, sealed in the core so far, **rises out of the apple**, glowing and pulsing. Tap it |
| Artifact used | It flies to the dragon's head; the fruit goes back to its branch; the dragon is soothed and comes to the player |
| Pomegranate | Halves open like a book; fully open, 40 seeds burst into a floating cloud you can drag. Hint: "No artifact in here: try an apple" |
| Wrong fruit (pomegranate, or an apple when the artifact is already out of another one) | Once opened, the panel says "No artifact in this one" and **Back to the Tree** becomes the prominent button. The fruit never leaves by itself: the player sends it back |
| Back to the Tree / Close It Again | The fruit flies back to its branch, closing gently on the way (the apple's slices settle, the pomegranate's seeds fly back inside) / closes it again with the worms inside |

Kept easy on purpose: there is a **single artifact** and it is always in the **first apple whose worms are
cleared**, so no choice is wrong and the number of apples does not matter. If the player leaves an apple before
clearing it, the artifact waits for the next apple. An apple that already freed the artifact keeps it until it
is used.

## Code layout

```
Sources/Macrowavers/
├── Model/Orchard/                       Pure logic (Foundation + simd), unit-tested
│   ├── AppleShape.swift                   Spiral-cut apple maths, shared with the shader (CPU fallback too)
│   ├── WormSwarm.swift                    Worm behaviour: crawl, burrow, speed up, hide when closed
│   └── OrchardViewModel.swift             @Observable: fruit focus, openings, worms, the artifact's state
└── Views/Orchard/
    ├── FruitPanelView.swift               Panel under the focused fruit (RealityView attachment, not a window)
    ├── OrchardInteractions.swift          Gestures (tap fruit/worm/artifact, pull stem, open pomegranate,
    │                                      drag seeds) and the link artifact → dragon
    └── RealityKit/
        ├── OrchardScene.swift               Components, OrchardSystem, FocusSystem, builder, placeholder artifact
        ├── AppleRig.swift                   LowLevelMesh + Metal compute pipeline, stem, worms
        ├── AppleSpiral.metal                `deformApple` kernel (one thread per vertex)
        └── PomegranateRig.swift             Halves, crown, seed burst
```

The fruit hangs from the island's root at the points `fruit_01` … `fruit_06` stored in `FloatingIsland.usdz`
(see the island section of the dragon docs).

### One frame

`OrchardSystem.update` (every frame):
1. `orchard.update(deltaTime:)` advances the worms of the focused apple and the artifact's reveal;
2. when the focused fruit changes, it moves the fruit between its branch and the **stage** in front of the
   player (`setParent(_:preservingWorldTransform:)` + `FocusComponent` easing), and switches tap targets;
3. applies the openings: `AppleRig.apply(opening:)` re-runs the Metal kernel only when the value changes;
4. moves the artifact: sealed in the core, rising out, or flying to the dragon's head. On arrival it calls
   `orchard.artifactDelivered()`; `OrchardInteractions` sees `.used` and calls `untangle.callDragon()`.

## Design decisions (and why)

- **No new window.** The prototype was a separate volumetric window; here everything lives in the existing
  immersive space and the instructions are a RealityView attachment under the fruit. The window architecture
  stays: one launch window, then panels inside the immersive space.
- **Every gesture targets its own component** (`FruitTapTargetComponent`, `AppleStemComponent`, `WormComponent`,
  `PomegranateBodyComponent`, `SeedComponent`, `ArtifactComponent`). The prototype used `.targetedToAnyEntity()`,
  which would have stolen the pinch from the dragon's tap and grabs and from spinning the island.
- **Two view models, connected by the view.** `OrchardViewModel` knows nothing about the dragon; the immersive
  view's `OrchardInteractions` checks that the dragon is still on the island (`DragonPhase.isOnIsland`) and calls
  `callDragon()` when the artifact arrives. Each stays small and testable on its own.
- **Metal with a safety net.** `AppleSpiralPipeline` is created once and shared by every apple; if Metal or the
  kernel is missing the apple is deformed on the CPU with the same maths (`AppleShape`) instead of crashing
  (the prototype force-unwrapped). Swift structs and shader structs are checked by a layout test.
- **Fruit on the island, focus on a stage.** On the tree the fruit is a child of the island (it turns and bobs
  with it); focused, it is moved to a stage placed between the player and the fruit, ~50 cm from the eyes, so the
  zoom-in always comes towards the player.
- **Worms: moving targets, but forgiving.** Slow crawl (≈ 4 cm/s on the focused apple), short burrows, large tap
  areas (5 cm), only 3 worms. The difficulty comes from timing, not precision.
- **While a fruit is close, nothing behind it takes the pinch.** The island's rock and the dragon's colliders are
  switched off (`OrchardComponent.background`), so a pinch that just misses the stem, a worm or a pomegranate half
  does not spin the island or make the dragon angry. Targets are generous: stem 6 cm, worms 3.5 cm (apple
  units), the pomegranate's collider covers both halves even fully open.
- **A wrong fruit is dismissed by the player, never automatically.** Only two things send a fruit back to the
  tree: **Back to the Tree**, and delivering the artifact (the right apple). The return is eased
  (`FocusComponent`) and the fruit closes gently on the way (`AppleRig.ease`, `PomegranateRig.ease`, seeds flying
  back in) instead of snapping shut or vanishing. `OrchardViewModel.isFocusedFruitEmpty` tells the panel when the
  fruit cannot hold the artifact.
- **Focus mode while a fruit is close** (`SceneFocus.fruit`). The island (and the fruit still hanging from it)
  and the dragon fade back (see the dragon docs); the focused fruit has moved to the stage, outside the island,
  so it is the only thing at full strength in front of the player. When the artifact flies, the scene comes
  back so the player can follow it to the dragon.
- **Pomegranate kept as a bonus.** Same interactions as the prototype; it shares `FloatingComponent` with the
  island instead of its own float system.

## Tuning

| Where | Parameter | Effect |
|---|---|---|
| `OrchardViewModel.init` | `apples`, `pomegranates` | how many fruits hang on the tree (up to 6 hang points) |
| `WormSwarm.Settings` | `count`, `crawlSpeed`, `speedUpPerCatch`, `burrowInterval`, `burrowDuration` | worm difficulty |
| `AppleShape` | `turns`, `gapPerTurn`, `height` | look of the spiral cut and how far the stem travels |
| `OrchardSceneBuilder` | `appleSizeOnTree`, `appleSizeFocused`, … | fruit sizes on the tree and in front of the player |
| `OrchardComponent.artifactSpeed` | m/s | how fast the artifact flies to the dragon |

## Assets

- **Artifact** (missing): put `Artifact.usdz` in `Sources/Macrowavers/Resources/` and it replaces the golden orb
  automatically. Origin at its centre, about 5 cm wide, PBR materials (an emissive part reads well as "magic").
- Apples and pomegranate are generated in code (the apple must stay procedural: the shader cuts it).

## Tests

`Tests/MacrowaversTests/OrchardTests.swift`: apple maths and profile, Swift/Metal struct layouts, worms hiding,
crawling, burrowing and speeding up, the artifact in the first cleared apple, leaving an apple early, the
artifact's flight and reset, a wrong fruit staying until sent back, the pomegranate burst.

## Known limits

- Pulling the stem uses the hand's height: if the player moves their head a lot while pulling, the opening
  follows the hand, not the apple.
- The two-handed pomegranate gesture needs a device (Option-drag in the simulator).
- The artifact flies in a straight line to the dragon's head; it may pass through the canopy.
