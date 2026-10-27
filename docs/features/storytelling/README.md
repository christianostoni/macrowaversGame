# Storytelling

The words around the game, from the low-fidelity wireframes (5 screens): a Start button in the room, the
narrator's two pages in a darkened room before the island appears, and the freed dragon's two pages above it.
Then the ride: the player flies on the dragon's back through a night sky in a full immersive space and feeds it,
wave after wave (chapter II); every fruit lights a petal of a star medallion in the sky, and once the dragon is full
it flies into the medallion's heart, where the story ends.

## The screens

| # | Step (`StoryStep`) | Where | Text | Moves on |
|---|---|---|---|---|
| 1 | `start` | Launch window (plain, no glass) | **Start**, and under it a small **App Icon** menu (see below) | Start opens the immersive space; until it has built its world (island, dragon, fruit: a few seconds) a spinner with "Loading…" turns in place of Start, then the window steps aside (`UntangleViewModel.isWorldLoaded`) |
| 2 | `searching` | In front of the player's eyes | **What are you searching for?** / I can see you are eager to find… | Tap the text |
| 3 | `chapter` | Same spot | **Chapter I** / Patience is bitter, but its fruit is sweet. | Tap the text: the island fades in |
| – | `adventure` | – | No story text: the island, its fruit, the dragon and its puzzle | The dragon is freed |
| 4 | `gratitude` | Above the dragon | **Thank you** / You freed me from the curse. / You don't need to be afraid. | Tap the text |
| 5 | `safety` | Above the dragon | **Thank you** / I will take you to safety. Are you ready? | **I'm Ready** button: the room goes dark, the ride's space takes over |
| – | `ride` | Full immersion | No page: out of the dark, on the dragon's back; while the hands don't hold the horns, a hint over its head shows how (pinch with both hands) | The dragon arrives (3.5 s) |
| 6 | `secondChapter` | In front of the eyes, above the dragon's head | **Chapter II** / Feed the dragon the right plants. / It doesn't like bananas! | Tap the text |
| – | `feast` | Above the dragon's head | No page: four waves of fruit in the sky and a tally (hearts, fire, wave, fruit eaten); see [Chapter II: the feast](#chapter-ii-the-feast) | The last wave eaten ("The dragon is full!") and the medallion complete, swelled for 2.5 s |
| – | `finale` | Full immersion | No page: the dragon roars, turns to the medallion on its own and flies into its heart through a rush of light (`ShamsehFinale.swift`); the light fills the view | 6 s at most turning, 7 s of flight, 1.2 s of light |
| 7 | `epilogue` | In front of the player's eyes, in the light | **Home at last** / The dragon is full, and the curse is gone. / Thank you for flying with it. | **The End** button |
| – | `ended` | – | No text: the ride's space closes and the launch window comes back | – |

Text changes from the wireframes: "ti safety" → "to safety", "Dont need to be afraid" → "You don't need to be
afraid.", the curse is not named yet ("the curse of XXX" → "the curse"; add the name in `StoryStep.page`),
and the narrator's cut-off line ends with an ellipsis. All the text lives in `StoryStep.page`.

## How it works

- **State machine** (`Model/Story/`, no SwiftUI or RealityKit): `StoryStep` holds the pages (title, lines,
  anchor, how to move on) and what each step does to the room; `StoryViewModel` moves through them:
  `begin()` (Start), `advance()` (tap or answer), `dragonFreed()`, `dragonRecaptured()` (`restartScene()` puts the
  dragon back on the island: its words come again next time), `rideArrived()`, `showFeast(_:)` (the feast's
  tally, `FeastProgress`, assigned only when it changes), `feastCelebrated()` (the feast finished and the medallion
  celebrated: `finale`), `rideEnded()` (the dragon in the medallion's heart: `epilogue`), `reset()` (the space
  closed).
- **The immersive view connects it to the dragon**: `UntangleViewModel.isSolved` → `dragonFreed()`. The free
  dragon stays in the play area, celebrating, for as long as the player needs. The story reaching `ride`
  (`isFullyImmersed`) → `DragonImmersiveView.handOverToRide()`: the room stays dark with the island fading for
  1.2 s, the mixed space closes and `DragonRideView` (full immersion) opens; if it cannot, the game starts over
  from the launch window.
- **The ride** (`Model/Ride/`, `Views/Ride/`): `DragonRide` is the flight (the hands on the horns turn, climb and
  boost it; without hand tracking an autopilot flies), the sky moves around the player; `DragonFeast` is chapter
  II (see below). **The End** (`ended`) or the Digital Crown closes the space: the game resets and the launch
  window comes back.
