//
//  mupdf_redact.h
//  ZeroNet Redact
//
//  MuPDF 真删除 C 桥接接口（AGPL-3.0，见 THIRD_PARTY_NOTICES.md）
//

#ifndef mupdf_redact_h
#define mupdf_redact_h

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * 对 PDF 内容流应用真删除（Redaction）：遮盖区域内的文字被物理移除。
 *
 * regions 为平坦数组，每区域 5 个 float：pageIndex, x0, y0, x1, y1。
 * 坐标空间与 PDFKit 的页面空间（PDFAnnotation.bounds / PDFSelection.bounds）
 * 相同：即 PDF user space（左下原点、y 向上、未旋转）。矩形直接写入
 * redaction 注释的 /Rect 字典，过滤器在同空间比较，无需任何转换。
 *
 * 成功：返回 0，*out_data 指向 malloc 分配的结果（用 mupdf_free 释放），
 *       *out_len 为字节数。
 * 失败：返回非 0，error_buf 填充以 NUL 结尾的错误消息（可能为空）。
 */
int mupdf_redact_pdf(
    const unsigned char *input_data, size_t input_len,
    const float *regions, size_t region_count,
    unsigned char **out_data, size_t *out_len,
    char *error_buf, size_t error_buf_size);

void mupdf_free(void *ptr);

#ifdef __cplusplus
}
#endif

#endif /* mupdf_redact_h */
