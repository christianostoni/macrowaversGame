import Foundation
import simd
import Testing
@testable import Macrowavers

struct DragonFeastTests {
    /// A ride past its arrival, flying straight on.
    private func flying() -> DragonRide {
        var ride = DragonRide()
        for _ in 0..<Int((DragonRide.Settings.arrivalDuration + 0.5) * 60) {
            ride.update(deltaTime: 1.0 / 60.0, left: nil, right: nil, isHandTrackingAvailable: true)
        }
        return ride
    }

    /// The dragon's mouth: in front of and below the player (ride space).
    private let mouth = SIMD3<Float>(0, -0.5, -1.8)

    /// One frame with fruit `index` put at the mouth, of `kind`, poisoned or not.
    private func feed(_ feast: inout DragonFeast, ride: DragonRide, index: Int = 0, kind: FruitKind = .apple,
                      isPoisoned: Bool = false, random: inout SeededRandom) -> [DragonFeast.Event] {
        let mouthInSky = ride.skyFromRide(mouth)
        feast.place(plant: index, at: mouthInSky, kind: kind, isPoisoned: isPoisoned)
        return feast.update(deltaTime: 1.0 / 60.0, mouth: mouthInSky, ride: ride, using: &random)
    }

    /// Lets `seconds` go by, straight on.
    private func wait(_ feast: inout DragonFeast, ride: DragonRide, seconds: Float,
                      random: inout SeededRandom) -> [DragonFeast.Event] {
        var events: [DragonFeast.Event] = []
        for _ in 0..<Int(seconds * 60) {
            events += feast.update(deltaTime: 1.0 / 60.0, mouth: ride.skyFromRide(mouth) + SIMD3(0, 50, 0), ride: ride,
                                   using: &random)
        }
        return events
    }

    @Test func theFirstSkyHoldsGoodFruitOnly() {
        var random = SeededRandom(seed: 3)
        let ride = flying()
        let feast = DragonFeast(ride: ride, using: &random)
        #expect(feast.plants.count == DragonFeast.Settings.count)
        #expect(Set(feast.plants.map(\.id)).count == feast.plants.count)
        for plant in feast.plants {
            let seen = ride.rideFromSky(plant.position)
            #expect(seen.z < -DragonFeast.Settings.firstAhead.lowerBound + 0.01)
            #expect(abs(seen.x) <= DragonFeast.Settings.side + 0.01)
        }
        #expect(feast.plants.allSatisfy { $0.isGood })
        #expect(feast.difficulty == 0 && feast.stage == 0)
        #expect(feast.hearts == DragonFeast.Settings.hearts && feast.phase == .playing)
    }

