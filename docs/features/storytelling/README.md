# Storytelling

The words around the game, from the low-fidelity wireframes (5 screens): a Start button in the room, the
story's scroll and the chapter's title in a darkened room before the island appears, and the freed dragon's two
pages above it. Then the ride: the player flies on the dragon's back through a night sky in a full immersive space
and feeds it in a sky that grows harder as they do well (chapter II); every fruit lights a petal of a star medallion in the sky, and once the
dragon is full it flies into the medallion's heart, where the story ends.

## The screens

| # | Step (`StoryStep`) | Where | Text | Moves on |
|---|---|---|---|---|
| 1 | `start` | Launch window (plain, no glass) | **Start**, and under it a small **App Icon** menu (see below) | Start opens the immersive space; until it has built its world (island, dragon, fruit: a few seconds) a spinner with "Loading…" turns in place of Start, then the window steps aside (`UntangleViewModel.isWorldLoaded`) |
| 2 | `scroll` | In front of the player's eyes | The story's scroll: the chapter's story in Persian Nastaliq, down to its painting of the tree and the dragon (see [The story's scroll](#the-storys-scroll)) | Pull it open (or pinch it), drag the paper up to the painting, **Continue** (or **Skip the story**): it rolls up and fades away |
| 3 | `chapter` | Same spot | **Chapter I** / Patience is bitter, but its fruit is sweet. | Tap the text: the island fades in |
| – | `adventure` | – | No story text: the island, its fruit, the dragon and its puzzle | The dragon is freed |
| 4 | `gratitude` | Above the dragon | **Thank you** / You freed me from the curse of the Black Div. / You don't need to be afraid. | Tap the text |
| 5 | `safety` | Above the dragon | **Thank you** / Child of the Shah, I will take you to safety. / Are you ready? | **I'm Ready** button: the room goes dark, the ride's space takes over |
| – | `ride` | Full immersion | A spinner ("Loading…", placed once 1.2 m in front of the eyes) while the ride's world loads; then no page: out of the dark, on the dragon's back; while the hands don't hold the horns, a hint over its head shows how (pinch with both hands) | The dragon arrives (3.5 s) |
| 6 | `secondChapter` | In front of the eyes, above the dragon's head | **Chapter II** / Feed the dragon the right plants. / It doesn't like bananas! | Tap the text |
| – | `feast` | Above the dragon's head | No page: fruit in the sky, harder as the player does well, and a tally (hearts, fire, fruit eaten); see [Chapter II: the feast](#chapter-ii-the-feast) | The 10th fruit eaten ("The dragon is full!") and the medallion complete, swelled for 2.5 s |
| – | `finale` | Full immersion | No page: the dragon roars, turns to the medallion on its own and flies into its heart through a rush of light (`ShamsehFinale.swift`); the light fills the view | 6 s at most turning, 7 s of flight, 1.2 s of light |
| 7 | `epilogue` | In front of the player's eyes, in the light | **Home at last** / The dragon is full, and the curse is gone. / Thank you for flying with it. | **The End** button |
| – | `ended` | – | No text: the ride's space closes and the launch window comes back | – |

Text changes from the wireframes: "ti safety" → "to safety", "Dont need to be afraid" → "You don't need to be
afraid.", and the curse is named after the scroll's story ("the curse of XXX" → "the curse of the Black Div"); the
player is the Shah's lost child. The narrator's "What are you searching for?" page became the scroll. All the
pages' text lives in `StoryStep.page`; the scroll's, in `Assets/Scroll/make_scroll_page.swift`.

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

## The story's scroll

The chapter's story, *The Shah's Tree* (درخت شاه), on a Persian scroll (*tumār*), in the game's low-poly airbrush
style: a paper with an ornamental border, the story in Nastaliq and, at its end, a painting of the island, the tree
and the dragon. It floats closed in front of the player in the darkened room; they pull its bottom roll down to
open it (or pinch it), drag the paper up to read, and once the painting is in sight **Continue** rolls it up and
it fades away: the chapter's title comes next. **Skip the story** does the same at any time.

The story, in English: the narrator reads it when the scroll opens (below), with these words as subtitles:

> Once there was, once there was not. Long ago, a Shah planted a tree on an island floating between earth and
> sky. Its fruit held the light of fallen stars, and only royal hands could pick it. To guard it, the Shah called
> on an old friend: a dragon of the sky.
> But the Black Div wanted that light. He could not take the fruit, so he cursed its guardian: circle the tree
> forever, guard it forever, and never touch a single fruit. He left his worms inside the fruit, then hunted the
> Shah's family until the world forgot them. With every circle, the dragon's body knots tighter and its heart
> grows angrier.
> Only an elixir brewed from the tree's own fruit can soften the curse, and only patient hands can untie what it
> has knotted. But no royal hands were left to pick the fruit.
> So the div believed. One child of the Shah's line survived and never knew it. The tree remembers you.
> Patience is bitter, but its fruit is sweet.

- **The page** (`ScrollPage.jpg`, 1536 px wide) is made by `Assets/Scroll/make_scroll_page.swift` from two
  images made with ChatGPT in the game's style, with a screenshot of the island as reference and without any text
  (image models cannot write Persian): the paper (`paper.png`) and the painting (`painting.png`). The script sets
  the title in the paper's cartouche and the story in Noto Nastaliq Urdu (it comes with macOS; any Nastaliq font
  installed on the Mac works, the font is not shipped), in the game's indigo, then the proverb in pink and the
  painting. It lengthens the paper as the story needs without stretching its border: the band of side borders is
  repeated one period of their pattern (216 rows) at a time, then each row of the band is evened out to the
  average of its neighbours, so the paper's airbrush gradient leaves no line at the joins. A new `paper.png` needs
  its measurements (header, footer, cartouche, borders, period) updated at the top of the script. Run it from the
  repository's root (`swift Assets/Scroll/make_scroll_page.swift`) after changing the text or the images: the
  scroll takes its length from the page's proportions.
