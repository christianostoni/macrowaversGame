# Storytelling

The words around the game, from the low-fidelity wireframes (5 screens): a Start button in the room, the
narrator's two pages in a darkened room before the island appears, and the freed dragon's two pages above it.
Then the ride: the player flies on the dragon's back in a full immersive space and feeds it, wave after wave
(chapter II), until it is full and the story ends.

## The screens

| # | Step (`StoryStep`) | Where | Text | Moves on |
|---|---|---|---|---|
| 1 | `start` | Launch window (plain, no glass) | **Start**, and under it a small **App Icon** menu (see below) | Start opens the immersive space; until it has built its world (island, dragon, fruit: a few seconds) a spinner with "Loading…" turns in place of Start, then the window steps aside (`UntangleViewModel.isWorldLoaded`) |
| 2 | `searching` | In front of the player's eyes | **What are you searching for?** / I can see you are eager to find… | Tap the text |
| 3 | `chapter` | Same spot | **Chapter I** / Patience is bitter, but its fruit is sweet. | Tap the text: the island fades in |
| – | `adventure` | – | No story text: the island, its fruit, the dragon and its puzzle | The dragon is freed |
| 4 | `gratitude` | Above the dragon | **Thank you** / You freed me from the curse. / You don't need to be afraid. | Tap the text |
| 5 | `safety` | Above the dragon | **Thank you** / I will take you to safety. Are you ready? | **I'm Ready** button: the room goes dark, the ride's space takes over |
| – | `ride` | Full immersion | No text: out of the dark, on the dragon's back, steering with both hands on its horns | The dragon arrives (3.5 s) |
| 6 | `secondChapter` | In front of the eyes, above the dragon's head | **Chapter II** / Feed the dragon the right plants. / It doesn't like bananas! | Tap the text |
| – | `feast` | Above the dragon's head | No page: four waves of fruit among the clouds and a tally (hearts, fire, wave, fruit eaten); see [Chapter II: the feast](#chapter-ii-the-feast) | The last wave eaten ("The dragon is full!", 3 s) |
| 7 | `finale` | In front of the player's eyes | **Home at last** / The dragon is full, and the curse is gone. / Thank you for flying with it. | **The End** button |
| – | `ended` | – | No text: the ride's space closes and the launch window comes back | – |

Text changes from the wireframes: "ti safety" → "to safety", "Dont need to be afraid" → "You don't need to be
afraid.", the curse is not named yet ("the curse of XXX" → "the curse"; add the name in `StoryStep.page`),
and the narrator's cut-off line ends with an ellipsis. All the text lives in `StoryStep.page`.

## How it works

- **State machine** (`Model/Story/`, no SwiftUI or RealityKit): `StoryStep` holds the pages (title, lines,
  anchor, how to move on) and what each step does to the room; `StoryViewModel` moves through them:
  `begin()` (Start), `advance()` (tap or answer), `dragonFreed()`, `dragonRecaptured()` (`restartScene()` puts the
  dragon back on the island: its words come again next time), `rideArrived()`, `showFeast(_:)` (the feast's
  tally, `FeastProgress`, assigned only when it changes), `feastFinished()`, `reset()` (the space closed).
- **The immersive view connects it to the dragon**: `UntangleViewModel.isSolved` → `dragonFreed()`. The free
  dragon stays in the play area, celebrating, for as long as the player needs. The story reaching `ride`
  (`isFullyImmersed`) → `DragonImmersiveView.handOverToRide()`: the room stays dark with the island fading for
  1.2 s, the mixed space closes and `DragonRideView` (full immersion) opens; if it cannot, the game starts over
  from the launch window.
- **The ride** (`Model/Ride/`, `Views/Ride/`): `DragonRide` is the flight (the hands on the horns turn, climb and
  boost it; without hand tracking an autopilot flies), the sky moves around the player; `DragonFeast` is chapter
  II (see below). **The End** (`ended`) or the Digital Crown closes the space: the game resets and the launch
  window comes back.

