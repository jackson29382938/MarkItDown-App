import AppKit
import SwiftUI

enum BrandImage {
    static func menuBarLogo(height pointSize: CGFloat = 18) -> NSImage? {
        guard let image = load(named: "MenuBarLogo") else {
            return nil
        }
        image.isTemplate = true
        image.size = fittedSize(for: image, height: pointSize)
        return image
    }

    static func menuBarLogoSize(height pointSize: CGFloat = 18) -> CGSize {
        guard let image = load(named: "MenuBarLogo") else {
            return CGSize(width: pointSize, height: pointSize)
        }
        return fittedSize(for: image, height: pointSize)
    }

    private static func load(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Brand"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image
    }

    private static func fittedSize(for image: NSImage, height: CGFloat) -> CGSize {
        let pixels = pixelDimensions(of: image)
        guard pixels.height > 0 else {
            return CGSize(width: height, height: height)
        }
        let aspect = pixels.width / pixels.height
        return CGSize(width: height * aspect, height: height)
    }

    private static func pixelDimensions(of image: NSImage) -> CGSize {
        if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }
        return image.size
    }
}

struct AppLogoView: View {
    var height: CGFloat = 28

    private var logoSize: CGSize {
        BrandImage.menuBarLogoSize(height: height)
    }

    var body: some View {
        Group {
            if let logo = BrandImage.menuBarLogo(height: height) {
                Image(nsImage: logo)
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: height * 0.72, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: logoSize.width, height: logoSize.height)
        .accessibilityLabel("MarkItDown")
    }
}
