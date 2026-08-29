#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
work_dir="${3:?work dir required}"
bundle_dir="${4:?bundle dir required}"
source "$repo_root/packages/.shared/upstream-port.sh"

workspace_dir="$work_dir/mksdl2-workspace"
script="$repo_root/scripts/mksdl2.sh"

require_mmiyoo_sdl_provider
image="$(ensure_union_toolchain_image)"
[[ -f "$script" ]] || { printf 'Missing buildbot mksdl2.sh: %s\n' "$script" >&2; exit 1; }
mkdir -p "$workspace_dir"

# The buildbot copy of mksdl2.sh supplies the add-ons.  Its skip flag makes the
# prebuilt MMIYOO provider the only SDL core accepted by configure/link steps.
docker run --rm --user root -e HOME=/root \
  -e BUILDBOT_UID="$(id -u)" \
  -e BUILDBOT_GID="$(id -g)" \
  -e NPROC="${NPROC:-}" \
  -v "$workspace_dir":/workspace \
  -v "$script":/opt/buildbot/mksdl2.sh:ro \
  -v "$MMIYOO_SDL2_PREFIX":/opt/mmiyoo-sdl2:ro \
  --workdir /workspace "$image" bash -lc '
    set -e
    cp -a /opt/mmiyoo-sdl2/. /workspace/build/
    SDL2_SKIP_CORE=1 WORKSPACE=/workspace SDL2_PREFIX=/workspace/build \
      bash /opt/buildbot/mksdl2.sh
    chown -R "$BUILDBOT_UID:$BUILDBOT_GID" /workspace
  '

mkdir -p "$bundle_dir/lib" "$bundle_dir/include" "$bundle_dir/lib/pkgconfig"
cp -a "$workspace_dir/build/include/." "$bundle_dir/include/"
for pattern in libSDL2_image*.so* libSDL2_ttf*.so* libSDL2_gfx*.so* libSDL2_mixer*.so* libSDL2_net*.so*; do
  for library in "$workspace_dir"/build/lib/$pattern; do
    [[ -e "$library" || -L "$library" ]] || continue
    cp -a "$library" "$bundle_dir/lib/"
  done
done
for pc in "$workspace_dir"/build/lib/pkgconfig/SDL2_{image,ttf,gfx,mixer,net}.pc; do
  [[ -f "$pc" ]] || continue
  sed 's|^prefix=.*|prefix=${pcfiledir}/../..|' "$pc" > "$bundle_dir/lib/pkgconfig/$(basename "$pc")"
done
install -m 644 "$repo_root/packages/sdl2-mmiyoo-addons/README.md" "$bundle_dir/README.md"
