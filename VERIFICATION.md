# Verification

Current acceptance: 2026-11-05, macOS.
Historical preflight: 2026-07-03 (the Linux results below are retained as historical evidence).

## 2026-11-05 macOS release and UI acceptance

- `swift test`: **35 tests passed, 0 failures** (includes reset of stale query filters/expansion).
- `bash scripts/build_app.sh`: Release build passed, three packaged dictionaries present.
- `codesign --verify --deep --strict dist/TranslateDesk.app`: passed.
- Installed to `/Applications/TranslateDesk.app`; one installed process running. Earlier duplicate-app test ambiguity was eliminated by archiving the old backup as `dist/backup/TranslateDesk-20261105-backup.zip`.
- 980 × 732 stacked layout: the input, language selectors and action button stay visible while only results scroll. Submitting `部署` shows `deploy` in the initial viewport above Collins 汉英 details; submitting `deployment` shows `部署；发布` above Cambridge and Collins definitions.
- 1244 × 732 wide layout: native window switches to left input / right results, with separate result scrolling. The translation card and Collins 汉英 entry were both visible without leaving the input pane.
- 820 × 560 minimum layout: input controls, submit button and `deployment` translation remain on screen.
- After testing, the window was restored to the user's 980 × 732 geometry.
- The app's network translation accuracy is not inferred from UI/unit test success; the configured remote service remains the authority for its own output.
- Local dictionaries are proprietary personal assets and must not be pushed to a public repository.

### 2026-11-05 compact-word UI follow-up

- Removed the always-visible left navigation rail; main translation surface fills the window, and the native settings scene remains available from the header gear and Command-comma.
- A short word uses a **44 pt** input editor instead of the former 78 pt stacked editor (or 144 pt wide editor). Longer text expands to 72/82/120/140 pt as needed.
- One-word translation is now a compact two-row card. Copy/current-result actions remain visible; latency, provider routing, cache provenance and fallback reasons are available from an info popover rather than occupying mandatory rows.
- New queries always reset the source filter to **All**. Smart mode resets previously expanded dictionary groups so a new lookup starts with short summaries; explicit dictionary mode retains its preferred detail layout.
- Collins 汉英 summaries show up to three distinct senses on one or two lines. Example: `接口` has colloquial `to carry on speaking`, general `to connect`, and technical `interface`; a single first sense is not a representative dictionary translation.
- Installed build passed code-signature verification and launched. UI automation observed 44 pt input, `部署 → deploy`, the All filter, and the `接口` preview containing the three senses in an 820 pt window. Multi-line editing and remote provider semantic accuracy are not claimed as empirically remeasured in this follow-up.
- Earlier source-tree migration remains uncommitted; personal Cambridge/Collins dictionary data is excluded from any public delivery.

## Historical checks (2026-07-03)

## Executed

```bash
python3 scripts/verify_tdict.py
swift test
swift build -c release
python3 -m json.tool config/default-config.json
bash -n scripts/build_app.sh scripts/package_dmg.sh
swiftc -frontend -parse -target x86_64-apple-macosx14.0 \
  Sources/TranslateDesk/*.swift Sources/TranslateDesk/Views/*.swift
```

## Result

- Cambridge index validated: 63,762 sorted searchable keys, 23.5 MiB.
- Collins index validated: 33,261 sorted searchable keys, 16.1 MiB.
- Probe queries validated for `apple`, `run`, and `running`.
- Swift package debug and release builds passed.
- 24 unit tests passed.
- Default JSON configuration is valid.
- Shell scripts passed syntax validation.
- macOS-only SwiftUI source passed a macOS-target syntax parse.

Covered behavior:

1. Chinese input routes to English translation.
2. English words route to dictionary lookup plus Chinese translation.
3. English sentences route to Chinese translation only.
4. Explicit dictionary mode does not call translation.
5. Cambridge and Collins load in the required order with expected entry counts.
6. Cambridge returns bilingual content and Collins returns English definitions.
7. Common inflected entries such as `running` resolve in both dictionaries.
8. Prefix suggestions return `apple` for `appl`.
9. Cambridge definitions, translations, examples, pronunciation, and related phrases are separated.
10. Cambridge numbered senses after an intermediate related-phrase section remain available.
11. Collins repeated grammar entries are split into separate senses.
12. Dictionary senses group into stable part-of-speech categories without losing source order.
13. The real Cambridge `run` entry contains both verb and noun groups and preserves every parsed sense.
14. Result filter keys and persisted dictionary layout preferences round-trip through `UserDefaults`.
15. Configuration encoding/decoding.
16. MyMemory request/response mapping and source detection.
17. Transparent provider fallback.
18. OpenAI-compatible expression output parsing.

