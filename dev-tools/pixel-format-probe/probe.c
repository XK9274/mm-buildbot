/* Round-trips a known color through each SDL2 pixel format via SDL_RenderCopy on sdl2_miyoo's renderer; a live reference for which formats decode correctly, not an assertion of which ones should. */
#include <SDL.h>
#include <stdio.h>
#include <unistd.h>

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

/* Reading the default framebuffer target is unsupported by design on this driver (see docs/MMIYOO_SDL_FEATURE_SUMMARY.md), so a target texture is required here. Writes the decoded RGB back through *out_r/g/b for on-screen display -- a wrong color IS the bug, more legible than a log line. */
static int test_format(SDL_Renderer *renderer, Uint32 sdl_format, const char *name, Uint8 *out_r, Uint8 *out_g, Uint8 *out_b)
{
    *out_r = *out_g = *out_b = 0;

    SDL_Texture *target = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, 4, 4);
    if (!target) {
        char msg[192];
        snprintf(msg, sizeof(msg), "%s: SDL_CreateTexture(TARGET) failed: %s => FAIL", name, SDL_GetError());
        log_checkpoint(msg);
        return 0;
    }

    SDL_Texture *tex = SDL_CreateTexture(renderer, sdl_format, SDL_TEXTUREACCESS_STREAMING, 4, 4);
    if (!tex) {
        char msg[192];
        snprintf(msg, sizeof(msg), "%s: SDL_CreateTexture failed: %s => FAIL", name, SDL_GetError());
        log_checkpoint(msg);
        SDL_DestroyTexture(target);
        return 0;
    }

    SDL_PixelFormat *fmt = SDL_AllocFormat(sdl_format);
    Uint32 test_color = SDL_MapRGBA(fmt, 200, 10, 20, 128); /* translucent, channel-distinguishable */

    void *pixels;
    int pitch;
    SDL_LockTexture(tex, NULL, &pixels, &pitch);
    for (int y = 0; y < 4; y++) {
        Uint32 *row = (Uint32 *)((Uint8 *)pixels + y * pitch);
        for (int x = 0; x < 4; x++) {
            row[x] = test_color;
        }
    }
    SDL_UnlockTexture(tex);

    SDL_SetTextureBlendMode(tex, SDL_BLENDMODE_NONE); /* isolate format mapping from blend math */
    SDL_SetRenderTarget(renderer, target);
    SDL_RenderCopy(renderer, tex, NULL, NULL);

    SDL_Rect one_pixel = {0, 0, 1, 1};
    Uint32 readback = 0;
    SDL_RenderReadPixels(renderer, &one_pixel, SDL_PIXELFORMAT_ARGB8888, &readback, 4);
    SDL_SetRenderTarget(renderer, NULL);

    SDL_PixelFormat *argb_fmt = SDL_AllocFormat(SDL_PIXELFORMAT_ARGB8888);
    Uint8 r, g, b, a;
    SDL_GetRGBA(readback, argb_fmt, &r, &g, &b, &a);
    *out_r = r;
    *out_g = g;
    *out_b = b;

    int pass = (r == 200 && g == 10 && b == 20);
    char msg[192];
    snprintf(msg, sizeof(msg), "%s: expected RGB=(200,10,20) actual RGB=(%d,%d,%d) => %s",
             name, r, g, b, pass ? "PASS" : "FAIL");
    log_checkpoint(msg);

    SDL_FreeFormat(fmt);
    SDL_FreeFormat(argb_fmt);
    SDL_DestroyTexture(tex);
    SDL_DestroyTexture(target);
    return pass;
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

    Uint8 r[4], g[4], b[4];
    test_format(renderer, SDL_PIXELFORMAT_ARGB8888, "ARGB8888", &r[0], &g[0], &b[0]);
    test_format(renderer, SDL_PIXELFORMAT_ABGR8888, "ABGR8888", &r[1], &g[1], &b[1]);
    test_format(renderer, SDL_PIXELFORMAT_BGRA8888, "BGRA8888", &r[2], &g[2], &b[2]);
    test_format(renderer, SDL_PIXELFORMAT_RGBA8888, "RGBA8888", &r[3], &g[3], &b[3]);

    /* Visual result: one quadrant per format, filled with its actual decoded color (all 4 should look identical -- any that don't ARE the bug). Held on screen for HOLD_SECONDS before exit. */
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
    int win_w = 0, win_h = 0;
    SDL_GetWindowSize(window, &win_w, &win_h);
    SDL_Rect quads[4] = {
        {0, 0, win_w / 2, win_h / 2},
        {win_w / 2, 0, win_w - win_w / 2, win_h / 2},
        {0, win_h / 2, win_w / 2, win_h - win_h / 2},
        {win_w / 2, win_h / 2, win_w - win_w / 2, win_h - win_h / 2},
    };
    for (int i = 0; i < 4; i++) {
        SDL_SetRenderDrawColor(renderer, r[i], g[i], b[i], 255);
        SDL_RenderFillRect(renderer, &quads[i]);
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
