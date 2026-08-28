/* Local/device probe: BV2-style SDL + PhysFS + BMP + optional SDL_ttf path. */
#include <SDL.h>
#include <SDL_ttf.h>
#include <physfs.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void ck(const char *s) { fprintf(stderr, "[live-asset] %s\n", s); fflush(stderr); }

static SDL_Texture **live_textures;
static int live_texture_count;
static SDL_Surface **live_surfaces;
static int live_surface_count;

typedef struct ProbeRoute {
    const char *name;
    int window_w;
    int window_h;
    int target_w;
    int target_h;
    float scale_x;
    float scale_y;
} ProbeRoute;

static ProbeRoute route_for_name(const char *name)
{
    ProbeRoute route = {"800", 800, 600, 800, 600, 1.0f, 1.0f};
    if (!name || !*name || strcmp(name, "800") == 0) return route;
    if (strcmp(name, "640") == 0) {
        route.name = "640";
        route.window_w = route.target_w = 640;
        route.window_h = route.target_h = 480;
        route.scale_x = route.scale_y = 0.8f;
    } else if (strcmp(name, "mixed") == 0) {
        route.name = "mixed";
        route.target_w = 640; route.target_h = 480;
        route.scale_x = route.scale_y = 0.8f;
    } else if (strcmp(name, "oversized") == 0) {
        route.name = "oversized";
        route.window_w = 640; route.window_h = 480;
    } else {
        fprintf(stderr, "[live-asset] unknown route '%s' (use 800, 640, mixed, or oversized)\n", name);
        exit(2);
    }
    return route;
}

static void retain_texture(SDL_Texture *t)
{
    SDL_Texture **p = (SDL_Texture **)realloc(live_textures, (live_texture_count + 1) * sizeof *p);
    if (p) { live_textures = p; live_textures[live_texture_count++] = t; }
}

static void retain_surface(SDL_Surface *s)
{
    SDL_Surface **p = (SDL_Surface **)realloc(live_surfaces, (live_surface_count + 1) * sizeof *p);
    if (p) { live_surfaces = p; live_surfaces[live_surface_count++] = s; }
}

static SDL_Surface *load_bmp(const char *name)
{
    PHYSFS_File *f = PHYSFS_openRead(name); PHYSFS_sint64 n; unsigned char *data;
    SDL_RWops *rw; SDL_Surface *surface; char msg[256];
    if (!f) { snprintf(msg, sizeof msg, "open failed: %s", name); ck(msg); return NULL; }
    n = PHYSFS_fileLength(f); data = (unsigned char *)malloc((size_t)n);
    if (!data || PHYSFS_readBytes(f, data, n) != n) {
        snprintf(msg, sizeof msg, "read failed: %s", name); ck(msg);
        free(data); PHYSFS_close(f); return NULL;
    }
    PHYSFS_close(f); rw = SDL_RWFromMem(data, (int)n);
    surface = rw ? SDL_LoadBMP_RW(rw, 1) : NULL; free(data);
    if (!surface) { snprintf(msg, sizeof msg, "SDL_LoadBMP_RW failed: %s (%s)", name, SDL_GetError()); ck(msg); }
    return surface;
}

static SDL_Texture *load_texture(SDL_Renderer *r, const char *name)
{
    SDL_Surface *s = load_bmp(name); SDL_Texture *t;
    if (!s) return NULL; t = SDL_CreateTextureFromSurface(r, s); SDL_FreeSurface(s);
    if (!t) ck(SDL_GetError()); else retain_texture(t); return t;
}

static void silent_audio_callback(void *userdata, Uint8 *stream, int len)
{
    (void)userdata;
    SDL_memset(stream, 0, len);
}

static void set_probe_target(SDL_Renderer *renderer, SDL_Texture *target, const ProbeRoute *route)
{
    SDL_SetRenderTarget(renderer, target);
    SDL_RenderSetScale(renderer, route->scale_x, route->scale_y);
}

