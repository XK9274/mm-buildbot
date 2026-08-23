#!/usr/bin/env bash
# Common staging helpers for Miyoo Mini-family app distributions.

stage_mmiyoo_sdl_runtime() {
  local prefix="${1:?SDL prefix required}"
  local destination="${2:?runtime destination required}"
  local library

  [[ -d "$prefix/lib" ]] || {
    printf 'MMIYOO SDL2 provider bundle is incomplete: %s\n' "$prefix" >&2
    return 1
  }
  mkdir -p "$destination"
  for library in libSDL2-2.0.so.0 libEGL.so libGLESv2.so libneonarmmiyoo.so; do
    [[ -f "$prefix/lib/$library" ]] || {
      printf 'Missing SDL runtime library: %s/lib/%s\n' "$prefix" "$library" >&2
      return 1
    }
    install -m 755 "$prefix/lib/$library" "$destination/$library"
  done
}

require_owned_data_dir() {
  local variable="${1:?environment variable name required}"
  local description="${2:?data description required}"
  local path="${!variable:-}"

  [[ -n "$path" && -d "$path" ]] || {
    printf '%s must point to a directory containing %s. Proprietary game data is not bundled.\n' "$variable" "$description" >&2
    return 1
  }
  printf '%s\n' "$path"
}

is_mmiyoo_platform_library() {
  case "$1" in
    libc.so.*|libm.so.*|libdl.so.*|librt.so.*|libpthread.so.*|libstdc++.so.*|libgcc_s.so.*|libz.so.*|ld-linux-armhf.so.*|libmi_*.so|libcam_os_wrapper.so)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

verify_mmiyoo_runtime_closure() {
  local root="${1:?distribution root required}"
  local target needed

  command -v arm-linux-gnueabihf-readelf >/dev/null 2>&1 || {
    printf 'Missing required tool: arm-linux-gnueabihf-readelf\n' >&2
    return 1
  }
  while IFS= read -r -d '' target; do
    while IFS= read -r needed; do
      is_mmiyoo_platform_library "$needed" && continue
      if ! find "$root" -type f -name "$needed" -print -quit | grep -q .; then
        printf 'Missing bundled runtime dependency for %s: %s\n' "$target" "$needed" >&2
        return 1
      fi
    done < <(arm-linux-gnueabihf-readelf -d "$target" 2>/dev/null | awk -F'[][]' '/Shared library:/ { print $2 }')
  done < <(find "$root" -type f \( -perm -0100 -o -name '*.so*' \) -print0)
}
