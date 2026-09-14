/* Exercises sdl2_miyoo's composed-blend-mode support: SDL_SetTextureBlendMode
 * rejection for unrepresentable modes, GFX_Copy's factor translation via
 * SDL_RenderCopy, SDL_RenderFillRect's blend handling, and the
 * BLEND_PREMULTIPLIED/ADD_PREMULTIPLIED premultiplied-alpha modes. */
#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
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

    /* --- Case C: SDL_RenderFillRect must actually blend, not silently ignore alpha/blend mode --- */
    if (SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    if (SDL_SetRenderDrawColor(renderer, 100, 100, 100, 255) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    if (SDL_RenderClear(renderer) != 0) { log_checkpoint(SDL_GetError()); return 1; }

    if (SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    if (SDL_SetRenderDrawColor(renderer, 200, 0, 0, 128) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    SDL_Rect full_rect = {0, 0, TEX_SIZE, TEX_SIZE};
    if (SDL_RenderFillRect(renderer, &full_rect) != 0) { log_checkpoint(SDL_GetError()); return 1; }

    Uint32 pixel_c = 0;
    if (SDL_RenderReadPixels(renderer, &one_pixel, SDL_PIXELFORMAT_ARGB8888, &pixel_c, 4) != 0) {
        log_checkpoint(SDL_GetError());
        return 1;
    }
    Uint8 cr, cg, cb, ca;
    SDL_GetRGBA(pixel_c, argb_fmt, &cr, &cg, &cb, &ca);

    /* Expected (100,100,100,255) background blended under (200,0,0,128) via
     * dstRGB = srcRGB*srcA/255 + dstRGB*(1-srcA/255): RGB=(150,50,50). Alpha
     * uses the same single hardware factor pair as RGB (MI_GFX has no
     * separate alpha factors), so it comes out as srcA*srcA/255 +
     * dstA*(1-srcA/255) rather than SDL's own srcA+dstA*(1-srcA/255)
     * formula: 128*128/255 + 255*127/255 =~ 191, not 255. The old bug (fill
     * ignores blend entirely) instead produces the exact draw color forced
     * opaque: (200,0,0,255) -- easily distinguished from either expectation
     * above by the still-correct RGB values here. */
    const int case_c_tolerance = 4;
    int case_c_pass = (abs((int)cr - 150) <= case_c_tolerance && abs((int)cg - 50) <= case_c_tolerance &&
                        abs((int)cb - 50) <= case_c_tolerance && abs((int)ca - 191) <= case_c_tolerance);
    {
        char msg[224];
        snprintf(msg, sizeof(msg),
                 "CASE C: blended-fill expected~=(150,50,50,191) actual=(%d,%d,%d,%d) => %s",
                 cr, cg, cb, ca, case_c_pass ? "PASS" : "FAIL");
        log_checkpoint(msg);
    }

    /* --- Case D: SDL_BLENDMODE_BLEND_PREMULTIPLIED must not re-multiply already-premultiplied source alpha --- */
    if (SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    if (SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    if (SDL_RenderClear(renderer) != 0) { log_checkpoint(SDL_GetError()); return 1; }

    SDL_Texture *src_d = make_solid_texture(renderer, 128, 64, 32, 128);
    if (!src_d) { log_checkpoint(SDL_GetError()); return 1; }
    if (SDL_SetTextureBlendMode(src_d, SDL_BLENDMODE_BLEND_PREMULTIPLIED) != 0) {
        char msg[192];
        snprintf(msg, sizeof(msg), "CASE D: SDL_SetTextureBlendMode(BLEND_PREMULTIPLIED) unexpectedly rejected: %s => FAIL",
                 SDL_GetError());
        log_checkpoint(msg);
        return 1;
    }
    if (SDL_RenderCopy(renderer, src_d, NULL, NULL) != 0) { log_checkpoint(SDL_GetError()); return 1; }

    Uint32 pixel_d = 0;
    if (SDL_RenderReadPixels(renderer, &one_pixel, SDL_PIXELFORMAT_ARGB8888, &pixel_d, 4) != 0) {
        log_checkpoint(SDL_GetError());
        return 1;
    }
    Uint8 dr, dg, db, da;
    SDL_GetRGBA(pixel_d, argb_fmt, &dr, &dg, &db, &da);

    /* Over a black background, a premultiplied (128,64,32,128) source must
     * reproduce its own RGB unchanged (dstRGB = srcRGB + dst*(1-srcA) = srcRGB
     * since dst=0). Standard (non-premultiplied) alpha blending would instead
     * halve it to roughly (64,32,16), which is the discriminating failure. */
    const int case_d_tolerance = 6;
    int case_d_pass = (abs((int)dr - 128) <= case_d_tolerance && abs((int)dg - 64) <= case_d_tolerance &&
                        abs((int)db - 32) <= case_d_tolerance);
    {
        char msg[224];
        snprintf(msg, sizeof(msg),
                 "CASE D: BLEND_PREMULTIPLIED over black expected~=(128,64,32,_) actual=(%d,%d,%d,%d) => %s",
                 dr, dg, db, da, case_d_pass ? "PASS" : "FAIL");
        log_checkpoint(msg);
    }
    SDL_DestroyTexture(src_d);

    /* --- Case E: SDL_BLENDMODE_ADD_PREMULTIPLIED must add raw RGB and leave destination alpha untouched --- */
    if (SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    if (SDL_SetRenderDrawColor(renderer, 10, 20, 30, 200) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    if (SDL_RenderClear(renderer) != 0) { log_checkpoint(SDL_GetError()); return 1; }

    SDL_Texture *src_e = make_solid_texture(renderer, 50, 60, 70, 90);
    if (!src_e) { log_checkpoint(SDL_GetError()); return 1; }
    if (SDL_SetTextureBlendMode(src_e, SDL_BLENDMODE_ADD_PREMULTIPLIED) != 0) {
        char msg[192];
        snprintf(msg, sizeof(msg), "CASE E: SDL_SetTextureBlendMode(ADD_PREMULTIPLIED) unexpectedly rejected: %s => FAIL",
                 SDL_GetError());
        log_checkpoint(msg);
        return 1;
    }
    if (SDL_RenderCopy(renderer, src_e, NULL, NULL) != 0) { log_checkpoint(SDL_GetError()); return 1; }

    Uint32 pixel_e = 0;
    if (SDL_RenderReadPixels(renderer, &one_pixel, SDL_PIXELFORMAT_ARGB8888, &pixel_e, 4) != 0) {
        log_checkpoint(SDL_GetError());
        return 1;
    }
    Uint8 er, eg, eb, ea;
    SDL_GetRGBA(pixel_e, argb_fmt, &er, &eg, &eb, &ea);

    /* dstRGB = srcRGB + dstRGB: (60,80,100). SDL's own formula leaves dstA
     * unchanged (200), but MI_GFX applies the same ONE/ONE factor pair to
     * alpha too (no separate alpha factors), giving srcA+dstA=90+200
     * saturated to 255 instead -- an unavoidable consequence of ADD_PREMULTIPLIED
     * needing asymmetric color/alpha factors on hardware that has only one
     * factor pair for all four channels. */
    const int case_e_tolerance = 4;
    int case_e_pass = (abs((int)er - 60) <= case_e_tolerance && abs((int)eg - 80) <= case_e_tolerance &&
                        abs((int)eb - 100) <= case_e_tolerance && abs((int)ea - 255) <= case_e_tolerance);
    {
        char msg[224];
        snprintf(msg, sizeof(msg),
                 "CASE E: ADD_PREMULTIPLIED expected~=(60,80,100,255) actual=(%d,%d,%d,%d) => %s",
                 er, eg, eb, ea, case_e_pass ? "PASS" : "FAIL");
        log_checkpoint(msg);
    }
    SDL_DestroyTexture(src_e);
    SDL_FreeFormat(argb_fmt);

    SDL_SetRenderTarget(renderer, NULL);
    SDL_DestroyTexture(target);

    /* --- Case F: a small blend fill (direct-write CPU path) and a large
     * blend fill (hardware blit path) of the same logical blend, both
     * against the live window/framebuffer, must read back identically. */
    argb_fmt = SDL_AllocFormat(SDL_PIXELFORMAT_ARGB8888);
    if (SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    if (SDL_SetRenderDrawColor(renderer, 100, 100, 100, 255) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    if (SDL_RenderClear(renderer) != 0) { log_checkpoint(SDL_GetError()); return 1; }

    if (SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    if (SDL_SetRenderDrawColor(renderer, 200, 0, 0, 128) != 0) { log_checkpoint(SDL_GetError()); return 1; }

    SDL_Rect small_rect = {0, 0, 10, 10};
    if (SDL_RenderFillRect(renderer, &small_rect) != 0) { log_checkpoint(SDL_GetError()); return 1; }
    SDL_Rect large_rect = {50, 50, 100, 100};
    if (SDL_RenderFillRect(renderer, &large_rect) != 0) { log_checkpoint(SDL_GetError()); return 1; }

    SDL_Rect small_sample = {5, 5, 1, 1};
    SDL_Rect large_sample = {100, 100, 1, 1};
    Uint32 pixel_small = 0, pixel_large = 0;
    if (SDL_RenderReadPixels(renderer, &small_sample, SDL_PIXELFORMAT_ARGB8888, &pixel_small, 4) != 0) {
        log_checkpoint(SDL_GetError());
        return 1;
    }
    if (SDL_RenderReadPixels(renderer, &large_sample, SDL_PIXELFORMAT_ARGB8888, &pixel_large, 4) != 0) {
        log_checkpoint(SDL_GetError());
        return 1;
    }
    Uint8 smr, smg, smb, sma, lgr, lgg, lgb, lga;
    SDL_GetRGBA(pixel_small, argb_fmt, &smr, &smg, &smb, &sma);
    SDL_GetRGBA(pixel_large, argb_fmt, &lgr, &lgg, &lgb, &lga);

    /* RGB only, not alpha: the small fill's CPU path reproduces SDL's real
     * dstA = srcA + dstA*(1-srcA) formula, while the large fill's hardware
     * path applies the same single blend-factor pair to alpha as to RGB
     * (no separate alpha factors on this hardware), so the two legitimately
     * disagree on alpha even when correct. */
    const int case_f_tolerance = 4;
    int case_f_pass = (abs((int)smr - (int)lgr) <= case_f_tolerance && abs((int)smg - (int)lgg) <= case_f_tolerance &&
                        abs((int)smb - (int)lgb) <= case_f_tolerance);
    {
        char msg[256];
        snprintf(msg, sizeof(msg),
                 "CASE F: small-fill(10x10)=(%d,%d,%d,%d) large-fill(100x100)=(%d,%d,%d,%d) => %s",
                 smr, smg, smb, sma, lgr, lgg, lgb, lga, case_f_pass ? "PASS" : "FAIL");
        log_checkpoint(msg);
    }
    SDL_FreeFormat(argb_fmt);

    /* Visual result: six horizontal bands, one per case, green=PASS/red=FAIL. Held on screen for HOLD_SECONDS before exit. */
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
    int win_w = 0, win_h = 0;
    SDL_GetWindowSize(window, &win_w, &win_h);
    int band_h = win_h / 6;
    int results[6] = {case_a_pass, rejected, case_c_pass, case_d_pass, case_e_pass, case_f_pass};
    for (int i = 0; i < 6; i++) {
        SDL_Rect band = {0, i * band_h, win_w, (i == 5) ? (win_h - i * band_h) : band_h};
        SDL_SetRenderDrawColor(renderer, results[i] ? 0 : 200, results[i] ? 200 : 0, 0, 255);
        SDL_RenderFillRect(renderer, &band);
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
