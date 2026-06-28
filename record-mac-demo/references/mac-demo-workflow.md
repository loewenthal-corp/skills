# Mac Demo Recording Workflow

## Purpose

Use this checklist to record demos like: browser on the right, Terminal on the left, live CLI commands that create a cloud resource, UI refreshes that show state changes, an API call proving the thing works, then destroy/cleanup.

## Preflight

1. Confirm requested mode:
   - Dry-run/storyboard only: do not run mutating commands.
   - Live recording: creation/destruction is allowed; still script cleanup.
2. Check repo/tooling:
   - `git status --short`
   - CLI versions, e.g. `terraform version`, `go version`, `ffmpeg -version`
   - provider/build status if recording local development software
3. Check credentials safely:
   - Prefer `.env` or existing shell env.
   - Print only `KEY=set` or a masked suffix such as `****1234`.
4. Check current remote resources before mutation:
   - Use the product API where possible.
   - Capture ids/names/status in a compact JSON summary.
5. Choose a low-risk demo resource:
   - Small/cheap instance/model/config.
   - Predictable unique name.
   - Clear timeout/cleanup path.

## Dry-Run Storyboard

For a preview without side effects:

1. Capture real browser screenshots for the relevant pages.
2. Generate mocked terminal frames and label them clearly as dry run/mocked.
3. Compose frames into a short MP4 with `ffmpeg`.
4. Use this to review pacing and layout before running live infrastructure.

Do not blur the line between mock and live. If a frame is mocked, say so in the frame or the filename.

## Window Layout

Good default layout:

- Left: Terminal running the scripted demo.
- Right: logged-in product UI at the relevant page.
- Keep Codex chat mostly hidden if possible; if not, put Terminal over it.

Find a capture region by taking a still screenshot first:

```sh
screencapture -x -R X,Y,WIDTH,HEIGHT /tmp/region-test.png
```

Inspect the screenshot visually. On Retina displays, the saved image may be double the logical dimensions; that is normal.

If the active app window has negative coordinates, `screencapture -R` still works. Use the exact coordinate rectangle from AppleScript/window inspection or a test capture.

## Recording With `screencapture`

Preferred live command:

```sh
scripts/record_region.sh ./demo-live.mov X Y WIDTH HEIGHT
```

Direct equivalent:

```sh
screencapture -v -k -R X,Y,WIDTH,HEIGHT ./demo-live.mov
```

Notes:

- `-v` records video.
- `-k` shows clicks.
- `-R` records a rectangle.
- Stop by pressing a key in the terminal where `screencapture` is running, or by writing a character to that PTY from Codex.
- Use a PTY session for `screencapture` so Codex can stop it cleanly after the demo completes.

## Running the Visible Terminal

Use AppleScript when a real Terminal window should appear in the recording:

```applescript
tell application "Terminal"
  activate
  do script "cd /path/to/project && clear && ./tmp-demo/run_demo.sh"
  delay 0.6
  set bounds of front window to {LEFT, TOP, RIGHT, BOTTOM}
end tell
```

Make the demo runner do the full operation:

- Load env and mask credentials.
- Show relevant config.
- Run plan/apply/create.
- Touch marker files at important points if Codex needs to refresh the browser.
- Call the live endpoint/API.
- Destroy/delete resources.
- Verify remote inventory is clean.
- Use an error trap that attempts cleanup if any later step fails.

Example cleanup trap pattern:

```bash
cleanup_on_error() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "Demo failed. Attempting cleanup..."
    terraform destroy -auto-approve || true
    touch demo.failed
  fi
  touch demo.done
  exit "$exit_code"
}
trap cleanup_on_error EXIT
```

## Browser Handling

Use the browser automation surface for:

- Loading the start page before recording.
- Refreshing after creation so the UI shows the new resource.
- Opening the detail page if the app redirects there.
- Refreshing after cleanup so the UI returns to the empty/list state.

Do not enter secrets into the browser unless the user explicitly authorizes that exact action. For logged-in pages, rely on the user's existing authenticated session.

## Monitoring While Recording

Do not rely only on the visible terminal. In parallel, use read-only commands to track:

- Marker files from the demo runner.
- Product API state.
- Whether a resource is stuck, starting, online, errored, or deleted.

If a resource is taking a long time but progressing, keep recording and plan to speed up the wait in post. If it errors, let the cleanup trap run and capture enough context to explain what happened.

## Editing and Condensing

Create a full MP4 first:

```sh
ffmpeg -i demo-live.mov -vf "scale=1920:-2,format=yuv420p" \
  -c:v libx264 -preset veryfast -crf 28 -movflags +faststart demo-full.mp4
```

Create a condensed cut with a sped-up wait:

```sh
scripts/condense_video.sh demo-full.mp4 demo-condensed.mp4 60 340 35
```

Choose speed-up boundaries by watching the first cut:

- Start speed-up just after the interesting setup/plan/create appears.
- End speed-up just before the successful ready/API-call sequence.
- Keep enough wait footage to prove a real lifecycle happened.

Sample frames for QA:

```sh
ffmpeg -ss 55 -i demo-condensed.mp4 -frames:v 1 frame-55.png
ffmpeg -ss 118 -i demo-condensed.mp4 -frames:v 1 frame-118.png
```

Inspect sampled frames visually.

## CleanShot X Notes

CleanShot X can be useful, but it is not the default automation path.

Official URL scheme examples:

```sh
open 'cleanshot://open-settings?tab=recording'
open 'cleanshot://record-screen?x=100&y=120&width=1280&height=720&display=1'
```

Use it when the user wants a manual/polished recording experience. For Codex-controlled automated demos, `screencapture` is simpler because it can be started/stopped from a terminal session.

## Final Checks

Before final response:

1. Verify remote inventory is clean with API/UI.
2. Confirm video files exist and report duration/size if useful:
   ```sh
   ffprobe -v error -show_entries format=duration,size \
     -show_entries stream=width,height,r_frame_rate -of json demo-condensed.mp4
   ```
3. Search text artifacts for obvious secrets:
   ```sh
   rg -a --glob '!*.mp4' 'API_KEY=|Bearer [A-Za-z0-9_-]{12,}|sk-[A-Za-z0-9]|hf_[A-Za-z0-9]' tmp-demo || true
   ```
   Do not treat random compressed video bytes as reliable text matches.
4. Remove heavyweight raw `.mov` files and transient state files when the MP4s are sufficient.
5. Return a local Markdown video link and explicitly state cleanup status.
