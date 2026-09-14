/* Exercises sdl2_miyoo's hardware source colorkey extension
 * (SDL_MMIYOO_SetTextureColorKey), on both an alpha-less RGB565 texture
 * (where SDL's own alpha=0 colorkey conversion at texture-creation time
 * cannot apply) and a 32-bit ARGB8888 texture (to isolate whether a
 * failure is specific to sub-32-bit formats or the colorkey mechanism
 * itself). */
#include <SDL.h>
#include <SDL_mmiyoo_colorkey.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define TEX_SIZE 64
#define MAGIC_R 255
#define MAGIC_G 0
#define MAGIC_B 255
#define BG_R 20
#define BG_G 150
#define BG_B 20

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

/* Runs the keyed-left/plain-right colorkey test against one texture format.
 * Returns SDL_TRUE if both halves match expectations. */
static SDL_bool run_case(SDL_Renderer *renderer, SDL_Texture *target, const char *case_name, Uint32 sdl_format)
{
    SDL_Texture *src = SDL_CreateTexture(renderer, sdl_format, SDL_TEXTUREACCESS_STREAMING, TEX_SIZE, TEX_SIZE);
    if (!src) {
        char msg[192];
        snprintf(msg, sizeof(msg), "%s: SDL_CreateTexture failed: %s => FAIL", case_name, SDL_GetError());
        log_checkpoint(msg);
        return SDL_FALSE;
    }

    SDL_PixelFormat *fmt = SDL_AllocFormat(sdl_format);
    Uint32 magic_pixel = SDL_MapRGB(fmt, MAGIC_R, MAGIC_G, MAGIC_B);
    Uint32 second_pixel = SDL_MapRGB(fmt, 10, 10, 200);
    int bpp = fmt->BytesPerPixel;

    void *pixels;
    int pitch;
    SDL_LockTexture(src, NULL, &pixels, &pitch);
    for (int y = 0; y < TEX_SIZE; y++) {
        Uint8 *row = (Uint8 *)pixels + y * pitch;
        for (int x = 0; x < TEX_SIZE; x++) {
            Uint32 value = (x < TEX_SIZE / 2) ? magic_pixel : second_pixel;
            if (bpp == 2) {
                ((Uint16 *)row)[x] = (Uint16)value;
            } else {
                ((Uint32 *)row)[x] = value;
            }
        }
    }
    SDL_UnlockTexture(src);

    Uint32 magic_key = ((Uint32)MAGIC_R << 16) | ((Uint32)MAGIC_G << 8) | (Uint32)MAGIC_B;
    SDL_bool set_ok = SDL_MMIYOO_SetTextureColorKey(src, SDL_TRUE, magic_key);
    {
        char msg[192];
        snprintf(msg, sizeof(msg), "%s: SDL_MMIYOO_SetTextureColorKey => %s", case_name, set_ok ? "accepted" : "REJECTED");
        log_checkpoint(msg);
    }
    if (!set_ok) {
        SDL_FreeFormat(fmt);
        SDL_DestroyTexture(src);
        return SDL_FALSE;
    }

    if (SDL_SetRenderTarget(renderer, target) != 0) { log_checkpoint(SDL_GetError()); return SDL_FALSE; }
    if (SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE) != 0) { log_checkpoint(SDL_GetError()); return SDL_FALSE; }
    if (SDL_SetRenderDrawColor(renderer, BG_R, BG_G, BG_B, 255) != 0) { log_checkpoint(SDL_GetError()); return SDL_FALSE; }
    if (SDL_RenderClear(renderer) != 0) { log_checkpoint(SDL_GetError()); return SDL_FALSE; }

    if (SDL_SetTextureBlendMode(src, SDL_BLENDMODE_NONE) != 0) { log_checkpoint(SDL_GetError()); return SDL_FALSE; }
    if (SDL_RenderCopy(renderer, src, NULL, NULL) != 0) { log_checkpoint(SDL_GetError()); return SDL_FALSE; }

    SDL_Rect left_pixel = {TEX_SIZE / 4, TEX_SIZE / 2, 1, 1};
    SDL_Rect right_pixel = {TEX_SIZE * 3 / 4, TEX_SIZE / 2, 1, 1};
    Uint32 left_readback = 0, right_readback = 0;
    if (SDL_RenderReadPixels(renderer, &left_pixel, SDL_PIXELFORMAT_ARGB8888, &left_readback, 4) != 0) {
        log_checkpoint(SDL_GetError());
        return SDL_FALSE;
    }
    if (SDL_RenderReadPixels(renderer, &right_pixel, SDL_PIXELFORMAT_ARGB8888, &right_readback, 4) != 0) {
        log_checkpoint(SDL_GetError());
        return SDL_FALSE;
    }

    SDL_PixelFormat *argb_fmt = SDL_AllocFormat(SDL_PIXELFORMAT_ARGB8888);
    Uint8 lr, lg, lb, la, rr, rg, rb, ra;
    SDL_GetRGBA(left_readback, argb_fmt, &lr, &lg, &lb, &la);
    SDL_GetRGBA(right_readback, argb_fmt, &rr, &rg, &rb, &ra);
    SDL_FreeFormat(argb_fmt);
    SDL_FreeFormat(fmt);
    SDL_DestroyTexture(src);

    /* Sub-32-bit formats quantize each channel; tolerate rounding to the
     * nearest representable level. */
    const int tolerance = 6;
    int left_shows_background = (abs((int)lr - BG_R) <= tolerance && abs((int)lg - BG_G) <= tolerance &&
                                  abs((int)lb - BG_B) <= tolerance);
    int right_shows_second_color = (abs((int)rr - 10) <= tolerance && abs((int)rg - 10) <= tolerance &&
                                     abs((int)rb - 200) <= tolerance);

    {
        char msg[224];
        snprintf(msg, sizeof(msg),
                 "%s LEFT (keyed-out region): expected background~=(%d,%d,%d) actual=(%d,%d,%d) => %s",
                 case_name, BG_R, BG_G, BG_B, lr, lg, lb, left_shows_background ? "PASS" : "FAIL");
        log_checkpoint(msg);
    }
    {
        char msg[224];
        snprintf(msg, sizeof(msg),
                 "%s RIGHT (non-keyed region): expected~=(10,10,200) actual=(%d,%d,%d) => %s",
                 case_name, rr, rg, rb, right_shows_second_color ? "PASS" : "FAIL");
        log_checkpoint(msg);
    }

    return left_shows_background && right_shows_second_color;
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

    SDL_Texture *target = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
                                             SDL_TEXTUREACCESS_TARGET, TEX_SIZE, TEX_SIZE);
    if (!target) { log_checkpoint(SDL_GetError()); return 1; }

    int rgb565_pass = run_case(renderer, target, "RGB565", SDL_PIXELFORMAT_RGB565);
    int argb8888_pass = run_case(renderer, target, "ARGB8888", SDL_PIXELFORMAT_ARGB8888);

    int overall_pass = rgb565_pass && argb8888_pass;
    {
        char msg[192];
        snprintf(msg, sizeof(msg), "SUMMARY: RGB565=%s ARGB8888=%s",
                 rgb565_pass ? "PASS" : "FAIL", argb8888_pass ? "PASS" : "FAIL");
        log_checkpoint(msg);
    }

    SDL_SetRenderTarget(renderer, NULL);
    SDL_DestroyTexture(target);

    /* Visual result: top half RGB565 case, bottom half ARGB8888 case; each split left(keyed)/right(plain), green=PASS/red=FAIL. Held on screen for HOLD_SECONDS before exit. */
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
    int win_w = 0, win_h = 0;
    SDL_GetWindowSize(window, &win_w, &win_h);
    SDL_Rect top = {0, 0, win_w, win_h / 2};
    SDL_Rect bottom = {0, win_h / 2, win_w, win_h - win_h / 2};
    SDL_SetRenderDrawColor(renderer, rgb565_pass ? 0 : 200, rgb565_pass ? 200 : 0, 0, 255);
    SDL_RenderFillRect(renderer, &top);
    SDL_SetRenderDrawColor(renderer, argb8888_pass ? 0 : 200, argb8888_pass ? 200 : 0, 0, 255);
    SDL_RenderFillRect(renderer, &bottom);
    SDL_RenderPresent(renderer);

    log_checkpoint("...exiting cleanly");
#define HOLD_SECONDS 5
    SDL_Delay(HOLD_SECONDS * 1000);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return overall_pass ? 0 : 1;
}
