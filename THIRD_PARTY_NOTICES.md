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
