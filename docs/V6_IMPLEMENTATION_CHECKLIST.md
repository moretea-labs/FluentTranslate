# v6 Implementation Checklist

- [x] Local SQLite lookup before network request
- [x] Incremental UI result: local result is published immediately
- [x] Cancel previous request when a new query starts
- [x] Keep local result when remote provider fails
- [x] Explicit English-English and Chinese definition labels
- [x] Independent translation provider selection
- [x] OpenAI Chat Completions compatible provider
- [x] DeepL API Free/Pro provider
- [x] LibreTranslate provider
- [x] MyMemory provider
- [x] Independent AI context-query switch
- [x] Independent expression switch
- [x] Truncated local dictionary hint sent to AI
- [x] Maximum three AI-extracted terms
- [x] DeepL key stored in Keychain
- [x] Bundled dictionary integrity verified: 33,320 entries

The container cannot compile AppKit because it is Linux. Run `./scripts/build_app.sh` on macOS for the native build.
