import SwiftUI
import AVFoundation

struct VideoRegionControls: View {
    @ObservedObject var model: VideoEditorViewModel
    @State private var editing: VideoManualRegion?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("video.review.title").font(.headline)
            coverageBar(manual: false)
            coverageBar(manual: true)
            Slider(value: Binding(get: { model.reviewSeconds }, set: model.seekReview), in: 0...max(0.001, model.video.duration), onEditingChanged: model.reviewScrubbingChanged)
                .accessibilityLabel(Text("video.review.time"))
            Text(String(format: NSLocalizedString("video.review.coverage", comment: ""), model.reviewSeconds, model.automaticCoverage, model.manualCoverage))
                .font(.caption).monospacedDigit()
            ForEach(model.manualRegions) { region in
                HStack {
                    Button {
                        editing = region
                        model.seekReview(region.start)
                    } label: {
                        Text(String(format: NSLocalizedString("video.manual.interval", comment: ""), region.start, region.end))
                    }
                    Spacer()
                    Button(role: .destructive) { model.removeRegion(region.id) } label: { Image(systemName: "trash") }
                        .accessibilityLabel(Text("video.manual.remove"))
                }
            }
            if !model.trackIDs.isEmpty {
                Text("video.group.title").font(.headline)
                Text("video.group.hint").font(.caption)
                ForEach(model.trackIDs, id: \.self) { id in
                    Toggle(isOn: Binding(get: { model.selectedTrackIDs.contains(id) }, set: { selected in
                        if selected {
                            model.selectedTrackIDs.insert(id)
                            if let range = model.trackRange(id) { model.seekReview(range.lowerBound) }
                        } else { model.selectedTrackIDs.remove(id) }
                    })) {
                        VStack(alignment: .leading) {
                            Text(String(format: NSLocalizedString("video.group.segment", comment: ""), id))
                            if let range = model.trackRange(id) {
                                Button(String(format: "%.3f–%.3f s", range.lowerBound, range.upperBound)) {
                                    model.selectedTrackIDs.insert(id)
                                    model.seekReview(range.lowerBound)
                                }
                                    .font(.caption)
                            }
                        }
                    }
                }
                Menu {
                    Button("video.effect.blur") { model.applyGroupEffect("blur") }
                    ForEach(VideoRedactionSticker.allCases) { sticker in
                        Button(sticker.displayName) { model.applyGroupEffect(sticker.rawValue) }
                    }
                } label: { Label("video.group.apply", systemImage: "person.2") }
                    .disabled(model.selectedTrackIDs.isEmpty)
                ForEach(model.groups) { group in
                    Text(group.trackIDs.map(String.init).joined(separator: ", ") + " · " + (VideoRedactionSticker(rawValue: group.effect)?.displayName ?? NSLocalizedString("video.effect.blur", comment: "")))
                        .font(.caption)
                }
            }
        }
        .sheet(item: $editing) { region in
            VideoManualRegionEditor(model: model, region: region)
                .presentationDetents([.large])
        }
    }

    private func coverageBar(manual: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(manual ? "video.review.manual" : "video.review.automatic").font(.caption)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.secondary.opacity(0.12))
                    ForEach(Array(model.coverageIntervals(manual: manual).enumerated()), id: \.offset) { _, interval in
                        Rectangle().fill(manual ? Color.orange : Color.blue)
                            .frame(width: max(1, geometry.size.width * (interval.upperBound - interval.lowerBound) / max(0.001, model.video.duration)))
                            .offset(x: geometry.size.width * interval.lowerBound / max(0.001, model.video.duration))
                    }
                    Rectangle().fill(Color.primary).frame(width: 2)
                        .offset(x: geometry.size.width * model.reviewSeconds / max(0.001, model.video.duration))
                }
            }.frame(height: 8)
        }
    }
}

struct VideoSelectedTracksOverlay: View {
    @ObservedObject var model: VideoEditorViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            GeometryReader { geometry in
                ForEach(model.highlightedTracks(at: model.player.currentTime().seconds), id: \.id) { track in
                    let rect = track.rect
                    Rectangle().stroke(.yellow, lineWidth: 3)
                        .overlay(alignment: .topLeading) {
                            Text("#\(track.id)").font(.caption.bold()).foregroundStyle(.black)
                                .padding(3).background(.yellow)
                        }
                        .frame(width: rect.width * geometry.size.width, height: rect.height * geometry.size.height)
                        .position(x: rect.midX * geometry.size.width, y: (1 - rect.midY) * geometry.size.height)
                }
            }
        }.allowsHitTesting(false)
    }
}