    @Test func theSkyGrowsHarderWithTheDifficulty() {
        let levels = DragonFeast.Settings.levels
        #expect(levels.first?.start == 0 && levels.last?.start == 1)
        #expect(levels.first?.bananaShare == 0 && levels.first?.poisonShare == 0)
        #expect(zip(levels, levels.dropFirst()).allSatisfy {
            $0.start < $1.start && $0.pullRadius >= $1.pullRadius && $0.sway <= $1.sway
        })
        // A new kind of fruit comes only with its stage (and its hint), not little by little before it.
        let easy = DragonFeast.Level.at(levels[1].start - 0.01)
        #expect(easy.bananaShare == 0 && easy.poisonShare == 0)
        #expect(DragonFeast.Level.at(levels[1].start).bananaShare > 0)
        #expect(DragonFeast.Level.at(levels[2].start - 0.01).poisonShare == 0)
        #expect(DragonFeast.Level.at(levels[2].start).poisonShare > 0)
        // In between, the values ease from one level to the next; past the hardest, the hardest.
        let middle = DragonFeast.Level.at((levels[2].start + levels[3].start) / 2)
        #expect(middle.pullRadius < levels[2].pullRadius && middle.pullRadius > levels[3].pullRadius)
        #expect(DragonFeast.Level.at(1) == levels[levels.count - 1])
    }

    @Test func eatingRaisesTheDifficultyFasterOnAStreak() {
        var random = SeededRandom(seed: 5)
        let ride = flying()
        var feast = DragonFeast(ride: ride, using: &random)
        var events: [DragonFeast.Event] = []
        for _ in 0..<2 { events += feed(&feast, ride: ride, random: &random) }
        let rise = DragonFeast.Settings.rise
        let bonus = DragonFeast.Settings.streakBonus
        #expect(abs(feast.difficulty - (2 * rise + bonus)) < 1e-5)
        #expect(feast.eaten == 2 && feast.streak == 2)
        // The second fruit took the sky past the bananas' stage: its hint, once. No pause: the sky still floats.
        #expect(events == [.ate(.apple), .ate(.apple), .stageReached(1)])
        #expect(feast.stage == 1 && feast.phase == .playing)
        #expect(feast.plants.dropFirst().allSatisfy { $0.isFloating })
        // On a streak each fruit raises it more: the third, by two fruit's bonus, into the poison's stage.
        events = feed(&feast, ride: ride, random: &random)
        #expect(abs(feast.difficulty - (3 * rise + 3 * bonus)) < 1e-5)
        #expect(events.last == .stageReached(2))

        // A banana breaks the streak: the next fruit raises the difficulty by the plain step.
        _ = feed(&feast, ride: ride, kind: .banana, random: &random)
        #expect(feast.streak == 0)
        let before = feast.difficulty
        _ = feed(&feast, ride: ride, index: 1, random: &random)
        #expect(abs(feast.difficulty - before - rise) < 1e-5)
    }

    @Test func withoutASlipTheSkyIsAtItsHardestBeforeTheEnd() {
        var random = SeededRandom(seed: 6)
        let ride = flying()
        var feast = DragonFeast(ride: ride, using: &random)
        var events: [DragonFeast.Event] = []
        var hardestAt: Int?
        for fruit in 1..<DragonFeast.Settings.totalGoal {
            events += feed(&feast, ride: ride, random: &random)
            if hardestAt == nil && feast.difficulty >= 1 { hardestAt = fruit }
        }
        // Poison comes with the 3rd fruit, the hardest sky with the 7th: the last fruit are eaten in it.
        #expect(hardestAt == 7)
        #expect(events.contains(.stageReached(DragonFeast.Settings.stageCount - 1)))
        #expect(feast.stage == DragonFeast.Settings.stageCount - 1)
    }

    @Test func theGoalEatenTheDragonIsFull() {
        var random = SeededRandom(seed: 7)
        let ride = flying()
        var feast = DragonFeast(ride: ride, using: &random)
        var events: [DragonFeast.Event] = []
        for _ in 0..<DragonFeast.Settings.totalGoal { events += feed(&feast, ride: ride, random: &random) }
        #expect(events.last == .finished)
        #expect(feast.phase == .finished && !feast.isFireReady && feast.eaten == DragonFeast.Settings.totalGoal)
        // Every stage's hint came once, and never a pause in between.
        #expect(events.filter { if case .stageReached = $0 { true } else { false } }.count
                == DragonFeast.Settings.stageCount - 1)
        _ = wait(&feast, ride: ride, seconds: 1, random: &random)
        #expect(!feast.plants.contains { $0.isFloating })
    }

    @Test func aPoisonedFruitCostsAHeartAndMakesTheDragonSick() {
        var random = SeededRandom(seed: 1)
        let ride = flying()
        var feast = DragonFeast(ride: ride, using: &random)
        let events = feed(&feast, ride: ride, kind: .pineapple, isPoisoned: true, random: &random)
        #expect(events == [.poisoned(.pineapple)])
        #expect(feast.hearts == DragonFeast.Settings.hearts - 1 && feast.eaten == 0)
        #expect(feast.sickness > 0.9 && feast.weakness > 0.5)
        _ = wait(&feast, ride: ride, seconds: DragonFeast.Settings.sicknessDuration, random: &random)
        #expect(feast.sickness == 0 && feast.weakness == 0)
    }

    @Test func aPoisonedFruitEasesTheSkyAndBreaksTheStreak() {
        var random = SeededRandom(seed: 8)
        let ride = flying()
        var feast = DragonFeast(ride: ride, using: &random)
        for _ in 0..<4 { _ = feed(&feast, ride: ride, random: &random) }
        let before = feast.difficulty
        _ = feed(&feast, ride: ride, kind: .orange, isPoisoned: true, random: &random)
        #expect(abs(before - feast.difficulty - DragonFeast.Settings.poisonRelief) < 1e-5)
        #expect(feast.streak == 0)
        // The poison's hint already shown stays shown: the stage does not go back.
        #expect(feast.stage == 2)
    }

    @Test func aPlayerWhoDoesNotEatGetsHelp() {
        var random = SeededRandom(seed: 9)
        let ride = flying()
        var feast = DragonFeast(ride: ride, using: &random)
        for _ in 0..<4 { _ = feed(&feast, ride: ride, random: &random) }
        let before = feast.difficulty
        _ = wait(&feast, ride: ride, seconds: DragonFeast.Settings.reliefDelay - 1, random: &random)
        #expect(feast.difficulty == before)
        _ = wait(&feast, ride: ride, seconds: 6, random: &random)
        #expect(feast.difficulty < before - 4 * DragonFeast.Settings.reliefRate)
    }

    @Test func outOfHeartsTheDragonLosesSomeFruitAndRests() {
        var random = SeededRandom(seed: 2)
        let ride = flying()
        var feast = DragonFeast(ride: ride, using: &random)
        var events: [DragonFeast.Event] = []
        for _ in 0..<3 { events += feed(&feast, ride: ride, random: &random) }
        for _ in 0..<DragonFeast.Settings.hearts {
            events += feed(&feast, ride: ride, kind: .orange, isPoisoned: true, random: &random)
        }
        let cost = DragonFeast.Settings.exhaustionCost
        #expect(events.last == .exhausted(lost: cost))
        #expect(feast.phase == .exhausted && feast.hearts == 0 && feast.weakness == 1)
        #expect(feast.eaten == 3 - cost)

        _ = wait(&feast, ride: ride, seconds: DragonFeast.Settings.restDuration + 0.1, random: &random)
        #expect(feast.phase == .playing && feast.eaten == 3 - cost)
        #expect(feast.hearts == DragonFeast.Settings.hearts)
        #expect(feast.plants.allSatisfy { $0.isFloating })
        #expect(feast.progress.poisoned == DragonFeast.Settings.hearts)
    }

    @Test func inAHardSkyTheFruitDodge() {
        var random = SeededRandom(seed: 10)
        let ride = flying()
        var calm = DragonFeast(ride: ride, using: &random)
        var hard = calm
        hard.setDifficulty(1)
        // Far from the mouth, poisoned (never pulled in): only the swing moves it.
        let spot = ride.skyFromRide(SIMD3(0, 0, -20))
        calm.place(plant: 0, at: spot, kind: .apple, isPoisoned: true)
        hard.place(plant: 0, at: spot, kind: .apple, isPoisoned: true)
        let mouthInSky = ride.skyFromRide(mouth)
        let sway = DragonFeast.Settings.levels[DragonFeast.Settings.levels.count - 1].sway
        var farthest: Float = 0
        // A whole swing: whatever its phase, the fruit strays at least `sway` from where it was.
        for _ in 0..<Int(DragonFeast.Settings.swayPeriod * 60) {
            _ = calm.update(deltaTime: 1.0 / 60.0, mouth: mouthInSky, ride: ride, using: &random)
            _ = hard.update(deltaTime: 1.0 / 60.0, mouth: mouthInSky, ride: ride, using: &random)
            let moved = hard.plants[0].position - spot
            farthest = max(farthest, simd_length(moved))
            // Sideways, level, never towards the player, and never farther than its swing.
            #expect(abs(moved.y) < 1e-3 && abs(simd_dot(moved, ride.forward)) < 1e-3)
            #expect(simd_length(moved) <= 2 * sway + 0.01)
        }
        #expect(calm.plants[0].position == spot)
        #expect(farthest > 0.9 * sway)
    }

    @Test func aBananaIsSpatOutAndCostsNothing() {
        var random = SeededRandom(seed: 1)
        let ride = flying()
        var feast = DragonFeast(ride: ride, using: &random)
        let events = feed(&feast, ride: ride, kind: .banana, random: &random)
        #expect(events == [.refused(.banana)])
        #expect(feast.disgust > 0.9 && feast.hearts == DragonFeast.Settings.hearts && feast.bananas == 1)
        if case .spat = feast.plants[0].state {} else { Issue.record("the banana was not spat out") }
    }

    @Test func onlyGoodFruitDriftToTheMouth() {
        var random = SeededRandom(seed: 1)
        let ride = flying()
        var feast = DragonFeast(ride: ride, using: &random)
        let mouthInSky = ride.skyFromRide(mouth)
        // Just out of reach, ahead and off to the side.
        let spot = mouthInSky + ride.forward * 2 + SIMD3(1, 0, 0)
        feast.place(plant: 0, at: spot, kind: .apple, isPoisoned: false)
        feast.place(plant: 1, at: spot + SIMD3(0, 0.5, 0), kind: .apple, isPoisoned: true)
        _ = feast.update(deltaTime: 0.1, mouth: mouthInSky, ride: ride, using: &random)
        #expect(simd_distance(feast.plants[0].position, mouthInSky) < simd_distance(spot, mouthInSky))
        #expect(feast.plants[1].position == spot + SIMD3(0, 0.5, 0))
        #expect(feast.appetite > 0)
    }

    @Test func fireBurnsTheFruitAheadOnlyAndNeedsToRecharge() {
        var random = SeededRandom(seed: 4)
        let ride = flying()
        var feast = DragonFeast(ride: ride, using: &random)
        let mouthInSky = ride.skyFromRide(mouth)
        let side = simd_normalize(simd_cross(ride.forward, SIMD3(0, 1, 0)))
        feast.place(plant: 0, at: mouthInSky + ride.forward * 8, kind: .apple, isPoisoned: true)
        feast.place(plant: 1, at: mouthInSky + ride.forward * 8 + side * 5, kind: .apple, isPoisoned: true)
        feast.place(plant: 2, at: mouthInSky + ride.forward * (DragonFeast.Settings.fireRange + 3), kind: .pineapple)
        #expect(feast.isFireReady)
        let breathed = feast.breatheFire()
        let breathedAgain = feast.breatheFire()
        #expect(breathed && !breathedAgain)
        var events: [DragonFeast.Event] = []
        for _ in 0..<6 {
            events += feast.update(deltaTime: 1.0 / 60.0, mouth: mouthInSky, ride: ride, using: &random)
        }
        #expect(events.contains(.burned(.apple, wasPoisoned: true)))
        if case .burnt = feast.plants[0].state {} else { Issue.record("the fruit ahead did not burn") }
        #expect(feast.plants[1].isFloating && feast.plants[2].isFloating)
        #expect(feast.fire > 0.5)

        _ = wait(&feast, ride: ride, seconds: DragonFeast.Settings.fireCooldown, random: &random)
        #expect(feast.fire == 0 && feast.isFireReady && feast.progress.burned >= 1)
    }

    @Test func aWeakDragonFliesSlower() {
        var strong = flying()
        var weak = flying()
        for _ in 0..<(3 * 60) {
            strong.update(deltaTime: 1.0 / 60.0, left: nil, right: nil, isHandTrackingAvailable: true)
            weak.update(deltaTime: 1.0 / 60.0, left: nil, right: nil, isHandTrackingAvailable: true, weakness: 1)
        }
        #expect(weak.speed < strong.speed * 0.7)
        // Only the dragon's body sways: the heading does not change.
        #expect(weak.yaw == strong.yaw)
    }

    @MainActor
    @Test func chapterTwoShowsTheFeastAndEndsOnTheLastPage() {
        let story = StoryViewModel()
        var progress = FeastProgress()
        progress.eaten = 2
        // Shown (or fire asked for) before the feast: nothing changes.
        story.showFeast(progress)
        story.requestFire()
        #expect(story.feast == FeastProgress() && !story.isFireRequested)
        story.skipToRide()
        story.rideArrived()
        #expect(story.step == .secondChapter)
        #expect(story.step.page?.title == "Chapter II")
        story.advance()
        #expect(story.step == .feast)
        story.showFeast(progress)
        #expect(story.feast.eaten == 2)
        // The fire button, taken once by the ride.
        story.requestFire()
        let firstTake = story.takeFireRequest()
        let secondTake = story.takeFireRequest()
        #expect(firstTake && !secondTake)

        // Not full yet: no finale.
        story.feastCelebrated()
        story.rideEnded()
        #expect(story.step == .feast)
        // Full, its medallion complete: the dragon flies into it on its own (no page), then the last page shows in
        // the light at its heart.
        progress.phase = .finished
        story.showFeast(progress)
        story.feastCelebrated()
        #expect(story.step == .finale && story.step.isFullyImmersed && story.step.page == nil)
        story.advance()
        #expect(story.step == .finale)
        story.rideEnded()
        #expect(story.step == .epilogue)
        #expect(story.step.page?.advance == .answer("The End"))
        story.advance()
        #expect(story.step == .ended && story.step.isFullyImmersed)
        story.reset()
        #expect(story.step == .start && story.feast == FeastProgress())
    }
}

