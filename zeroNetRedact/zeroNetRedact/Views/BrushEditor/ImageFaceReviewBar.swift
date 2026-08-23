import SwiftUI

struct ImageFaceReviewBar: View {
    let selectedCount: Int
    let totalCount: Int
    let selectedSticker: FaceRedactionSticker
    let hasUnlimitedAccess: Bool
    let onSelectSticker: (FaceRedactionSticker) -> Void
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("image.face.review.title", comment: ""))
                        .font(.headline)
                    Text(
                        String(
                            format: NSLocalizedString("image.face.review.count", comment: ""),
                            selectedCount,
                            totalCount
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(NSLocalizedString("image.face.review.selectAll", comment: ""), action: onSelectAll)
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
                Button(NSLocalizedString("image.face.review.selectNone", comment: ""), action: onDeselectAll)
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FaceRedactionSticker.allCases) { sticker in
                        stickerButton(sticker)
                    }
                }
                .padding(.horizontal, 1)
            }

            Label(
                NSLocalizedString("image.face.review.warning", comment: ""),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(NSLocalizedString("common.cancel", comment: ""), action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)

                Button(action: onApply) {
                    Text(
                        String(
                            format: NSLocalizedString("image.face.review.apply", comment: ""),
                            selectedCount
                        )
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(selectedCount == 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func stickerButton(_ sticker: FaceRedactionSticker) -> some View {
        let selected = sticker == selectedSticker
        let locked = sticker.isLocked(hasUnlimitedAccess: hasUnlimitedAccess)
        return Button {
            onSelectSticker(sticker)
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    artwork(sticker)
                        .frame(width: 36, height: 36)
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(.orange))
                    } else if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                    }
                }
                Text(sticker.displayName)
                    .font(.system(size: 9, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .frame(width: 66, height: 58)
            .background(selected ? Color.blue.opacity(0.12) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.blue : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sticker.displayName)
        .accessibilityValue(sticker.accessibilityValue(hasUnlimitedAccess: hasUnlimitedAccess))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func artwork(_ sticker: FaceRedactionSticker) -> some View {
        switch sticker.artwork {
        case .systemImage(let name):
            Image(systemName: name)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(sticker == .orangeSmiley ? Color.orange : Color.blue)
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
        }
    }
}
