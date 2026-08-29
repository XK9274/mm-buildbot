/* Exercises sdl2_miyoo's composed-blend-mode translation in GFX_Copy
 * (src/video/mmiyoo/SDL_video_mmiyoo_gfx.c).
 *
 * Case A: a representable composed mode -- SDL_ComposeCustomBlendMode(ONE,
 * ZERO, ADD, ZERO, ONE, ADD), the exact mode from the original bug report
 * (an icon-alpha-masked gradient effect that rendered as plain black with
 * only flickering edge fragments). Draws it onto a render-target texture
 * over a known destination color and checks the read-back pixel against the
 * expected math: dstRGB=srcRGB, dstA unchanged.
 *
 * Case B: a deliberately unrepresentable composed mode (mismatched
 * color-vs-alpha factors) -- confirms the fallback path runs without
 * crashing, and captures whether the driver's one-time warning fired via a
 * custom SDL_LogOutputFunction. */
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

    /* --- Case A: representable composed mode --- */
    SDL_BlendMode replace_rgb_mode = SDL_ComposeCustomBlendMode(
        SDL_BLENDFACTOR_ONE, SDL_BLENDFACTOR_ZERO, SDL_BLENDOPERATION_ADD,
        SDL_BLENDFACTOR_ZERO, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_ADD);

    SDL_SetRenderTarget(renderer, target);
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
    SDL_SetRenderDrawColor(renderer, 10, 20, 30, 200); /* known destination color/alpha */
    SDL_RenderClear(renderer);

    SDL_SetRenderDrawBlendMode(renderer, replace_rgb_mode);
    SDL_SetRenderDrawColor(renderer, 200, 100, 50, 128); /* src alpha irrelevant to this mode */
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

    int case_a_pass = (r == 200 && g == 100 && b == 50 && a == 200);
    {
        char msg[192];
        snprintf(msg, sizeof(msg),
                 "CASE A: expected=(200,100,50,200) actual=(%d,%d,%d,%d) => %s",
                 r, g, b, a, case_a_pass ? "PASS" : "FAIL");
        log_checkpoint(msg);
    }

    /* --- Case B: unrepresentable composed mode (mismatched color/alpha factors) --- */
    SDL_BlendMode unsupported_mode = SDL_ComposeCustomBlendMode(
        SDL_BLENDFACTOR_SRC_ALPHA, SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, SDL_BLENDOPERATION_ADD,
        SDL_BLENDFACTOR_ONE, SDL_BLENDFACTOR_ZERO, SDL_BLENDOPERATION_ADD);
    SDL_SetRenderDrawBlendMode(renderer, unsupported_mode);
    SDL_SetRenderDrawColor(renderer, 1, 2, 3, 4);
    SDL_RenderFillRect(renderer, NULL); /* must not crash */
    log_checkpoint("unsupported-compose draw completed without crash");

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
