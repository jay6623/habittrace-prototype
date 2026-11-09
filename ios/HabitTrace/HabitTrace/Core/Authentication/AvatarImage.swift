import UIKit

/// Avatar preparation matching the PWA's `fileToAvatarDataUrl`: longest
/// edge 256px, JPEG, quality stepped down until the inline fallback fits.
nonisolated enum AvatarImage {
    static let maxEdge: CGFloat = 256
    static let maxDataURLLength = 90_000
    static let maxSourceBytes = 8 * 1024 * 1024

    nonisolated static func compressedJPEG(from data: Data) throws -> Data {
        guard data.count <= maxSourceBytes else {
            throw AuthManager.AccountError.imageTooLarge
        }
        guard let image = UIImage(data: data) else {
            throw AuthManager.AccountError.invalidImage
        }

        let scale = min(1, maxEdge / max(image.size.width, image.size.height))
        let size = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        var quality: CGFloat = 0.86
        var jpeg = resized.jpegData(compressionQuality: quality) ?? Data()
        while jpeg.base64EncodedString().count + 23 > maxDataURLLength, quality > 0.45 {
            quality -= 0.08
            jpeg = resized.jpegData(compressionQuality: quality) ?? jpeg
        }
        guard !jpeg.isEmpty else { throw AuthManager.AccountError.invalidImage }
        return jpeg
    }
}
