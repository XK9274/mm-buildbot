/* Documents which SDL2 pixel formats round-trip correctly through
 * sdl2_miyoo's renderer. Writes a known, channel-distinguishable translucent
 * test color into a texture of each format via that format's own
 * SDL_MapRGBA (format-safe, never a hand-written byte offset), renders and
 * reads it back, and decodes with SDL_GetRGBA.
 *
 * SDL_PIXELFORMAT_RGBA8888 is expected to always FAIL here: MI_GFX has no
 * native format matching its real little-endian memory order (A,B,G,R), so
 * MMIYOO_SDLToMIGfxFormat force-maps it to ARGB8888, swapping R/B. That is a
 * documented, permanent limitation (see docs/MMIYOO_SDL_FEATURE_SUMMARY.md
 * in sdl2_miyoo), not a bug this probe is meant to catch going green. */
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

static void test_format(SDL_Renderer *renderer, Uint32 sdl_format, const char *name)
{
    SDL_Texture *tex = SDL_CreateTexture(renderer, sdl_format, SDL_TEXTUREACCESS_STREAMING, 4, 4);
    if (!tex) {
        char msg[192];
        snprintf(msg, sizeof(msg), "%s: SDL_CreateTexture failed: %s => FAIL", name, SDL_GetError());
        log_checkpoint(msg);
        return;
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
    SDL_RenderCopy(renderer, tex, NULL, NULL);

    SDL_Rect one_pixel = {0, 0, 1, 1};
    Uint32 readback = 0;
    SDL_RenderReadPixels(renderer, &one_pixel, SDL_PIXELFORMAT_ARGB8888, &readback, 4);

    SDL_PixelFormat *argb_fmt = SDL_AllocFormat(SDL_PIXELFORMAT_ARGB8888);
    Uint8 r, g, b, a;
    SDL_GetRGBA(readback, argb_fmt, &r, &g, &b, &a);

    int pass = (r == 200 && g == 10 && b == 20);
    char msg[192];
    snprintf(msg, sizeof(msg), "%s: expected RGB=(200,10,20) actual RGB=(%d,%d,%d) => %s",
             name, r, g, b, pass ? "PASS" : "FAIL");
    log_checkpoint(msg);

    SDL_FreeFormat(fmt);
    SDL_FreeFormat(argb_fmt);
    SDL_DestroyTexture(tex);
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

    test_format(renderer, SDL_PIXELFORMAT_ARGB8888, "ARGB8888");
    test_format(renderer, SDL_PIXELFORMAT_ABGR8888, "ABGR8888");
    test_format(renderer, SDL_PIXELFORMAT_BGRA8888, "BGRA8888");
    test_format(renderer, SDL_PIXELFORMAT_RGBA8888, "RGBA8888");

    log_checkpoint("...exiting cleanly");
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
