#!/usr/bin/env bash
# Assembles compiled probe binaries (from build.sh) into an on-device app
# directory: config.json, icon.png, launch.sh, bin/, lib/, res/. launch.sh
# runs whichever probe is named in its PROBE= line -- edit that one line
# (and re-run this script, or edit it directly on-device) to switch probes.
# No push -- see ../../scripts/push-app.sh to deploy the result.
#
# Usage: package.sh <bin_dir> <app_dist_dir> [label] [default_probe]
#   bin_dir       output of build.sh (probe binaries, plus a res/ subdir
#                 for any probe that staged its own data files there)
#   app_dist_dir  where to assemble the app
#   label         on-device app name, default "Device Probes"
#   default_probe which binary in bin_dir launch.sh runs by default,
#                 default: the first one found
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dev_tools_dir="$(CDPATH= cd -- "$script_dir/.." && pwd)"
repo_root="$(CDPATH= cd -- "$dev_tools_dir/.." && pwd)"

bin_dir="${1:?usage: package.sh <bin_dir> <app_dist_dir> [label] [default_probe]}"
app_dist_dir="${2:?usage: package.sh <bin_dir> <app_dist_dir> [label] [default_probe]}"
label="${3:-Device Probes}"

sdl2_bundle="${MMIYOO_SDL2_PREFIX:-$repo_root/work/sdl2-mmiyoo-lib/bundle}"
runtime_libs="${RUNTIME_LIBS_DIR:-$repo_root/work/love-mmiyoo-demo/sysroot-libs}"
icon_src="${PROBES_APP_ICON:-$repo_root/packages/blobbyvolley2-mmiyoo/templates/BlobbyVolley2/icon.png}"

built=()
for f in "$bin_dir"/*; do
  [[ -f "$f" && -x "$f" ]] && built+=("$(basename "$f")")
done
[[ ${#built[@]} -gt 0 ]] || { printf 'package.sh: no executables found in %s\n' "$bin_dir" >&2; exit 1; }

default_probe="${4:-${built[0]}}"

rm -rf "$app_dist_dir"
mkdir -p "$app_dist_dir/bin" "$app_dist_dir/lib" "$app_dist_dir/res"

for name in "${built[@]}"; do
  install -m 755 "$bin_dir/$name" "$app_dist_dir/bin/$name"
done
[[ -d "$bin_dir/res" ]] && cp -a "$bin_dir/res/." "$app_dist_dir/res/"

needs_sdl2=0
needs_neon_only=0
needs_freetype=0
for name in "${built[@]}"; do
  case "$name" in
    downscale-bench-probe) needs_neon_only=1; needs_freetype=1 ;;
    *) needs_sdl2=1 ;;
  esac
done

if [[ $needs_sdl2 -eq 1 ]]; then
  for f in libSDL2-2.0.so.0 libEGL.so libGLESv2.so libneonarmmiyoo.so; do
    [[ -f "$sdl2_bundle/lib/$f" ]] && install -m 755 "$sdl2_bundle/lib/$f" "$app_dist_dir/lib/$f"
  done
elif [[ $needs_neon_only -eq 1 ]]; then
  [[ -f "$sdl2_bundle/lib/libneonarmmiyoo.so" ]] && \
    install -m 755 "$sdl2_bundle/lib/libneonarmmiyoo.so" "$app_dist_dir/lib/libneonarmmiyoo.so"
fi
if [[ $needs_freetype -eq 1 ]]; then
  # libfreetype needs libpng16 (embedded PNG bitmap strikes), which in turn
  # needs a newer zlib than this device's own -- all three or the dynamic
  # linker falls back to the system libpng16 and fails on a ZLIB symbol
  # version mismatch.
  for f in libfreetype.so.6 libpng16.so.16 libz.so.1; do
    [[ -f "$runtime_libs/$f" ]] && install -m 755 "$runtime_libs/$f" "$app_dist_dir/lib/$f"
  done
fi

[[ -f "$icon_src" ]] && install -m 644 "$icon_src" "$app_dist_dir/icon.png"

icon_field=""
[[ -f "$app_dist_dir/icon.png" ]] && icon_field='"icon": "icon.png",
  '
cat > "$app_dist_dir/config.json" <<EOF
{
  "label": "$label",
  ${icon_field}"launch": "launch.sh",
  "description": "Standalone diagnostic probes -- edit PROBE= in launch.sh to switch which one runs"
}
EOF

{
  printf '#!/bin/sh\nset -eu\n\n'
  printf '# Edit this line to switch which probe runs. Built into this app: %s\n' "${built[*]}"
  printf 'PROBE="%s"\n' "$default_probe"
  printf '# Args passed to the probe, e.g. for downscale-bench-probe: frames_per_variant\n'
  printf 'PROBE_ARGS=""\n\n'
  printf 'app_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"\n'
  printf 'cd "$app_dir/res" 2>/dev/null || cd "$app_dir"\n'
  printf 'export LD_LIBRARY_PATH="$app_dir/lib:/config/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\n\n'
  printf 'mkdir -p "$app_dir/logs"\n'
  printf 'run_log="$app_dir/logs/${PROBE}-$(date +%%Y%%m%%d-%%H%%M%%S).log"\n'
  printf 'set +e\n'
  printf '"$app_dir/bin/$PROBE" $PROBE_ARGS > "$run_log" 2>&1\n'
  printf 'probe_exit=$?\n'
  printf 'set -e\n'
  printf 'echo "exit code: $probe_exit" >> "$run_log"\n'
  printf 'exit "$probe_exit"\n'
} > "$app_dist_dir/launch.sh"
chmod 755 "$app_dist_dir/launch.sh"

printf 'package.sh: assembled %s at %s (default probe: %s)\n' "$label" "$app_dist_dir" "$default_probe"
