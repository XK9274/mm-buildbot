/* Minimal repro for the MI_GFX/MI_SYS hang found while testing the
 * sdl2_miyoo downscale-on-composite fix: BlobbyVolley2's asset loading
 * (many small SDL_CreateTextureFromSurface calls -- fonts, blobs,
 * backgrounds) hangs the device after ~162 successful texture-creation
 * ioctl triples, with no relation to the oversized-texture/rotation
 * mechanism that fix targets. See bv2/docs/WHERE3.md and
 * miyoo_sdl2_benchmarks/.claude/commands/miyoo-debug.md.
 *
 * KEEP_ALIVE=1 (default): every texture stays live, matching BV2's actual
 * behavior -- tests whether this is a live-handle-count cap.
 * KEEP_ALIVE=0: each texture is destroyed before the next is created --
 * tests whether it's instead a cumulative create-call leak regardless of
 * how many are simultaneously live. */
#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define TEX_W 32
#define TEX_H 32
#define MAX_TEXTURES 4000

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
    int keep_alive = 1;
    int delay_us = 0;
    int mode = 0; /* 0 = CreateTextureFromSurface (STATIC), matches background/font/ball loading.
                   * 1 = CreateTexture(STREAMING) + UpdateTexture, matches blob color-variant loading. */
    if (argc > 1) keep_alive = atoi(argv[1]);
    if (argc > 2) delay_us = atoi(argv[2]);
    if (argc > 3) mode = atoi(argv[3]);
    remove("probe.log");

    char msg[128];
    snprintf(msg, sizeof(msg), "start, keep_alive=%d, delay_us=%d, mode=%d", keep_alive, delay_us, mode);
    log_checkpoint(msg);

    if (SDL_Init(SDL_INIT_VIDEO) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_Init ok");

    SDL_Window *window = SDL_CreateWindow("probe", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                           640, 480, SDL_WINDOW_FULLSCREEN);
    if (!window) { log_checkpoint(SDL_GetError()); return 1; }

    SDL_Renderer *renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    if (!renderer) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_CreateRenderer ok");

    /* Matches BlobbyVolley2's actual sequence: an oversized (800x600)
     * TARGET-access texture created first and left unbound (pristine
     * upstream never calls SDL_SetRenderTarget in init()), then many small
     * textures loaded while it sits alive in the handle table. */
    SDL_Texture *big_target = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
                                                 SDL_TEXTUREACCESS_TARGET, 800, 600);
    if (!big_target) { log_checkpoint(SDL_GetError()); return 1; }
    log_checkpoint("SDL_CreateTexture(800x600, TARGET, unbound) ok, starting small-texture loop");

    SDL_Surface *src = SDL_CreateRGBSurfaceWithFormat(0, TEX_W, TEX_H, 32, SDL_PIXELFORMAT_ABGR8888);
    SDL_FillRect(src, NULL, 0xFFAA5533);

    SDL_Texture **kept = keep_alive ? calloc(MAX_TEXTURES, sizeof(SDL_Texture*)) : NULL;

    for (int i = 0; i < MAX_TEXTURES; i++) {
        SDL_Texture *tex;
        if (mode == 1) {
            tex = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ABGR8888, SDL_TEXTUREACCESS_STREAMING, TEX_W, TEX_H);
            if (tex) {
                SDL_UpdateTexture(tex, NULL, src->pixels, src->pitch);
            }
        } else {
            tex = SDL_CreateTextureFromSurface(renderer, src);
        }
        if (!tex) {
            snprintf(msg, sizeof(msg), "texture create FAILED at i=%d: %s", i, SDL_GetError());
            log_checkpoint(msg);
            break;
        }
        if (keep_alive) {
            kept[i] = tex;
        } else {
            SDL_DestroyTexture(tex);
        }
        if ((i + 1) % 10 == 0) {
            snprintf(msg, sizeof(msg), "created %d textures ok", i + 1);
            log_checkpoint(msg);
        }
        if (delay_us > 0) usleep(delay_us);
    }

    log_checkpoint("loop completed without hanging, exiting cleanly");
    SDL_FreeSurface(src);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