- **The paper** (`ScrollRoll`, no RealityKit) is a port of the design team's Blender scroll
  (`Assets/Scroll/scroll_rollable_5.blend`, node group "Scroll Roll"): each roll is an Archimedean spiral that
  keeps the paper's length, curling towards the reader with the page inside, and the open paper has their gentle
  wave. Theirs opens from the middle; this one opens from the top (the bottom roll lets the paper out) and the
  paper slides through the window, so a page longer than the window can be read. A violet silk lead at each end
  stays around the rods.
- **The mesh** (`ScrollPaper`, `Views/Story/ScrollScene.swift`) is a `LowLevelMesh` (~700 vertices) rewritten
  in place whenever the pose changes: the front, smooth, with the page unlit in its painted colours, and the back
  in flat facets, like the rest of the game. A box collider around paper and rods takes the gestures.
- **Its look** (`ScrollLooks`): the design team's airbrush shader graph, loaded from the island's file
  (`Airbrush_Trunk`) and recoloured through its parameters (`Stop0Color`…`Stop3Color`, `EmissionBoost`): the
  silk in the flowers' violet, the paper's back in cream, the rods in the trunk's colours, low-poly prisms with a
  gold crystal at each end like the island's floating gems. Without the island's file it falls back to plain
  colours.
- **The player** (`StoryScroll`, no RealityKit): closed, a drag down opens it (past 30% it opens all the way,
  otherwise it closes again); open, the paper follows the hand up and down; at 97% the painting is in sight and
  **Continue** appears under it (`ScrollHintView`, an attachment placed by `ScrollSystem`). Closing rolls the
  paper up, then it fades; `isDone` moves the story on (`DragonImmersiveView`).
- **Where it floats** (`ScrollSystem`): 0.95 m in front of the eyes, its window's top 19 cm above them (the open
  page a little below), facing the player; it waits for head tracking (up to 3 s) so it appears in front of the
  real eyes, and glides back in front of them if they look more than 40° away or move 30 cm, never while they hold
  it. Under it, `ScrollHintView` (placed from its real size, its top 2 cm under the bottom roll): the hint,
  **Continue** or **Skip the story**.
