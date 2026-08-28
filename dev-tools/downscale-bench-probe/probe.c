/* Compares three ways to get an oversized ARGB8888 surface down to the real
 * 640x480 panel: MI_GFX_BitBlit's own implicit hardware scale (source and
 * destination rects of different sizes on the same call), the plain C
 * downscale_area_c32, and the NEON downscale_area_n32 currently used by
 * sdl2_miyoo's per-frame composite path. No SDL2 -- raw MI_SYS/MI_GFX only,
 * mirroring the exact sequence sdl2_miyoo's own FB_Init()/GFX_Copy() use
 * (SDL_video_mmiyoo.c). Runs the same resolution above the panel size
 * through all three variants in turn, logging every frame's wall time so a
 * hang's last-logged line still pinpoints exactly where it happened. Each
 * variant's held on-screen result is rotated 180 (the panel is mounted
 * upside down, same as every screen-target draw in sdl2_miyoo itself) and
 * carries an on-screen banner naming the resolution/target/variant. */
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

typedef enum { VARIANT_HW = 0, VARIANT_C, VARIANT_NEON, VARIANT_COUNT } Variant;
static const char *variant_name[VARIANT_COUNT] = { "hw", "c", "neon" };

typedef struct { int w, h; } Resolution;
static const Resolution g_resolutions[] = {
    { 800, 600 }, { 1024, 768 }, { 1280, 720 }, { 1440, 900 }, { 1920, 1080 },
};
#define RES_COUNT (int)(sizeof(g_resolutions) / sizeof(g_resolutions[0]))

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
static MI_U16 g_fences[MAX_FENCES];
static int g_fence_count;

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
    fprintf(stderr, "[downscale-bench] %s\n", line);
}

static double now_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e6 + (double)ts.tv_nsec / 1e3;
}

static void log_mma_heap(const char *label)
{
    FILE *f = fopen("/proc/mi_modules/mi_sys_mma/mma_heap_name0", "r");
    char line[256];
    if (!f) {
        ck("mma_heap[%s]: could not open /proc/mi_modules/mi_sys_mma/mma_heap_name0", label);
        return;
    }
    ck("mma_heap[%s]:", label);
    while (fgets(line, sizeof(line), f)) {
        size_t n = strlen(line);
        if (n && line[n - 1] == '\n') line[n - 1] = '\0';
        ck("  %s", line);
    }
    fclose(f);
}

