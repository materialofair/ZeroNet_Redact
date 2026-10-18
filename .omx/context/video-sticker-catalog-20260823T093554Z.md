# Video Sticker Catalog Context

- Activation prompt: add attractive open-source stickers to video redaction; orange and blue smileys are free, every other sticker requires Premium.
- Status: activation-prompt.
- Desired outcome: a visually richer, privacy-safe sticker picker with deterministic free/Premium access rules.
- Known facts: `VideoRedactionSticker` currently has five programmatically drawn cases; `VideoEditorView` selects them directly; `AppState.shared.hasUnlimitedAccess` is the existing entitlement source; `PremiumView` is the existing purchase UI; rendering must remain fully offline and opaque.
- External evidence: Twemoji graphics are available from `jdecked/twemoji` under CC-BY-4.0 and require attribution.
- Constraints: iOS 17+, SwiftUI, no runtime network dependency, preserve unrelated dirty Xcode user-state files, do not weaken export quota checks.
- Decision boundaries: choose a small cohesive set of face-covering emoji, asset naming, card presentation, and targeted tests without further confirmation.
- Non-goals: new StoreKit products, subscriptions, server-side entitlement, changing video export limits, or replacing the app-wide Premium purchase model.
- Likely touchpoints: `BusinessLogic/Video/VideoModels.swift`, `VideoRedactionRenderer.swift`, `Views/Video/VideoEditorView.swift`, `VideoEditorViewModel.swift`, localized strings, asset catalog, renderer/model tests, and `THIRD_PARTY_NOTICES.md`.
- Prompt-safe initial-context summary: not_needed.
- Repo guidance inspected: global `AGENTS.md`, `readme.md`, `PRODUCT.md`, existing video source/tests, localization, and third-party notices.

