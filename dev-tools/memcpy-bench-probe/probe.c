/* Compares three memcpy implementations at the sizes/alignments sdl2_miyoo
 * actually uses: neon_memcpy (current, used by MMIYOO_UpdateTexture's
 * per-row copy), neon_memcpy_relaxed (a sibling in neon-arm-library-miyoo
 * that drops neon_memcpy's destination-alignment prologue and aligned-store
 * hints, unnecessary on Linux/Cortex-A7), and libc memcpy as a sanity
 * baseline. No SDL2, no on-screen rendering needed per-combination -- this
 * probe is timing only. Buffers are MI_SYS_MMA_Alloc'd (not malloc'd) to
 * match the real driver's memory characteristics (the same
 * physically-contiguous, mmap'd pool MMIYOO_UpdateTexture actually copies
 * into). */
#include <mi_sys.h>
#include <mi_gfx.h>
#include <neon.h>

#include <fcntl.h>
#include <linux/fb.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define SYS_ALIGN 4096u
#define ALIGN_UP(v, a) (((v) + (a) - 1u) & ~((a) - 1u))
#define PAD 16

typedef enum { VARIANT_NEON = 0, VARIANT_RELAXED, VARIANT_LIBC, VARIANT_COUNT } Variant;
static const char *variant_name[VARIANT_COUNT] = { "neon", "relaxed", "libc" };

/* 2560 = one 640px ARGB8888 row (the real per-row texture-copy hot path);
 * 76800/614400/1228800 = 1/16, 1/2, and full 640x480 ARGB8888 frame, for a
 * proper full-screen-scale comparison alongside the small/row-sized cases. */
static const size_t g_sizes[] = { 16, 32, 64, 512, 1024, 2048, 2560, 76800, 614400, 1228800 };
#define SIZE_COUNT (int)(sizeof(g_sizes) / sizeof(g_sizes[0]))

static const uint32_t g_offsets[] = { 0, 1, 2, 3 };
#define OFFSET_COUNT (int)(sizeof(g_offsets) / sizeof(g_offsets[0]))

typedef struct {
    double min_us, max_us, sum_us;
    long count;
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
    fprintf(stderr, "[memcpy-bench] %s\n", line);
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

static void update_stats(Stats *s, double us)
{
    if (s->count == 0 || us < s->min_us) s->min_us = us;
    if (s->count == 0 || us > s->max_us) s->max_us = us;
    s->sum_us += us;
    s->count++;
}

int main(int argc, char *argv[])
{
    long iters_per_case = (argc > 1) ? atol(argv[1]) : 2000;
    Stats table[SIZE_COUNT][OFFSET_COUNT][VARIANT_COUNT];
    memset(table, 0, sizeof(table));

    remove("probe.log");
    g_log = fopen("probe.log", "a");
    ck("start, iters_per_case=%ld", iters_per_case);

    if (MI_SYS_Init() != MI_SUCCESS) { ck("MI_SYS_Init FAILED"); return 1; }
    ck("MI_SYS_Init ok");

    size_t max_size = g_sizes[SIZE_COUNT - 1] + PAD;
    Buf src = {0}, dst = {0};
    if (alloc_buf(&src, (MI_U32)max_size) != 0 || alloc_buf(&dst, (MI_U32)max_size) != 0) {
        ck("alloc failed, aborting");
        return 1;
    }
    memset(src.vir, 0x5A, src.size);

    for (int si = 0; si < SIZE_COUNT; si++) {
        size_t n = g_sizes[si];
        for (int oi = 0; oi < OFFSET_COUNT; oi++) {
            uint32_t off = g_offsets[oi];
            ck("=== size=%zu offset=%u ===", n, off);

            /* Cap total bytes moved per case (~32MB) so the large full-
             * screen-scale sizes don't turn a run into a multi-hour test --
             * scales iteration count down as size grows, floor of 5. */
            long iters_this_case = iters_per_case;
            {
                long byte_capped = (long)((32 * 1024 * 1024) / (n ? n : 1));
                if (byte_capped < iters_this_case) iters_this_case = byte_capped;
                if (iters_this_case < 5) iters_this_case = 5;
            }

            for (int vi = 0; vi < VARIANT_COUNT; vi++) {
                Variant variant = (Variant)vi;
                Stats *st = &table[si][oi][vi];

                for (long iter = 0; iter < iters_this_case; iter++) {
                    void *s = (uint8_t *)src.vir + off;
                    void *d = (uint8_t *)dst.vir + off;

                    double t0 = now_us();
                    if (variant == VARIANT_NEON) {
                        neon_memcpy(d, s, n);
                    } else if (variant == VARIANT_RELAXED) {
                        neon_memcpy_relaxed(d, s, n);
                    } else {
                        memcpy(d, s, n);
                    }
                    double t1 = now_us();
                    update_stats(st, t1 - t0);
                }

                ck("size=%zu offset=%u %-8s avg_us=%.3f min_us=%.3f max_us=%.3f",
                   n, off, variant_name[vi],
                   st->sum_us / (double)st->count, st->min_us, st->max_us);
            }
        }
    }

    ck("=== final summary ===");
    for (int si = 0; si < SIZE_COUNT; si++) {
        for (int oi = 0; oi < OFFSET_COUNT; oi++) {
            for (int vi = 0; vi < VARIANT_COUNT; vi++) {
                Stats *st = &table[si][oi][vi];
                ck("size=%-6zu offset=%u %-8s avg_us=%-9.3f min_us=%-9.3f max_us=%-9.3f",
                   g_sizes[si], g_offsets[oi], variant_name[vi],
                   st->count ? st->sum_us / (double)st->count : 0.0, st->min_us, st->max_us);
            }
        }
    }

    free_buf(&src);
    free_buf(&dst);
    MI_SYS_Exit();
    ck("done, exiting cleanly");
    if (g_log) fclose(g_log);
    return 0;
}
