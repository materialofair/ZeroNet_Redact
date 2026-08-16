# MuPDF 集成说明

ZeroNet Redact 使用 [MuPDF](https://github.com/ArtifexSoftware/mupdf)（AGPL-3.0）在
PDF 导出时执行**真删除（Redaction）**：遮盖区域内的文字从内容流中被物理移除，导出后
无法被选中或提取；页面其余文字保持矢量、可选。视觉上的效果覆盖层仍由 PDFKit
方形注释绘制，与编辑器中所见完全一致。

## 架构

```
PDFRedactionEditor.exportRedactedFile()
  ├─ 从页面注释收集遮盖区域（PDFKit annotation.bounds，显示空间坐标）
  ├─ 干净底稿 = 原始 PDF 数据 + 元数据清理（PDFKit）
  ├─ MuPDFRedactor.redact()（Swift 封装，后台线程）
  │     └─ mupdf_redact_pdf()（C 桥接，fz_try/fz_catch 必须位于 C 中）
  │           ├─ pdf_create_annot(PDF_ANNOT_REDACT) + pdf_set_annot_rect
  │           └─ pdf_apply_redaction（opts: black_boxes=0, image=PIXELS,
  │               line_art=NONE, text=REMOVE）
  ├─ 失败时兜底：退回旧的视觉遮盖导出 + 用户警告
  └─ 重新叠加效果覆盖层 → 最终 PDF
```

## 坐标约定

PDFKit 的页面空间（`PDFAnnotation.bounds`、`PDFSelection.bounds`）即 PDF user
space：左下原点、y 向上、未旋转。MuPDF 侧通过公开 API
`pdf_page_transform` 取同一变换矩阵（fitz 显示空间 ↔ user space），先把输入矩形
转到 fitz 空间再交给 `pdf_set_annot_rect`（其内部用逆变换写回 `/Rect`）——两者
互为逆变换，净效果是 `/Rect` 直接等于 PDFKit 给的矩形，旋转页、UserUnit、CropBox
偏移都自动成立。旋转页行为由单元测试
`testRedactOnRotatedPageUsingPDFKitCoordinates` 覆盖。

## 构建

静态库**从源码**构建（仓库不含预编译产物）：

```sh
# 1. 初始化子模块（含 MuPDF 的嵌套第三方库）
git submodule update --init --recursive --depth 1

# 2. 构建三个架构并合成（真机 arm64；模拟器 arm64 + x86_64）
scripts/build-mupdf.sh          # 产物已存在时跳过；--force 强制重建
```

产物输出到 `third_party/mupdf-build/`（已在 .gitignore 中）：

- `lib/iphoneos/libmupdf.a`、`lib/iphoneos/libmupdf-third.a`
- `lib/iphonesimulator/libmupdf.a`、`lib/iphonesimulator/libmupdf-third.a`
- `include/mupdf/...`

Xcode 工程通过 `OTHER_LDFLAGS`（`$(PLATFORM_NAME)` 选择真机/模拟器库）、
`HEADER_SEARCH_PATHS` 与 `SWIFT_OBJC_BRIDGING_HEADER` 链接；工程内有一个
"Build MuPDF (if needed)" 预构建脚本阶段，产物缺失时自动运行构建脚本。

MuPDF 子模块固定在 1.28.2（commit `fe374accd98a43174a328fa7980d7675e06d5b0d`），
`scripts/build-mupdf.sh` 会校验该版本，升级 MuPDF 时需同步更新脚本中的
`EXPECTED_SHA` 并重新验证冒烟测试。

## 许可

MuPDF 为 AGPL-3.0-or-later。App 自身代码保持 GPL-3.0；二进制与 MuPDF 链接后，
合并作品按 AGPL-3.0 条款分发（GPLv3 §13）。完整源码通过 git submodule 随仓库提供，
详见 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。
