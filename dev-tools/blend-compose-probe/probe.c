/* Exercises sdl2_miyoo's composed-blend-mode support (MMIYOO_SupportsBlendMode + GFX_Copy's translation) via SDL_RenderCopy, the only draw path that reaches GFX_Copy on this driver -- SDL_RenderFillRect/RenderClear always use an opaque QuickFill that ignores blend mode entirely. */
#include <SDL.h>
#include <stdio.h>
#include <unistd.h>

#define TEX_SIZE 64

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

static SDL_Texture *make_solid_texture(SDL_Renderer *renderer, Uint8 r, Uint8 g, Uint8 b, Uint8 a)
{
    SDL_Texture *tex = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING,
                                          TEX_SIZE, TEX_SIZE);
    if (!tex) {
        return NULL;
    }

    SDL_PixelFormat *fmt = SDL_AllocFormat(SDL_PIXELFORMAT_ARGB8888);
    Uint32 color = SDL_MapRGBA(fmt, r, g, b, a);
    SDL_FreeFormat(fmt);

    void *pixels;
    int pitch;
    SDL_LockTexture(tex, NULL, &pixels, &pitch);
    for (int y = 0; y < TEX_SIZE; y++) {
        Uint32 *row = (Uint32 *)((Uint8 *)pixels + y * pitch);
        for (int x = 0; x < TEX_SIZE; x++) {
            row[x] = color;
        }
    }
    SDL_UnlockTexture(tex);
    return tex;
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
    log_checkpoint("SDL_CreateTexture(TARGET) ok");

    if (SDL_SetRenderTarget(renderer, target) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    if (SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    if (SDL_SetRenderDrawColor(renderer, 10, 20, 30, 200) != 0) { log_checkpoint(SDL_GetError()); return 1; } /* known destination color/alpha */
    if (SDL_RenderClear(renderer) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("target cleared to (10,20,30,200)");

    /* --- Case A: representable composed mode ("keep destination, ignore source") --- */
    SDL_BlendMode keep_dest_mode = SDL_ComposeCustomBlendMode(
        SDL_BLENDFACTOR_ZERO, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_ADD,
        SDL_BLENDFACTOR_ZERO, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_ADD);

    SDL_Texture *src_a = make_solid_texture(renderer, 200, 100, 50, 128);
    if (!src_a) { log_checkpoint(SDL_GetError()); return 1; }

    if (SDL_SetTextureBlendMode(src_a, keep_dest_mode) != 0) {
        char msg[192];
        snprintf(msg, sizeof(msg), "CASE A: SDL_SetTextureBlendMode unexpectedly rejected a representable mode: %s => FAIL",
                 SDL_GetError());
        log_checkpoint(msg);
        return 1;
    }
    log_checkpoint("CASE A: SDL_SetTextureBlendMode accepted (as expected)");

    if (SDL_RenderCopy(renderer, src_a, NULL, NULL) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("CASE A: SDL_RenderCopy ok");

    SDL_Rect one_pixel = {0, 0, 1, 1};
    Uint32 pixel = 0;
    if (SDL_RenderReadPixels(renderer, &one_pixel, SDL_PIXELFORMAT_ARGB8888, &pixel, 4) != 0) {
        log_checkpoint(SDL_GetError());
        return 1;
    }

    SDL_PixelFormat *argb_fmt = SDL_AllocFormat(SDL_PIXELFORMAT_ARGB8888);
    Uint8 r, g, b, a;
    SDL_GetRGBA(pixel, argb_fmt, &r, &g, &b, &a);
    SDL_FreeFormat(argb_fmt);

    int case_a_pass = (r == 10 && g == 20 && b == 30 && a == 200);
    {
        char msg[192];
        snprintf(msg, sizeof(msg),
                 "CASE A: expected=(10,20,30,200) [destination untouched] actual=(%d,%d,%d,%d) => %s",
                 r, g, b, a, case_a_pass ? "PASS" : "FAIL");
        log_checkpoint(msg);
    }

    /* --- Case B: the exact mode from the original bug report -- confirmed unrepresentable --- */
    SDL_BlendMode replace_rgb_keep_alpha_mode = SDL_ComposeCustomBlendMode(
        SDL_BLENDFACTOR_ONE, SDL_BLENDFACTOR_ZERO, SDL_BLENDOPERATION_ADD,
        SDL_BLENDFACTOR_ZERO, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_ADD);

    SDL_Texture *src_b = make_solid_texture(renderer, 1, 2, 3, 4);
    if (!src_b) { log_checkpoint(SDL_GetError()); return 1; }

    int rejected = (SDL_SetTextureBlendMode(src_b, replace_rgb_keep_alpha_mode) != 0);
    {
        char msg[192];
        snprintf(msg, sizeof(msg),
                 "CASE B: SDL_SetTextureBlendMode on the original bug-report mode was %s (error: %s) => %s",
                 rejected ? "rejected" : "accepted", SDL_GetError(), rejected ? "PASS" : "FAIL");
        log_checkpoint(msg);
    }

    SDL_DestroyTexture(src_b);
    SDL_DestroyTexture(src_a);
    SDL_SetRenderTarget(renderer, NULL);
    SDL_DestroyTexture(target);

    /* Visual result: top half = Case A (green=PASS/red=FAIL), bottom half = Case B. Held on screen for HOLD_SECONDS before exit. */
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
    int win_w = 0, win_h = 0;
    SDL_GetWindowSize(window, &win_w, &win_h);
    SDL_Rect top = {0, 0, win_w, win_h / 2};
    SDL_Rect bottom = {0, win_h / 2, win_w, win_h - win_h / 2};
    SDL_SetRenderDrawColor(renderer, case_a_pass ? 0 : 200, case_a_pass ? 200 : 0, 0, 255);
    SDL_RenderFillRect(renderer, &top);
    SDL_SetRenderDrawColor(renderer, rejected ? 0 : 200, rejected ? 200 : 0, 0, 255);
    SDL_RenderFillRect(renderer, &bottom);
    SDL_RenderPresent(renderer);

    log_checkpoint("...exiting cleanly");
#define HOLD_SECONDS 5
    SDL_Delay(HOLD_SECONDS * 1000);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
