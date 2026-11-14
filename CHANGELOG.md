# Changelog


## 1.6.0 - 2026-07-03

### Added

- Added a native menu-bar resident mode with a status item for opening, hiding, configuring, and quitting TranslateDesk.
- Added a system-wide `Option + A` hotkey that opens the main window and focuses the input editor.
- Added a top-level `install.sh` wrapper and improved installation into `/Applications` or `~/Applications`.

### Changed

- Closing the main window now hides it instead of terminating the application.
- The yellow minimize button now hides the window to the menu bar instead of leaving it in the Dock.
- The app runs as an accessory/menu-bar application and does not occupy the Dock while idle.
- Fixed app-logo resource lookup and corrected macOS `.icns` generation sizes.


## 1.5.0 - 2026-07-03

### Added

- Added a bundled app logo and macOS app icon source artwork, displayed in the main workspace header and packaged into the built `.app` bundle as `AppIcon.icns`.
- Added `scripts/install_app.sh` to build and install `TranslateDesk.app` into `/Applications` or `~/Applications`.

### Changed

- The macOS build script now generates the app icon set from `Sources/TranslateDesk/Assets/translatedesk-logo.png` and embeds it into the app bundle.
- The DMG packaging script now produces `TranslateDesk-1.5.0.dmg`.

## 1.4.0 - 2026-07-03

### Added

- Added a result-source filter bar for All, each matched dictionary, Translation, and Expression results.
- Added reusable dictionary sense grouping for verbs, nouns, adjectives, adverbs, phrases, idioms, and other grammar categories.
- Added independent collapse controls for the whole dictionary card, each grammar group, and each group's full senses/examples.
- Added persistent result filters and dictionary layout preferences backed by UserDefaults.
- Added a cached `DictionaryPresentation` map so result filtering and expansion reuse parsed dictionary content.

### Changed

- The first grammar category opens by default; remaining groups stay compact until requested.
- Long dictionary entries now expose 2–3 preview senses per category rather than one global preview limit.
- Invalid persisted filters automatically fall back to All when the selected source is unavailable for a new query.
- Dictionary menus now provide expand all, collapse all, show all details, and restore default summary actions.

### Fixed

- Corrected part-of-speech classification where `adverb` could be mistaken for `verb` and `pronoun` for `noun`.
- Direct accurate/provider translation of new text now switches to the Translation result filter immediately.

## 1.3.0 - 2026-07-02

### Added

- Added source-specific dictionary presentation parsing for Cambridge and Collins entries.
- Added structured sense, definition, Chinese translation, example, grammar-label, and related-phrase rendering.
- Added bilingual example splitting when English and Chinese share one imported line.
- Added macOS system speech for dictionary headwords.
- Added `Command+L` to focus and select the input, automatic result scrolling, copy confirmation, and starter examples.

### Changed

- Long entries are now collapsed by sense and example count instead of a fixed character limit.
- Input height is more compact so results appear sooner in the window.
- Translation and expression results from the same provider/scene are updated instead of duplicated.
- Results are explicitly tied to the last submitted text, with a warning when the input has changed.

### Fixed

- Removed the duplicate Return shortcut from the primary button; the text editor is now the sole Return handler.
- Accurate or provider-specific translation of newly edited text no longer appends to the previous query.
- Smart-mode accurate translation now re-detects the current input language instead of reusing a previous query's source language.
- Cambridge senses appearing after an intermediate Related Phrases/Idioms section are no longer lost.

## 1.2.1 - 2026-07-02

### Fixed

- Fixed the macOS build failure caused by ambiguous inference of `greatestFiniteMagnitude` in `SubmitTextEditor`; the text-container height now explicitly uses `CGFloat.greatestFiniteMagnitude`.
- Return no longer submits while a macOS input method has marked text, so confirming a Chinese IME candidate does not prematurely execute a query.

## 1.2.0 - 2026-07-02

### Added

- Bundled Cambridge English-Chinese bilingual dictionary with 63,762 searchable headwords.
- Bundled Collins COBUILD advanced English dictionary with 33,261 searchable headwords.
- Memory-mapped `.tdict` reader with binary search and no runtime MDX parsing.
- Prefix suggestions after an exact dictionary miss.
- Collapsible rendering for very long dictionary entries.
- Read-only loaded-dictionary overview in Settings.
- Reproducible MDX-to-TDICT conversion and dictionary integrity verification scripts.

### Changed

- Dictionary lookup order is Cambridge, Collins, then the original built-in work vocabulary.
- Missing MDD images, scripts, styles, and audio references are removed during conversion while textual content is retained.
- App packaging now copies both dictionary resources into `Contents/Resources` and fails when either resource is missing.

## 1.1.0 - 2026-07-02

### Added

- Smart input analysis for Chinese, English words, English phrases, and sentences.
- Smart, dictionary-only, and translation-only workspace modes.
- Return submit, Shift+Return newline, and Command+Return accurate translation.
- Structured dictionary cards with Chinese meanings, English definitions, and examples.
- Separate dictionary, translation, and expression result sections.

### Changed

- New primary queries replace previous query results instead of continuously appending.
- Accurate and provider-specific translations remain appendable for comparison.
- Translation cache persistence is coalesced and performed off the result path.
- MyMemory default timeout reduced from 10 to 8 seconds.
- Main navigation renamed from Translation to Dictionary & Translation.

## 1.0.0 - 2026-06-23

### Added

- Local-first default translation route.
- Visible provider, model, credential source, cache, and fallback metadata.
- MyMemory, DeepL, LibreTranslate, and OpenAI-compatible adapters.
- User-configurable translation presets and provider order.
- Separate accurate translation provider.
- Separate daily, Teams, and email expression routes.
- macOS Keychain credential storage.
- SwiftUI provider settings and result cards.
- App/DMG build scripts and GitHub Actions CI.
- Chinese and English usage, configuration, architecture, release, security, and contribution documentation.