## Chapter II: the feast

**Flying.** Both hands on the horns (the middle finger's knuckle is read; their first comfortable position becomes
"straight and level"): one hand lower than the other turns towards its side, both raised climb, both lowered dive,
**both pushed forward (20 cm) speed up** from 3 to 6.5 m/s. The view never rolls or sways: only the dragon leans.

**Waves** (`DragonFeast.Settings.waves`), 12 fruit in the sky at a time, new ones ahead as the old are passed:

| Wave | Goal | Bananas | Poisoned | Aim help (good fruit drift to the mouth within) | Hint |
|---|---|---|---|---|---|
| 1 | 3 | – | – | 3.2 m | Fly into the fruit; push both hands forward to fly faster |
| 2 | 4 | 30% | – | 2.6 m | Bananas: the dragon spits them out (a waste of time) |
| 3 | 5 | 15% | 30% | 2.1 m | Poisoned fruit: avoid them, or snap your fingers to breathe fire |
| 4 | 6 | 15% | 45% | 1.6 m | The last stretch: less help aiming |

A wave's goal eaten, the sky clears ("Wave cleared!", 3.5 s) and the next wave fills it. After the last, "The dragon
is full!" for 3 s, then the story's last page.

**Poison and hearts.** A poisoned fruit is one the dragon likes, darkened to a sickly purple with a faint green glow
in a clinging green haze (its own model, tinted: no new asset), turning slowly. Eaten, it costs one of the dragon's
**3 hearts**: it coughs smoke from its nostrils, its head droops and sways, and for 3 s it flies slower (its body
sways, never the view). The aim's help never pulls poison to the mouth. Out of hearts the dragon is **exhausted**:
the sky clears, it rests 4 s, then the wave starts over with full hearts.

