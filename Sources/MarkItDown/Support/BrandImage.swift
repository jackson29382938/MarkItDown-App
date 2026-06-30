import AppKit
import SwiftUI

@MainActor
enum BrandImage {
    static let aspectRatio = MarkItDownLogoShape.designSize.width / MarkItDownLogoShape.designSize.height

    static func menuBarLogo(height pointSize: CGFloat = 18) -> NSImage? {
        renderVectorImage(size: menuBarLogoSize(height: pointSize), template: true)
    }

    static func menuBarLogoSize(height pointSize: CGFloat = 18) -> CGSize {
        CGSize(width: pointSize * aspectRatio, height: pointSize)
    }

    @MainActor
    private static func renderVectorImage(size: CGSize, template: Bool) -> NSImage? {
        let content = MarkItDownLogoView(lineWidth: size.height * 0.09)
            .frame(width: size.width, height: size.height)
            .padding(size.height * 0.04)

        let renderer = ImageRenderer(content: content)
        renderer.isOpaque = false
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0

        guard let cgImage = renderer.cgImage else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: size)
        image.isTemplate = template
        return image
    }
}

struct AppLogoView: View {
    var height: CGFloat = 28

    private var logoSize: CGSize {
        BrandImage.menuBarLogoSize(height: height)
    }

    var body: some View {
        MarkItDownLogoView(lineWidth: height * 0.09)
            .frame(width: logoSize.width, height: logoSize.height)
            .accessibilityLabel("MarkItDown")
    }
}
