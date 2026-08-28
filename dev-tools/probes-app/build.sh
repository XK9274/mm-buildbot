#!/usr/bin/env bash
# Compiles every dev-tools/*-probe (or just the ones named on the command
# line) into a shared output directory, via each probe's own compile.sh.
# Build-only -- see package.sh to assemble an on-device app from the
# result, and ../../scripts/push-app.sh to deploy one.
#
# Usage: build.sh [out_dir] [probe-name ...]
#   out_dir defaults to work/probes-app/bin
#   with no probe names, every dev-tools/*-probe with a compile.sh is built
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dev_tools_dir="$(CDPATH= cd -- "$script_dir/.." && pwd)"
repo_root="$(CDPATH= cd -- "$dev_tools_dir/.." && pwd)"

out_dir="${1:-$repo_root/work/probes-app/bin}"
[[ $# -gt 0 ]] && shift
probes=("$@")

if [[ ${#probes[@]} -eq 0 ]]; then
  for d in "$dev_tools_dir"/*-probe; do
    [[ -f "$d/compile.sh" ]] && probes+=("$(basename "$d")")
  done
fi

mkdir -p "$out_dir"
built=()
failed=()
for probe in "${probes[@]}"; do
  compile="$dev_tools_dir/$probe/compile.sh"
  if [[ ! -f "$compile" ]]; then
    printf 'build.sh: no compile.sh for probe "%s", skipping\n' "$probe" >&2
    failed+=("$probe")
    continue
  fi
  printf 'build.sh: building %s\n' "$probe"
  if "$compile" "$out_dir"; then
    built+=("$probe")
  else
    printf 'build.sh: %s failed to build, skipping\n' "$probe" >&2
    failed+=("$probe")
  fi
done

printf 'build.sh: built %d probe(s) into %s: %s\n' "${#built[@]}" "$out_dir" "${built[*]:-none}"
[[ ${#failed[@]} -eq 0 ]] || printf 'build.sh: %d probe(s) skipped/failed: %s\n' "${#failed[@]}" "${failed[*]}" >&2
[[ ${#built[@]} -gt 0 ]] || exit 1
