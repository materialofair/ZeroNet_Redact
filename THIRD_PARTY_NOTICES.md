# Third-Party Notices

## MuPDF

- **Version**: 1.28.2 (commit `fe374accd98a43174a328fa7980d7675e06d5b0d`)
- **Upstream**: https://github.com/ArtifexSoftware/mupdf
- **License**: GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later)
- **Source**: vendored unmodified as a git submodule at `third_party/mupdf`
- **Usage**: physically removes covered text from PDF page content streams at export time (`BusinessLogic/PDFRedaction/MuPDFRedactor.swift`)

### License note

ZeroNet Redact's own source code is licensed under GPL-3.0. When the app
binary links MuPDF (AGPL-3.0), the combined work is distributed under the
terms of AGPL-3.0, per GPLv3 section 13. The complete, unmodified source of
MuPDF is available at the upstream URL above and via the git submodule
included with this repository.

### Build

The static library is built from source by `scripts/build-mupdf.sh` (no
prebuilt binaries are checked in). See `docs/MUPDF_INTEGRATION.md` for
details.

## Twemoji Graphics

- **Work**: Twemoji emoji graphics
- **Version**: v17.0.1 (commit `196eef6169eccb902ae42a3c827034a22153a61a`)
- **Authors**: jdecked/Twemoji contributors; derived from the original Twitter Twemoji project
- **Upstream**: https://github.com/jdecked/twemoji
- **License**: Creative Commons Attribution 4.0 International (CC-BY-4.0)
- **License text**: https://creativecommons.org/licenses/by/4.0/legalcode
- **Assets used**: `1f60e`, `1f43c`, `1f47d`, `1f60d`, `1f916`, `1f921`, and `1f981`
- **Usage and modifications**: bundled as vector artwork for video face-cover stickers. ZeroNet Redact places the original transparent graphics on app-created opaque colored backgrounds and scales them to fit the covered face rectangle so underlying video pixels cannot show through.

The pinned asset checksums are recorded in
`third_party/twemoji-stickers/SHA256SUMS`.
