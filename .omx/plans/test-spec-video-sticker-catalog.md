# Test Spec — Video Sticker Catalog

- Policy: exactly two free cases and they are orange/blue smileys; all remaining cases require Premium.
- Asset integrity: every imported sticker names a bundled `UIImage` asset and matches the pinned-file checksum manifest.
- Rendering: standardize the face rectangle to its clipped integral pixel bounds; render every case over two different opaque sources, compare every integer pixel in that covered rect for exact source-independence, and verify pixels outside the rect are preserved exactly, including fractional normalized input rectangles.
- Selection: test a pure entitlement/intent state seam. Locked selection is rejected without entitlement and retained as a sticker Premium intent; free selection succeeds; successful entitlement applies the pending sticker without export retry; export Premium intent still retries export; unauthorized Premium-sticker export visibly reopens the sticker paywall.
- Presentation: pure policy assertions cover asset-vs-programmatic artwork, lock visibility for free/Premium entitlement, localized Premium accessibility value/hint, and the Premium feature-list copy; perform the documented Simulator smoke acceptance for actual SwiftUI wiring.
- Build: compile the application target for an available iOS Simulator destination.
- Adversarial checks: repeated locked taps replace the pending choice deterministically; dismiss without purchase keeps the free selection; sticker intent never triggers export; export intent never mutates sticker selection; imported transparent art cannot expose underlying pixels anywhere in the covered rectangle.
