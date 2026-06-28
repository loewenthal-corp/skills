#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage:
  condense_video.sh INPUT OUTPUT SPEED_START SPEED_END [SPEED_FACTOR]

Times are seconds. The segment [SPEED_START, SPEED_END] is accelerated.
Default SPEED_FACTOR is 35.

Example:
  condense_video.sh demo-full.mp4 demo-condensed.mp4 60 340 35
USAGE
}

if [[ $# -lt 4 || $# -gt 5 ]]; then
  usage
  exit 2
fi

input="$1"
output="$2"
speed_start="$3"
speed_end="$4"
speed_factor="${5:-35}"

if [[ ! -f "$input" ]]; then
  echo "Input not found: $input" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required." >&2
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "ffprobe is required." >&2
  exit 1
fi

duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$input")"

awk -v start="$speed_start" -v end="$speed_end" -v factor="$speed_factor" -v duration="$duration" '
  BEGIN {
    if (start < 0 || end <= start || factor <= 1 || start >= duration) {
      exit 1
    }
  }
' || {
  echo "Invalid timing. Require 0 <= SPEED_START < SPEED_END, SPEED_FACTOR > 1, and SPEED_START < duration ($duration)." >&2
  exit 1
}

mkdir -p "$(dirname "$output")"

if awk -v end="$speed_end" -v duration="$duration" 'BEGIN { exit !(end >= duration) }'; then
  filter="[0:v]trim=start=0:end=${speed_start},setpts=PTS-STARTPTS[v0];\
[0:v]trim=start=${speed_start},setpts=(PTS-STARTPTS)/${speed_factor}[v1];\
[v0][v1]concat=n=2:v=1:a=0,scale=1920:-2,format=yuv420p[v]"
else
  filter="[0:v]trim=start=0:end=${speed_start},setpts=PTS-STARTPTS[v0];\
[0:v]trim=start=${speed_start}:end=${speed_end},setpts=(PTS-STARTPTS)/${speed_factor}[v1];\
[0:v]trim=start=${speed_end},setpts=PTS-STARTPTS[v2];\
[v0][v1][v2]concat=n=3:v=1:a=0,scale=1920:-2,format=yuv420p[v]"
fi

ffmpeg -hide_banner -loglevel error -y -i "$input" \
  -filter_complex "$filter" \
  -map "[v]" -r 30 \
  -c:v libx264 -preset veryfast -crf 28 -movflags +faststart "$output"

ls -lh "$output"
ffprobe -v error \
  -show_entries format=duration,size \
  -show_entries stream=width,height,r_frame_rate \
  -of json "$output"