static const char *gfx_err_name(MI_S32 code)
{
    if (code == MI_SUCCESS) return "MI_SUCCESS";
    if (code == MI_ERR_GFX_INVALID_PARAM) return "MI_ERR_GFX_INVALID_PARAM";
    if (code == MI_ERR_GFX_DEV_BUSY) return "MI_ERR_GFX_DEV_BUSY";
    if (code == MI_ERR_GFX_NOT_INIT) return "MI_ERR_GFX_NOT_INIT";
    if (code == MI_ERR_GFX_DRV_NOT_SUPPORT) return "MI_ERR_GFX_DRV_NOT_SUPPORT";
    if (code == MI_ERR_GFX_DRV_FAIL_FORMAT) return "MI_ERR_GFX_DRV_FAIL_FORMAT";
    if (code == MI_ERR_GFX_NON_ALIGN_ADDRESS) return "MI_ERR_GFX_NON_ALIGN_ADDRESS";
    if (code == MI_ERR_GFX_NON_ALIGN_PITCH) return "MI_ERR_GFX_NON_ALIGN_PITCH";
    if (code == MI_ERR_GFX_DRV_FAIL_OVERLAP) return "MI_ERR_GFX_DRV_FAIL_OVERLAP";
    if (code == MI_ERR_GFX_DRV_FAIL_STRETCH) return "MI_ERR_GFX_DRV_FAIL_STRETCH";
    if (code == MI_ERR_GFX_DRV_FAIL_LOCKED) return "MI_ERR_GFX_DRV_FAIL_LOCKED";
    if (code == MI_ERR_GFX_DRV_FAIL_BLTADDR) return "MI_ERR_GFX_DRV_FAIL_BLTADDR";
    return "UNKNOWN";
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

static void add_fence(MI_U16 fence)
{
    if (g_fence_count >= MAX_FENCES) {
        for (int i = 0; i < g_fence_count; i++) MI_GFX_WaitAllDone(FALSE, g_fences[i]);
        g_fence_count = 0;
    }
    g_fences[g_fence_count++] = fence;
}

static void flush_fences(void)
{
    for (int i = 0; i < g_fence_count; i++) MI_GFX_WaitAllDone(FALSE, g_fences[i]);
    g_fence_count = 0;
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

/* This panel is mounted upside down -- sdl2_miyoo's own driver rotates
 * every screen-target draw 180 for exactly this reason (My_QueueCopy,
 * SDL_render_mmiyoo.c: base_rotation = is_target_texture ? ROTATE_0 :
 * ROTATE_180). Only the final present-to-fb blit below is a screen-target
 * draw; every other blit in this probe writes to an off-screen MI_SYS
 * surface and stays unrotated, matching that same convention. */
#define SCREEN_ROTATE E_MI_GFX_ROTATE_180

static FT_Library g_ft;
static FT_Face g_face;
static int g_font_ok = 0;

static void font_init(const char *path, int pixel_size)
{
    if (FT_Init_FreeType(&g_ft) != 0) {
        ck("FT_Init_FreeType failed");
        return;
    }
    if (FT_New_Face(g_ft, path, 0, &g_face) != 0) {
        ck("FT_New_Face failed for %s", path);
        return;
    }
    FT_Set_Pixel_Sizes(g_face, 0, (FT_UInt)pixel_size);
    g_font_ok = 1;
}

/* Stamps opaque white glyph coverage (above a threshold, no alpha blend)
 * directly into an ARGB8888 buffer -- avoids needing to read back
 * whatever GFX previously wrote under the text. Silently clips at the
 * buffer edges. */
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

static void draw_synthetic_frame(MI_GFX_Surface_t *src_surf, int w, int h, long frame)
{
    MI_GFX_Rect_t rects[3];
    MI_U32 colors[3];
    MI_U16 fence;

    rects[0] = (MI_GFX_Rect_t){ 0, 0, (MI_U32)w / 2, (MI_U32)h / 2 };
    rects[1] = (MI_GFX_Rect_t){ (MI_S32)(w / 2), (MI_S32)(h / 2), (MI_U32)(w - w / 2), (MI_U32)(h - h / 2) };
    rects[2] = (MI_GFX_Rect_t){ (MI_S32)(w / 4), (MI_S32)(h / 4), (MI_U32)(w / 2), (MI_U32)(h / 2) };
    colors[0] = 0xFF000000u | (MI_U32)((frame * 37) & 0xFF) << 16;
    colors[1] = 0xFF000000u | (MI_U32)((frame * 53) & 0xFF) << 8;
    colors[2] = 0xFF000000u | (MI_U32)((frame * 91) & 0xFF);

    for (int i = 0; i < 3; i++) {
        if (MI_GFX_QuickFill(src_surf, &rects[i], colors[i], &fence) == MI_SUCCESS) {
            add_fence(fence);
        }
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
    long frames_per_variant = (argc > 1) ? atol(argv[1]) : 150;
    const char *font_path = (argc > 2) ? argv[2] : "font.otf";
    Stats table[RES_COUNT][VARIANT_COUNT];
    memset(table, 0, sizeof(table));

    remove("probe.log");
    g_log = fopen("probe.log", "a");
    ck("start, frames_per_variant=%ld font=%s", frames_per_variant, font_path);

    font_init(font_path, 18);
    if (!g_font_ok) {
        ck("WARNING: on-screen text disabled, font failed to load");
    }

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

    for (int ri = 0; ri < RES_COUNT; ri++) {
        int w = g_resolutions[ri].w, h = g_resolutions[ri].h;
        char reslabel[32];
        snprintf(reslabel, sizeof(reslabel), "%dx%d", w, h);
        ck("=== resolution %s ===", reslabel);

        char heaplabel[64];
        snprintf(heaplabel, sizeof(heaplabel), "before-alloc %s", reslabel);
        log_mma_heap(heaplabel);

        Buf src = {0}, scratch = {0}, dst = {0};
        if (alloc_buf(&src, (MI_U32)(w * h * 4)) != 0 ||
            alloc_buf(&scratch, (MI_U32)(PANEL_W * PANEL_H * 4)) != 0 ||
            alloc_buf(&dst, (MI_U32)(PANEL_W * PANEL_H * 4)) != 0) {
            ck("alloc failed for %s, skipping this resolution", reslabel);
            free_buf(&src); free_buf(&scratch); free_buf(&dst);
            continue;
        }

        MI_GFX_Surface_t src_surf, scratch_surf, dst_surf;
        memset(&src_surf, 0, sizeof(src_surf));
        src_surf.phyAddr = src.phy;
        src_surf.eColorFmt = E_MI_GFX_FMT_ARGB8888;
        src_surf.u32Width = (MI_U32)w;
        src_surf.u32Height = (MI_U32)h;
        src_surf.u32Stride = (MI_U32)(w * 4);

        memset(&scratch_surf, 0, sizeof(scratch_surf));
        scratch_surf.phyAddr = scratch.phy;
        scratch_surf.eColorFmt = E_MI_GFX_FMT_ARGB8888;
        scratch_surf.u32Width = PANEL_W;
        scratch_surf.u32Height = PANEL_H;
        scratch_surf.u32Stride = PANEL_W * 4;

        memset(&dst_surf, 0, sizeof(dst_surf));
        dst_surf.phyAddr = dst.phy;
        dst_surf.eColorFmt = E_MI_GFX_FMT_ARGB8888;
        dst_surf.u32Width = PANEL_W;
        dst_surf.u32Height = PANEL_H;
        dst_surf.u32Stride = PANEL_W * 4;

        for (int vi = 0; vi < VARIANT_COUNT; vi++) {
            Variant variant = (Variant)vi;
            Stats *st = &table[ri][vi];
            ck("--- %s / %s ---", reslabel, variant_name[vi]);

            for (long frame = 0; frame < frames_per_variant; frame++) {
                draw_synthetic_frame(&src_surf, w, h, frame);

                double t0 = now_us();
                MI_S32 result;
                MI_U16 fence;

                if (variant == VARIANT_HW) {
                    MI_GFX_Rect_t src_rect = { 0, 0, (MI_U32)w, (MI_U32)h };
                    MI_GFX_Rect_t dst_rect = { 0, 0, PANEL_W, PANEL_H };
                    MI_GFX_Opt_t opt;
                    build_plain_opt(&opt, &dst_rect, E_MI_GFX_ROTATE_0);
                    result = MI_GFX_BitBlit(&src_surf, &src_rect, &dst_surf, &dst_rect, &opt, &fence);
                    if (result != MI_SUCCESS) {
                        ck("%s/%s frame=%ld MI_GFX_BitBlit(scale) FAILED result=0x%x (%s)",
                           reslabel, variant_name[vi], frame, result, gfx_err_name(result));
                        st->aborted = 1;
                        g_fence_count = 0;
                        break;
                    }
                    MI_GFX_WaitAllDone(FALSE, fence);
                } else {
                    flush_fences();
                    MI_SYS_FlushInvCache(src.vir, (MI_U32)(w * h * 4));
                    if (variant == VARIANT_C) {
                        downscale_area_c32(src.vir, scratch.vir, (uint32_t)w, (uint32_t)h,
                                            (uint32_t)(w * 4), (uint32_t)(PANEL_W * 4), PANEL_W, PANEL_H);
                    } else {
                        downscale_area_n32(src.vir, scratch.vir, (uint32_t)w, (uint32_t)h,
                                            (uint32_t)(w * 4), (uint32_t)(PANEL_W * 4), PANEL_W, PANEL_H);
                    }
                    MI_SYS_FlushInvCache(scratch.vir, (MI_U32)(PANEL_W * PANEL_H * 4));

                    MI_GFX_Rect_t full_rect = { 0, 0, PANEL_W, PANEL_H };
                    MI_GFX_Opt_t opt;
                    build_plain_opt(&opt, &full_rect, E_MI_GFX_ROTATE_0);
                    result = MI_GFX_BitBlit(&scratch_surf, &full_rect, &dst_surf, &full_rect, &opt, &fence);
                    if (result != MI_SUCCESS) {
                        ck("%s/%s frame=%ld MI_GFX_BitBlit(unscaled) FAILED result=0x%x (%s)",
                           reslabel, variant_name[vi], frame, result, gfx_err_name(result));
                        st->aborted = 1;
                        break;
                    }
                    MI_GFX_WaitAllDone(FALSE, fence);
                }

                double t1 = now_us();
                double dt = t1 - t0;
                update_stats(st, dt);
                ck("%s/%s frame=%ld us=%.1f", reslabel, variant_name[vi], frame, dt);
            }

            if (st->count > 0) {
                ck("%s/%s summary: frames=%ld avg_us=%.1f min_us=%.1f max_us=%.1f%s",
                   reslabel, variant_name[vi], st->frames_completed,
                   st->sum_us / (double)st->count, st->min_us, st->max_us,
                   st->aborted ? " (ABORTED EARLY)" : "");
            } else {
                ck("%s/%s summary: no frames completed%s", reslabel, variant_name[vi],
                   st->aborted ? " (ABORTED EARLY)" : "");
            }

            if (fb_fd >= 0 && fb_surf.phyAddr) {
                /* Every blit into dst_surf above already waited its own
                 * fence synchronously, so dst.vir is safe to touch on the
                 * CPU here with no extra flush_fences() call. Band sits at
                 * the BOTTOM of dst_surf's (unrotated) coordinate space so
                 * it lands at the TOP of the actual, rotated, viewed
                 * screen -- SCREEN_ROTATE flips the whole image. */
                char banner[96];
                MI_GFX_Rect_t band = { 0, PANEL_H - 24, PANEL_W, 24 };
                MI_GFX_Opt_t band_opt;
                MI_U16 band_fence;
                snprintf(banner, sizeof(banner), "%s  %d x %d -> %d x %d  %s scale  rot180",
                         reslabel, w, h, PANEL_W, PANEL_H, variant_name[vi]);
                build_plain_opt(&band_opt, &band, E_MI_GFX_ROTATE_0);
                if (MI_GFX_QuickFill(&dst_surf, &band, 0xFF000000u, &band_fence) == MI_SUCCESS) {
                    MI_GFX_WaitAllDone(FALSE, band_fence);
                }
                draw_text(dst.vir, PANEL_W, PANEL_H, PANEL_W * 4, 4, PANEL_H - 20, banner);
                MI_SYS_FlushInvCache(dst.vir, dst.size);

                MI_GFX_Rect_t full_rect = { 0, 0, PANEL_W, PANEL_H };
                MI_GFX_Opt_t opt;
                MI_U16 fence;
                build_plain_opt(&opt, &full_rect, SCREEN_ROTATE);
                if (MI_GFX_BitBlit(&dst_surf, &full_rect, &fb_surf, &full_rect, &opt, &fence) == MI_SUCCESS) {
                    MI_GFX_WaitAllDone(FALSE, fence);
                    ck("%s/%s now on screen", reslabel, variant_name[vi]);
                    sleep(1);
                } else {
                    ck("%s/%s present-to-fb failed", reslabel, variant_name[vi]);
                }
            }
        }

        free_buf(&src);
        free_buf(&scratch);
        free_buf(&dst);
        snprintf(heaplabel, sizeof(heaplabel), "after-free %s", reslabel);
        log_mma_heap(heaplabel);
    }

    ck("=== final summary ===");
    for (int ri = 0; ri < RES_COUNT; ri++) {
        for (int vi = 0; vi < VARIANT_COUNT; vi++) {
            Stats *st = &table[ri][vi];
            ck("%dx%d %-4s frames=%-4ld avg_us=%-9.1f min_us=%-9.1f max_us=%-9.1f%s",
               g_resolutions[ri].w, g_resolutions[ri].h, variant_name[vi],
               st->frames_completed,
               st->count ? st->sum_us / (double)st->count : 0.0,
               st->min_us, st->max_us, st->aborted ? " ABORTED" : "");
        }
    }

    if (fb_fd >= 0) close(fb_fd);
    if (g_font_ok) { FT_Done_Face(g_face); FT_Done_FreeType(g_ft); }
    MI_GFX_Close();
    MI_SYS_Exit();
    ck("done, exiting cleanly");
    if (g_log) fclose(g_log);
    return 0;
}