struct RideSnapTests {
    /// The hologram hand's pose at `time`, read like a tracked right hand, moved by `offset` (the whole hand).
    private func sample(_ time: Float, at timestamp: TimeInterval, offset: SIMD3<Float> = .zero) -> HandSample {
        let pose = SnapHint.pose(at: time)
        let knuckles = SnapHint.fingers.map(\.knuckle)
        return HandSample(chirality: .right, timestamp: timestamp, knuckle: knuckles[1] + offset, wrist: offset,
                          thumbTip: pose.thumbTip + offset, indexTip: pose.fingers[0][2] + offset,
                          middleDistal: pose.fingers[1][1] + offset, middleTip: pose.fingers[1][2] + offset,
                          indexKnuckle: knuckles[0] + offset, ringKnuckle: knuckles[2] + offset,
                          littleKnuckle: knuckles[3] + offset, ringTip: pose.fingers[2][2] + offset,
                          littleTip: pose.fingers[3][2] + offset)
    }

    @Test func steeringTheHornsWhileSnappingIsNotASnap() {
        let loaded = sample(1.1, at: 10)
        let released = sample(SnapHint.snapTime, at: 10.05)
        // The whole hand jerks 10 cm as it opens (turning the horns).
        let jerked = sample(SnapHint.snapTime, at: 10.05, offset: SIMD3(0, -0.1, 0))

        var ride = SnapDetector(settings: .whileSteering)
        _ = ride.process(loaded)
        #expect(ride.isLoaded(.right) && !ride.isLoaded(.left))
        let snapped = ride.process(released)
        #expect(snapped)

        var steering = SnapDetector(settings: .whileSteering)
        _ = steering.process(loaded)
        let snappedWhileSteering = steering.process(jerked)
        #expect(!snappedWhileSteering)

        // For the elixir (no steering) the same movement still counts.
        var orchard = SnapDetector()
        _ = orchard.process(loaded)
        let snappedForTheElixir = orchard.process(jerked)
        #expect(snappedForTheElixir)
    }

