#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$script_dir/common.sh"

command="${1:-}"
package_id="${2:-}"
root="$(repo_root)"
image="${MM_X86_BUILDBOT_IMAGE:-x86-mm-buildbot:latest}"
dockerfile="$root/docker/x86-mm-buildbot/Dockerfile"

usage() {
  printf 'usage: %s build|run <package> | shell\n' "$(basename "$0")" >&2
  printf '       MM_X86_BUILDBOT_IMAGE=name:tag %s build <package>\n' "$(basename "$0")" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

[[ "$command" == build || "$command" == run || "$command" == shell ]] || {
  usage
  exit 2
}
[[ -n "$package_id" || "$command" == shell ]] || {
  usage
  exit 2
}

require_command docker
[[ -f "$dockerfile" ]] || {
  printf 'Missing x86 build image Dockerfile: %s\n' "$dockerfile" >&2
  exit 1
}

if [[ "${MM_X86_BUILDBOT_REBUILD:-0}" == 1 ]] || ! docker image inspect "$image" >/dev/null 2>&1; then
  printf 'Building Docker image: %s\n' "$image"
  docker build -f "$dockerfile" -t "$image" "$root"
fi

docker_args=(
  run --rm
  --user "$(id -u):$(id -g)"
  --env HOME=/workspace/work/docker-home
  --env HOST_JOBS="${HOST_JOBS:-}"
  --volume "$root:/workspace"
  --workdir /workspace
)

if [[ -n "${HOST_SOURCE_DIR:-}" ]]; then
  host_source_dir="$(CDPATH= cd -- "$HOST_SOURCE_DIR" && pwd)"
  root_abs="$(CDPATH= cd -- "$root" && pwd)"
  if [[ "$host_source_dir" == "$root_abs"/* ]]; then
    relative_source="${host_source_dir#"$root_abs"/}"
    docker_args+=(--env "HOST_SOURCE_DIR=/workspace/$relative_source")
  else
    docker_args+=(
      --env HOST_SOURCE_DIR=/mnt/host-source
      --volume "$host_source_dir:/mnt/host-source:ro"
    )
  fi
fi

case "$command" in
  build)
    exec docker "${docker_args[@]}" "$image" scripts/build-host.sh "$package_id"
    ;;
  shell)
    exec docker "${docker_args[@]}" --entrypoint /bin/bash "$image"
    ;;
  run)
    if [[ -n "${DISPLAY:-}" && -d /tmp/.X11-unix ]]; then
      docker_args+=(--env DISPLAY --volume /tmp/.X11-unix:/tmp/.X11-unix:ro)
    fi

    if [[ -n "${WAYLAND_DISPLAY:-}" && -n "${XDG_RUNTIME_DIR:-}" && -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]]; then
      docker_args+=(
        --env WAYLAND_DISPLAY=mm-wayland
        --env XDG_RUNTIME_DIR=/tmp
        --volume "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY:/tmp/mm-wayland:ro"
      )
    fi

    if [[ -d /mnt/wslg ]]; then
      docker_args+=(--env PULSE_SERVER="${PULSE_SERVER:-unix:/mnt/wslg/PulseServer}" --volume /mnt/wslg:/mnt/wslg:ro)
    elif [[ -n "${PULSE_SERVER:-}" ]]; then
      printf 'Warning: PULSE_SERVER is set but /mnt/wslg is unavailable; audio may not connect.\n' >&2
      docker_args+=(--env PULSE_SERVER)
    fi

    exec docker "${docker_args[@]}" "$image" scripts/run-host.sh "$package_id"
    ;;
esac