- **The narration** (`StoryNarration`, `StoryNarrator`): the English story read by an ElevenLabs voice (Eleven
  Multilingual v2, made in Pika's Speech Studio; source `Assets/Audio/story_narration.mp3`, in the game
  `StoryNarration.m4a`, 59 s). It starts when the scroll opens, in the player's ears like the music, which steps back
  under it (`GameMusic.duck`); Continue or Skip fades it out. "Div" is written "Deev" in the text given to the
  voice, so it is not said like "divide". The subtitles are one cue a sentence (the long one in two), their times
  the pauses in the recording: its 29 spoken phrases match the story's 29 clauses one for one, so a new recording
  needs new times (`StoryNarration.cues`). The subtitles (`StorySubtitleView`) float a little below wherever the
  player looks, like visionOS's Live Captions, so they are read without bending the neck (under the scroll they
  were too low): 15° below the gaze, 0.8 m away (in front of the scroll), on a dark background over the scroll's
  writing. They follow lazily (`GazeFollow`): the small movements of reading leave them still, a turn of more than
  12° makes them glide after the gaze. The paper moves with the voice (`StoryNarration.pageProgress`): from 7 s
  it scrolls down so the painting comes into the window as the narrator says "The tree remembers you"; once the
  player drags the paper, it is theirs.

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

**A sky that grows harder** (`DragonFeast.difficulty`, 0…1): **10 fruit** to eat, 12 in the sky at a time, new
ones ahead as the old are passed, and no waves and no pauses. The ride makes some players dizzy (the sky turns
around them in every turn), so the chapter is short and gets hard quickly instead of long:
- each fruit eaten raises the difficulty by 0.1, plus 0.04 for each fruit before it in a streak (up to two; a
  banana or a poisoned fruit breaks the streak). Without a slip, bananas come with the 2nd fruit, poison with the
  3rd, the last stretch with the 5th and the hardest sky with the 7th: the last four are eaten in it;
- a poisoned fruit lowers it by 0.12, being exhausted by 0.25, and after 10 s without eating it falls by 0.02 a
  second: a player who struggles gets help.

The difficulty sets the new fruit (`DragonFeast.Settings.levels`; between two levels the values ease from one to
the next, but a kind of fruit comes only with its stage, and its hint):

| Stage, from difficulty | Bananas | Poisoned | Aim help (good fruit drift to the mouth within) | Swing (to either side) | Hint (the first time the stage is reached) |
|---|---|---|---|---|---|
| 0, 0 | – | – | 3.2 m | – | Fly into the fruit; push the horns forward to fly faster |
| 1, 0.15 | 30% | – | 2.8 m | – | Bananas: the dragon spits them out (a waste of time) |
| 2, 0.4 | 15% | 30% | 2.4 m | 0.15 m | Poisoned fruit: avoid them, or let go of a horn and snap your fingers to breathe fire |
| 3, 0.75 | 10% | 45% | 2.1 m | 0.3 m | The last stretch: the fruit dodge and less help aiming |
| hardest, 1 | 10% | 55% | 2 m | 0.4 m | – |

The fruit swing slowly from side to side across the flight (4 s a swing; one being pulled in stops). The hard sky
is hard in what to eat and what to burn more than in aiming: with the aim helped down to 1.2 m and swings of 1 m,
lining up each fruit took many more turns and the ride ~40 s longer. A headless simulation of the feast with a bot
rider (the real model, 300 rides) gave ~36–40 s instead of the four waves' ~64–69 s, and about a third less turning
of the view (~700–830° instead of ~1050–1250°); real riders are slower than the bot. The 10th fruit eaten, "The
dragon is full!" while the medallion celebrates, then the finale.

**The shamseh** (`Shamseh`, drawn by `ShamsehSky`): a Persian star medallion hung far away over the way ahead when
the feast begins, its strapwork faint. Every fruit the dragon eats glazes one of its petals in that fruit's colour;
there is a petal for every fruit to eat (`DragonFeast.Settings.totalGoal`: a ten-pointed shamseh). Out of hearts,
the petals of the fruit the dragon loses lose their colour (`Shamseh.uncolour(last:)`).
Complete, its star lights up in the dragon's blue, the lines and kites turn gold and it swells for 2.5 s; then the
dragon flies into its heart (`DragonRide.destination`) and the story's last page shows in the light there (the
light widens to 2.4 m around the player, past the page).

