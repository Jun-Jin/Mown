#!/usr/bin/env bash
#
# Rebuild Mown and install the product over ./Mown.app so that `open Mown.app`
# runs the latest binary. Xcode builds into DerivedData, not the repo, so the
# copy step is what keeps ./Mown.app current (CLAUDE.md ▸ Build).
#
# Usage:
#   bash .claude/skills/rebuild/rebuild.sh                  # Debug build + install
#   bash .claude/skills/rebuild/rebuild.sh --release        # Release build + install
#   bash .claude/skills/rebuild/rebuild.sh --run            # + relaunch the app
#   bash .claude/skills/rebuild/rebuild.sh --release --run  # flags combine, any order
set -euo pipefail

CONFIG="Debug"
RUN=0
for arg in "$@"; do
    case "$arg" in
        --release) CONFIG="Release" ;;
        --debug)   CONFIG="Debug" ;;
        --run)     RUN=1 ;;
        *)
            echo "Unknown option: $arg" >&2
            echo "Usage: rebuild.sh [--release|--debug] [--run]" >&2
            exit 2
            ;;
    esac
done

# Repo root, regardless of where this is invoked from (.claude/skills/rebuild → ../../..).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

PROJECT="Mown.xcodeproj"
SCHEME="Mown"
TARGET="Mown"
LOG="$(mktemp -t mown_build.XXXXXX.log)"

echo "Building $SCHEME ($CONFIG)…"
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
        build CODE_SIGNING_ALLOWED=NO >"$LOG" 2>&1; then
    echo "BUILD FAILED — errors:" >&2
    grep -nE "error:" "$LOG" | head -40 || tail -30 "$LOG"
    echo "(full log: $LOG)" >&2
    exit 1
fi

# Resolve the product path from build settings rather than hardcoding the
# machine-specific DerivedData hash. Query with -scheme (not -target) so the
# reported TARGET_BUILD_DIR matches where the build above actually wrote the
# product; -json filters to the Mown app target unambiguously.
APP="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
        -showBuildSettings -json 2>/dev/null | python3 -c '
import json, sys
for item in json.load(sys.stdin):
    if item.get("target") == "'"$TARGET"'":
        bs = item["buildSettings"]
        print(bs["TARGET_BUILD_DIR"] + "/" + bs["FULL_PRODUCT_NAME"])
        break
')"

if [[ -z "$APP" || ! -d "$APP" ]]; then
    echo "Build succeeded but product not found at: ${APP:-<unresolved>}" >&2
    exit 1
fi

rm -rf "$REPO_ROOT/Mown.app"
cp -R "$APP" "$REPO_ROOT/Mown.app"
echo "BUILD SUCCEEDED ($CONFIG) → installed ./Mown.app"

if [[ "$RUN" -eq 1 ]]; then
    pkill -x Mown 2>/dev/null || true
    sleep 1
    open "$REPO_ROOT/Mown.app"
    echo "relaunched Mown.app"
fi
