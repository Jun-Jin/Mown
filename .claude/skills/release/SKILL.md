---
name: release
description: Build, codesign (Developer ID), notarize, and staple Mown for distribution outside the Mac App Store, producing a notarized artifact under ./dist/. Use whenever the user says "release", "ship it", "make a release build to distribute", "notarize", "sign for distribution", or "build a DMG". Not for plain local rebuilds — use /rebuild for those.
user-invocable: true
allowed-tools:
  - Bash
---

# /release — Sign, notarize & package Mown for Developer ID distribution

Produces a Gatekeeper-passing `.app` (and optionally a DMG) under `./dist/` for
distribution outside the Mac App Store (SPEC.md §8).

Pipeline: **Release build → codesign (Developer ID + hardened runtime + secure
timestamp) → notarytool submit → stapler staple → package**.

## One-time prerequisites (the user does these — interactive / secret)

1. **Developer ID Application certificate** installed in the login keychain:
   Xcode ▸ Settings ▸ Accounts ▸ (Apple ID) ▸ Manage Certificates ▸ "+" ▸
   *Developer ID Application*. Verify with
   `security find-identity -v -p codesigning`.
2. **Notarization credentials** stored under a keychain profile:
   ```bash
   xcrun notarytool store-credentials "MownNotary" \
       --apple-id "you@example.com" --team-id "TEAMID" \
       --password "app-specific-password"
   ```
   The app-specific password comes from appleid.apple.com ▸ Sign-In and
   Security ▸ App-Specific Passwords (not the normal Apple ID password).

The script autodetects the signing identity and Team ID from the installed
certificate, so nothing in `project.pbxproj` needs editing.

## Steps

1. From the repo root, run the release script:
   ```bash
   bash .claude/skills/release/release.sh            # sign + notarize + staple + zip
   bash .claude/skills/release/release.sh --dmg      # also build a notarized DMG
   bash .claude/skills/release/release.sh --no-notarize  # sign only (local smoke test)
   ```
2. Report the artifact path(s) under `./dist/` and the final Gatekeeper
   assessment (`spctl -a -t exec`). If notarization is rejected, fetch the log:
   `xcrun notarytool log <submission-id> --keychain-profile MownNotary`.

## Notes

- `./dist/` is git-ignored; artifacts are not committed.
- Notarization round-trips hit Apple's service and can take a few minutes each
  (`--wait` blocks until done). `--dmg` notarizes twice (app, then DMG).
- For a plain local Debug/Release build that just refreshes `./Mown.app`, use
  **/rebuild** instead.
