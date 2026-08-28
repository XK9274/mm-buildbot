/* Targeted repro for the BlobbyVolley2-only hang found while testing the
 * sdl2_miyoo downscale-on-composite fix (see bv2/docs/WHERE3.md and
 * .claude/plans/recursive-booping-cerf.md "Live debugging session update").
 *
 * v2: matches BlobbyVolley2's ACTUAL RenderManagerSDL::init()/refresh()
 * behavior exactly, not an approximation:
 *   - Window created at 800x600 (BASE_RESOLUTION_X/Y), not the 640x480
 *     panel size -- xResolution/yResolution are passed straight through.
 *   - SDL_WINDOW_RESIZABLE, NOT SDL_WINDOW_FULLSCREEN -- data/config.xml's
 *     default "fullscreen" value is false, so BV2 actually runs with
 *     window flags = SDL_WINDOW_RESIZABLE on this embedded framebuffer-only
 *     driver, not fullscreen. Every earlier probe used FULLSCREEN + a
 *     640x480 window, both wrong relative to BV2's real behavior.
 *   - SDL_CreateRenderer flags = 0, not SDL_RENDERER_ACCELERATED.
 *   - refresh()'s exact viewport-resync sequence
 *     (SDL_RenderGetViewport/SDL_GetWindowSize/SDL_RenderSetViewport when
 *     they differ) before the composite, which no earlier probe exercised.
 *
 * Earlier, less faithful variants (bulk texture count, unbound oversized
 * target present, STREAMING+UpdateTexture, creation pacing, small-textures-
 * then-big-target with a FULLSCREEN 640x480 window) all completed cleanly.
 * Real BlobbyVolley2 freezes 100% of the time on the first refresh()'s
 * composite call. This version closes every remaining known gap between
 * the probe and the real app. */
#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define TEX_W 32
#define TEX_H 32
#define BASE_RESOLUTION_X 800
#define BASE_RESOLUTION_Y 600
#define DEFAULT_SMALL_COUNT 200

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
    int small_count = DEFAULT_SMALL_COUNT;
    if (argc > 1) small_count = atoi(argv[1]);
    remove("probe.log");

    char msg[192];
    snprintf(msg, sizeof(msg), "start (v2, faithful window/flags), small_count=%d", small_count);
    log_checkpoint(msg);

    if (SDL_Init(SDL_INIT_VIDEO) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_Init ok");

    /* Matches RenderManagerSDL::init() exactly: window at BASE_RESOLUTION_X/Y
     * (800x600), RESIZABLE (config.xml's default fullscreen=false). */
    SDL_Window *window = SDL_CreateWindow("probe", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                           BASE_RESOLUTION_X, BASE_RESOLUTION_Y, SDL_WINDOW_RESIZABLE);
    if (!window) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_CreateWindow(800x600, RESIZABLE) ok");

    /* Matches RenderManagerSDL::init(): SDL_CreateRenderer(mWindow, -1, 0). */
    SDL_Renderer *renderer = SDL_CreateRenderer(window, -1, 0);
    if (!renderer) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_CreateRenderer(flags=0) ok");

    /* Phase 1: small textures first, matching BV2's real loading order. */
    SDL_Surface *src = SDL_CreateRGBSurfaceWithFormat(0, TEX_W, TEX_H, 32, SDL_PIXELFORMAT_ABGR8888);
    SDL_FillRect(src, NULL, 0xFFAA5533);
    SDL_Texture **kept = calloc(small_count, sizeof(SDL_Texture*));

    for (int i = 0; i < small_count; i++) {
        SDL_Texture *tex = SDL_CreateTextureFromSurface(renderer, src);
        if (!tex) {
            snprintf(msg, sizeof(msg), "small texture create FAILED at i=%d: %s", i, SDL_GetError());
            log_checkpoint(msg);
            return 1;
        }
        kept[i] = tex;
        if ((i + 1) % 20 == 0) {
            snprintf(msg, sizeof(msg), "created %d small textures ok", i + 1);
            log_checkpoint(msg);
        }
    }
    snprintf(msg, sizeof(msg), "phase 1 done: %d small textures alive", small_count);
    log_checkpoint(msg);

    /* Phase 2: matches RenderManagerSDL::init()'s mRenderTarget creation --
     * BASE_RESOLUTION_X/Y (800x600), unbound (pristine BV2 never calls
     * SDL_SetRenderTarget in init()). */
    SDL_Texture *render_target = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
                                                    SDL_TEXTUREACCESS_TARGET, BASE_RESOLUTION_X, BASE_RESOLUTION_Y);
    if (!render_target) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("phase 2: mRenderTarget SDL_CreateTexture(800x600, TARGET, unbound) ok");

    /* Draw something into it so the composite isn't blank -- matches BV2
     * binding it for the first real time only inside refresh(). */
    SDL_SetRenderTarget(renderer, render_target);
    SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255);
    SDL_RenderClear(renderer);
    log_checkpoint("phase 2: filled render_target");

    /* Phase 3: RenderManagerSDL::refresh(), verbatim sequence. */
    SDL_SetRenderTarget(renderer, NULL);
    log_checkpoint("phase 3: SDL_SetRenderTarget(NULL) ok");

    SDL_Rect renderRect;
    int windowX, windowY;
    SDL_RenderGetViewport(renderer, &renderRect);
    SDL_GetWindowSize(window, &windowX, &windowY);
    snprintf(msg, sizeof(msg), "phase 3: viewport=(%d,%d,%d,%d) windowSize=%dx%d",
             renderRect.x, renderRect.y, renderRect.w, renderRect.h, windowX, windowY);
    log_checkpoint(msg);
    if (renderRect.w != windowX || renderRect.h != windowY) {
        renderRect.w = windowX;
        renderRect.h = windowY;
        SDL_RenderSetViewport(renderer, &renderRect);
        log_checkpoint("phase 3: SDL_RenderSetViewport applied (viewport/window size differed)");
    } else {
        log_checkpoint("phase 3: viewport already matches window size, no resync needed");
    }

    log_checkpoint("phase 3: about to composite (SDL_RenderCopy mRenderTarget -> screen) -- the exact call BlobbyVolley2 freezes on");
    if (SDL_RenderCopy(renderer, render_target, NULL, NULL) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("phase 3: SDL_RenderCopy returned -- device did not hang");

    SDL_RenderPresent(renderer);
    log_checkpoint("phase 3: SDL_RenderPresent ok");

    SDL_SetRenderTarget(renderer, render_target);
    log_checkpoint("phase 3: SDL_SetRenderTarget(render_target) ok -- refresh() sequence complete, matches BV2 exactly, done");

    sleep(3);
    SDL_Quit();
    return 0;
}
