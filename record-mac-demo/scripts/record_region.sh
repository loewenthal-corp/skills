#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage:
  record_region.sh OUTPUT [X Y WIDTH HEIGHT]

Examples:
  record_region.sh /tmp/demo.mov
  record_region.sh /tmp/demo.mov -377 -1415 2560 1415

Starts a macOS screencapture video recording. Stop by typing any character
in the recording terminal or by writing to the PTY from Codex.
USAGE
}

if [[ $# -ne 1 && $# -ne 5 ]]; then
  usage
  exit 2
fi

output="$1"
mkdir -p "$(dirname "$output")"
rm -f "$output"

args=(-v -k)
if [[ $# -eq 5 ]]; then
  x="$2"
  y="$3"
  width="$4"
  height="$5"
  args+=(-R "${x},${y},${width},${height}")
fi

echo "Recording to: $output"
echo "Stop with any key in this terminal."
screencapture "${args[@]}" "$output"

if [[ -s "$output" ]]; then
  ls -lh "$output"
  if command -v ffprobe >/dev/null 2>&1; then
    ffprobe -v error \
      -show_entries format=duration,size \
      -show_entries stream=width,height,r_frame_rate \
      -of json "$output"
  fi
else
  echo "No output file was produced." >&2
  exit 1
fi
