/* Isolates whether the BlobbyVolley2 hang (freezes inside PHYSFS_readBytes
 * when reading gfx/titel.bmp, a 314KB DEFLATE entry in gfx.zip, after ~160
 * prior small successful reads from the same archive) is a PhysFS/zlib
 * issue on its own -- no SDL2, no MI_SYS, no MI_GFX at all. Mounts gfx.zip,
 * repeats BV2's real access pattern (many small font/blob reads, then one
 * big titel.bmp read) for several iterations in a single process, printing
 * a flushed checkpoint before/after every single PHYSFS_readBytes call so a
 * hang is pinpointed to the exact iteration and file. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "physfs.h"

static void log_ckpt(const char *msg)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    printf("[%ld.%03ld] %s\n", (long)ts.tv_sec, ts.tv_nsec / 1000000, msg);
    fflush(stdout);
}

static int read_file(const char *path)
{
    char msg[256];
    PHYSFS_file *f;
    PHYSFS_sint64 len;
    char *buf;
    PHYSFS_sint64 num_read;

    snprintf(msg, sizeof(msg), "about to PHYSFS_openRead(%s)", path);
    log_ckpt(msg);

    f = PHYSFS_openRead(path);
    if (!f) {
        snprintf(msg, sizeof(msg), "PHYSFS_openRead(%s) FAILED: %s", path,
                 PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode()));
        log_ckpt(msg);
        return -1;
    }

    len = PHYSFS_fileLength(f);
    snprintf(msg, sizeof(msg), "opened %s, length=%lld, about to malloc+PHYSFS_readBytes", path, (long long)len);
    log_ckpt(msg);

    buf = (char *)malloc((size_t)len);
    if (!buf) {
        log_ckpt("malloc FAILED");
        PHYSFS_close(f);
        return -1;
    }

    num_read = PHYSFS_readBytes(f, buf, (PHYSFS_uint64)len);

    snprintf(msg, sizeof(msg), "PHYSFS_readBytes(%s) returned num_read=%lld (expected %lld)",
             path, (long long)num_read, (long long)len);
    log_ckpt(msg);

    free(buf);
    PHYSFS_close(f);

    snprintf(msg, sizeof(msg), "closed %s", path);
    log_ckpt(msg);

    return (num_read == len) ? 0 : -1;
}

int main(int argc, char *argv[])
{
    const char *zip_path = (argc > 1) ? argv[1] : "gfx.zip";
    int iterations = (argc > 2) ? atoi(argv[2]) : 20;
    int iter;

    log_ckpt("probe starting");

    if (!PHYSFS_init(argv[0])) {
        log_ckpt("PHYSFS_init FAILED");
        return 1;
    }
    log_ckpt("PHYSFS_init complete");

    if (!PHYSFS_mount(zip_path, "/", 1)) {
        char msg[256];
        snprintf(msg, sizeof(msg), "PHYSFS_mount(%s) FAILED: %s", zip_path,
                 PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode()));
        log_ckpt(msg);
        return 1;
    }
    log_ckpt("PHYSFS_mount complete");

    for (iter = 0; iter < iterations; iter++) {
        char msg[128];
        int i;

        snprintf(msg, sizeof(msg), "=== iteration %d/%d: reading 59 font bmps ===", iter, iterations);
        log_ckpt(msg);

        for (i = 0; i <= 58; i++) {
            char path[64];
            snprintf(path, sizeof(path), "gfx/font%02d.bmp", i);
            if (read_file(path) != 0) {
                snprintf(msg, sizeof(msg), "=== iteration %d FAILED on %s ===", iter, path);
                log_ckpt(msg);
                return 1;
            }
        }

        snprintf(msg, sizeof(msg), "=== iteration %d: reading blood.bmp ===", iter);
        log_ckpt(msg);
        if (read_file("gfx/blood.bmp") != 0) {
            log_ckpt("=== iteration FAILED on blood.bmp ===");
            return 1;
        }

        snprintf(msg, sizeof(msg), "=== iteration %d: reading titel.bmp (the suspect) ===", iter);
        log_ckpt(msg);
        if (read_file("gfx/titel.bmp") != 0) {
            snprintf(msg, sizeof(msg), "=== iteration %d FAILED on titel.bmp ===", iter);
            log_ckpt(msg);
            return 1;
        }

        snprintf(msg, sizeof(msg), "=== iteration %d/%d complete, all reads succeeded ===", iter, iterations);
        log_ckpt(msg);
    }

    log_ckpt("all iterations complete, probe exiting cleanly");
    PHYSFS_deinit();
    return 0;
}
