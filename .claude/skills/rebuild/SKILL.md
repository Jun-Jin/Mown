---
name: rebuild
description: Rebuild the Mown macOS app and install the fresh product over ./Mown.app so `open Mown.app` runs the latest binary. Defaults to a Debug build; use a Release build when the user says "release". Use whenever the user says "rebuild", "build it", "rebuild the project/app", or after code changes that must be reflected in the running app. If the user also says "run", "launch", or "open it", relaunch the app after installing.
user-invocable: true
allowed-tools:
  - Bash
---

# /rebuild — Rebuild & install Mown

Builds the app and copies the product over `./Mown.app`. Xcode builds into
DerivedData, not the repo, so this copy is what keeps `open Mown.app` pointing
at the latest binary (see CLAUDE.md ▸ Build).

## Steps

1. From the repo root, run the rebuild script. Choose flags based on the request:
   ```bash
   bash .claude/skills/rebuild/rebuild.sh            # Debug (default)
   bash .claude/skills/rebuild/rebuild.sh --release  # Release build
   bash .claude/skills/rebuild/rebuild.sh --run      # also relaunch the app
   ```
   Flags combine in any order, e.g. `--release --run`. Pick `--release` when the
   user asks for a release/optimized build (a real single binary, like the
   distributed app); otherwise default to Debug.
2. On failure the script prints the `error:` lines from the build log and exits
   non-zero. Report those errors and stop — **do not** install or relaunch a
   stale product.
3. On success it prints `BUILD SUCCEEDED (<config>) → installed ./Mown.app` (and
   `relaunched Mown.app` when `--run` was passed).

## Notes

- The script resolves the build-product path via `xcodebuild -showBuildSettings`,
  so it never depends on the machine-specific DerivedData hash.
- Local Debug builds skip code signing (`CODE_SIGNING_ALLOWED=NO`).
- Adding a source file does **not** require touching `project.pbxproj` — the
  project uses synchronized folders (CLAUDE.md ▸ Project Structure).
