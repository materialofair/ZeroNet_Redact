import SwiftUI
import AVFoundation

struct VideoRegionControls: View {
    @ObservedObject var model: VideoEditorViewModel
    @State private var editing: VideoManualRegion?
    @State private var start = 0.0
    @State private var end = 1.0
    @State private var effect = "blur"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("video.review.title").font(.headline)
            coverageBar(manual: false)
            coverageBar(manual: true)
            Slider(value: Binding(get: { model.reviewSeconds }, set: model.seekReview), in: 0...max(0.001, model.video.duration), onEditingChanged: model.reviewScrubbingChanged)
                .accessibilityLabel(Text("video.review.time"))
            Text(String(format: NSLocalizedString("video.review.coverage", comment: ""), model.reviewSeconds, model.automaticCoverage, model.manualCoverage))
                .font(.caption).monospacedDigit()
            Button(model.drawingRegion ? "common.cancel" : "video.manual.draw") {
                model.player.pause()
                let seconds = model.player.currentTime().seconds
                if seconds.isFinite { model.reviewSeconds = min(model.video.duration, max(0, seconds)) }
                model.drawingRegion.toggle()
                model.redrawingManualRegion = nil
            }.buttonStyle(.bordered)
            if model.drawingRegion { Text(model.redrawingManualRegion == nil ? "video.manual.drawHint" : "video.manual.redrawHint").font(.caption) }
            ForEach(model.manualRegions) { region in
                HStack {
                    Button {
                        editing = region
                        start = region.start
                        end = region.end
                        effect = region.effect
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
        .onChange(of: model.pendingManualRegion?.id) { _, _ in
            if let region = model.pendingManualRegion {
                start = region.start
                end = region.end
                effect = region.effect
                editing = region
                model.pendingManualRegion = nil
            }
        }
        .sheet(item: $editing) { region in
            NavigationStack {
                Form {
                    Text("video.manual.halfOpen")
                    Button("video.manual.redraw") {
                        guard var candidate = VideoManualRegion(rect: region.rect, start: start, end: end, duration: model.video.duration) else { return }
                        candidate.id = region.id
                        candidate.effect = effect
                        model.beginRedrawing(candidate)
                        editing = nil
                    }.disabled(VideoManualRegion(rect: region.rect, start: start, end: end, duration: model.video.duration) == nil)
                    TextField("video.manual.start", value: $start, format: .number).keyboardType(.decimalPad)
                    TextField("video.manual.end", value: $end, format: .number).keyboardType(.decimalPad)
                    Picker("video.effect.title", selection: $effect) {
                        Text("video.effect.blur").tag("blur")
                        ForEach(VideoRedactionSticker.allCases.filter { !$0.isLocked(hasUnlimitedAccess: AppState.shared.hasUnlimitedAccess) }) { sticker in
                            Text(sticker.displayName).tag(sticker.rawValue)
                        }
                    }
                    Button("video.manual.save") {
                        if model.saveRegion(rect: region.rect, start: start, end: end, replacing: region.id, effect: effect) { editing = nil }
                    }.disabled(VideoManualRegion(rect: region.rect, start: start, end: end, duration: model.video.duration) == nil)
                }.navigationTitle(Text("video.manual.edit"))
                    .toolbar { Button("common.cancel") { editing = nil } }
            }.presentationDetents([.medium])
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

struct VideoRegionDrawingOverlay: View {
    @ObservedObject var model: VideoEditorViewModel
    @State private var origin: CGPoint?
    @State private var current: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Color.clear.contentShape(Rectangle())
                if let origin, let current {
                    let rect = CGRect(x: min(origin.x, current.x), y: min(origin.y, current.y), width: abs(current.x - origin.x), height: abs(current.y - origin.y))
                    Rectangle().fill(.orange.opacity(0.3)).overlay(Rectangle().stroke(.orange, lineWidth: 2))
                        .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                }
            }.gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    origin = value.startLocation
                    current = CGPoint(x: min(size.width, max(0, value.location.x)), y: min(size.height, max(0, value.location.y)))
                }
                .onEnded { _ in
                    defer { origin = nil; current = nil }
                    guard let origin, let current, size.width > 0, size.height > 0 else { return }
                    let rect = CGRect(x: min(origin.x, current.x) / size.width, y: 1 - max(origin.y, current.y) / size.height,
                                      width: abs(current.x - origin.x) / size.width, height: abs(current.y - origin.y) / size.height)
                    let start = min(model.reviewSeconds, max(0, model.video.duration - 0.001))
                    let candidate: VideoManualRegion?
                    if let existing = model.redrawingManualRegion {
                        candidate = existing.redrawing(rect: rect, duration: model.video.duration)
                    } else {
                        candidate = VideoManualRegion(rect: rect, start: start, end: model.video.duration, duration: model.video.duration)
                    }
                    if let region = candidate {
                        model.pendingManualRegion = region
                        model.drawingRegion = false
                        model.redrawingManualRegion = nil
                    }
                })
        }.accessibilityLabel(Text("video.manual.drawHint"))
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
