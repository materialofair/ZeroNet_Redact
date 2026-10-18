# Video Sticker Catalog — Clarified Requirements

The user explicitly selected the commercial boundary: only orange smiley and blue smiley are free; all other stickers require the existing Premium entitlement. Repository evidence resolves the remaining implementation questions: use `AppState.shared.hasUnlimitedAccess`, present `PremiumView`, keep processing offline, and keep every rendered face-cover opaque.

Pressure check: transparent open-source emoji art would reveal portions of a face if composited directly. The implementation therefore places each imported graphic over a fully opaque, sticker-specific background before compositing. A Premium request must not overwrite the current selection until entitlement succeeds, and dismissing a sticker paywall must not trigger the unrelated export retry path.

No additional user decision is necessary because sticker count/style and internal asset organization were explicitly delegated by “帮我增加一些”.

