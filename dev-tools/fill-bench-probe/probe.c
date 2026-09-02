/* Compares three ways to fill a solid-color rect into the panel-sized
 * ARGB8888 surface: MI_GFX_QuickFill (hardware), fill_solid_c32 (the scalar
 * CPU loop MMIYOO_TryDirectSpanFill already used, sdl2_miyoo's own
 * comparison baseline), and fill_solid_n32 (a NEON kernel in
 * neon-arm-library-miyoo). No SDL2 -- raw MI_SYS/MI_GFX only,
 * mirroring downscale-bench-probe's shape. Rect sizes cover both a
 * triangle-span shape (narrow, a few rows tall) and a divider-line shape
 * (full/partial panel width, one row tall), matching the two places
 * MMIYOO_TryDirectSpanFill/MI_GFX_QuickFill actually get called from in the
 * real driver+overlay. */
#include <mi_sys.h>
#include <mi_gfx.h>
#include <neon.h>

#include <ft2build.h>
#include FT_FREETYPE_H

#include <fcntl.h>
#include <linux/fb.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define SYS_ALIGN 4096u
#define ALIGN_UP(v, a) (((v) + (a) - 1u) & ~((a) - 1u))
#define PANEL_W 640
#define PANEL_H 480
#define MAX_FENCES 64

/* HW_STRICT dispatches one MI_GFX_QuickFill and blocks on its fence before
 * the next -- a full hardware round-trip per call. HW_BATCHED dispatches
 * HW_BATCH fills back-to-back with no wait between them (matching the real
 * driver's GFX_AddTextureFence/deferred-flush pattern instead of the
 * artificially pessimistic per-call wait) and blocks once for the whole
 * batch, reporting the amortized per-op cost. Both are reported so neither
 * number is presented as the only truth. */
typedef enum { VARIANT_HW_STRICT = 0, VARIANT_HW_BATCHED, VARIANT_C, VARIANT_NEON, VARIANT_COUNT } Variant;
static const char *variant_name[VARIANT_COUNT] = { "hw_strict", "hw_batched", "c", "neon" };
#define HW_BATCH 20

typedef struct { int w, h; } RectSize;
static const RectSize g_sizes[] = {
    { 10, 1 }, { 50, 2 }, { 100, 3 }, { 197, 1 }, { 640, 1 },
    { 320, 240 }, { 640, 480 },
};
#define SIZE_COUNT (int)(sizeof(g_sizes) / sizeof(g_sizes[0]))

typedef struct {
    double min_us, max_us, sum_us;
    long count;
    long frames_completed;
    int aborted;
} Stats;

typedef struct {
    MI_PHY phy;
    void *vir;
    MI_U32 size;
} Buf;

static FILE *g_log;

static void ck(const char *fmt, ...)
{
    va_list ap;
    char line[512];
    va_start(ap, fmt);
    vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);
    if (g_log) {
        fprintf(g_log, "%s\n", line);
        fflush(g_log);
        fsync(fileno(g_log));
    }
    fprintf(stderr, "[fill-bench] %s\n", line);
}

static double now_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e6 + (double)ts.tv_nsec / 1e3;
}

static int alloc_buf(Buf *b, MI_U32 size)
{
    size = ALIGN_UP(size, SYS_ALIGN);
    if (MI_SYS_MMA_Alloc(NULL, size, &b->phy) != MI_SUCCESS) {
        ck("MI_SYS_MMA_Alloc FAILED size=%u", size);
        return -1;
    }
    if (MI_SYS_Mmap(b->phy, size, &b->vir, TRUE) != MI_SUCCESS) {
        ck("MI_SYS_Mmap FAILED phy=0x%llx size=%u", (unsigned long long)b->phy, size);
        MI_SYS_MMA_Free(b->phy);
        return -1;
    }
    b->size = size;
    return 0;
}

