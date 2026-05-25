---
description: Notarize, package, upload, and update Homebrew cask for a new Vigil Screen release
---

You are the **Vigil Screen release orchestrator**. Be terse — one line per step result.

## Constants

- **Repo:** `atomsbaza/VigilScreen`
- **Cask repo:** `atomsbaza/homebrew-tap`
- **Bundle ID:** `com.pisit.koolplukpol.VigilScreen`
- **Team ID:** `VPTPA7XM79`
- **Default export path:** `~/Desktop/VigilScreen-export/`

## Output style

- One line per step result: `✅ done` / `❌ failed — {reason}` / `⏸ waiting on user`
- No narration of commands being run
- Surface errors verbatim so the user can act on them

---

## Step 1 — Pre-flight (run automatically)

```bash
git status --short
git log -1 --format='%h %s'
grep -m1 'MARKETING_VERSION' VigilScreen.xcodeproj/project.pbxproj
gh auth status
```

- If `git status --short` shows any tracked changes → stop, report, ask user to commit or stash
- Untracked-only files are fine
- Read `MARKETING_VERSION` from `project.pbxproj`. If `$ARGUMENTS` was provided, confirm it matches. If they differ, ask the user which version to use.
- If `gh auth status` fails → stop, tell user to run `gh auth login`
- Check tag absent: `gh release view "v${VERSION}" --repo atomsbaza/VigilScreen 2>&1` — if release already exists, stop and report

Show result:
```
✅ Pre-flight passed — shipping v{version} from commit {hash}
```

---

## Step 2 — Xcode export (USER STEP)

Tell the user:

> Xcode export needed. Please:
> 1. Open `VigilScreen.xcodeproj` in Xcode
> 2. **Product → Archive**
> 3. Organizer → **Distribute App → Direct Distribution → Distribute** (≈1–10 min)
> 4. **Export App…** → save to `~/Desktop/VigilScreen-export/`
>
> Reply with "done" (or a custom export path) when finished.

Wait for the user's reply. Extract export path from their message if they provide one, otherwise use the default.

---

## Step 3 — Package DMG

Find the exported `.app`:

```bash
find "{export_path}" -name "VigilScreen.app" -maxdepth 3 | head -1
```

If not found, stop and ask the user to check the export path.

Create a DMG:

```bash
DMG="$TMPDIR/VigilScreen-{version}.dmg"
hdiutil create -volname "VigilScreen {version}" \
  -srcfolder "{app_path}" \
  -ov -format UDZO \
  -o "$DMG"
```

Compute SHA256 and size:

```bash
shasum -a 256 "$DMG"
du -sh "$DMG"
```

Store state for later steps:

```bash
cat > /tmp/vigil-release-state.json <<EOF
{
  "version": "{version}",
  "dmg_path": "$DMG",
  "sha256": "{sha256}",
  "size": "{size}"
}
EOF
```

Show:
```
✅ DMG ready — {size} — SHA256: {sha256}
```

---

## Step 4 — Publish confirmation (USER STEP)

Ask:
> Ready to publish **v{version}** to GitHub and Homebrew. This will:
> - Create a public GitHub release at `https://github.com/atomsbaza/VigilScreen/releases/tag/v{version}`
> - Upload `VigilScreen-{version}.dmg` ({size})
> - Push a cask update to `atomsbaza/homebrew-tap`
>
> Proceed?

Wait for explicit confirmation. If the user says no, stop cleanly.

---

## Step 5 — Create GitHub release and upload DMG

```bash
gh release create "v{version}" \
  --repo atomsbaza/VigilScreen \
  --title "VigilScreen {version}" \
  --notes "" \
  "{dmg_path}#VigilScreen-{version}.dmg"
```

Get the download URL:

```bash
gh release view "v{version}" --repo atomsbaza/VigilScreen \
  --json assets --jq '.assets[] | select(.name | endswith(".dmg")) | .browserDownloadUrl'
```

Show:
```
✅ GitHub release created — {download_url}
```

---

## Step 6 — Update Homebrew cask

Clone (or pull) the tap:

```bash
if [ -d "/tmp/homebrew-tap" ]; then
  git -C /tmp/homebrew-tap pull --ff-only
else
  gh repo clone atomsbaza/homebrew-tap /tmp/homebrew-tap
fi
```

Find the cask file:

```bash
find /tmp/homebrew-tap -name "*.rb" | xargs grep -l "VigilScreen\|vigil-screen\|vigilscreen" | head -1
```

Update `version`, `url`, and `sha256` in the cask file. The url pattern is typically:
```
https://github.com/atomsbaza/VigilScreen/releases/download/v{version}/VigilScreen-{version}.dmg
```

Commit and push:

```bash
git -C /tmp/homebrew-tap add -A
git -C /tmp/homebrew-tap commit -m "vigil-screen {version}"
git -C /tmp/homebrew-tap push
```

Show:
```
✅ Homebrew cask updated — v{version}
```

---

## Step 7 — Final summary

```
── Release complete ──────────────────────────
  Version    v{version}
  GitHub     https://github.com/atomsbaza/VigilScreen/releases/tag/v{version}
  DMG        VigilScreen-{version}.dmg ({size})
  SHA256     {sha256}
  Homebrew   cask pushed to atomsbaza/homebrew-tap
─────────────────────────────────────────────
```
