import simd
import Testing
@testable import Macrowavers

struct ShamsehColourTests {
    private let folds = DragonFeast.Settings.totalGoal

    @Test func thePetalsRunRoundTheWheelSmoothlyAndCloseTheCircle() {
        let petals = (0..<folds).map { ShamsehSky.glaze(petal: $0, of: .apple, folds: folds) }
        let steps = zip(petals, petals.dropFirst() + [petals[0]]).map { simd_distance($0, $1) }
        // Neighbours stay close, the last one too next to the first: one rainbow, no seam.
        for step in steps {
            #expect(step < 0.75)
        }
        // And the wheel goes all the way round: far colours across the medallion.
        #expect(simd_distance(petals[0], petals[folds / 2]) > 0.8)
    }

    @Test func theFruitOnlyPullsItsPetalALittle() {
        for index in 0..<folds {
            let wheel = ShamsehSky.wheelColour(at: (Float(index) + 0.5) / Float(folds))
            for fruit in [FruitKind.apple, .pomegranate, .orange, .pineapple] {
                let petal = ShamsehSky.glaze(petal: index, of: fruit, folds: folds)
                let pull = simd_distance(petal, wheel) / max(simd_distance(ShamsehSky.glaze(of: fruit), wheel), 1e-5)
                #expect(abs(pull - ShamsehSky.fruitPull) < 1e-3)
            }
        }
    }

    @Test func theWheelWrapsAround() {
        #expect(simd_distance(ShamsehSky.wheelColour(at: 0), ShamsehSky.wheelColour(at: 1)) < 1e-5)
        #expect(simd_distance(ShamsehSky.wheelColour(at: 0), RidePalette.red) < 1e-5)
    }

    @Test func poisonDarkensAndTheFinaleGilds() {
        let colour = RidePalette.teal
        #expect(ShamsehSky.shown(colour, sickness: 0, warmth: 0) == colour)
        let sick = ShamsehSky.shown(colour, sickness: 1, warmth: 0)
        #expect(simd_reduce_add(sick) < simd_reduce_add(colour) * 0.4)
        let gilded = ShamsehSky.shown(colour, sickness: 0, warmth: 1)
        #expect(simd_distance(gilded, RidePalette.gold) < simd_distance(colour, RidePalette.gold) * 0.35)
    }
}