    @Test func theSnappingHandDoesNotSteer() {
        var hold = SteeringHold()
        let left = SIMD3<Float>(-0.2, -0.35, -0.35)
        let right = SIMD3<Float>(0.2, -0.35, -0.35)
        _ = hold.steering(left: left, right: right, loaded: [], snapped: [], time: 0)
        // The right hand loads and snaps, moving a few centimetres: the steering keeps its place.
        let jerked = right + SIMD3(0, 0.06, 0.03)
        var hands = hold.steering(left: left + SIMD3(0, 0.01, 0), right: jerked, loaded: [.right],
                                  snapped: [], time: 0.1)
        #expect(hands.right == right && hands.left == left + SIMD3(0, 0.01, 0))
        hands = hold.steering(left: left, right: jerked, loaded: [], snapped: [.right],
                              time: 0.2)
        #expect(hands.right == right)
        hands = hold.steering(left: left, right: jerked, loaded: [], snapped: [],
                              time: 0.2 + SteeringHold.afterSnap - 0.05)
        #expect(hands.right == right)
        // Then it steers again.
        hands = hold.steering(left: left, right: jerked, loaded: [], snapped: [],
                              time: 0.2 + SteeringHold.afterSnap + 0.01)
        #expect(hands.right == jerked)
    }