static void free_buf(Buf *b)
{
    if (b->vir) MI_SYS_Munmap(b->vir, b->size);
    if (b->phy) MI_SYS_MMA_Free(b->phy);
    memset(b, 0, sizeof(*b));
}

static void build_plain_opt(MI_GFX_Opt_t *opt, const MI_GFX_Rect_t *clip, MI_GFX_Rotate_e rotate)
{
    memset(opt, 0, sizeof(*opt));
    opt->eRotate = rotate;
    opt->eMirror = E_MI_GFX_MIRROR_NONE;
    opt->eDFBBlendFlag = E_MI_GFX_DFB_BLEND_NOFX;
    opt->eSrcDfbBldOp = E_MI_GFX_DFB_BLD_ONE;
    opt->eDstDfbBldOp = E_MI_GFX_DFB_BLD_ZERO;
    opt->stClipRect = *clip;
}

/* This panel is mounted upside down, same convention as downscale-bench-probe. */
#define SCREEN_ROTATE E_MI_GFX_ROTATE_180

static FT_Library g_ft;
static FT_Face g_face;
static int g_font_ok = 0;

static void font_init(const char *path, int pixel_size)
{
    if (FT_Init_FreeType(&g_ft) != 0) { ck("FT_Init_FreeType failed"); return; }
    if (FT_New_Face(g_ft, path, 0, &g_face) != 0) { ck("FT_New_Face failed for %s", path); return; }
    FT_Set_Pixel_Sizes(g_face, 0, (FT_UInt)pixel_size);
    g_font_ok = 1;
}

static void draw_text(void *vir, int buf_w, int buf_h, int stride, int x, int y, const char *text)
{
    if (!g_font_ok) return;
    int pen_x = x;
    int baseline_y = y + (int)(g_face->size->metrics.ascender >> 6);

    for (const unsigned char *p = (const unsigned char *)text; *p; p++) {
        if (FT_Load_Char(g_face, *p, FT_LOAD_RENDER) != 0) continue;
        FT_GlyphSlot slot = g_face->glyph;
        FT_Bitmap *bmp = &slot->bitmap;
        int gx = pen_x + slot->bitmap_left;
        int gy = baseline_y - slot->bitmap_top;

        for (unsigned int row = 0; row < bmp->rows; row++) {
            int py = gy + (int)row;
            if (py < 0 || py >= buf_h) continue;
            for (unsigned int col = 0; col < bmp->width; col++) {
                int px = gx + (int)col;
                if (px < 0 || px >= buf_w) continue;
                unsigned char coverage = bmp->buffer[row * (unsigned int)bmp->pitch + col];
                if (coverage < 96) continue;
                *(uint32_t *)((uint8_t *)vir + (size_t)py * stride + (size_t)px * 4) = 0xFFFFFFFFu;
            }
        }
        pen_x += (int)(slot->advance.x >> 6);
    }
}

static void update_stats(Stats *s, double us)
{
    if (s->count == 0 || us < s->min_us) s->min_us = us;
    if (s->count == 0 || us > s->max_us) s->max_us = us;
    s->sum_us += us;
    s->count++;
    s->frames_completed++;
}

