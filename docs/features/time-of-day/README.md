# Time of Day

The light tells the player that time is passing: the island wakes up at **dawn** while they gather the
ingredients, the sun is high at **noon** while they untangle the dragon, and the day ends in a **sunset** as the
dragon flies away. The sun, the sky and the colour of the real room change together, slowly, never in one jump.

Status: playable, with procedural skies (gradients painted in code) and eyeballed values: the light needs tuning
on device (see [Tuning](#tuning)).

## How to try it

1. Run the app and press **Start**. When the island fades in it is dawn: a warm, low sun from the left, the
   room slightly warm.
2. Every ingredient that joins the orbit moves the sun on (morning with all three).
3. When the soothed dragon flies to you the sun climbs to noon (~6 s, about its flight): white light from above,
   short sharp shadows, the room as it is.
4. Untangle it: the golden hour while it thanks you, then the sunset (orange and violet, grazing from the right,
   the room dimmed and tinted) when you answer **I'm Ready**.
5. **Restart Scene** rewinds to dawn in under 2 s. In the dragon panel, **Hold the Time of Day** freezes the clock
   and its slider moves it from sunrise to sunset (debug, to tune the light).

## The clock

One number, `clock`, from 0 (dawn) to 1 (sunset). The game sets where it should be (`TimeOfDay.target`), the clock
runs there at a steady pace (`TimeOfDay.advance`) and the light is read along it (`TimeOfDay.daylight(at:)`).
A single clock means one interpolation for everything, and a change of state halfway through a transition just
turns it around: no jumps.

| Moment | `clock` | When (`TimeOfDay.target`) | Sun | Sky | Room |
|---|---|---|---|---|---|
| `dawn` | 0 | The island appears, no ingredient yet | (1, 0.62, 0.42), 900 lux, 8° high, 65° left | dawn | dimmed peach (0.9, 0.72, 0.62) |
| `morning` | 0.25 × found / 3 | Each ingredient in orbit; 0.25 with all three (elixir brewed, flying) | (1, 0.85, 0.7), 1500 lux, 30°, 40° left | dawn ↔ noon | warm (1, 0.88, 0.74) |
| `noon` | 0.5 | `approaching`, `landing`, `untangling` | (1, 0.98, 0.94), 1800 lux, 72°, ahead | noon | brightest, sunny yellow (1, 0.96, 0.84) |
| `goldenHour` | 0.8 | `free` (the dragon's words) | (1, 0.6, 0.3), 1300 lux, 18°, 45° right | noon ↔ sunset | golden (1, 0.72, 0.48) |
| `sunset` | 1 | Story `farewell`, phase `gone` | (0.95, 0.42, 0.35), 700 lux, 4°, 65° right | sunset | darker, orange-violet (0.8, 0.5, 0.6) |

- **Pace**: forward 0.08 clock/s (dawn to noon ~6 s, golden hour to sunset ~2.5 s), back 0.6 clock/s (Restart
  Scene is not part of the story).
- **Between two moments** every value is blended with a smoothstep of the segment's fraction: the light eases out
  of a moment and settles on the next. The sun's angles are blended as angles (elevation, azimuth), so it travels
  along its arc from left to right; it never goes below the horizon.

## What the clock drives

| Layer | How | Why |
|---|---|---|
| Sun | `DirectionalLightComponent` (colour, intensity) on an entity turned so its +Z points at the sun; `DirectionalLightComponent.Shadow` (`.automatic(maximumDistance: 6)`) | The key light and its shadows on the island (the tree on the grass, the dragon on the rock). The real floor keeps the grounding shadows |
| Sky | `ImageBasedLightComponent(source: .blend(a, b, t))`, `intensityExponent` = `skyExposure` | The colour of the shade and of the reflections. `skyBlend` 0...2 picks the two skies and the fraction |
| Room light | `EnvironmentLightingConfigurationComponent(environmentLightingWeight:)` 0.4–0.6 (highest at noon) | In a mixed space the real room lights the virtual content too: turned down, the sun and the sky show on the island |
| Room | `.preferredSurroundingsEffect(.colorMultiply(tint))` | In mixed reality the eye judges the hour from the room: the strongest cue, so every moment tints it about as much as the sunset (a multiply can only darken: noon is the brightest, dawn and sunset the darkest). The tinted room and the island lit the same way look like one place. The story's pages keep `.dark` |

The skies are three `SkyGradient`s (zenith, horizon, ground) painted into tiny equirectangular images (64 × 32)
and turned into `EnvironmentResource`s when the scene is built: no assets. The design team can replace them with
HDR images later (same three moments). If they cannot be made, only the sun lights the scene and the room light
is left as it is.

The island root, the dragon's play area and the orchard root receive the sky (`ImageBasedLightReceiverComponent`)
and have their room light turned down. The sun lights every entity; SwiftUI panels are not affected.

## Architecture

```
Sources/Macrowavers/
├── Model/Sky/
│   ├── TimeOfDay.swift            Daylight (one moment's light), TimeOfDay (moments, target, advance, daylight(at:)),
│   │                              SkyGradient (dawn / noon / sunset skies). Pure, no RealityKit/SwiftUI
│   └── SkyViewModel.swift         The clock, the debug clock, the room tint and the moment (observed, stepped)
└── Views/Sky/RealityKit/
    └── SkyScene.swift             TimeOfDayComponent/System (every frame: target → clock → light),
                                   SkySceneBuilder (sun, sky light, painted skies, receivers)
Tests/MacrowaversTests/TimeOfDayTests.swift
```

- Like `SceneFocus` / `FocusDimmingSystem`: the moment is a pure function of the game's state (`DragonPhase`,
  `StoryStep`, ingredients in orbit), so no view model knows about another. `TimeOfDayComponent` holds the view
  models; `TimeOfDaySystem` advances `SkyViewModel` and applies the light **only while the clock runs**.
- The clock changes every frame during a transition, so it is not observed. SwiftUI reads only `roomTint`
  (rounded to 1/64 of the clock: a smooth fade with few updates) and `moment` (debug), assigned only when they
  change.
- The sky's root is not under the island: the sun does not turn with the turntable.
- Registered in `DragonBodySystem.registerAll()`; `SkyViewModel` lives in `MacrowaversApp` and is passed to the
  immersive space; `sky.reset()` when the space closes.

## Tuning

| Value | Where | Effect |
|---|---|---|
| Sun colour / intensity / elevation / azimuth per moment | `TimeOfDay.Moment.daylight` | The key light |
| `skyExposure` | same | Brightness of the shade (stops): it adds to the room's light, so it stays below 0 |
| `roomLightWeight` | same | Lower: our light shows more on the island. With the room barely tinted the island looked detached at noon: the room now carries the change instead |
| `roomTint` | same | How much the real room is tinted (white = untouched). Near white it is not noticed: only a sunset at (0.88, 0.66, 0.72) was |
| Moments' `clock` | `TimeOfDay.Moment.clock` | Where each moment sits (golden hour at 0.8) |
| `forwardSpeed`, `rewindSpeed` | `TimeOfDay` | How long the transitions take |
| `SkyGradient.dawn/noon/sunset` | `TimeOfDay.swift` | The colours of the skies |

`TimeOfDayTests` covers: the morning moving on with every ingredient, noon while untangling and sunset at the
farewell, each moment's exact light, the sun rising to noon then setting from left to right above the horizon,
the clock never overshooting and taking several seconds, the quick rewind, the skies' gradients, the debug clock
and the reset.

## Known limits

- All values are eyeballed in code: intensities, exposures and room weights need checking on device (simulator
  lighting differs).
- Whether the system crossfades `.colorMultiply` changes is not documented: the tint changes in 1/64 steps, which
  should look continuous during the slow transitions.
- The dragon's own glow, smoke and sparks are unlit materials: they do not change with the hour.
- Directional shadows fall only on virtual surfaces; on the real floor only the grounding shadows show.
