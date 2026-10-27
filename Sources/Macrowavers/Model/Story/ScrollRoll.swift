import Foundation
import simd

/// The story's scroll: a long sheet of paper, its two ends rolled around rods, the reading window between them.
///
/// A port of the design team's Blender scroll (`Assets/Scroll/scroll_rollable_5.blend`, node group "Scroll Roll"):
/// each roll is an Archimedean spiral that keeps the paper's length, curling towards the reader (the page rolls up
/// inside), and the open paper has the same gentle wave. Their scroll opens from the middle; this one opens from
/// the top (the bottom roll lets the paper out) and the paper also slides through the window, the top roll taking
/// up what the bottom one lets out, so a page longer than the window can be read.
///
/// Space: the origin is the window's top edge, in the middle of the paper's width; y up, z towards the reader.
/// Along the paper, distances (`along`) run from its top end (0) to its bottom end (`length`): a silk lead around
/// each rod, the page between them.
struct ScrollRoll {
    /// How open the scroll is and which part of the paper is in the window.
    struct Pose: Equatable {
        /// Length of paper between the rolls (m).
        var window: Float
        /// Where the window's top edge is along the paper (m).
        var top: Float
        /// 0 closed … 1 open: the open paper's wave grows with it.
        var open: Float
    }

    /// The paper's parts, each its own material: the page and the silk leads, front and back.
    enum MeshPart: Int, CaseIterable {
        case page, frontLeads, back, backLeads
    }

    /// The paper as triangles: the front (the page and the silk leads), smooth, and the back, in flat facets like
    /// the rest of the game (each quad its own four vertices, after the front's two per row).
    struct Mesh {
        /// Along the paper (m): one row of vertices across the width at each.
        var rows: [Float] = []
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        /// The indices of each part.
        var parts: [MeshPart: Range<Int>] = [:]
    }

    /// Width of the paper (m).
    let width: Float
    /// Length of the page, between the leads (m).
    let pageLength: Float
    /// Silk at each end, always around the rods (m).
    var lead: Float = 0.1
    /// Room left inside the innermost turn, for the rod (m). The designers': 0.05 of their 1.02 m wide sheet.
    var coreRadius: Float = 0.022
    /// Between two turns of a roll (m).
    var layerGap: Float = 0.004
    /// Paper between the rolls when the scroll is open (m): the painting fits in it.
    var openWindow: Float = 0.56
    /// The open paper's wave, as a fraction of the window's length (the designers' Bend: 0.12 of their window).
    var wave: Float = 0.04
    /// Rows of vertices along the paper are this far apart (m): the rolls' facets, ~40° a step around the innermost
    /// turn, ~17° around the outermost.
    var rowSpacing: Float = 0.015

    /// Whole sheet, leads included (m).
    var length: Float { pageLength + 2 * lead }

    /// Radius of a roll holding `rolled` m of paper.
    func radius(rolled: Float) -> Float {
        (coreRadius * coreRadius + 2 * spiralStep * max(rolled, 0)).squareRoot()
    }

    /// The spiral's radius shrinks by this much per radian.
    private var spiralStep: Float { layerGap / (2 * .pi) }

    /// Window of the closed scroll: its two rolls touching, all the paper but the top lead in the bottom one.
    var closedWindow: Float { radius(rolled: lead) + radius(rolled: length - lead) + 0.004 }

    /// `open` from 0 (closed) to 1, `scroll` from 0 (the window on the page's top) to 1 (on its end).
    func pose(open: Float, scroll: Float) -> Pose {
        let open = min(max(open, 0), 1)
        let window = closedWindow + (openWindow - closedWindow) * open
        return Pose(window: window, top: lead + travel(window: window) * min(max(scroll, 0), 1), open: open)
    }

    /// How far the paper slides through a window of this length, from the page's top to its end (m).
    func travel(window: Float) -> Float {
        max(0, length - 2 * lead - window)
    }

    /// Paper in the top and the bottom roll (m).
    func rolled(_ pose: Pose) -> (top: Float, bottom: Float) {
        (pose.top, length - pose.top - pose.window)
    }

    /// The rods' axes (y, z): at the window's edges, as far in front of the paper as their roll is thick.
    func rods(_ pose: Pose) -> (top: SIMD2<Float>, bottom: SIMD2<Float>) {
        let paper = rolled(pose)
        return (SIMD2(0, radius(rolled: paper.top)), SIMD2(-pose.window, radius(rolled: paper.bottom)))
    }

    /// Where the paper `along` m from its top end is (y, z).
    func point(at along: Float, pose: Pose) -> SIMD2<Float> {
        let bottomEdge = pose.top + pose.window
        if along < pose.top {
            return curl(depth: pose.top - along, rolled: pose.top)
        }
        if along > bottomEdge {
            let turn = curl(depth: along - bottomEdge, rolled: length - bottomEdge)
            return SIMD2(-pose.window - turn.x, turn.y)
        }
        // In the window: flat but for its wave (an S from top to bottom, -1…1, none at the rolls).
        let down = along - pose.top
        let wavePhase = pose.window > 1e-5 ? 2 * down / pose.window - 1 : 0
        return SIMD2(-down, wave * pose.window * pose.open * sin(.pi * wavePhase) * (1 - wavePhase * wavePhase))
    }

