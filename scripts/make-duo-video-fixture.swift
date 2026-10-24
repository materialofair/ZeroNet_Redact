import AppKit
import AVFoundation
import CoreVideo
let output = URL(fileURLWithPath: "/tmp/Cloakmark-Duo-Fixture.mp4")
try? FileManager.default.removeItem(at: output)
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 600, AVVideoHeightKey: 400])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 600, kCVPixelBufferHeightKey as String: 400, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
let source = NSImage(contentsOfFile: "/tmp/Cloakmark-Duo-Fixture.png")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
for frame in 0..<90 {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    let pixelBuffer = buffer!
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    context.draw(source, in: CGRect(x: 0, y: 0, width: 600, height: 400))
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    if !adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) { fatalError("append failed") }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print(writer.status.rawValue, writer.error as Any)