**Poison and hearts.** A poisoned fruit is one the dragon likes, darkened to a sickly purple with a faint green glow
in a clinging green haze (its own model, tinted: no new asset), turning slowly. Eaten, it costs one of the dragon's
**3 hearts**: it coughs smoke from its nostrils, its head droops and sways, and for 3 s it flies slower (its body
sways, never the view). The aim's help never pulls poison to the mouth. Out of hearts the dragon is **exhausted**:
it loses 2 of the fruit it ate (`exhaustionCost`), the sky clears and eases, it rests 4 s, then flies on with
full hearts.

**Fire.** A **snap of the fingers** (the gesture learnt for the elixir, either hand) makes the dragon breathe fire
for 0.9 s: a long jet from the middle of its mouth (`DragonRideSceneBuilder.makeFireBreath`, the same fire as the island's
roar, `DragonEffects.fireEmitter`) burns every fruit in a
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
├── Model/Story/StoryScroll.swift        The scroll in the player's hands: open, read, continue / skip
├── Model/Story/ScrollRoll.swift         The scroll's paper: rolls, window, mesh (port of the Blender roll)
├── Views/Story/ScrollScene.swift        ScrollPaper (LowLevelMesh, rods, collider), ScrollComponent/System
├── Views/Story/ScrollHintView.swift     Under the scroll: what to do, Continue, Skip (attachment)
├── Views/Story/StorySubtitleView.swift  The narrator's subtitles (attachment), StorySubtitleComponent/System
├── Model/Story/GazeFollow.swift         Where the subtitles float: a little below the gaze, following it lazily
├── Model/Story/StoryNarration.swift     The narration's subtitles and their times, the paper following the voice
├── Views/Story/StoryNarrator.swift      Plays the narration in the player's ears
├── Resources/StoryNarration.m4a         The narration (source Assets/Audio/story_narration.mp3)
├── Resources/ScrollPage.jpg             The page, made by Assets/Scroll/make_scroll_page.swift
├── Views/ContentView.swift              Screen 1: the Start button (launch window, plain style)
├── Views/AppIconMenu.swift              Screen 1: the app icon picker under Start
├── Model/AppIconChoice.swift            The app icons (asset catalog names, titles)
├── Model/Story/MusicTrack.swift         Which track plays at each step (intro, puzzle, farewell)
├── Views/GameMusic.swift                Plays it: channel audio, crossfades, ducks while the dragon roars
├── Views/Story/StoryPanelView.swift     The page (attachment): title, lines, tap / answer
└── Views/Story/StoryPanelPlacement.swift StoryPanelComponent/System: in front of the player or above the dragon
Tests/MacrowaversTests/StoryTests.swift, ScrollRollTests.swift, StoryScrollTests.swift, StoryNarrationTests.swift,
                                         GazeFollowTests.swift
