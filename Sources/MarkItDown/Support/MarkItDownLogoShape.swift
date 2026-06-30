import SwiftUI

/// Vector logo: document → markdown (# and lines).
struct MarkItDownLogoShape: Shape {
    static let designSize = CGSize(width: 150, height: 100)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / Self.designSize.width
        let scaleY = rect.height / Self.designSize.height

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scaleX, y: y * scaleY)
        }

        // Document outline with folded corner
        path.move(to: point(28, 15))
        path.addLine(to: point(98, 15))
        path.addLine(to: point(110, 27))
        path.addLine(to: point(110, 85))
        path.addLine(to: point(28, 85))
        path.closeSubpath()

        path.move(to: point(98, 15))
        path.addLine(to: point(110, 27))
        path.addLine(to: point(98, 27))
        path.closeSubpath()

        // Down arrow
        path.move(to: point(40, 30))
        path.addLine(to: point(40, 48))
        path.move(to: point(34, 42))
        path.addLine(to: point(40, 48))
        path.addLine(to: point(46, 42))

        // Hash symbol
        path.move(to: point(72, 32))
        path.addLine(to: point(68, 50))
        path.move(to: point(82, 32))
        path.addLine(to: point(78, 50))
        path.move(to: point(66, 38))
        path.addLine(to: point(84, 38))
        path.move(to: point(64, 44))
        path.addLine(to: point(86, 44))

        // Markdown lines
        path.move(to: point(36, 68))
        path.addLine(to: point(94, 68))
        path.move(to: point(36, 76))
        path.addLine(to: point(78, 76))

        return path
    }
}

struct MarkItDownLogoView: View {
    var lineWidth: CGFloat = 6

    var body: some View {
        MarkItDownLogoShape()
            .stroke(
                Color.primary,
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .aspectRatio(MarkItDownLogoShape.designSize, contentMode: .fit)
    }
}
