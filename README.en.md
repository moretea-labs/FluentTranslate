# TranslateDesk

TranslateDesk is a personal macOS app that combines local dictionary lookup, machine translation, and optional AI rewriting without mixing those result types together.

## Default interaction

- Chinese input is translated to English.
- An English word queries the bundled dictionaries and also produces a separate Chinese translation.
- English phrases and sentences are translated to Chinese.
- `Return` executes, `Shift+Return` inserts a newline, `Command+Return` invokes accurate translation, and `Command+L` focuses and selects the input.
- Smart, Dictionary, and Translation modes remain available when automatic routing needs to be overridden.

## Bundled dictionaries

The package contains two pre-indexed dictionaries generated from user-supplied MDX files:

1. Cambridge English-Chinese bilingual dictionary — 63,762 searchable headwords.
2. Collins COBUILD advanced English dictionary — 33,261 searchable headwords.

They are queried in that order and rendered as separate cards with structured senses, translations, examples, grammar labels, and related phrases. A result filter bar can instantly show All, Cambridge, Collins, Translation, or Expression results without running the query again. A small built-in work vocabulary remains as the last fallback. The supplied MDX files did not include matching MDD resources, so text, phonetics, grammar labels, examples, and phrases are preserved while missing images, scripts, styles, and audio references are removed.

The generated `.tdict` files use a memory-mapped sorted binary index. The app does not parse the MDX files at startup or scan the full dictionary during each query. Prefix suggestions are available after an exact miss. Very long entries are grouped by part of speech. Each dictionary, grammar group, and group's full details can be collapsed independently. Filter and expansion preferences persist across later queries. Parsed dictionary presentations are cached for the active query, so filtering and SwiftUI refreshes do not parse long entries again. macOS system speech can pronounce the headword when MDD audio is unavailable.

These dictionary resources are intended for the user's personal installation and should not be published in a public repository.

## Translation and writing features

- MyMemory enabled as the initial low-cost translation route.
- Optional DeepL and LibreTranslate adapters.
- Multiple OpenAI-compatible endpoints and models.
- Separate AI routes for everyday language, Teams messages, and work email.
- Provider, model, credential source, cache, and fallback metadata shown with every result.
- Automatic result scrolling, copy confirmation, stale-input warnings, and duplicate-result replacement.
- API keys stored in macOS Keychain.

## Run

```bash
open Package.swift
```

Select the `TranslateDesk` scheme in Xcode and run it.

Build a local app bundle:

```bash
./scripts/build_app.sh
open dist/TranslateDesk.app
```

Run validation and tests:

```bash
python3 scripts/verify_tdict.py
swift test
```

To regenerate a dictionary index:

```bash
python3 -m pip install -r requirements-mdict.txt
python3 scripts/import_mdict.py input.mdx output.tdict
```

See the [Chinese README](README.md) and [`docs/DICTIONARIES.md`](docs/DICTIONARIES.md).


## Menu bar and global shortcut

TranslateDesk stays in the macOS menu bar. Press `Option + A` globally to show the main window and focus the input editor. Closing or minimizing the main window hides it to the menu bar instead of quitting.

Install with:

```bash
./install.sh
# or without administrator access
./install.sh --user
```