## Platform limitation

The execution environment is Linux, so AppKit, SwiftUI runtime layout, Keychain, and `NSSpeechSynthesizer` cannot be executed here. A real macOS build remains the authoritative type-check and runtime gate.

Before local use on a Mac, run:

```bash
rm -rf .build dist
python3 scripts/verify_tdict.py
swift test
./scripts/build_app.sh
open dist/TranslateDesk.app
```

Manually verify:

- `apple` shows structured Cambridge and Collins cards.
- `run` is grouped into verb and noun sections; each section can independently switch between summary and full content.
- the result filter switches among Cambridge, Collins, and Translation without re-running the query.
- result filters and dictionary expansion preferences remain effective after querying a second word.
- bilingual examples appear as separate English and Chinese lines.
- Return submits exactly once; Shift+Return inserts a newline; Chinese IME candidate confirmation does not submit.
- Command+L focuses and selects the input.
- copying displays a confirmation badge.
- the speaker button reads the headword with macOS system speech.
- editing text after a query shows a stale-input warning and accurate translation replaces the old query.

## Previous compiler correction

Version 1.2.1 fixed the macOS ambiguity between `CGFloat.greatestFiniteMagnitude` and `Double.greatestFiniteMagnitude`. Version 1.6.0 retains the explicit `CGFloat` type and marked-text handling.


## 1.6.0 packaging additions

- Verified the source logo asset exists at `Sources/TranslateDesk/Assets/translatedesk-logo.png`.
- Added `scripts/install_app.sh` for one-step local installation on macOS.
- `build_app.sh` now generates `AppIcon.icns` on macOS from the bundled PNG logo.


## 1.6.0 macOS manual checks

- Launch the installed app and confirm the menu-bar item appears.
- Press `Option + A` from another app and confirm the main window opens with input focus.
- Click close and minimize; confirm the process remains in the menu bar.
- Confirm the Finder/Dock app icon uses `AppIcon.icns`.


## 1.6.0 automated verification

- Both bundled TDICT files passed structural verification: Cambridge 63,762 keys and Collins 33,261 keys.
- `swift test` completed with 24 tests and no failures.
- Every Swift source file passed frontend syntax parsing.
- `Package.swift` passed `swift package dump-package`.
- `install.sh`, `build_app.sh`, `install_app.sh`, and `package_dmg.sh` passed `bash -n`.
- The bundled logo is a square 1254 × 1254 PNG and is large enough to generate the complete macOS icon set.

The current build environment is Linux, so AppKit, `MenuBarExtra`, Carbon hot-key registration, `.icns` generation, codesigning, and the final `.app` installation must still be run on macOS. The source and scripts are prepared for that Mac-side verification.

### 2026-11-05 bilingual smart lookup follow-up

- Smart mode now tries an exact local dictionary lookup alongside translation for both words and phrases in English/Chinese. Translation-only mode and full punctuated sentences retain their existing routing.
- `swift test`: **41/41 PASS**, including actual Cambridge phrase `take into account`, Collins Chinese term `人工智能`, and no fabricated match for an unpunctuated Chinese request.
- Release build, codesign verification, and installation at `/Applications/TranslateDesk.app`: passed.
- Real macOS accessibility observation: `take into account` produced a translation and Cambridge dictionary card; `人工智能` produced `AI` translation and Collins 汉英 sense `artificial intelligence`.
- Dictionary coverage is exact-match, not guaranteed for every phrase. Distinct translation and dictionary wording is preserved with source attribution rather than automatically replacing one with the other.

### 2026-11-05 stable signing and login item

- Found that the packaged app used ad-hoc signing while provider API keys were stored in macOS login Keychain. This can change code identity on rebuild and lead to recurring access prompts.
- Replaced ad-hoc build signing with the local owner's Apple Development identity. Installed app passes `codesign --verify --deep --strict` and reports a stable nonempty team identifier.
- `/Applications` is writable by this user, so this install did not require `sudo`. Installation script verifies the installed signature and removes the secondary `dist/TranslateDesk.app` bundle on success.
- Confirmed exactly one installed `TranslateDesk.app` and one running TranslateDesk process. Existing Keychain credentials were neither read as plaintext nor deleted.
- macOS System Events login items list includes one `TranslateDesk` item pointing to `/Applications/TranslateDesk.app`; no duplicate TranslateDesk LaunchAgent was added.
- Login after actual reboot has not been exercised; OS login item registration is verified, not a simulated reboot. One initial Keychain approval may still be necessary after signing identity changes.
