#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?missing package id}"
root="${2:?missing repository root}"
host_root="${3:?missing host root}"
source_dir="${4:?missing source directory}"
shift 4

[[ "$package_id" == "konpacto-mmiyoo" ]] || exit 1

export LD_LIBRARY_PATH="$host_root/deps/luajit/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# konpacto reads/writes paths like "assets/songs" relative to its working
# directory; those live under src/ in the upstream checkout.
cd "$source_dir/src"

# konpacto's configTheme/configFont default to NULL and are only set from an
# existing config.txt; InitializePages() then strcmp()s them unconditionally,
# so it segfaults on every first run with no config.txt present (upstream
# bug, not a packaging issue -- see packages/konpacto-mmiyoo/README.md).
[[ -f config.txt ]] || cp "$root/packages/konpacto-mmiyoo/templates/Konpacto/config.txt" config.txt

exec "$host_root/bin/konpacto" "$@"
