import AVFoundation
import UIKit

enum VideoThumbnailGenerator {
    static func jpegData(from url: URL, maximumSize: CGFloat = 800) throws -> Data {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumSize, height: maximumSize)
        var actualTime = CMTime.zero
        let image = try generator.copyCGImage(
            at: CMTime(seconds: 0.1, preferredTimescale: 600),
            actualTime: &actualTime
        )
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.82) else {
            throw VideoProcessingError.unableToCreateThumbnail
        }
        return data
    }
}