- **Dimming**: every step with a page darkens the passthrough with `.preferredSurroundingsEffect(.dark)` (the
  system's own dimming of the room, applied to the immersive space). While the dragon speaks, focus mode also
  fades the island, tree and fruit to 25% (`SceneFocus.dragon`), so only the dragon and its words stand out.
- **Reveal**: the island, the dragon, the orchard and the island panel are built when the space opens but added
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

## Chapter II: the feast

**Flying.** A **pinch with both hands** holds the horns (`Pinch`: thumb and index tips closer than 2 cm, let go
past 4.5 cm, so tracking wobbles never drop it); where the pinches are taken is "straight and level", wherever the
player holds them. From there the arms lead: moved to a side (20 cm) turn that way, raised climb, lowered dive,
**pushed forward (20 cm) speed up** from 3 to 6.5 m/s. Letting go of either hand releases the horns: the dragon
glides straight and levels out, and the next hold starts level again. While the hands don't hold, a hint over the
dragon's head shows how (`HornsHintView`; after a hold it waits 1.5 s, so a hand let go to snap the fire does not
bring it back). The view never rolls or sways: only the dragon leans.

**The night sky** (`RideScenery`, `RideAirbrush`, `RideShapes`): an almost black airbrush
dome with Persian clouds, sparkles and a crescent moon (`RideSky.jpg`, `Assets/Blender/ride-sky/make_ride_sky.py`),
floating Persian lanterns and mountain peaks far below (made in code, shaded with the cloud asset's airbrush
material, recoloured from `RidePalette`), a twinkling glitter wound around the dragon, which glows. The
canopy-shaped 3D clouds are off for now (`DragonRideSystem.cloudCount = 0`).

**Waves** (`DragonFeast.Settings.waves`), 12 fruit in the sky at a time, new ones ahead as the old are passed:

| Wave | Goal | Bananas | Poisoned | Aim help (good fruit drift to the mouth within) | Hint |
|---|---|---|---|---|---|
| 1 | 3 | – | – | 3.2 m | Fly into the fruit; push the horns forward to fly faster |
| 2 | 4 | 30% | – | 2.6 m | Bananas: the dragon spits them out (a waste of time) |
| 3 | 4 | 15% | 30% | 2.1 m | Poisoned fruit: avoid them, or let go of a horn and snap your fingers to breathe fire |
| 4 | 5 | 15% | 45% | 1.6 m | The last stretch: less help aiming |

A wave's goal eaten, the sky clears ("Wave cleared!", 3.5 s) and the next wave fills it. After the last, "The dragon
is full!" while the medallion celebrates, then the finale.

**The shamseh** (`Shamseh`, drawn by `ShamsehSky`): a Persian star medallion hung far away over the way ahead when
the feast begins, its strapwork faint. Every fruit the dragon eats glazes one of its petals in that fruit's colour;
there is a petal for every fruit of every wave (`DragonFeast.Settings.totalGoal`, 16, the goals add up to a classic
16-point shamseh). Out of hearts, the wave starts over and its petals lose their colour (`Shamseh.uncolour(last:)`).
Complete, its star lights up in the dragon's blue, the lines and kites turn gold and it swells for 2.5 s; then the
dragon flies into its heart (`DragonRide.destination`) and the story's last page shows in the light there (the
light widens to 2.4 m around the player, past the page).

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
- holding the horns is a pinch (thumb on index), the snap starts from the thumb on the middle finger: to snap, a
  hand lets go of its horn (the dragon glides level meanwhile) and takes hold again after (level again, no swerve);
- the snap is read only during the feast, with `SnapDetector.Settings.whileSteering`: the wrist may move at most
  4 cm between the loaded and the released pose, so a quick move of the horns that opens a curled hand is not a
  snap;
- `SteeringHold` (on the pinched hands): while a hand holds the loaded pose, and for 0.35 s after its snap, the steering reads it where
  it was just before, so the dragon does not swerve; a hand that keeps looking loaded (a curled grip) steers again
  after 0.8 s.

**Smoke and fire where they belong.** The stone dragon's `nostrils` and `mouth` markers sit at x = 0, but its head
is not centred there (the snout spans x −2.5…+6.6 cm): smoke and fire came out of the snout's left edge.
`DragonSnout` now measures the snout on the head's meshes when the rig loads: two nostrils either side of its
centre line on the front of the nose, and the mouth halfway between the upper lip and the lower jaw's front edge,
moved with the jaw every frame, so the fire leaves from the middle of the opening, tilted down by half its angle.
```
Sources/Macrowavers/
├── Model/Story/StoryStep.swift          Steps, pages and their text, dimming / reveal / focus rules
├── Model/Story/StoryViewModel.swift     @Observable @MainActor state machine
├── Views/ContentView.swift              Screen 1: the Start button (launch window, plain style)
├── Views/AppIconMenu.swift              Screen 1: the app icon picker under Start
├── Model/AppIconChoice.swift            The app icons (asset catalog names, titles)
├── Model/Story/MusicTrack.swift         Which track plays at each step (intro, puzzle, farewell)
├── Views/GameMusic.swift                Plays it: channel audio, crossfades, ducks while the dragon roars
├── Views/Story/StoryPanelView.swift     The page (attachment): title, lines, tap / answer
└── Views/Story/StoryPanelPlacement.swift StoryPanelComponent/System: in front of the player or above the dragon
Tests/MacrowaversTests/StoryTests.swift
```

