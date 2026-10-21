# Storytelling

The words around the game, from the low-fidelity wireframes (5 screens): a Start button in the room, the
narrator's two pages in a darkened room before the island appears, and the freed dragon's two pages above it
before its farewell.

## The screens

| # | Step (`StoryStep`) | Where | Text | Moves on |
|---|---|---|---|---|
| 1 | `start` | Launch window (plain, no glass) | **Start** | Start opens the immersive space |
| 2 | `searching` | In front of the player's eyes | **What are you searching for?** / I can see you are eager to find… | Tap the text |
| 3 | `chapter` | Same spot | **Chapter I** / Patience is bitter, but its fruit is sweet. | Tap the text: the island fades in |
| – | `adventure` | – | No story text: the island, its fruit, the dragon and its puzzle | The dragon is freed |
| 4 | `gratitude` | Above the dragon | **Thank you** / You freed me from the curse. / You don't need to be afraid. | Tap the text |
| 5 | `safety` | Above the dragon | **Thank you** / I will take you to safety. Are you ready? | **I'm Ready** button: the dragon takes off |
| – | `farewell` | – | No text: the farewell flight (see [Untangle the Dragon](../untangle-dragon/README.md)) | – |

Text changes from the wireframes: "ti safety" → "to safety", "Dont need to be afraid" → "You don't need to be
afraid.", the curse is not named yet ("the curse of XXX" → "the curse"; add the name in `StoryStep.page`),
and the narrator's cut-off line ends with an ellipsis. All the text lives in `StoryStep.page`.

## How it works

- **State machine** (`Model/Story/`, no SwiftUI or RealityKit): `StoryStep` holds the pages (title, lines,
  anchor, how to move on) and what each step does to the room; `StoryViewModel` moves through them:
  `begin()` (Start), `advance()` (tap or answer), `dragonFreed()`, `dragonRecaptured()` (Restart Scene puts the
  dragon back on the island: its words come again next time), `reset()` (the space closed).
- **The immersive view connects it to the dragon**: `UntangleViewModel.isSolved` → `dragonFreed()`; the story
  reaching `farewell` → `UntangleViewModel.beginFarewell()`. The app creates the dragon's view model with
  `farewellWaitsForPlayer: true`, so the free dragon stays in the play area (celebrating) until the answer.
- **Dimming**: every step with a page darkens the passthrough with `.preferredSurroundingsEffect(.dark)` (the
  system's own dimming of the room, applied to the immersive space). While the dragon speaks, focus mode also
  fades the island, tree and fruit to 25% (`SceneFocus.dragon`), so only the dragon and its words stand out.
- **Reveal**: the island, the dragon, the orchard and the side panels are built when the space opens but added
  to the scene only when the story reaches `adventure` (`HiddenWorld` in `DragonImmersiveView`); island and
  dragon start at opacity 0 and focus mode fades them in. Until then nothing can be tapped by mistake and the
  dragon does not fly.
- **The page** is one RealityView attachment (`StoryPanelView`), never disabled: between pages and during the
  game it shows nothing. `StoryPanelSystem` places it:
  - the narrator's pages 1.3 m in front of the eyes, 8 cm below them, world-locked; looking more than 35° away
    brings the page back in front of the player, and so does moving 30 cm (standing up, walking) (lazy follow,
    never stuck to the head);
  - the dragon's pages 20 cm above the highest point of its body, over its middle, following it as it moves;
  - `BillboardComponent` keeps the text facing the player.
- **Interaction**: a narrator's or thank-you page is one big plain button (look at it, it highlights; pinch to
  go on), with a "Tap to continue" hint and an accessibility hint. The last question has its own prominent
  **I'm Ready** button. Pages cross-fade (0.6 s).

```
Sources/Macrowavers/
├── Model/Story/StoryStep.swift          Steps, pages and their text, dimming / reveal / focus rules
├── Model/Story/StoryViewModel.swift     @Observable @MainActor state machine
├── Views/ContentView.swift              Screen 1: the Start button (launch window, plain style)
├── Views/Story/StoryPanelView.swift     The page (attachment): title, lines, tap / answer
└── Views/Story/StoryPanelPlacement.swift StoryPanelComponent/System: in front of the player or above the dragon
Tests/MacrowaversTests/StoryTests.swift
```

## Tuning

| Where | Parameter | Effect |
|---|---|---|
| `StoryStep.page` | text | every word of the story |
| `StoryPanelComponent` | `viewerDistance`, `viewerDrop`, `lookAwayAngle`, `driftTolerance` | where the narrator's pages float, when they follow the gaze or a player who stands up / walks |
| `StoryPanelComponent` | `dragonClearance`, `responsiveness` | how high above the dragon its words float, how fast the page glides |
| `DragonImmersiveView` | `.preferredSurroundingsEffect(.dark)` | how dark the room gets (`.semiDark`, `.ultraDark`, `.dim(intensity:)`) |

## Tests

`StoryTests.swift`:
- `StoryTests`: the five screens in order (and nothing moving the story before Start or during the game),
  Restart Scene and closing the space going back, which pages dim the room and where they sit, the island
  hidden until after the chapter's title, no placeholder text left;
- `FarewellCueTests`: the free dragon waiting for the answer (and taking off on its own without the story).

## Known limits

- The narrator's pages assume the player is looking roughly ahead when the space opens; they follow the gaze
  only after a 35° look away.
- Above the dragon, the words sit ~0.6 m from a seated player's eyes: font sizes need checking on device.
- The darkened room is the system's effect: how dark it looks depends on the real room's lighting.
