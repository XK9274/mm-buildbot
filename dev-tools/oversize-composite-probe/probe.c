/* Minimal repro: create an 800x600 render-target texture, fill it with a
 * visible test pattern, composite it to the screen. Isolates exactly the
 * mechanism the sdl2_miyoo downscale-on-composite fix targets, with no game
 * loop / assets / gdbserver needed for the common case -- see
 * bv2/docs/NEON_DOWNSCALE_PLAN.md. Not a shipped app; dev-only probe. */
#include <SDL.h>
#include <stdio.h>
#include <unistd.h>

#define OVERSIZED_W 800
#define OVERSIZED_H 600

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
    (void)argc; (void)argv;
    remove("probe.log");
    log_checkpoint("start");

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        log_checkpoint(SDL_GetError());
        return 1;
    }
    log_checkpoint("SDL_Init ok");

    SDL_Window *window = SDL_CreateWindow("probe", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                           640, 480, SDL_WINDOW_FULLSCREEN);
    if (!window) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_CreateWindow ok");

    SDL_Renderer *renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    if (!renderer) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_CreateRenderer ok");

    /* The whole point: a target texture bigger than the 640x480 panel. */
    SDL_Texture *target = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
                                             SDL_TEXTUREACCESS_TARGET, OVERSIZED_W, OVERSIZED_H);
    if (!target) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_CreateTexture(800x600, TARGET) ok");

    if (SDL_SetRenderTarget(renderer, target) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_SetRenderTarget(target) ok");

    /* Visible test pattern: quadrant colors + a diagonal line, so a
     * correctly-scaled-and-rotated composite is easy to eyeball. */
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
    SDL_RenderClear(renderer);
    SDL_Rect quads[4] = {
        {0, 0, OVERSIZED_W / 2, OVERSIZED_H / 2},
        {OVERSIZED_W / 2, 0, OVERSIZED_W / 2, OVERSIZED_H / 2},
        {0, OVERSIZED_H / 2, OVERSIZED_W / 2, OVERSIZED_H / 2},
        {OVERSIZED_W / 2, OVERSIZED_H / 2, OVERSIZED_W / 2, OVERSIZED_H / 2},
    };
    SDL_Color colors[4] = { {255,0,0,255}, {0,255,0,255}, {0,0,255,255}, {255,255,0,255} };
    for (int i = 0; i < 4; i++) {
        SDL_SetRenderDrawColor(renderer, colors[i].r, colors[i].g, colors[i].b, 255);
        SDL_RenderFillRect(renderer, &quads[i]);
    }
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
    for (int x = 0; x < OVERSIZED_W; x += 4) {
        SDL_RenderDrawPoint(renderer, x, x * OVERSIZED_H / OVERSIZED_W);
    }
    log_checkpoint("test pattern drawn into target");

    if (SDL_SetRenderTarget(renderer, NULL) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_SetRenderTarget(NULL) ok -- about to composite oversized target to screen");

    /* This is the call that used to hang the device: composites the whole
     * oversized target texture to the screen, hitting My_QueueCopy's
     * automatic 180-rotation path with a source larger than the panel. */
    if (SDL_RenderCopy(renderer, target, NULL, NULL) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_RenderCopy(oversized target -> screen) returned -- device did not hang");

    SDL_RenderPresent(renderer);
    log_checkpoint("SDL_RenderPresent ok");

    /* Hold the frame on screen for visual confirmation. */
    sleep(5);
    log_checkpoint("done, exiting cleanly");

    SDL_DestroyTexture(target);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
