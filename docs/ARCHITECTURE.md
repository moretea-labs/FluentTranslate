# Architecture

## Main flow

1. Carbon registers the global `⌥A` shortcut.
2. `SelectionCaptureService` saves the full clipboard snapshot, sends `⌘C`, reads the selected text and restores the clipboard.
3. `TranslationCoordinator` performs local lookup first when offline dictionaries are enabled.
4. The selected backend then runs:
   - OpenAI-compatible Chat Completions;
   - LibreTranslate followed by OpenAI-compatible enrichment; or
   - LibreTranslate only.
5. If the API is unavailable but an exact local dictionary entry exists, the app returns the offline query result rather than failing the entire request.
6. SwiftUI renders Translation → Query → optional Expression.
7. The result can be copied, spoken or pasted back into the source application.

## Provider boundary

`AIAPIFormat` is an extension point. v5 implements `OpenAI Chat Completions` only. The endpoint resolver accepts:

- a root URL and appends `/v1/chat/completions`;
- a `/v1` or `/api/v1` URL and appends `/chat/completions`; or
- a complete custom endpoint.

`AITranslationClient` uses only common request fields (`model`, `messages`, `stream`) to avoid optional-parameter incompatibilities across third-party services.

## Dictionary boundary

`LocalDictionaryService` merges two optional sources:

- bundled `dictionary_entries` SQLite converted from MDX;
- user-installed ECDICT `stardict` SQLite.

The bundled source provides English definitions. ECDICT can enrich the same entry with phonetics, part of speech and Chinese definitions.