static int font_surface_test(const char *font_path)
{
    TTF_Font *font; SDL_Surface *text, *rgb565;
    if (!font_path || !*font_path) { ck("SDL_ttf test skipped"); return 0; }
    ck("TTF_OpenFont: starting"); font = TTF_OpenFont(font_path, 34);
    if (!font) { ck(TTF_GetError()); return -1; }
    text = TTF_RenderUTF8_Blended(font, "BlobbyVolley2", (SDL_Color){255,255,255,255});
    if (!text) { ck(TTF_GetError()); TTF_CloseFont(font); return -1; }
    rgb565 = SDL_CreateRGBSurfaceWithFormat(0, text->w, text->h, 16, SDL_PIXELFORMAT_RGB565);
    if (!rgb565) { ck(SDL_GetError()); SDL_FreeSurface(text); TTF_CloseFont(font); return -1; }
    SDL_BlitSurface(text, NULL, rgb565, NULL); SDL_FreeSurface(text); SDL_FreeSurface(rgb565);
    TTF_CloseFont(font); ck("SDL_ttf test complete"); return 0;
}

int main(int argc, char **argv)
{
    const char *gfx = argc > 1 ? argv[1] : "gfx.zip";
    const char *backgrounds = argc > 2 ? argv[2] : "backgrounds.zip";
    const char *font_path = argc > 3 ? argv[3] : "pokemon-dppt.ttf";
    int frame_count = argc > 4 ? atoi(argv[4]) : 1, i, j;
    ProbeRoute route = route_for_name(argc > 5 ? argv[5] : "800");
    SDL_Window *w; SDL_Renderer *r; SDL_Texture *target; SDL_Surface *icon;
    SDL_Texture *first_background = NULL, *font_a = NULL, *font_b = NULL, *blob_a = NULL;
    char name[64], msg[96];
    snprintf(msg, sizeof msg, "starting route=%s window=%dx%d target=%dx%d scale=%.2fx%.2f frames=%d",
             route.name, route.window_w, route.window_h, route.target_w, route.target_h,
             route.scale_x, route.scale_y, frame_count);
    ck(msg);
    if (!PHYSFS_init(argv[0]) || !PHYSFS_mount(gfx, "/", 1) || !PHYSFS_mount(backgrounds, "/", 1)) { ck("PhysFS init/mount failed"); return 1; }
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_JOYSTICK) != 0) { ck(SDL_GetError()); return 1; }
    if (TTF_Init() != 0) { ck(TTF_GetError()); return 1; }
    /* Real BV2 constructs SoundManager (opens the audio device + plays two
     * preload sounds) before setupRenderManager() -- match that ordering
     * here, before window/renderer creation, not just setting the
     * SDL_INIT_AUDIO flag. */
    {
        SDL_AudioSpec desired, obtained; SDL_AudioDeviceID dev;
        SDL_zero(desired);
        desired.freq = 44100; desired.format = AUDIO_S16LSB; desired.channels = 2;
        desired.samples = 1024; desired.callback = silent_audio_callback;
        dev = SDL_OpenAudioDevice(NULL, 0, &desired, &obtained, SDL_AUDIO_ALLOW_FORMAT_CHANGE);
        if (dev == 0) { ck(SDL_GetError()); ck("audio device open failed; continuing without it"); }
        else { SDL_PauseAudioDevice(dev, 0); ck("audio device opened and unpaused"); }
    }
    w = SDL_CreateWindow("live asset probe", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                         route.window_w, route.window_h, SDL_WINDOW_RESIZABLE);
    if (!w) { ck(SDL_GetError()); return 1; }
    icon = SDL_LoadBMP("Icon.bmp"); if (icon) { SDL_SetWindowIcon(w, icon); SDL_FreeSurface(icon); ck("Icon.bmp loaded"); } else ck("Icon.bmp unavailable; continuing");
    r = SDL_CreateRenderer(w, -1, 0); if (!r) { ck(SDL_GetError()); return 1; }
    target = SDL_CreateTexture(r, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET,
                               route.target_w, route.target_h);
    if (!target) { ck(SDL_GetError()); return 1; }
    set_probe_target(r, target, &route);
    snprintf(msg, sizeof msg, "route established: window=%dx%d target=%dx%d scale=%.2fx%.2f",
             route.window_w, route.window_h, route.target_w, route.target_h,
             route.scale_x, route.scale_y);
    ck(msg);
    SDL_SetRenderDrawColor(r, 0, 0, 0, 255); SDL_RenderClear(r);
    /* Real BV2's init() loads every asset below exactly ONCE, then the
     * continuous while(running) mainloop only re-draws/re-composites
     * already-loaded textures every frame -- it never reloads from PhysFS
     * per frame. The original version of this probe re-ran this entire
     * load block every "iteration" and never freed anything, so it hit an
     * artificial MMA OOM ceiling after ~3-4 iterations (~740 retained
     * textures) without ever reaching sustained per-frame composite/present
     * load. Restructured: load once here, then loop just the per-frame
     * draw+composite+present phase below like a real mainloop would. */
    {
        ck("asset phase: background/ball/shadow/blobs/blood");
        {
            SDL_Surface *s = SDL_CreateRGBSurface(0, 1, 1, 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000);
            SDL_Texture *t;
            if (!s) { ck(SDL_GetError()); goto done; }
            SDL_FillRect(s, NULL, SDL_MapRGB(s->format, 255, 255, 255));
            t = SDL_CreateTextureFromSurface(r, s); SDL_FreeSurface(s);
            if (!t) { ck(SDL_GetError()); goto done; } retain_texture(t);
            s = SDL_CreateRGBSurface(0, 5, 5, 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000);
            if (!s) { ck(SDL_GetError()); goto done; }
            SDL_FillRect(s, NULL, SDL_MapRGB(s->format, 255, 255, 255));
            t = SDL_CreateTextureFromSurface(r, s); if (!t) { SDL_FreeSurface(s); ck(SDL_GetError()); goto done; } retain_texture(t);
            SDL_FillRect(s, NULL, SDL_MapRGB(s->format, 0, 0, 0));
            t = SDL_CreateTextureFromSurface(r, s); SDL_FreeSurface(s);
            if (!t) { ck(SDL_GetError()); goto done; } retain_texture(t);
        }
        {
            SDL_Texture *bg1 = load_texture(r, "backgrounds/strand2.bmp");
            if (!bg1) goto done;
            first_background = bg1;
        }
        for (j = 1; j <= 16; ++j) { snprintf(name, sizeof name, "gfx/ball%02d.bmp", j); if (!load_texture(r, name)) goto done; }
        if (!load_texture(r, "gfx/schball.bmp")) goto done;
        for (j = 1; j <= 5; ++j) {
            SDL_Surface *blob, *shadow, *blob8888, *shadow8888; SDL_Texture *t;
            snprintf(name, sizeof name, "gfx/blobbym%d.bmp", j); blob = load_bmp(name); if (!blob) goto done;
            blob8888 = SDL_ConvertSurfaceFormat(blob, SDL_PIXELFORMAT_ABGR8888, 0); SDL_FreeSurface(blob);
            if (!blob8888) { ck(SDL_GetError()); goto done; } retain_surface(blob8888);
            t = SDL_CreateTexture(r, SDL_PIXELFORMAT_ABGR8888, SDL_TEXTUREACCESS_STREAMING, blob8888->w, blob8888->h);
            if (!t) { ck(SDL_GetError()); goto done; } retain_texture(t); SDL_SetTextureBlendMode(t, SDL_BLENDMODE_BLEND); SDL_UpdateTexture(t, NULL, blob8888->pixels, blob8888->pitch);
            if (!blob_a) blob_a = t;
            t = SDL_CreateTexture(r, SDL_PIXELFORMAT_ABGR8888, SDL_TEXTUREACCESS_STREAMING, blob8888->w, blob8888->h);
            if (!t) { ck(SDL_GetError()); goto done; } retain_texture(t); SDL_SetTextureBlendMode(t, SDL_BLENDMODE_BLEND); SDL_UpdateTexture(t, NULL, blob8888->pixels, blob8888->pitch);
            snprintf(name, sizeof name, "gfx/sch1%d.bmp", j); shadow = load_bmp(name); if (!shadow) goto done;
            shadow8888 = SDL_ConvertSurfaceFormat(shadow, SDL_PIXELFORMAT_ABGR8888, 0); SDL_FreeSurface(shadow);
            if (!shadow8888) { ck(SDL_GetError()); goto done; } retain_surface(shadow8888);
            t = SDL_CreateTexture(r, SDL_PIXELFORMAT_ABGR8888, SDL_TEXTUREACCESS_STREAMING, shadow8888->w, shadow8888->h);
            if (!t) { ck(SDL_GetError()); goto done; } retain_texture(t); SDL_UpdateTexture(t, NULL, shadow8888->pixels, shadow8888->pitch);
            t = SDL_CreateTexture(r, SDL_PIXELFORMAT_ABGR8888, SDL_TEXTUREACCESS_STREAMING, shadow8888->w, shadow8888->h);
            if (!t) { ck(SDL_GetError()); goto done; } retain_texture(t); SDL_UpdateTexture(t, NULL, shadow8888->pixels, shadow8888->pitch);
        }
        if (!load_texture(r, "gfx/blood.bmp")) goto done;
        /* Real BV2's setBackground() (called right after RenderManagerSDL::
         * init() completes, before entering the mainloop) loads the
         * background a SECOND time into a fresh texture, then destroys the
         * first one -- in that create-then-destroy order. One of this
         * investigation's observed freeze locations. Mirror it exactly:
         * live_textures[0] is strand2.bmp's first load from the block above
         * (the very first real load_texture() call this iteration). */
        {
            SDL_Texture *new_bg = load_texture(r, "backgrounds/strand2.bmp");
            if (!new_bg) goto done;
            ck("setBackground-style: second background loaded, about to destroy first");
            SDL_DestroyTexture(first_background);
            first_background = new_bg;
            ck("setBackground-style: first background destroyed");
        }
        if (font_surface_test(font_path) != 0) goto done;
        ck("asset phase: lazy font glyphs (normal + highlight textures)");
        for (j = 0; j <= 58; ++j) {
            SDL_Surface *s, *h; SDL_Texture *a, *b;
            snprintf(name, sizeof name, "gfx/font%02d.bmp", j); s = load_bmp(name); if (!s) goto done;
            a = SDL_CreateTextureFromSurface(r, s); h = SDL_CreateRGBSurfaceWithFormat(0, s->w, s->h, 32, SDL_PIXELFORMAT_ABGR8888);
            if (!a || !h) { ck(SDL_GetError()); if (a) SDL_DestroyTexture(a); SDL_FreeSurface(s); if (h) SDL_FreeSurface(h); goto done; }
            SDL_FillRect(h, NULL, 0); SDL_BlitSurface(s, NULL, h, NULL); b = SDL_CreateTextureFromSurface(r, h);
            retain_texture(a); if (b) retain_texture(b); else { ck(SDL_GetError()); SDL_FreeSurface(h); SDL_FreeSurface(s); goto done; }
            retain_surface(s); retain_surface(h);
            if (!font_a) { font_a = a; font_b = b; }
            /* BV2 queues glyph copies before the first present; keep the
             * command-buffer pressure present while more glyphs are loaded. */
            SDL_RenderCopy(r, a, NULL, NULL); SDL_RenderCopy(r, b, NULL, NULL);
        }
        set_probe_target(r, NULL, &route); SDL_RenderCopy(r, target, NULL, NULL); SDL_RenderPresent(r); set_probe_target(r, target, &route);
        SDL_PumpEvents(); ck("load phase complete, entering per-frame mainloop simulation");
    }
    /* Per-frame mainloop simulation: real BV2's while(running) loop just
     * re-draws already-loaded textures (background/blobs/ball/font glyphs)
     * onto mRenderTarget every frame, then composites+presents -- it never
     * re-loads from PhysFS after init(). No new allocation happens in this
     * loop (no CreateTexture/UpdateTexture), matching that shape, so it can
     * genuinely run for many frames without hitting an artificial MMA
     * ceiling like the old repeated-load-per-iteration version did. */
    for (i = 0; i < frame_count; ++i) {
        SDL_Rect dst;
        SDL_SetRenderDrawColor(r, 0, 0, 0, 255); SDL_RenderClear(r);
        dst.x = 0; dst.y = 0; dst.w = 800; dst.h = 600;
        SDL_RenderCopy(r, first_background, NULL, &dst);
        if (blob_a) { dst.x = (i * 3) % 700; dst.y = 200; dst.w = 32; dst.h = 32; SDL_RenderCopy(r, blob_a, NULL, &dst); }
        if (font_a) { dst.x = 10; dst.y = 10; dst.w = 60; dst.h = 20; SDL_RenderCopy(r, font_a, NULL, &dst); SDL_RenderCopy(r, font_b, NULL, &dst); }
        set_probe_target(r, NULL, &route); SDL_RenderCopy(r, target, NULL, NULL); SDL_RenderPresent(r); set_probe_target(r, target, &route);
        SDL_PumpEvents();
        if (i == 0 || (i + 1) % 100 == 0 || i + 1 == frame_count) {
            snprintf(msg, sizeof msg, "frame %d/%d complete", i + 1, frame_count); ck(msg);
        }
    }
done:
    SDL_DestroyTexture(target); SDL_DestroyRenderer(r); SDL_DestroyWindow(w); TTF_Quit(); SDL_Quit(); PHYSFS_deinit(); ck("exiting"); return 0;
}
