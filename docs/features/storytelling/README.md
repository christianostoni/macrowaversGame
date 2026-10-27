# Storytelling

The words around the game, from the low-fidelity wireframes (5 screens): a Start button in the room, the
story's scroll and the chapter's title in a darkened room before the island appears, and the freed dragon's two
pages above it before its farewell.

## The screens

| # | Step (`StoryStep`) | Where | Text | Moves on |
|---|---|---|---|---|
| 1 | `start` | Launch window (plain, no glass) | **Start**, and under it a small **App Icon** menu (see below) | Start opens the immersive space |
| 2 | `scroll` | In front of the player's eyes | The story's scroll: the chapter's story in Persian Nastaliq, down to its painting of the tree and the dragon (see [The story's scroll](#the-storys-scroll)) | Pull it open (or pinch it), drag the paper up to the painting, **Continue** (or **Skip the story**): it rolls up and fades away |
| 3 | `chapter` | Same spot | **Chapter I** / Patience is bitter, but its fruit is sweet. | Tap the text: the island fades in |
| – | `adventure` | – | No story text: the island, its fruit, the dragon and its puzzle | The dragon is freed |
| 4 | `gratitude` | Above the dragon | **Thank you** / You freed me from the curse of the Black Div. / You don't need to be afraid. | Tap the text |
| 5 | `safety` | Above the dragon | **Thank you** / Child of the Shah, I will take you to safety. / Are you ready? | **I'm Ready** button: the dragon takes off |
| – | `farewell` | – | No text: the farewell flight (see [Untangle the Dragon](../untangle-dragon/README.md)) | – |

Text changes from the wireframes: "ti safety" → "to safety", "Dont need to be afraid" → "You don't need to be
afraid.", and the curse is named after the scroll's story ("the curse of XXX" → "the curse of the Black Div"); the
player is the Shah's lost child. The narrator's "What are you searching for?" page became the scroll. All the
pages' text lives in `StoryStep.page`; the scroll's, in `Assets/Scroll/make_scroll_page.swift`.

## How it works

- **State machine** (`Model/Story/`, no SwiftUI or RealityKit): `StoryStep` holds the pages (title, lines,
  anchor, how to move on) and what each step does to the room; `StoryViewModel` moves through them:
  `begin()` (Start), `advance()` (tap or answer), `dragonFreed()`, `dragonRecaptured()` (`restartScene()` puts the
  dragon back on the island: its words come again next time), `reset()` (the space closed).
- **The immersive view connects it to the dragon**: `UntangleViewModel.isSolved` → `dragonFreed()`; the story
  reaching `farewell` → `UntangleViewModel.beginFarewell()`. The app creates the dragon's view model with
  `farewellWaitsForPlayer: true`, so the free dragon stays in the play area (celebrating) until the answer.
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

The story, in English (for the narration to come):

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
- **Where it floats** (`ScrollSystem`): 0.95 m in front of the eyes, its window's top 15 cm above them (the open
  page a little below), facing the player; it glides back in front of them if they look more than 40° away or move
  30 cm, never while they hold it.

```
Sources/Macrowavers/
├── Model/Story/StoryStep.swift          Steps, pages and their text, dimming / reveal / focus rules
├── Model/Story/StoryViewModel.swift     @Observable @MainActor state machine
├── Model/Story/StoryScroll.swift        The scroll in the player's hands: open, read, continue / skip
├── Model/Story/ScrollRoll.swift         The scroll's paper: rolls, window, mesh (port of the Blender roll)
├── Views/Story/ScrollScene.swift        ScrollPaper (LowLevelMesh, rods, collider), ScrollComponent/System
├── Views/Story/ScrollHintView.swift     Under the scroll: what to do, Continue, Skip (attachment)
├── Resources/ScrollPage.jpg             The page, made by Assets/Scroll/make_scroll_page.swift
├── Views/ContentView.swift              Screen 1: the Start button (launch window, plain style)
├── Views/AppIconMenu.swift              Screen 1: the app icon picker under Start
├── Model/AppIconChoice.swift            The app icons (asset catalog names, titles)
├── Model/Story/MusicTrack.swift         Which track plays at each step (intro, puzzle, farewell)
├── Views/GameMusic.swift                Plays it: channel audio, crossfades, ducks while the dragon roars
├── Views/Story/StoryPanelView.swift     The page (attachment): title, lines, tap / answer
└── Views/Story/StoryPanelPlacement.swift StoryPanelComponent/System: in front of the player or above the dragon
Tests/MacrowaversTests/StoryTests.swift, ScrollRollTests.swift, StoryScrollTests.swift
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
| `ScrollSceneBuilder` | `width` | the scroll's width (0.45 m); its length follows from the page |
| `ScrollRoll` | `openWindow`, `lead`, `coreRadius`, `layerGap`, `wave` | how much paper shows when open (the painting must fit), the silk at the ends, the rolls' thickness, the open paper's wave |
| `StoryScroll` | `openThreshold`, `endThreshold`, `openRate`, `closeRate`, `fadeDuration` | how far to pull before it opens by itself, when Continue appears, how fast it opens, closes and fades |
| `ScrollComponent` | `distance`, `rise`, `lookAwayAngle`, `driftTolerance` | where the scroll floats and when it comes back in front of the player |
| `make_scroll_page.swift` | text, `bodySize`, `titleSize`, painting width | the story's words, their size on the page, how much room the painting takes |

## Tests

`StoryTests.swift`:
- `StoryTests`: the five screens in order (and nothing moving the story before Start or during the game),
  `restartScene()` and closing the space going back, which pages dim the room and where they sit, the island
  hidden until after the chapter's title, no placeholder text left;
- `FarewellCueTests`: the free dragon waiting for the answer (and taking off on its own without the story).

`MusicTrackTests.swift`: silence before Start, the intro under the pages and the fruit, the puzzle from the flight
to the knot, the farewell once the dragon is free (played once).

`ScrollRollTests.swift`: the paper keeps its length however it is rolled, the window goes from the page's top to
its end, each roll is a spiral around its rod in front of the window, the closed rolls touch without crossing, the
page sits between the leads the right way up, and every face turns its side.

`StoryScrollTests.swift`: it fades in closed, opens when pulled past a third (closes again if not) or tapped, the
paper follows the hand to the painting (Continue then stays), finishing rolls it up and fades it, and it can be
skipped even without its page.

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
- The scroll's story is in Persian only: the English narration (the text above) is still to be recorded.
- In the simulator the scroll opens with a click (no hand to pull it) and the paper is dragged with the pointer.
