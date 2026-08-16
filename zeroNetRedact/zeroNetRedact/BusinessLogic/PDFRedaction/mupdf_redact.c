//
//  mupdf_redact.c
//  ZeroNet Redact
//
//  MuPDF 真删除实现：fz_try/fz_catch 是宏，必须在 C 中完成异常处理。
//

#include "mupdf_redact.h"

#include <mupdf/fitz.h>
#include <mupdf/pdf.h>

#include <stdlib.h>
#include <string.h>

static void set_error(char *buf, size_t size, const char *msg)
{
    if (buf == NULL || size == 0)
        return;
    strncpy(buf, msg ? msg : "unknown error", size - 1);
    buf[size - 1] = '\0';
}

int mupdf_redact_pdf(
    const unsigned char *input_data, size_t input_len,
    const float *regions, size_t region_count,
    unsigned char **out_data, size_t *out_len,
    char *error_buf, size_t error_buf_size)
{
    fz_context *ctx = NULL;
    int result = 0;
    size_t i;

    *out_data = NULL;
    *out_len = 0;

    if (input_data == NULL || out_data == NULL || out_len == NULL ||
        (region_count > 0 && regions == NULL)) {
        set_error(error_buf, error_buf_size, "invalid arguments");
        return 1;
    }

    ctx = fz_new_context(NULL, NULL, FZ_STORE_UNLIMITED);
    if (ctx == NULL) {
        set_error(error_buf, error_buf_size, "failed to create MuPDF context");
        return 1;
    }

    fz_try(ctx)
    {
        fz_stream *stream = NULL;
        pdf_document *doc = NULL;
        fz_buffer *buf = NULL;
        fz_output *out = NULL;
        pdf_page *page = NULL;

        fz_var(stream);
        fz_var(doc);
        fz_var(buf);
        fz_var(out);
        fz_var(page);

        fz_register_document_handlers(ctx);

        stream = fz_open_memory(ctx, input_data, input_len);
        doc = pdf_open_document_with_stream(ctx, stream);

        /* 区域按页分组处理：同一页只加载一次（页面由文档持有，无需逐个释放） */
        int last_page = -1;
        for (i = 0; i < region_count; i++) {
            int page_index = (int)regions[i * 5 + 0];
            float x0 = regions[i * 5 + 1];
            float y0 = regions[i * 5 + 2];
            float x1 = regions[i * 5 + 3];
            float y1 = regions[i * 5 + 4];
            pdf_annot *annot = NULL;

            if (page_index < 0 || page_index >= pdf_count_pages(ctx, doc)) {
                fz_throw(ctx, FZ_ERROR_ARGUMENT, "redaction page index out of range: %d", page_index);
            }
            if (page_index != last_page) {
                page = pdf_load_page(ctx, doc, page_index);
                last_page = page_index;
            }

            annot = pdf_create_annot(ctx, page, PDF_ANNOT_REDACT);

            /*
             * 输入的矩形位于 PDFKit 页面空间（＝PDF user space：左下原点、
             * y 向上、未旋转）。pdf_set_annot_rect 会把 fitz 显示空间矩形经
             * inv_page_ctm 转回 user space 存入 /Rect；因此这里先用同一个
             * pdf_page_transform 取 page_ctm 把矩形转到 fitz 空间，两者互为
             * 逆变换，净效果即 /Rect 直接等于输入矩形——旋转页、UserUnit、
             * CropBox 偏移都自动成立。
             */
            {
                fz_matrix page_ctm;
                fz_rect user_rect = fz_make_rect(x0, y0, x1, y1);
                pdf_page_transform(ctx, page, NULL, &page_ctm);
                pdf_set_annot_rect(ctx, annot, fz_transform_rect(user_rect, page_ctm));
            }

            /*
             * black_boxes=0：不画黑框（视觉覆盖由 PDFKit 方形注释层负责，
             *   与编辑器所见完全一致）。
             * image_method=PIXELS：扫描件只清除遮盖区域像素，避免整图被移除。
             * line_art=NONE：矢量线稿不动（不可提取为文本，且被覆盖层遮挡）。
             * text=REMOVE：文字物理删除（安全默认）。
             */
            pdf_redact_options opts = { 0 };
            opts.black_boxes = 0;
            opts.image_method = PDF_REDACT_IMAGE_PIXELS;
            opts.line_art = PDF_REDACT_LINE_ART_NONE;
            opts.text = PDF_REDACT_TEXT_REMOVE;

            if (!pdf_apply_redaction(ctx, annot, &opts))
                fz_throw(ctx, FZ_ERROR_GENERIC, "failed to apply redaction on page %d", page_index);
        }

        pdf_write_options wopts = pdf_default_write_options;
        wopts.do_garbage = 1;
        wopts.do_incremental = 0;

        buf = fz_new_buffer(ctx, 4096);
        out = fz_new_output_with_buffer(ctx, buf);
        pdf_write_document(ctx, doc, out, &wopts);
        fz_close_output(ctx, out);

        unsigned char *data = NULL;
        size_t len = fz_buffer_storage(ctx, buf, &data);

        /* 之后的步骤不再允许 fz 异常（malloc 失败走普通错误路径） */
        unsigned char *copy = (unsigned char *)malloc(len > 0 ? len : 1);
        if (copy == NULL) {
            set_error(error_buf, error_buf_size, "out of memory copying redacted PDF");
            result = 1;
        } else {
            if (len > 0)
                memcpy(copy, data, len);
            *out_data = copy;
            *out_len = len;
        }

        fz_drop_output(ctx, out);
        fz_drop_buffer(ctx, buf);
        pdf_drop_document(ctx, doc);
        fz_drop_stream(ctx, stream);
    }
    fz_catch(ctx)
    {
        set_error(error_buf, error_buf_size, fz_caught_message(ctx));
        result = 1;
    }

    fz_drop_context(ctx);
    return result;
}

void mupdf_free(void *ptr)
{
    free(ptr);
}
