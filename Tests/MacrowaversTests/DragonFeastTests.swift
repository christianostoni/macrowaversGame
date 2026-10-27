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

    @Test func theSkyFillsWithFruitAheadSomeOfThemBananas() {
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
        #expect(feast.plants.contains { $0.kind == .banana })
        #expect(feast.plants.contains { $0.kind.isLikedByDragon })
    }

    @Test func theDragonEatsTheFruitItFliesIntoAndSpitsOutBananas() {
        var random = SeededRandom(seed: 5)
        var ride = flying()
        var feast = DragonFeast(ride: ride, using: &random)
        var events: [DragonFeast.Event] = []
        // Straight on for 30 s: the fruit on the way end up in the mouth, the others pass by and come back ahead.
        for _ in 0..<(30 * 60) {
            ride.update(deltaTime: 1.0 / 60.0, left: nil, right: nil, isHandTrackingAvailable: true)
            events += feast.update(deltaTime: 1.0 / 60.0, mouth: ride.skyFromRide(mouth), ride: ride, using: &random)
            for plant in feast.plants where plant.isFloating {
                // Nothing left behind: missed fruit come back ahead.
                #expect(ride.rideFromSky(plant.position).z <= DragonFeast.Settings.behind + 0.5)
            }
        }
        #expect(feast.plants.count == DragonFeast.Settings.count)
        for event in events {
            switch event {
            case .ate(let fruit): #expect(fruit.isLikedByDragon)
            case .refused(let fruit): #expect(fruit == .banana)
            }
        }
    }

    @Test func aFruitAtTheMouthIsEatenABananaRefused() {
        var random = SeededRandom(seed: 1)
        let ride = flying()
        var feast = DragonFeast(ride: ride, using: &random)
        let mouthInSky = ride.skyFromRide(mouth)
        guard let liked = feast.plants.firstIndex(where: { $0.kind.isLikedByDragon }),
              let banana = feast.plants.firstIndex(where: { $0.kind == .banana }) else {
            Issue.record("the seed gave no banana or no liked fruit")
            return
        }
        feast.place(plant: liked, at: mouthInSky)
        var events = feast.update(deltaTime: 1.0 / 60.0, mouth: mouthInSky, ride: ride, using: &random)
        #expect(events == [.ate(feast.plants[liked].kind)])
        #expect(feast.appetite >= 0 && feast.disgust == 0)

        feast.place(plant: banana, at: mouthInSky + SIMD3(0.3, 0, 0))
        events = feast.update(deltaTime: 1.0 / 60.0, mouth: mouthInSky, ride: ride, using: &random)
        #expect(events == [.refused(.banana)])
        #expect(feast.disgust > 0.9)
        if case .spat = feast.plants[banana].state {} else { Issue.record("the banana was not spat out") }
    }

    @Test func aLikedFruitCloseInFrontDriftsToTheMouthAndOpensTheJaws() {
        var random = SeededRandom(seed: 1)
        let ride = flying()
        var feast = DragonFeast(ride: ride, using: &random)
        let mouthInSky = ride.skyFromRide(mouth)
        guard let liked = feast.plants.firstIndex(where: { $0.kind.isLikedByDragon }) else { return }
        // Just out of reach, ahead and off to the side.
        feast.place(plant: liked, at: mouthInSky + ride.forward * 2 + SIMD3(1, 0, 0) * 1)
        let before = simd_distance(feast.plants[liked].position, mouthInSky)
        _ = feast.update(deltaTime: 0.1, mouth: mouthInSky, ride: ride, using: &random)
        #expect(simd_distance(feast.plants[liked].position, mouthInSky) < before)
        #expect(feast.appetite > 0)
    }

    @MainActor
    @Test func chapterTwoComesAfterTheArrivalAndCountsOnlyTheRightFruit() {
        let story = StoryViewModel()
        // Fed before the feast: nothing counts.
        story.dragonAte(.apple)
        #expect(story.plantsEaten == 0)
        story.skipToRide()
        story.rideArrived()
        #expect(story.step == .secondChapter)
        #expect(story.step.page?.title == "Chapter II")
        story.advance()
        #expect(story.step == .feast)
        story.dragonAte(.apple)
        story.dragonAte(.banana)
        story.dragonAte(.pineapple)
        #expect(story.plantsEaten == 2 && story.bananasRefused == 1)
        for _ in 0..<StoryViewModel.plantsGoal { story.dragonAte(.pomegranate) }
        #expect(story.isFeastComplete)
        story.reset()
        #expect(story.step == .start && story.plantsEaten == 0 && story.bananasRefused == 0)
    }

    @MainActor
    @Test func onceFullTheDragonFliesIntoTheMedallionAndTheRideEnds() {
        let story = StoryViewModel()
        story.skipToRide()
        story.rideArrived()
        story.advance()
        // Not full yet: no finale.
        story.feastCelebrated()
        story.rideEnded()
        #expect(story.step == .feast && !story.isRideOver)
        for _ in 0..<StoryViewModel.plantsGoal { story.dragonAte(.orange) }
        story.feastCelebrated()
        #expect(story.step == .finale && story.step.isFullyImmersed && story.step.page == nil)
        story.dragonAte(.apple)
        #expect(story.plantsEaten == StoryViewModel.plantsGoal)
        story.rideEnded()
        #expect(story.isRideOver)
        story.reset()
        #expect(story.step == .start && !story.isRideOver)
    }
}
