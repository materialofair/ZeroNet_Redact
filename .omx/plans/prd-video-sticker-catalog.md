# PRD — Video Sticker Catalog

## Principles

- Privacy coverage is non-negotiable.
- Entitlement policy has one source of truth on the sticker model.
- Assets are local, attributed, and visually represented in the picker.
- The smallest integration reuses the current lifetime Premium entitlement.

## Decision drivers

1. Correct free/Premium boundary.
2. Opaque rendering in preview and export.
3. No runtime network dependency.

## Options considered

- Twemoji vector assets (chosen): cohesive artwork, maintained open-source repository, CC-BY-4.0 commercial use with attribution.
- Continue programmatic drawings: no new asset license, but does not satisfy the request for open-source sticker art and provides weaker visual quality.
- Remote sticker catalog: rejected because it conflicts with the product's offline promise and adds availability/privacy risk.

## Implementation plan

1. Extend the sticker model with imported asset metadata and `requiresPremium`; verify with policy tests.
2. Bundle selected Twemoji SVGs and record attribution; verify every named asset loads.
3. Standardize each normalized face rect to an integral pixel rect clipped to the integral source extent. Build an opaque `CIImage(color:)` background directly in that target rect, aspect-fit the SVG artwork inside it, clamp/crop artwork sampling to its own bounds, and composite the completed target sticker over the source. This makes every covered integer pixel independent of the source, including scale boundaries.
4. Make `sticker` externally read-only and route selection through a pure, testable selection state plus the view model. Model Premium sheet origin as an explicit sticker or export intent so dismissal only resumes the matching action; defensively route an unauthorized Premium-sticker export back to the sticker paywall with visible feedback rather than silently returning.
5. Centralize picker presentation metadata (`assetName`, artwork kind, `requiresPremium`, lock visibility, accessibility value) on the model and use it from the SwiftUI card. Add Premium sticker copy to `PremiumView` so sticker-origin purchases explain what is unlocked.
6. Update Chinese/English strings, About attribution, full notice, and run the exact verification commands below.

## Fixed catalog

All imported graphics are pinned to `jdecked/twemoji` v17.0.1, commit `196eef6169eccb902ae42a3c827034a22153a61a`.

| Case | Access | Asset | Code point | Treatment |
|---|---|---|---|---|
| orangeSmiley | Free | programmatic | — | orange opaque background |
| blueSmiley | Free | programmatic | — | blue opaque background |
| sunglasses | Premium | `StickerSunglasses` | `1f60e` | aspect-fit on opaque slate background |
| panda | Premium | `StickerPanda` | `1f43c` | aspect-fit on opaque warm-white background |
| alien | Premium | `StickerAlien` | `1f47d` | aspect-fit on opaque mint background |
| heartEyes | Premium | `StickerHeartEyes` | `1f60d` | aspect-fit on opaque rose background |
| robot | Premium | `StickerRobot` | `1f916` | aspect-fit on opaque steel background |
| clown | Premium | `StickerClown` | `1f921` | aspect-fit on opaque cream background |
| lion | Premium | `StickerLion` | `1f981` | aspect-fit on opaque amber background |

Each imported SVG must be downloaded from
`https://raw.githubusercontent.com/jdecked/twemoji/196eef6169eccb902ae42a3c827034a22153a61a/assets/svg/<codepoint>.svg`.
Asset integrity tests must load each `assetName`; a checksum manifest records each downloaded file so a mislabeled or drifted asset is detectable.

## UI and accessibility verification

- A pure presentation policy test asserts imported cases use asset artwork, only orange/blue are free, a free user sees locks on all seven Premium cards, and an entitled user sees no locks.
- Each locked card exposes localized “Premium sticker” accessibility value/hint; unlocked cards retain the normal selection hint.
- Simulator smoke acceptance: open a video editor, capture the horizontal picker showing imported artwork and at least one lock badge, tap a locked sticker and confirm the Premium feature list mentions Premium stickers, dismiss without purchase, and confirm the previous free sticker remains selected with no export started.

## ADR

- Decision: bundled Twemoji SVG assets plus a model-owned Premium flag and view-model selection coordinator.
- Consequences: seven Premium sticker cases gain high-quality artwork; the app must retain CC-BY-4.0 attribution; opaque padding is intentionally added around transparent art.
- Follow-up: add a compact Twemoji attribution entry to About and retain the full notice in `THIRD_PARTY_NOTICES.md`.

## Attribution fields

The notice and About legal entry identify “Twemoji graphics”, jdecked/Twemoji contributors, the pinned source repository and commit, CC-BY-4.0 with a license link, and the modification that transparent artwork is placed on app-created opaque backgrounds.

## Verification commands

From the repository root:

```bash
xcodebuild -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/zeronet-sticker-derived build
xcodebuild -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/zeronet-sticker-derived -only-testing:zeroNetRedactTests/VideoStickerPolicyTests -only-testing:zeroNetRedactTests/VideoRedactionRendererTests test
plutil -lint zeroNetRedact/zeroNetRedact/en.lproj/Localizable.strings zeroNetRedact/zeroNetRedact/zh-Hans.lproj/Localizable.strings
rg -n 'Twemoji|CC-BY-4.0|196eef6169eccb902ae42a3c827034a22153a61a' THIRD_PARTY_NOTICES.md
```
