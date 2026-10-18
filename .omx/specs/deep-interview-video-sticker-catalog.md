# Video Sticker Catalog Spec

- Profile: quick
- Context: brownfield
- Final ambiguity: 0.18 (threshold 0.30)
- Context snapshot: `.omx/context/video-sticker-catalog-20260823T093554Z.md`

## Intent and outcome

Make video face-cover stickers more attractive while monetizing variety through the existing one-time Premium purchase.

## In scope

- Keep orange smiley and blue smiley free.
- Make every other existing and new sticker Premium-only.
- Add a cohesive set of open-source Twemoji graphics stored locally in the asset catalog.
- Show actual artwork and a lock cue in the picker.
- Open `PremiumView` when a free user taps a Premium sticker; apply the requested sticker only after entitlement succeeds.
- Preserve opaque face coverage in preview and export.
- Add attribution and targeted tests.

## Non-goals

- No new SKU, subscription, backend, network fetch, export quota change, or broader Premium redesign.

## Acceptance criteria

1. `orangeSmiley` and `blueSmiley` report free access; every other case reports Premium access.
2. A non-entitled user cannot select a Premium sticker and sees the purchase sheet instead.
3. An entitled user can select every sticker; a successful purchase resumes the pending sticker selection without exporting unexpectedly.
4. Picker cards use the real sticker artwork for imported stickers, include a lock badge when locked, and expose the locked state to VoiceOver.
5. For every sticker, all integer pixels in the standardized covered face rectangle are independent of the source image, and pixels outside are unchanged.
6. All assets are bundled for offline use and Twemoji CC-BY-4.0 attribution is recorded.

## Assumption resolution

Transparent upstream art is wrapped in an opaque renderer background to preserve the app's privacy invariant. Existing export paywall behavior remains separate from sticker-unlock behavior.