## The music

`MusicTrack.playing(story:dragon:)` picks the track: silence on Start; `MusicIntro` (a setar, looped) under the
narrator's pages and the fruit; `MusicPuzzle` (looped) from the soothed dragon's flight to the player until it is
untangled; `MusicFarewell` (once) from the moment it is free through its words and its flight. `GameMusic` plays it
as non-spatial channel audio (−14 dB), crossfades over 2 s when the track changes, and ducks to −26 dB while the
dragon rears up. The tracks are streamed from their files (`GameAudio.load(streams:)`); the sound effects are
preloaded (`DragonEffects`, `OrchardSounds`).

## Tuning

| Where | Parameter | Effect |
|---|---|---|
| `StoryStep.page` | text | every word of the story |
| `StoryPanelComponent` | `viewerDistance`, `viewerDrop`, `lookAwayAngle`, `driftTolerance` | where the narrator's pages float, when they follow the gaze or a player who stands up / walks |
| `StoryPanelComponent` | `dragonClearance`, `responsiveness` | how high above the dragon its words float, how fast the page glides |
| `DragonImmersiveView` | `.preferredSurroundingsEffect(.dark)` | how dark the room gets (`.semiDark`, `.ultraDark`, `.dim(intensity:)`) |
| `DragonFeast.Settings` | `waves` (goal, shares, `pullRadius`), `hearts`, `biteRadius`, `count` | how long and how hard chapter II is |
| `DragonFeast.Settings` | `sicknessDuration`, `breakDuration`, `restDuration` | how long poison lasts, the pauses |
| `DragonFeast.Settings` | `fireDuration`, `fireCooldown`, `fireRange`, `fireAngle` | how the fire breath plays |
| `DragonRide.Settings` | `fullTurnReach`, `fullClimbRaise`, `fullBoostReach`, `cruiseSpeed`, `boostSpeed` | how the hands steer and how fast it flies |
| `Pinch` | `closing`, `opening` | how close thumb and index hold the horns, how far they let go |
| `ShamsehSky` | `distance`, `elevation`, `angularRadius`, `celebration`, `swell` | where the medallion hangs, how big, how it celebrates |
| `DragonRideSystem` | `finaleTurn`, `finaleFlight`, `finaleHold`, `epilogueLight` | the finale's timing, the light around the last page |
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
  next brings bananas), the last wave ending the feast, poison costing a
  heart and slowing the dragon, out of hearts resting then starting the wave over, bananas costing nothing, only
  good fruit drifting to the mouth, fire burning only the fruit ahead and recharging, a weak dragon flying slower
  without turning the view, the tally on the story, the finale only once the feast is finished, then the last
  page → `ended`;
- `RideSnapTests`: a snap with the whole hand jerking is not a snap on the ride (it still is for the elixir), the
  snapping hand not steering (and steering again after it), a hand loaded for long steering again;
- `DragonSnoutTests`: nostrils either side of an off-centre snout, the fire from the middle of the opening and
  tilted down, no snout without geometry.

`DragonRideTests.swift`: the flight, both hands moved to a side turning that way, letting go levelling out and a
new hold starting level, the pinch holding through small gaps, a destination flown to whatever the hands.
`ShamsehTests.swift`: the medallion's tiles (8, 10 and 16 folds) convex and turning counter-clockwise, shared edges
drawn once, rays, orbs and dots around the rim, petals coloured by every fruit but bananas and uncoloured when a wave
starts over. `RideShapesTests.swift`: the lantern and the mountains well formed.

`MusicTrackTests.swift`: silence before Start, the intro under the pages and the fruit, the puzzle from the flight
to the knot, the farewell once the dragon is free (played once).

`AppIconTests.swift`: the stone dragon is the primary icon, every choice is found again from the system's icon
name, and every alternate icon is declared in the app's Info.plist.

## The app icon

Three icons, picked in the **App Icon** menu under Start (`AppIconMenu`, `AppIconChoice`): **Stone Dragon** (the
design team's 3D stone dragon on a dark fill, the default: `AppIcon`), **Red Dragon** (`AppIconRedDragon`) and
**Black Dragon** (the first icon, `AppIconBlackDragon`), both coiled around an orange. The system changes the icon
with `UIApplication.setAlternateIconName` and tells the player; the menu shows only where
`supportsAlternateIcons` is true. The alternates are listed in the build setting
`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` (the `Macrowavers` target, Debug and Release), so the asset catalog compiles them
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
