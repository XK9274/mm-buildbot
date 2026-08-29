/* Exercises sdl2_miyoo's composed-blend-mode translation in GFX_Copy
 * (src/video/mmiyoo/SDL_video_mmiyoo_gfx.c).
 *
 * Case A: a genuinely representable composed mode --
 * SDL_ComposeCustomBlendMode(ZERO, ONE, ADD, ZERO, ONE, ADD), i.e. "keep the
 * destination, ignore the source" on all 4 channels equally. Matching
 * color/alpha factors is exactly what MI_GFX's single (eSrcDfbBldOp,
 * eDstDfbBldOp) pair can represent -- this is not one of SDL's 4 named
 * short constants, so it only reaches the new translation path, not an
 * existing hardcoded case. Draws it over a known destination color with a
 * different source color; if the translation is wired correctly the
 * destination must come back completely unchanged (the old SRCALPHA/
 * INVSRCALPHA fallback would visibly blend the new color in instead).
 *
 * Case B: the *exact* mode from the original bug report --
 * SDL_ComposeCustomBlendMode(ONE, ZERO, ADD, ZERO, ONE, ADD), used by
 * syncthing-app-miyoo to replace destination RGB while preserving
 * destination alpha. Decomposed, its color factors (ONE, ZERO) don't match
 * its alpha factors (ZERO, ONE) -- MI_GFX applies one factor pair
 * uniformly across all 4 channels, so this specific mode is NOT
 * representable on this hardware, translation or not. This case confirms
 * that instead of the old silent mis-blend, it now falls back cleanly
 * (no crash) and fires the driver's one-time warning -- captured here via
 * a custom SDL_LogOutputFunction. The original app's need (replace RGB,
 * keep alpha, in one hardware blit) genuinely has no representation here;
 * an app hitting this must composite it another way (e.g. CPU-side). */
#include <SDL.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define TEX_SIZE 64

static SDL_LogOutputFunction g_prev_log_fn;
static void *g_prev_log_userdata;
static int g_saw_fallback_warning = 0;

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

static void capture_log(void *userdata, int category, SDL_LogPriority priority, const char *message)
{
    if (category == SDL_LOG_CATEGORY_RENDER && priority >= SDL_LOG_PRIORITY_WARN) {
        char msg[256];
        snprintf(msg, sizeof(msg), "[sdl-log] %s", message);
        log_checkpoint(msg);
        if (strstr(message, "not representable on MI_GFX") != NULL) {
            g_saw_fallback_warning = 1;
        }
    }
    if (g_prev_log_fn) {
        g_prev_log_fn(g_prev_log_userdata, category, priority, message);
    }
}

int main(int argc, char *argv[])
{
    (void)argc;
    (void)argv;
    remove("probe.log");
    log_checkpoint("start");

    SDL_LogGetOutputFunction(&g_prev_log_fn, &g_prev_log_userdata);
    SDL_LogSetOutputFunction(capture_log, NULL);

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

    /* --- Case A: representable composed mode ("keep destination") --- */
    SDL_BlendMode keep_dest_mode = SDL_ComposeCustomBlendMode(
        SDL_BLENDFACTOR_ZERO, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_ADD,
        SDL_BLENDFACTOR_ZERO, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_ADD);

    SDL_SetRenderTarget(renderer, target);
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
    SDL_SetRenderDrawColor(renderer, 10, 20, 30, 200); /* known destination color/alpha */
    SDL_RenderClear(renderer);

    SDL_SetRenderDrawBlendMode(renderer, keep_dest_mode);
    SDL_SetRenderDrawColor(renderer, 200, 100, 50, 128); /* must have zero effect under this mode */
    SDL_RenderFillRect(renderer, NULL);

    Uint32 pixel = 0;
    if (SDL_RenderReadPixels(renderer, NULL, SDL_PIXELFORMAT_ARGB8888, &pixel, TEX_SIZE * 4) != 0) {
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

    /* --- Case B: the original bug report's mode, confirmed unrepresentable --- */
    SDL_BlendMode replace_rgb_keep_alpha_mode = SDL_ComposeCustomBlendMode(
        SDL_BLENDFACTOR_ONE, SDL_BLENDFACTOR_ZERO, SDL_BLENDOPERATION_ADD,
        SDL_BLENDFACTOR_ZERO, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_ADD);
    SDL_SetRenderDrawBlendMode(renderer, replace_rgb_keep_alpha_mode);
    SDL_SetRenderDrawColor(renderer, 1, 2, 3, 4);
    SDL_RenderFillRect(renderer, NULL); /* must not crash */
    log_checkpoint("original-bug-report-mode draw completed without crash");

    {
        char msg[128];
        snprintf(msg, sizeof(msg), "CASE B: fallback warning seen=%s", g_saw_fallback_warning ? "yes" : "no");
        log_checkpoint(msg);
    }

    SDL_SetRenderTarget(renderer, NULL);
    SDL_DestroyTexture(target);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    log_checkpoint("...exiting cleanly");
    SDL_Quit();
    return 0;
}