int main(int argc, char *argv[])
{
    long frames_per_variant = (argc > 1) ? atol(argv[1]) : 500;
    const char *font_path = (argc > 2) ? argv[2] : "font.otf";
    Stats table[SIZE_COUNT][VARIANT_COUNT];
    memset(table, 0, sizeof(table));

    remove("probe.log");
    g_log = fopen("probe.log", "a");
    ck("start, frames_per_variant=%ld font=%s", frames_per_variant, font_path);

    font_init(font_path, 18);
    if (!g_font_ok) ck("WARNING: on-screen text disabled, font failed to load");

    if (MI_SYS_Init() != MI_SUCCESS) { ck("MI_SYS_Init FAILED"); return 1; }
    ck("MI_SYS_Init ok");
    if (MI_GFX_Open() != MI_SUCCESS) { ck("MI_GFX_Open FAILED"); return 1; }
    ck("MI_GFX_Open ok");

    int fb_fd = open("/dev/fb0", O_RDWR);
    struct fb_fix_screeninfo finfo;
    struct fb_var_screeninfo vinfo;
    MI_GFX_Surface_t fb_surf;
    memset(&fb_surf, 0, sizeof(fb_surf));
    if (fb_fd >= 0 && ioctl(fb_fd, FBIOGET_FSCREENINFO, &finfo) == 0 &&
        ioctl(fb_fd, FBIOGET_VSCREENINFO, &vinfo) == 0) {
        fb_surf.phyAddr = finfo.smem_start;
        fb_surf.eColorFmt = E_MI_GFX_FMT_ARGB8888;
        fb_surf.u32Width = PANEL_W;
        fb_surf.u32Height = PANEL_H;
        fb_surf.u32Stride = finfo.line_length ? finfo.line_length : (MI_U32)(PANEL_W * 4);
        ck("fb0 ok phyAddr=0x%llx stride=%u", (unsigned long long)fb_surf.phyAddr, fb_surf.u32Stride);
    } else {
        ck("WARNING: could not open/query /dev/fb0 -- per-variant present step will be skipped");
    }

    Buf surf = {0};
    if (alloc_buf(&surf, (MI_U32)(PANEL_W * PANEL_H * 4)) != 0) {
        ck("alloc failed, aborting");
        return 1;
    }
    MI_GFX_Surface_t gfx_surf;
    memset(&gfx_surf, 0, sizeof(gfx_surf));
    gfx_surf.phyAddr = surf.phy;
    gfx_surf.eColorFmt = E_MI_GFX_FMT_ARGB8888;
    gfx_surf.u32Width = PANEL_W;
    gfx_surf.u32Height = PANEL_H;
    gfx_surf.u32Stride = PANEL_W * 4;

    for (int si = 0; si < SIZE_COUNT; si++) {
        int w = g_sizes[si].w, h = g_sizes[si].h;
        char sizelabel[32];
        snprintf(sizelabel, sizeof(sizelabel), "%dx%d", w, h);
        ck("=== rect %s ===", sizelabel);

        for (int vi = 0; vi < VARIANT_COUNT; vi++) {
            Variant variant = (Variant)vi;
            Stats *st = &table[si][vi];
            ck("--- %s / %s ---", sizelabel, variant_name[vi]);

            if (variant == VARIANT_HW_BATCHED) {
                long batches = frames_per_variant / HW_BATCH;
                for (long batch = 0; batch < batches; batch++) {
                    MI_U16 fences[HW_BATCH];
                    MI_S32 result = MI_SUCCESS;
                    double t0 = now_us();
                    for (int b = 0; b < HW_BATCH; b++) {
                        uint32_t color = 0xFF000000u | (uint32_t)(((batch * HW_BATCH + b) * 61) & 0xFFFFFF);
                        MI_GFX_Rect_t rect = { 0, 0, (MI_U32)w, (MI_U32)h };
                        result = MI_GFX_QuickFill(&gfx_surf, &rect, color, &fences[b]);
                        if (result != MI_SUCCESS) break;
                    }
                    MI_GFX_WaitAllDone(TRUE, 0);
                    double t1 = now_us();
                    if (result != MI_SUCCESS) {
                        ck("%s/%s batch=%ld MI_GFX_QuickFill FAILED result=0x%x",
                           sizelabel, variant_name[vi], batch, result);
                        st->aborted = 1;
                        break;
                    }
                    update_stats(st, (t1 - t0) / HW_BATCH);
                }
            } else {
                for (long frame = 0; frame < frames_per_variant; frame++) {
                    uint32_t color = 0xFF000000u | (uint32_t)((frame * 61) & 0xFFFFFF);

                    double t0 = now_us();
                    if (variant == VARIANT_HW_STRICT) {
                        MI_GFX_Rect_t rect = { 0, 0, (MI_U32)w, (MI_U32)h };
                        MI_U16 fence;
                        MI_S32 result = MI_GFX_QuickFill(&gfx_surf, &rect, color, &fence);
                        if (result != MI_SUCCESS) {
                            ck("%s/%s frame=%ld MI_GFX_QuickFill FAILED result=0x%x",
                               sizelabel, variant_name[vi], frame, result);
                            st->aborted = 1;
                            break;
                        }
                        MI_GFX_WaitAllDone(FALSE, fence);
                    } else if (variant == VARIANT_C) {
                        fill_solid_c32(surf.vir, color, (uint32_t)w, (uint32_t)h, (uint32_t)(PANEL_W * 4));
                    } else {
                        fill_solid_n32(surf.vir, color, (uint32_t)w, (uint32_t)h, (uint32_t)(PANEL_W * 4));
                    }
                    double t1 = now_us();
                    update_stats(st, t1 - t0);
                }
            }

            if (st->count > 0) {
                ck("%s/%s summary: frames=%ld avg_us=%.2f min_us=%.2f max_us=%.2f%s",
                   sizelabel, variant_name[vi], st->frames_completed,
                   st->sum_us / (double)st->count, st->min_us, st->max_us,
                   st->aborted ? " (ABORTED EARLY)" : "");
            }

            if (fb_fd >= 0 && fb_surf.phyAddr) {
                MI_SYS_FlushInvCache(surf.vir, surf.size);

                char banner[96];
                MI_GFX_Rect_t band = { 0, PANEL_H - 24, PANEL_W, 24 };
                MI_GFX_Opt_t band_opt;
                MI_U16 band_fence;
                snprintf(banner, sizeof(banner), "fill %s  %s  avg=%.1fus  rot180",
                         sizelabel, variant_name[vi],
                         st->count ? st->sum_us / (double)st->count : 0.0);
                build_plain_opt(&band_opt, &band, E_MI_GFX_ROTATE_0);
                if (MI_GFX_QuickFill(&gfx_surf, &band, 0xFF000000u, &band_fence) == MI_SUCCESS) {
                    MI_GFX_WaitAllDone(FALSE, band_fence);
                }
                draw_text(surf.vir, PANEL_W, PANEL_H, PANEL_W * 4, 4, PANEL_H - 20, banner);
                MI_SYS_FlushInvCache(surf.vir, surf.size);

                MI_GFX_Rect_t full_rect = { 0, 0, PANEL_W, PANEL_H };
                MI_GFX_Opt_t opt;
                MI_U16 fence;
                build_plain_opt(&opt, &full_rect, SCREEN_ROTATE);
                if (MI_GFX_BitBlit(&gfx_surf, &full_rect, &fb_surf, &full_rect, &opt, &fence) == MI_SUCCESS) {
                    MI_GFX_WaitAllDone(FALSE, fence);
                    ck("%s/%s now on screen", sizelabel, variant_name[vi]);
                    sleep(1);
                }
            }
        }
    }

    ck("=== final summary ===");
    for (int si = 0; si < SIZE_COUNT; si++) {
        for (int vi = 0; vi < VARIANT_COUNT; vi++) {
            Stats *st = &table[si][vi];
            ck("%dx%-4d %-4s frames=%-4ld avg_us=%-9.2f min_us=%-9.2f max_us=%-9.2f%s",
               g_sizes[si].w, g_sizes[si].h, variant_name[vi],
               st->frames_completed,
               st->count ? st->sum_us / (double)st->count : 0.0,
               st->min_us, st->max_us, st->aborted ? " ABORTED" : "");
        }
    }

    free_buf(&surf);
    if (fb_fd >= 0) close(fb_fd);
    if (g_font_ok) { FT_Done_Face(g_face); FT_Done_FreeType(g_ft); }
    MI_GFX_Close();
    MI_SYS_Exit();
    ck("done, exiting cleanly");
    if (g_log) fclose(g_log);
    return 0;
}
