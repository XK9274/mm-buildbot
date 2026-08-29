/* Verifies SDL_ConvertSurfaceFormat(ABGR8888 -> RGBA8888) preserves alpha, using only format-aware SDL_GetRGBA reads (never a fixed byte offset). */
#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define GRADIENT_WIDTH 16

static void log_checkpoint(const char *msg)
{
    FILE *f = fopen("probe.log", "a");
    if (f) {
        fprintf(f, "[probe] %s\n", msg);
        fclose(f);
        sync();
    }
    fprintf(stderr, "[probe] %s\n", msg);
}

int main(int argc, char *argv[])
{
    (void)argc;
    (void)argv;
    remove("probe.log");
    log_checkpoint("start");

    if (SDL_Init(SDL_INIT_VIDEO) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_Init ok");

    SDL_Surface *src = SDL_CreateRGBSurfaceWithFormat(0, GRADIENT_WIDTH, 1, 32, SDL_PIXELFORMAT_ABGR8888);
    if (!src) { log_checkpoint(SDL_GetError()); return 1; }

    SDL_LockSurface(src);
    Uint32 *src_row = (Uint32 *)src->pixels;
    for (int x = 0; x < GRADIENT_WIDTH; x++) {
        Uint8 alpha = (Uint8)(x * 255 / (GRADIENT_WIDTH - 1)); /* real gradient, not constant */
        src_row[x] = SDL_MapRGBA(src->format, 100, 150, 200, alpha);
    }
    SDL_UnlockSurface(src);

    SDL_Surface *dst = SDL_ConvertSurfaceFormat(src, SDL_PIXELFORMAT_RGBA8888, 0);
    if (!dst) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_ConvertSurfaceFormat(ABGR8888 -> RGBA8888) ok");

    int pass_count = 0;
    const int tolerance = 2;
    Uint32 *src_pixels = (Uint32 *)src->pixels;
    Uint32 *dst_pixels = (Uint32 *)dst->pixels;

    for (int x = 0; x < GRADIENT_WIDTH; x++) {
        Uint8 sr, sg, sb, sa, dr, dg, db, da;
        SDL_GetRGBA(src_pixels[x], src->format, &sr, &sg, &sb, &sa);
        SDL_GetRGBA(dst_pixels[x], dst->format, &dr, &dg, &db, &da);

        int ok = (abs((int)sa - (int)da) <= tolerance);
        pass_count += ok;

        char msg[192];
        snprintf(msg, sizeof(msg),
                 "x=%d src_alpha(format-aware)=%d dst_alpha(format-aware)=%d => %s",
                 x, sa, da, ok ? "PASS" : "FAIL");
        log_checkpoint(msg);
    }

    {
        char msg[128];
        snprintf(msg, sizeof(msg), "SUMMARY: %d/%d pixels PASS (alpha survives SDL_ConvertSurfaceFormat)",
                 pass_count, GRADIENT_WIDTH);
        log_checkpoint(msg);
    }

    /* A fixed offset+3 read is right for ABGR8888 but wrong for packed32 RGBA8888. */
    for (int x = 0; x < 2; x++) {
        Uint8 *bytes = (Uint8 *)dst->pixels + x * 4;
        char msg[192];
        snprintf(msg, sizeof(msg),
                 "x=%d NAIVE fixed-offset+3 read of dst = %d (WRONG -- real alpha is at byte offset 0 "
                 "for RGBA8888 on this little-endian target)",
                 x, bytes[3]);
        log_checkpoint(msg);
    }

    SDL_FreeSurface(src);
    SDL_FreeSurface(dst);
    log_checkpoint("...exiting cleanly");
    SDL_Quit();
    return 0;
}
