#!/usr/bin/env bash
# Strips embedded cover-art video streams from DungeonRush's BGM .ogg files.
# The MMIYOO SDL2_mixer cross-build falls back to the bundled stb_vorbis
# decoder (no libvorbis in the toolchain sysroot for ./configure to find),
# which -- unlike the host's full libvorbisfile -- can't demux a Vorbis
# audio stream out of an Ogg container that also carries a multiplexed
# Theora video/cover-art stream, and fails with
# "stb_vorbis_open_rwops: VORBIS_invalid_first_page". Re-mux to audio-only,
# lossless, before staging. Runs against the staged res/audio directory;
# never touches the pinned upstream source checkout.
set -euo pipefail

audio_dir="${1:?usage: fix-bgm-audio.sh <staged res/audio dir>}"

command -v ffprobe >/dev/null 2>&1 || { printf 'fix-bgm-audio.sh: ffprobe required\n' >&2; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { printf 'fix-bgm-audio.sh: ffmpeg required\n' >&2; exit 1; }

for ogg in "$audio_dir"/*.ogg; do
  [[ -f "$ogg" ]] || continue
  stream_count=$(ffprobe -v error -show_entries stream=index -of csv=p=0 "$ogg" | wc -l)
  if [[ "$stream_count" -le 1 ]]; then
    continue
  fi
  tmp="${ogg%.ogg}.audio-only.ogg"
  ffmpeg -y -v error -i "$ogg" -map 0:a:0 -c copy -f ogg "$tmp"
  mv -f "$tmp" "$ogg"
  printf 'fix-bgm-audio: stripped non-audio stream(s) from %s\n' "$(basename "$ogg")"
done
