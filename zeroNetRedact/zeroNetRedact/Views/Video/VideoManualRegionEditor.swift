import AVKit
import SwiftUI

/// Edits a local proposal; only Save changes the redaction timeline.
struct VideoManualRegionEditor: View {
    @ObservedObject var model: VideoEditorViewModel
    let region: VideoManualRegion
    @Environment(\.dismiss) private var dismiss
    @State private var rect: CGRect
    @State private var start: Double
    @State private var end: Double
    @State private var effect: String
    @State private var preset: Int
    @State private var seconds: Double
    @State private var player = AVPlayer()
    @State private var moveOrigin: CGRect?
    @State private var resizeOrigin: CGRect?
    private let entrySeconds: Double

    init(model: VideoEditorViewModel, region: VideoManualRegion) {
        self.model = model
        self.region = region
        _rect = State(initialValue: region.rect)
        _start = State(initialValue: region.start)
        _end = State(initialValue: region.end)
        _effect = State(initialValue: region.effect)
        _preset = State(initialValue: region.start == 0 && region.end == model.video.duration ? 0 : 2)
        let current = model.player.currentTime().seconds
        let time = min(max(0, current.isFinite ? current : 0), max(0, model.video.duration - 0.001))
        entrySeconds = time
        _seconds = State(initialValue: time)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 12) {
                    Text("video.manual.positionHint").font(.subheadline)
                        .padding(.horizontal)
                    canvas.frame(height: max(130, min(360, geometry.size.height * 0.44)))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("video.manual.sourceHint").font(.caption).foregroundStyle(.secondary)
                            Text("video.manual.size").font(.headline)
                            HStack {
                                Text("video.manual.width")
                                Slider(value: Binding(get: { rect.width }, set: {
                                    rect = VideoRegionGeometry.resized(rect, width: $0, height: rect.height)
                                }), in: 0.05...1).accessibilityLabel(Text("video.manual.width"))
                            }
                            HStack {
                                Text("video.manual.height")
                                Slider(value: Binding(get: { rect.height }, set: {
                                    rect = VideoRegionGeometry.resized(rect, width: rect.width, height: $0)
                                }), in: 0.05...1).accessibilityLabel(Text("video.manual.height"))
                            }
                            Text("video.manual.when").font(.headline)
                            Picker("video.manual.when", selection: $preset) {
                                Text("video.manual.whole").tag(0)
                                Text("video.manual.fromHere").tag(1)
                                Text("video.manual.custom").tag(2)
                            }.pickerStyle(.segmented)
                                .onChange(of: preset) { _, value in
                                    if value == 0 { start = 0; end = model.video.duration }
                                    if value == 1 { start = entrySeconds; end = model.video.duration }
                                }
                            if preset == 2 {
                                Text("video.manual.startLabel") + Text("  " + timeLabel(start))
                                Slider(value: Binding(get: { start }, set: { start = $0; seek($0) }),
                                       in: 0...max(0, end - minimumInterval))
                                    .accessibilityLabel(Text("video.manual.startLabel"))
                                Text("video.manual.endLabel") + Text("  " + timeLabel(end))
                                Slider(value: Binding(get: { end }, set: { end = $0; seek(max(start, $0 - minimumInterval)) }),
                                       in: min(model.video.duration, start + minimumInterval)...model.video.duration)
                                    .accessibilityLabel(Text("video.manual.endLabel"))
                            }
                            Text(timeLabel(start) + " – " + timeLabel(end)).monospacedDigit().font(.caption)
                            Text("video.manual.checkFrame").font(.headline)
                            Slider(value: Binding(get: { seconds }, set: seek), in: 0...max(0.001, model.video.duration))
                                .accessibilityLabel(Text("video.manual.checkFrame"))
                            Text(timeLabel(seconds)).monospacedDigit().font(.caption)
                            Text("video.manual.fixedHint").font(.footnote).foregroundStyle(.secondary)
                            Picker("video.effect.title", selection: $effect) {
                                Text("video.effect.blur").tag("blur")
                                ForEach(VideoRedactionSticker.allCases.filter {
                                    !$0.isLocked(hasUnlimitedAccess: AppState.shared.hasUnlimitedAccess)
                                }) { sticker in
                                    Text(sticker.displayName).tag(sticker.rawValue)
                                }
                            }
                        }.padding(.horizontal).padding(.bottom)
                    }
                }
            }
            .navigationTitle("video.manual.positionTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("video.manual.done") {
                        if model.saveRegion(rect: rect, start: start, end: end, replacing: region.id, effect: effect) {
                            model.seekReview(start)
                            dismiss()
                        }
                    }.fontWeight(.semibold)
                    .accessibilityIdentifier("video.manual.save")
                }
            }
            .onAppear {
                model.player.pause()
                // Sheet state can survive dismissal. Recreate the source item on every presentation.
                player.isMuted = true
                if let asset = model.player.currentItem?.asset {
                    player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                }
                seek(seconds)
            }
            .onDisappear { player.pause(); player.replaceCurrentItem(with: nil) }
        }
    }

    private var minimumInterval: Double { min(0.01, model.video.duration / 2) }

    private func timeLabel(_ value: Double) -> String {
        String(format: "%02d:%05.2f", Int(value) / 60, value.truncatingRemainder(dividingBy: 60))
    }

    private func seek(_ value: Double) {
        seconds = value
        player.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let aspect = CGFloat(max(1, model.video.width)) / CGFloat(max(1, model.video.height))
            let width = min(geometry.size.width, geometry.size.height * aspect)
            let size = CGSize(width: width, height: width / aspect)
            ZStack {
                VideoPlayer(player: player).allowsHitTesting(false)
                Color.clear.contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        rect = VideoRegionGeometry.centered(rect, at: CGPoint(x: value.location.x / size.width, y: 1 - value.location.y / size.height))
                    })
                Rectangle().fill(.orange.opacity(0.45))
                    .overlay(Rectangle().stroke(.orange, lineWidth: 3))
                    .frame(width: rect.width * size.width, height: rect.height * size.height)
                    .position(x: rect.midX * size.width, y: (1 - rect.midY) * size.height)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("manualCanvas"))
                        .onChanged { value in
                            if moveOrigin == nil { moveOrigin = rect }
                            move(value.translation, size: size)
                        }
                        .onEnded { value in move(value.translation, size: size); moveOrigin = nil })
                    .accessibilityLabel(Text("video.manual.positionHint"))
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 32, height: 32).background(.orange, in: Circle())
                    .frame(width: 48, height: 48).contentShape(Rectangle())
                    .position(x: rect.maxX * size.width, y: (1 - rect.minY) * size.height)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("manualCanvas"))
                        .onChanged { value in
                            if resizeOrigin == nil { resizeOrigin = rect }
                            resize(value.translation, size: size)
                        }
                        .onEnded { value in resize(value.translation, size: size); resizeOrigin = nil })
                    .accessibilityLabel(Text("video.manual.size"))
            }
            .coordinateSpace(name: "manualCanvas")
            .frame(width: size.width, height: size.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }.background(.black)
    }

    private func move(_ translation: CGSize, size: CGSize) {
        guard let origin = moveOrigin else { return }
        rect = VideoRegionGeometry.centered(origin, at: CGPoint(x: origin.midX + translation.width / size.width, y: origin.midY - translation.height / size.height))
    }

    private func resize(_ translation: CGSize, size: CGSize) {
        guard let origin = resizeOrigin else { return }
        let width = min(1 - origin.minX, max(0.05, origin.width + translation.width / size.width))
        let height = min(origin.maxY, max(0.05, origin.height + translation.height / size.height))
        rect = CGRect(x: origin.minX, y: origin.maxY - height, width: width, height: height)
    }
}

enum VideoRegionGeometry {
    static func centered(_ rect: CGRect, at point: CGPoint) -> CGRect {
        CGRect(x: min(1 - rect.width, max(0, point.x - rect.width / 2)),
               y: min(1 - rect.height, max(0, point.y - rect.height / 2)),
               width: rect.width, height: rect.height)
    }

    static func resized(_ rect: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        let size = CGRect(x: 0, y: 0, width: min(1, max(0.05, width)), height: min(1, max(0.05, height)))
        return centered(size, at: CGPoint(x: rect.midX, y: rect.midY))
    }
}