**Fire.** A **snap of the fingers** (the gesture learnt for the elixir, either hand) makes the dragon breathe fire
for 0.9 s: a long jet from the middle of its mouth (`DragonRideSceneBuilder.makeFireBreath`) burns every fruit in a
cone ahead (14 m, ±0.2 rad, plus the fruit's size), with a puff of embers: poisoned fruit are cleared off the way,
a good one burnt is lost. Then it recharges for 2.5 s (the flame in the tally is grey meanwhile). The flame is also a button: pressed, it
breathes fire like a snap (`StoryViewModel.requestFire()`), the way to do it without hand tracking (simulator). The snap and the
steering never fight:
- the snap is read only during the feast, with `SnapDetector.Settings.whileSteering`: the wrist may move at most
  4 cm between the loaded and the released pose, so a quick move of the horns that opens a curled hand is not a
  snap;
- `SteeringHold`: while a hand holds the loaded pose, and for 0.35 s after its snap, the steering reads it where
  it was just before, so the dragon does not swerve; a hand that keeps looking loaded (a curled grip) steers again
  after 0.8 s.

**Smoke and fire where they belong.** The stone dragon's `nostrils` and `mouth` markers sit at x = 0, but its head
is not centred there (the snout spans x −2.5…+6.6 cm): smoke and fire came out of the snout's left edge.
`DragonSnout` now measures the snout on the head's meshes when the rig loads: two nostrils either side of its
centre line on the front of the nose, and the mouth halfway between the upper lip and the lower jaw's front edge,
moved with the jaw every frame, so the fire leaves from the middle of the opening, tilted down by half its angle.
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
├── Views/AppIconMenu.swift              Screen 1: the app icon picker under Start
├── Model/AppIconChoice.swift            The app icons (asset catalog names, titles)
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
| `DragonFeast.Settings` | `waves` (goal, shares, `pullRadius`), `hearts`, `biteRadius`, `count` | how long and how hard chapter II is |
| `DragonFeast.Settings` | `sicknessDuration`, `breakDuration`, `restDuration`, `finaleDelay` | how long poison lasts, the pauses |
| `DragonFeast.Settings` | `fireDuration`, `fireCooldown`, `fireRange`, `fireAngle` | how the fire breath plays |
| `DragonRide.Settings` | `fullTurnTilt`, `fullClimbRaise`, `fullBoostReach`, `cruiseSpeed`, `boostSpeed` | how the hands steer and how fast it flies |
| `DragonRide.Settings` | `weakSlowdown`, `weakSway` | how a sick or exhausted dragon flies |
| `SteeringHold` | `afterSnap`, `longestHold` | how long a snapping hand stops steering |
| `SnapDetector.Settings.whileSteering` | `maxWristTravel` | how still the wrist must stay for a snap on the ride |
| `DragonRideSceneBuilder` | `fireRate`, `poisonTint`, `poisonGlow` | the fire jet's density, the poisoned look |
| `DragonSnout` | `frontShare`, `nostrilSpread`, `nostrilDrop`, `inset` | where the smoke and the fire leave the head |

## Tests

`StoryTests.swift`:
- `StoryTests`: the five screens in order (and nothing moving the story before Start or during the game),
  `restartScene()` and closing the space going back, which pages dim the room and where they sit, the island
  hidden until after the chapter's title, no placeholder text left;
- `FreeDragonTests`: the free dragon staying in the play area while it speaks (it never flies off by itself),
  and `restartScene()` putting it back around the tree.

`DragonFeastTests.swift`:
- `DragonFeastTests`: the first wave only good fruit, harder waves, the goal clearing a wave (the sky empties, the
  next brings bananas), the last wave ending the feast (and the pause before the last page), poison costing a
  heart and slowing the dragon, out of hearts resting then starting the wave over, bananas costing nothing, only
  good fruit drifting to the mouth, fire burning only the fruit ahead and recharging, a weak dragon flying slower
  without turning the view, the tally on the story and the last page → `ended`;
- `RideSnapTests`: a snap with the whole hand jerking is not a snap on the ride (it still is for the elixir), the
  snapping hand not steering (and steering again after it), a hand loaded for long steering again;
- `DragonSnoutTests`: nostrils either side of an off-centre snout, the fire from the middle of the opening and
  tilted down, no snout without geometry.

`AppIconTests.swift`: the stone dragon is the primary icon, every choice is found again from the system's icon
name, and every alternate icon is declared in the app's Info.plist.

## The app icon

Three icons, picked in the **App Icon** menu under Start (`AppIconMenu`, `AppIconChoice`): **Stone Dragon** (the
design team's 3D stone dragon on a dark fill, the default: `AppIcon`), **Red Dragon** (`AppIconRedDragon`) and
**Black Dragon** (the first icon, `AppIconBlackDragon`), both coiled around an orange. The system changes the icon
with `UIApplication.setAlternateIconName` and tells the player; the menu shows only where
`supportsAlternateIcons` is true. The alternates are listed in the build setting
`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` (project, Debug and Release), so the asset catalog compiles them
into the app and its Info.plist (`CFBundleAlternateIcons`).

Each icon is an Icon Composer document in `Assets/Icon/` (`<name>.icon`), rendered into the three layers of
`<name>.solidimagestack` by `Assets/Icon/make_visionos_icon.swift` (Xcode compiles `.icon` documents for iOS,
macOS and watchOS only): the frontmost layer (the stone dragon's head, the coiled dragon) in front, the other
layers in the middle, and the document's fill behind (`automatic` light, `system-dark` dark). To add one: a new
`.icon`, its render into a new `.solidimagestack`, its name in the build setting and a case in `AppIconChoice`.

## Known limits

- The narrator's pages assume the player is looking roughly ahead when the space opens; they follow the gaze
  only after a 35° look away.
- Above the dragon, the words sit ~0.6 m from a seated player's eyes: font sizes need checking on device.
- The darkened room is the system's effect: how dark it looks depends on the real room's lighting.