    /// `depth` m into a roll of `rolled` m: (distance past the window's edge, towards the reader).
    private func curl(depth: Float, rolled: Float) -> SIMD2<Float> {
        let outer = radius(rolled: rolled)
        let inner = max(outer * outer - 2 * spiralStep * depth, coreRadius * coreRadius).squareRoot()
        let angle = (outer - inner) / spiralStep
        return SIMD2(inner * sin(angle), outer - inner * cos(angle))
    }

    /// The rows of vertices: evenly spaced, and one on each end of the page (where the silk meets the paper).
    func rows() -> [Float] {
        let steps = Int((length / rowSpacing).rounded(.up))
        var rows = (0...steps).map { length * Float($0) / Float(steps) }
        rows.append(contentsOf: [lead, length - lead])
        return Array(Set(rows)).sorted()
    }

    /// The paper at this pose. The front faces the reader where the paper is open; each row is two vertices, across
    /// the width. The page's texture: u from left to right, v from its bottom (0) to its top (1).
    func mesh(pose: Pose) -> Mesh {
        var mesh = Mesh()
        mesh.rows = rows()
        (mesh.positions, mesh.normals) = vertices(rows: mesh.rows, pose: pose)
        let uvs: [SIMD2<Float>] = mesh.rows.flatMap { along -> [SIMD2<Float>] in
            let height = 1 - min(max((along - lead) / pageLength, 0), 1)
            return [SIMD2(0, height), SIMD2(1, height)]
        }
        let backUVs: [SIMD2<Float>] = (0..<(mesh.rows.count - 1)).flatMap { row in
            Array(uvs[(2 * row)..<(2 * row + 4)])
        }
        mesh.uvs = uvs + backUVs
        // Quads between rows: the page's, the leads', on the front then the back.
        let back = UInt32(2 * mesh.rows.count)
        func quads(_ range: Range<Int>, back isBack: Bool) -> [UInt32] {
            range.flatMap { row -> [UInt32] in
                let topLeft = isBack ? back + UInt32(4 * row) : UInt32(2 * row), topRight = topLeft + 1
                let bottomLeft = topLeft + 2, bottomRight = topLeft + 3
                return isBack
                    ? [topLeft, bottomRight, bottomLeft, topLeft, topRight, bottomRight]
                    : [topLeft, bottomLeft, bottomRight, topLeft, bottomRight, topRight]
            }
        }
        let pageStart = mesh.rows.firstIndex { $0 >= lead } ?? 0
        let pageEnd = mesh.rows.firstIndex { $0 >= length - lead } ?? mesh.rows.count - 1
        let page = pageStart..<pageEnd
        let leads = [0..<pageStart, pageEnd..<(mesh.rows.count - 1)]
        for (part, triangles) in [(MeshPart.page, quads(page, back: false)),
                                  (.frontLeads, leads.flatMap { quads($0, back: false) }),
                                  (.back, quads(page, back: true)),
                                  (.backLeads, leads.flatMap { quads($0, back: true) })] {
            mesh.parts[part] = mesh.indices.count..<(mesh.indices.count + triangles.count)
            mesh.indices.append(contentsOf: triangles)
        }
        return mesh
    }

    /// Positions and normals of the front's vertices (two per row, smooth), then the back's (four per quad, each
    /// facet facing away from the reader, flat).
    func vertices(rows: [Float], pose: Pose) -> (positions: [SIMD3<Float>], normals: [SIMD3<Float>]) {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        positions.reserveCapacity(6 * rows.count)
        normals.reserveCapacity(6 * rows.count)
        let halfWidth = width / 2
        /// The front's normal: the tangent (down the paper) turned a quarter towards the reader.
        func facing(_ tangent: SIMD2<Float>) -> SIMD3<Float> {
            let normal = simd_length(tangent) > 1e-7 ? simd_normalize(SIMD2(tangent.y, -tangent.x)) : SIMD2(0, 1)
            return SIMD3(0, normal.x, normal.y)
        }
        let places = rows.map { point(at: $0, pose: pose) }
        for (along, place) in zip(rows, places) {
            let tangent = point(at: along + 0.001, pose: pose) - point(at: along - 0.001, pose: pose)
            positions.append(contentsOf: [SIMD3(-halfWidth, place.x, place.y), SIMD3(halfWidth, place.x, place.y)])
            normals.append(contentsOf: Array(repeating: facing(tangent), count: 2))
        }
        for (above, below) in zip(places, places.dropFirst()) {
            positions.append(contentsOf: [SIMD3(-halfWidth, above.x, above.y), SIMD3(halfWidth, above.x, above.y),
                                          SIMD3(-halfWidth, below.x, below.y), SIMD3(halfWidth, below.x, below.y)])
            normals.append(contentsOf: Array(repeating: -facing(below - above), count: 4))
        }
        return (positions, normals)
    }
}
