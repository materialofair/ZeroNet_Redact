import SwiftUI

private struct SelectableOCRRegion: Identifiable {
    let id = UUID()
    var boundingBox: CGRect
    let text: String
}

enum TextSelectionGeometry {
    static func screenRect(_ normalized: CGRect, size: CGSize) -> CGRect {
        CGRect(x: normalized.minX * size.width, y: (1 - normalized.maxY) * size.height,
               width: normalized.width * size.width, height: normalized.height * size.height)
    }

    static func resized(_ rect: CGRect, corner: Int, to point: CGPoint) -> CGRect {
        let x = min(1, max(0, point.x)), y = min(1, max(0, point.y))
        let minX = corner == 0 ? min(x, max(0, rect.maxX - 0.005)) : rect.minX
        let maxX = corner == 0 ? rect.maxX : max(x, min(1, rect.minX + 0.005))
        let minY = corner == 0 ? rect.minY : min(y, max(0, rect.maxY - 0.005))
        let maxY = corner == 0 ? max(y, min(1, rect.minY + 0.005)) : rect.maxY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func intersects(_ rect: CGRect, from start: CGPoint, to end: CGPoint) -> Bool {
        var lower: CGFloat = 0, upper: CGFloat = 1
        let dx = end.x - start.x, dy = end.y - start.y
        for (p, q) in [(-dx, start.x - rect.minX), (dx, rect.maxX - start.x),
                       (-dy, start.y - rect.minY), (dy, rect.maxY - start.y)] {
            if p == 0 { if q < 0 { return false }; continue }
            let ratio = q / p
            if p < 0 { lower = max(lower, ratio) } else { upper = min(upper, ratio) }
            if lower > upper { return false }
        }
        return true
    }
}

struct OCRTextSelectionView: View {
    let image: UIImage
    let onApply: ([CGRect]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var regions: [SelectableOCRRegion] = []
    @State private var selected = Set<UUID>()
    @State private var activeID: UUID?
    @State private var cursor: CGPoint?
    @State private var previous: CGPoint?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("textSelection.hint").font(.caption).padding(.horizontal)
                if loading { ProgressView("search.recognizing") }
                if let error { Text(error).foregroundStyle(.red) }
                GeometryReader { geometry in
                    let size = CoordinateConverter.calculateDisplaySize(for: image.size, in: geometry.size)
                    ZStack {
                        Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                        ForEach(regions) { region in
                            let rect = TextSelectionGeometry.screenRect(region.boundingBox, size: size)
                            Rectangle().fill(selected.contains(region.id) ? Color.orange.opacity(0.35) : .clear)
                                .overlay(Rectangle().stroke(selected.contains(region.id) ? .orange : .blue.opacity(0.4), lineWidth: 1))
                                .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                                .allowsHitTesting(false)
                        }
                        if previous == nil, let id = activeID, selected.contains(id), let index = regions.firstIndex(where: { $0.id == id }) {
                            let rect = TextSelectionGeometry.screenRect(regions[index].boundingBox, size: size)
                            ForEach(0..<2) { corner in
                                Circle().fill(.orange).frame(width: 14, height: 14)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                                    .position(x: corner == 0 ? rect.minX : rect.maxX, y: corner == 0 ? rect.minY : rect.maxY)
                                    .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("textCanvas"))
                                        .onChanged { value in
                                            guard size.width > 0, size.height > 0 else { return }
                                            cursor = value.location
                                            regions[index].boundingBox = TextSelectionGeometry.resized(regions[index].boundingBox, corner: corner,
                                                to: CGPoint(x: value.location.x / size.width, y: 1 - value.location.y / size.height))
                                        }.onEnded { _ in cursor = nil })
                                    .accessibilityLabel(Text(corner == 0 ? "textSelection.topLeft" : "textSelection.bottomRight"))
                            }
                        }
                        if let cursor {
                            Image(uiImage: image).resizable().frame(width: size.width * 2, height: size.height * 2)
                                .offset(x: size.width - cursor.x * 2, y: size.height - cursor.y * 2)
                                .frame(width: 110, height: 110).clipShape(Circle())
                                .overlay(Circle().stroke(.orange, lineWidth: 3))
                                .position(x: min(max(55, cursor.x), max(55, size.width - 55)), y: cursor.y > 130 ? cursor.y - 75 : min(size.height - 55, cursor.y + 75))
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .coordinateSpace(name: "textCanvas")
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("textCanvas"))
                        .onChanged { value in
                            guard !loading else { return }
                            cursor = value.location
                            for region in regions where TextSelectionGeometry.intersects(TextSelectionGeometry.screenRect(region.boundingBox, size: size), from: previous ?? value.startLocation, to: value.location) {
                                selected.insert(region.id); activeID = region.id
                            }
                            previous = value.location
                        }.onEnded { value in
                            // A fast or coalesced drag may deliver its final position only here.
                            for region in regions where TextSelectionGeometry.intersects(TextSelectionGeometry.screenRect(region.boundingBox, size: size), from: previous ?? value.startLocation, to: value.location) {
                                selected.insert(region.id); activeID = region.id
                            }
                            cursor = nil; previous = nil
                        })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack {
                    Button("textSelection.clear") { selected.removeAll(); activeID = nil }
                    Spacer()
                    Button("search.applySelected") {
                        onApply(regions.filter { selected.contains($0.id) }.map(\.boundingBox)); dismiss()
                    }.buttonStyle(.borderedProminent).disabled(selected.isEmpty)
                }.padding()
                DisclosureGroup("textSelection.list") {
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(regions) { region in
                                Toggle(region.text, isOn: Binding(get: { selected.contains(region.id) }, set: {
                                    if $0 { selected.insert(region.id); activeID = region.id }
                                    else { selected.remove(region.id) }
                                })).padding(.horizontal)
                            }
                        }
                    }.frame(maxHeight: 160)
                }.padding(.horizontal)
            }
            .navigationTitle("textSelection.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } } }
            .task {
                defer { loading = false }
                do {
                    guard let data = image.pngData() else { throw CocoaError(.fileReadCorruptFile) }
                    let texts = try await ImageOCRRecognizer().recognizeText(in: data, fileType: .image)
                    try Task.checkCancellation()
                    regions = texts.flatMap { text in
                        var matches: [SelectableOCRRegion] = []
                        text.text.enumerateSubstrings(in: text.text.startIndex..<text.text.endIndex, options: .byWords) { word, range, _, _ in
                            guard let word else { return }
                            let box = (text.substringBox?(NSRange(range, in: text.text)) ?? text.boundingBox)
                                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                            guard !box.isNull, box.width > 0, box.height > 0 else { return }
                            matches.append(SelectableOCRRegion(boundingBox: box, text: word))
                        }
                        return matches
                    }
                } catch is CancellationError { } catch { self.error = error.localizedDescription }
            }
        }
    }
}
