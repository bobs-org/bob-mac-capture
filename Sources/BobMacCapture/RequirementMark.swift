import CaptureCore
import SwiftUI

/// One fixed-size criterion mark. Indentation carries depth; shape carries state.
struct RequirementMark: View {
    let state: CaptureRequirementState
    var size: CGFloat = 13

    var body: some View {
        let glyph = RequirementMarkShape(state: state)
        let inkSize = size * 0.92
        ZStack {
            if state == .met {
                glyph.fill(Color.teal)
            }
            glyph.stroke(
                Color.teal,
                style: StrokeStyle(
                    lineWidth: inkSize * 1.75 / 16, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: inkSize, height: inkSize)
        .opacity(state.markOpacity)
        .frame(width: size, height: size)
        .accessibilityLabel("Requirement · \(state.rawValue.capitalized)")
    }
}

/// Normalized 16×16 geometry shared with Bob's Obsidian requirement masks.
struct RequirementMarkShape: Shape {
    let state: CaptureRequirementState

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 16, y: rect.minY + rect.height * y / 16)
        }
        var path = Path()
        if state == .carried {
            path.move(to: point(2.4, 8))
            path.addLine(to: point(12.8, 8))
            path.move(to: point(9.2, 4.3))
            path.addLine(to: point(12.9, 8))
            path.addLine(to: point(9.2, 11.7))
        } else {
            path.move(to: point(8, 1.7))
            path.addLine(to: point(14.3, 8))
            path.addLine(to: point(8, 14.3))
            path.addLine(to: point(1.7, 8))
            path.closeSubpath()
            if state == .dropped {
                path.move(to: point(4.4, 11.6))
                path.addLine(to: point(11.6, 4.4))
            }
        }
        return path
    }
}