Assets/Scroll/                           paper.png, painting.png, make_scroll_page.swift, the Blender scroll
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
| `DragonFeast.Settings` | `totalGoal`, `levels` (shares, `pullRadius`, `sway`), `hearts`, `biteRadius`, `count` | how long and how hard chapter II is |
| `DragonFeast.Settings` | `rise`, `streakBonus`, `longestStreakBonus`, `poisonRelief`, `exhaustionRelief`, `reliefDelay`, `reliefRate`, `exhaustionCost`, `swayPeriod` | how fast the sky grows harder, how it eases for a player who struggles |
| `DragonFeast.Settings` | `sicknessDuration`, `restDuration` | how long poison lasts, the dragon's rest |
| `DragonFeast.Settings` | `fireDuration`, `fireCooldown`, `fireRange`, `fireAngle` | how the fire breath plays |
| `DragonRide.Settings` | `fullTurnReach`, `fullClimbRaise`, `fullBoostReach`, `cruiseSpeed`, `boostSpeed` | how the hands steer and how fast it flies |
| `Pinch` | `closing`, `opening` | how close thumb and index hold the horns, how far they let go |
| `ShamsehSky` | `distance`, `elevation`, `angularRadius`, `celebration`, `swell` | where the medallion hangs, how big, how it celebrates |
| `DragonRideSystem` | `finaleTurn`, `finaleFlight`, `finaleHold`, `epilogueLight` | the finale's timing, the light around the last page |
| `DragonRide.Settings` | `weakSlowdown`, `weakSway` | how a sick or exhausted dragon flies |
| `SteeringHold` | `afterSnap`, `longestHold` | how long a snapping hand stops steering |
| `SnapDetector.Settings.whileSteering` | `maxWristTravel` | how still the wrist must stay for a snap on the ride |
| `DragonRideSceneBuilder` | `poisonTint`, `poisonGlow` | the poisoned look |
| `DragonEffects` | `fireRate`, `fireEmitter(size:speed:followsMouth:)` | the fire's density and look, shared with the island's roar |
| `DragonSnout` | `frontShare`, `nostrilSpread`, `nostrilDrop`, `inset` | where the smoke and the fire leave the head |
| `ScrollSceneBuilder` | `width` | the scroll's width (0.45 m); its length follows from the page |
| `ScrollRoll` | `openWindow`, `lead`, `coreRadius`, `layerGap`, `wave` | how much paper shows when open (the painting must fit), the silk at the ends, the rolls' thickness, the open paper's wave |
| `StoryScroll` | `openThreshold`, `endThreshold`, `openRate`, `closeRate`, `fadeDuration` | how far to pull before it opens by itself, when Continue appears, how fast it opens, closes and fades |
| `StoryNarration` | `cues`, `scrollStartTime`, `paintingTime` | the subtitles and their times, when the paper starts following the voice and when the painting is in sight |
| `StoryNarrator` | `level`, `fadeOut` | how loud the narrator is, how fast the voice fades on Continue or Skip |
| `GazeFollow` | `distance`, `drop`, `startAngle`, `responsiveness` | how far and how far below the gaze the subtitles float, how big a turn moves them, how fast they follow |
| `ScrollComponent` | `distance`, `rise`, `lookAwayAngle`, `driftTolerance` | where the scroll floats and when it comes back in front of the player |
| `make_scroll_page.swift` | text, `bodySize`, `titleSize`, painting width | the story's words, their size on the page, how much room the painting takes |

## Tests

`StoryTests.swift`:
- `StoryTests`: the five screens in order (and nothing moving the story before Start or during the game),
  `restartScene()` and closing the space going back, which pages dim the room and where they sit, the island
  hidden until after the chapter's title, no placeholder text left;
- `FreeDragonTests`: the free dragon staying in the play area while it speaks (it never flies off by itself),
  and `restartScene()` putting it back around the tree.

`DragonFeastTests.swift`:
- `DragonFeastTests`: the first sky only good fruit, the levels growing harder (a kind of fruit only with its
  stage), each fruit raising the difficulty and more on a streak (each stage's hint once, no pause), the hardest
  sky with the 7th fruit without a slip, the goal ending the feast, poison costing a heart, slowing the dragon,
  easing the sky and breaking the streak, help for a player who does not eat, out of hearts losing two fruit and
  resting, the fruit swinging sideways in a hard sky, bananas costing nothing, only
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
drawn once, rays, orbs and dots around the rim, petals coloured by every fruit but bananas and uncoloured when the dragon,
exhausted, loses fruit. `RideShapesTests.swift`: the lantern and the mountains well formed.

`MusicTrackTests.swift`: silence before Start, the intro under the pages and the fruit, the puzzle from the flight
to the knot, the farewell once the dragon is free (played once).

`ScrollRollTests.swift`: the paper keeps its length however it is rolled, the window goes from the page's top to
its end, each roll is a spiral around its rod in front of the window, the closed rolls touch without crossing, the
page sits between the leads the right way up, and every face turns its side.

`StoryScrollTests.swift`: it fades in closed, opens when pulled past a third (closes again if not) or tapped, the
paper follows the hand to the painting (Continue then stays), opened the narrator speaks and the paper follows the
voice to the painting (until the player drags it), finishing rolls it up, stops the voice and fades it, and it can be
skipped even without its page.

`StoryNarrationTests.swift`: the cues follow the voice from the first word to the last (the last stays a moment),
the subtitles spell "Div" as the scroll does, and the paper reaches the painting with the voice.

`GazeFollowTests.swift`: the subtitles float 15° below the gaze, stay still while the player reads, and glide under
the new gaze after a bigger turn.

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
- The scroll is in Persian, the narration and subtitles in English only.
- In the simulator the scroll opens with a click (no hand to pull it) and the paper is dragged with the pointer.