    @Test func aHandLoadedForLongSteersAgain() {
        var hold = SteeringHold()
        let right = SIMD3<Float>(0.2, -0.35, -0.35)
        _ = hold.steering(left: nil, right: right, loaded: [], snapped: [], time: 0)
        let moved = right + SIMD3(0, 0.1, 0)
        var hands = hold.steering(left: nil, right: moved, loaded: [.right], snapped: [], time: 0.1)
        #expect(hands.right == right)
        // A curled grip that keeps looking loaded: after `longestHold` the hand steers again.
        hands = hold.steering(left: nil, right: moved, loaded: [.right], snapped: [],
                              time: 0.1 + SteeringHold.longestHold + 0.01)
        #expect(hands.right == moved && hands.left == nil)
    }
}

struct DragonSnoutTests {
    /// A box-shaped snout centred at x = 2 cm (not 0), its tip at z = 0.15, with a jaw under it.
    private let face: [SIMD3<Float>] = [-0.025, 0.065].flatMap { x in
        [-0.04, 0.005].flatMap { y in [-0.12, 0.15].map { z in SIMD3<Float>(x, y, z) } }
    }
    private let jaw: [SIMD3<Float>] = [-0.02, 0.05].flatMap { x in
        [-0.07, -0.035].flatMap { y in [0.08, 0.145].map { z in SIMD3<Float>(x, y, z) } }
    }
    private let hinge = SIMD3<Float>(0, -0.03, 0.03)

