---
name: record-mac-demo
description: Record polished live product or developer demos on macOS from Codex, especially flows that combine browser UI, terminal commands, provisioning/apply/destroy steps, API calls, cleanup verification, and condensed review cuts. Use when the user asks Codex to record, storyboard, dry-run, screen-capture, trim, speed up, or package a Mac demo video.
---

# Record Mac Demo

## Core Workflow

Use this workflow for Mac demo recordings where Codex drives a browser, Terminal, and local tools.

1. Clarify whether the user wants a dry-run storyboard, a real live recording, or both.
2. Preflight the live system before recording: login state, target page, CLI tools, credentials, expected side effects, cleanup path, and current remote resource inventory.
3. Create a temporary demo workspace and script the risky sequence so cleanup is deterministic.
4. Put the visible browser and Terminal into a stable two-pane layout.
5. Record with macOS `screencapture` unless the user explicitly prefers another tool.
6. Monitor the run out-of-band with read-only checks, refresh UI at useful moments, and stop the recording after cleanup is verified.
7. Produce a full MP4 and a condensed review cut with slow waits accelerated.
8. Verify no live resources remain and no secrets were printed or persisted.

Read [references/mac-demo-workflow.md](references/mac-demo-workflow.md) before doing a real live recording, editing a recorded demo, or handling cloud resources that must be cleaned up.

## Tool Choices

Prefer these tools in order:

- `screencapture`: reliable built-in macOS screen/video recording. Use for automated start/stop and fixed regions.
- `ffmpeg`/`ffprobe`: transcode, trim, speed up waits, inspect duration/resolution.
- CleanShot X: useful for polished manual recordings and region selection. Its URL scheme can open record mode, but do not rely on it for fully automated start/stop/save.
- Browser plugin / in-app browser: use for logged-in web UI, state refreshes, screenshots, and DOM checks.
- Terminal app via AppleScript: use when the user needs the recording to show a real shell instead of hidden command output.

## Scripts

- `scripts/record_region.sh OUTPUT [X Y WIDTH HEIGHT]`: start a `screencapture` recording. With coordinates, records a fixed region; without them, records using default screen-capture behavior. Stop by sending a character to the PTY or pressing a key in the recording terminal.
- `scripts/condense_video.sh INPUT OUTPUT SPEED_START SPEED_END [SPEED_FACTOR]`: create a review cut where the interval from `SPEED_START` to `SPEED_END` is accelerated. Use seconds for times. Default speed factor is `35`.

Always inspect the produced video or sampled frames before telling the user it is ready.

## Safety Rules

- Never print API keys or credentials. Load them from `.env`, environment variables, or the user-authenticated browser session, and show only masked status.
- Before creating resources, capture the baseline inventory and name demo resources predictably.
- If a live run creates remote resources, verify cleanup with an authoritative API or UI check before final response.
- If cleanup fails, report the exact resource name/id and the manual cleanup action needed.
- Keep generated demo files in an ignored temp directory when working inside a source repo.

## Output Shape

Return the most useful video first, usually the condensed review cut. Also include the full real-time recording when available, plus a concise cleanup status.
