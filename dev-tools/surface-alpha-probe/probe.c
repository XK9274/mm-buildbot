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

    SDL_Window *window = SDL_CreateWindow("probe", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                           640, 480, SDL_WINDOW_FULLSCREEN);
    if (!window) { log_checkpoint(SDL_GetError()); return 1; }
    SDL_Renderer *renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    if (!renderer) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_CreateRenderer ok");

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
    Uint8 sa_vals[GRADIENT_WIDTH], da_vals[GRADIENT_WIDTH];

    for (int x = 0; x < GRADIENT_WIDTH; x++) {
        Uint8 sr, sg, sb, sa, dr, dg, db, da;
        SDL_GetRGBA(src_pixels[x], src->format, &sr, &sg, &sb, &sa);
        SDL_GetRGBA(dst_pixels[x], dst->format, &dr, &dg, &db, &da);
        sa_vals[x] = sa;
        da_vals[x] = da;

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

    /* Visual result: top half = source alpha gradient (grayscale), bottom half = destination alpha gradient -- should look identical. Held on screen for HOLD_SECONDS before exit. */
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
    int win_w = 0, win_h = 0;
    SDL_GetWindowSize(window, &win_w, &win_h);
    int strip_w = win_w / GRADIENT_WIDTH;
    for (int x = 0; x < GRADIENT_WIDTH; x++) {
        SDL_Rect top = {x * strip_w, 0, strip_w, win_h / 2};
        SDL_Rect bottom = {x * strip_w, win_h / 2, strip_w, win_h - win_h / 2};
        SDL_SetRenderDrawColor(renderer, sa_vals[x], sa_vals[x], sa_vals[x], 255);
        SDL_RenderFillRect(renderer, &top);
        SDL_SetRenderDrawColor(renderer, da_vals[x], da_vals[x], da_vals[x], 255);
        SDL_RenderFillRect(renderer, &bottom);
    }
    SDL_RenderPresent(renderer);

    log_checkpoint("...exiting cleanly");
#define HOLD_SECONDS 5
    SDL_Delay(HOLD_SECONDS * 1000);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