    @Test func theNostrilsSitEitherSideOfTheSnoutsCentreOnItsFront() throws {
        let snout = try #require(DragonSnout(face: face, jaw: jaw, hinge: hinge))
        #expect(snout.nostrils.count == 2)
        #expect(abs((snout.nostrils[0].x + snout.nostrils[1].x) / 2 - 0.02) < 1e-5)
        #expect(snout.nostrils[0].x < snout.nostrils[1].x)
        #expect(snout.nostrils.allSatisfy { $0.y > -0.01 && $0.y < 0.005 && $0.z > 0.14 && $0.z <= 0.15 })
    }

    @Test func theFireLeavesFromTheMiddleOfTheOpening() throws {
        let snout = try #require(DragonSnout(face: face, jaw: jaw, hinge: hinge))
        let closed = snout.mouth(jawAngle: 0)
        let open = snout.mouth(jawAngle: 0.49)
        // On the snout's centre line, between the lips, lower as the jaw opens.
        #expect(abs(closed.x - (0.02 + 0.015) / 2) < 1e-5)
        #expect(closed.y < -0.035 && closed.y > -0.04)
        #expect(open.y < closed.y - 0.01 && open.z > 0.1)
        // Tilted down by half the jaw's angle.
        let direction = snout.fireTilt(jawAngle: 0.49).act(SIMD3(0, 0, 1))
        #expect(direction.y < 0 && abs(asin(-direction.y) - 0.245) < 1e-4)
    }

    @Test func noGeometryNoSnout() {
        #expect(DragonSnout(face: [], jaw: jaw, hinge: hinge) == nil)
        #expect(DragonSnout(face: face, jaw: [], hinge: hinge) == nil)
    }
}
