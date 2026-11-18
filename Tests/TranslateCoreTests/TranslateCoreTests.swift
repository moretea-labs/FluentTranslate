import XCTest
@testable import TranslateCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class TranslateCoreTests: XCTestCase {
    func testEnglishMeaningPronunciationHandlesInfinitiveWithoutMislabelingPhrase() {
        XCTAssertEqual(EnglishMeaningHeadword.extract(from: "to deploy"), "deploy")
        XCTAssertEqual(EnglishMeaningHeadword.extract(from: "plan"), "plan")
        XCTAssertEqual(EnglishMeaningHeadword.extract(from: " deployment "), "deployment")
        XCTAssertNil(EnglishMeaningHeadword.extract(from: "make military deployments"))
        XCTAssertNil(EnglishMeaningHeadword.extract(from: "deployment of forces"))
        XCTAssertNil(EnglishMeaningHeadword.extract(from: "部署"))
    }

    func testChineseDefinitionEnglishHeadwordsHaveOfflineIPA() throws {
        let catalog = DictionaryCatalog(sources: BundledDictionaries.makeSources())
        let chinese = try XCTUnwrap(catalog.lookup("部署").first {
            $0.dictionaryID == "collins-han-en"
        })
        let meanings = DictionaryPresentationParser.parse(chinese).senses
            .flatMap { $0.definitions.map(\.text) }
        let words = Set(meanings.compactMap { EnglishMeaningHeadword.extract(from: $0) })
        XCTAssertTrue(words.contains("deploy"))
        XCTAssertTrue(words.contains("plan"))
        let expected = ["deploy": "/dɪˈplɔɪ/", "plan": "/plæn/"]
        for (word, ipa) in expected {
            let english = try XCTUnwrap(catalog.lookup(word).first {
                $0.dictionaryID == "cambridge-en-zh"
            })
            XCTAssertEqual(DictionaryPresentationParser.parse(english).pronunciation, ipa)
        }
    }

    func testPronunciationSelectsMatchingAccentWithoutCrossAccentAudio() throws {
        let json = """
        [{
          "word": "hello",
          "phonetic": "/generic/",
          "phonetics": [
            {"text": "/həˈləʊ/", "audio": "https://api.dictionaryapi.dev/media/pronunciations/en/hello-uk.mp3"},
            {"text": "/həˈloʊ/", "audio": "https://api.dictionaryapi.dev/media/pronunciations/en/hello-us.mp3"}
          ]
        }]
        """
        let entry = try XCTUnwrap(JSONDecoder().decode([EnglishPronunciationEntry].self, from: Data(json.utf8)).first)
        XCTAssertEqual(entry.localizedIPA(for: .american), "/həˈloʊ/")
        XCTAssertEqual(entry.localizedIPA(for: .british), "/həˈləʊ/")
        XCTAssertTrue(entry.audioURL(for: .american)!.absoluteString.hasSuffix("-us.mp3"))
        XCTAssertTrue(entry.audioURL(for: .british)!.absoluteString.hasSuffix("-uk.mp3"))
    }

    func testPronunciationMissingAccentUsesGenericIPAButNotWrongAudio() throws {
        let json = """
        [{"word":"test","phonetic":"/test/","phonetics":[
          {"text":"/tɛst/","audio":"https://api.dictionaryapi.dev/media/pronunciations/en/test-uk.mp3"},
          {"audio":"https://untrusted.example/test-us.mp3"}]}]
        """
        let entry = try XCTUnwrap(JSONDecoder().decode([EnglishPronunciationEntry].self, from: Data(json.utf8)).first)
        XCTAssertNil(entry.localizedIPA(for: .american))
        XCTAssertEqual(entry.ipa(for: .american), "/test/")
        XCTAssertNil(entry.audioURL(for: .american))
        XCTAssertNotNil(entry.audioURL(for: .british))
    }

    func testResultDisplayPreferencesRoundTripAndDictionaryFilterKey() throws {
        let suiteName = "TranslateDeskTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ResultDisplayPreferenceStore(defaults: defaults, storageKey: "result-layout")
        let value = ResultDisplayPreferences(
            selectedFilterKey: ResultFilterKey.dictionary("cambridge-en-zh"),
            collapsedDictionaryIDs: ["collins-cobuild-en"],
            groupExpansion: ["cambridge-en-zh::verb": true],
            groupDetailExpansion: ["cambridge-en-zh::verb": false]
        )

        store.save(value)

        XCTAssertEqual(store.load(), value)
        XCTAssertEqual(
            ResultFilterKey.dictionaryID(from: value.selectedFilterKey),
            "cambridge-en-zh"
        )
        XCTAssertNil(ResultFilterKey.dictionaryID(from: "dictionary:"))
    }

    func testDefaultConfigurationRoundTrips() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(AppConfiguration.default)
        let decoded = try decoder.decode(AppConfiguration.self, from: data)

        XCTAssertEqual(decoded.defaultPresetID, "local-first")
        XCTAssertEqual(decoded.providers.first(where: { $0.id == "mymemory-public" })?.displayName, "MyMemory")
        XCTAssertEqual(decoded.providers.first(where: { $0.id == "deepl-user" })?.deepLAccountType, .free)
        XCTAssertEqual(decoded.expressionRouting.teamsProviderID, "openai-compatible-user")
    }

    func testDeepLSecretReferenceSurvivesConfigurationRoundTrip() throws {
        let original = AppConfiguration.default.providers.first { $0.id == "deepl-user" }
        let data = try JSONEncoder().encode(AppConfiguration.default)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)
        let restored = decoded.providers.first { $0.id == "deepl-user" }

        XCTAssertEqual(restored?.secretReference, original?.secretReference)
    }

    func testDeepLProviderUsesConfiguredSecretReference() async throws {
        var configuration = AppConfiguration.default.providers.first { $0.id == "deepl-user" }!
        configuration.enabled = true
        let reference = try XCTUnwrap(configuration.secretReference)
        let client = MockHTTPClient { request in
            XCTAssertEqual(request.url?.absoluteString, ProviderConfiguration.deepLFreeTranslateURL)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "DeepL-Auth-Key test-only-secret")
            let requestBody = try XCTUnwrap(request.httpBody)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
            XCTAssertEqual(payload["text"] as? [String], ["hello"])
            let response = #"{"translations":[{"detected_source_language":"EN","text":"你好","model_type_used":"latency_optimized"}]}"#.data(using: .utf8)!
            return (response, Self.response(url: request.url!, statusCode: 200))
        }
        let provider = DeepLProvider(
            configuration: configuration,
            httpClient: client,
            secrets: DictionarySecretResolver(values: [reference: "test-only-secret"])
        )

        let result = try await provider.translate(.init(text: "hello", sourceLanguage: "en", targetLanguage: "zh"))

        XCTAssertEqual(result.translatedText, "你好")
        XCTAssertEqual(result.providerID, "deepl-user")
    }

    func testNativeTranslationIsDefaultForSentencesAndNeedsNoCredentials() {
        let config = AppConfiguration.default
        let preset = config.presets.first { $0.id == "local-first" }!
        XCTAssertEqual(preset.providerOrder.first, "apple-system")
        let native = config.providers.first { $0.id == "apple-system" }!
        XCTAssertTrue(native.enabled)
        XCTAssertEqual(native.kind, .appleSystem)
        XCTAssertEqual(native.credentialSource, .local)
        XCTAssertTrue(native.runtimeConfigurationIssues(secretAvailable: false).isEmpty)
        XCTAssertFalse(native.supportsConnectionCheck)
    }

    func testExistingLocalFirstConfigurationMigratesWithoutReplacingCustomRoutes() {
        var existing = AppConfiguration.default
        existing.providers.removeAll { $0.id == "apple-system" }
        let index = existing.presets.firstIndex { $0.id == "local-first" }!
        existing.presets[index].providerOrder = ["mymemory-public"]
        XCTAssertTrue(existing.addNativeTranslationIfNeeded())
        XCTAssertEqual(existing.presets[index].providerOrder, ["apple-system", "mymemory-public"])
        XCTAssertFalse(existing.addNativeTranslationIfNeeded())

        var custom = existing
        custom.providers.removeAll { $0.id == "apple-system" }
        custom.presets[index].providerOrder = ["deepl-user", "mymemory-public"]
        XCTAssertTrue(custom.addNativeTranslationIfNeeded())
        XCTAssertEqual(custom.presets[index].providerOrder, ["deepl-user", "mymemory-public"])
    }

    func testDeepLAccountTypeSwitchesOfficialEndpoint() {
        var configuration = AppConfiguration.default.providers.first { $0.id == "deepl-user" }!

        XCTAssertEqual(configuration.deepLAccountType, .free)
        XCTAssertEqual(configuration.baseURL, ProviderConfiguration.deepLFreeTranslateURL)

        configuration.setDeepLAccountType(.pro)

        XCTAssertEqual(configuration.deepLAccountType, .pro)
        XCTAssertEqual(configuration.baseURL, ProviderConfiguration.deepLProTranslateURL)
        XCTAssertEqual(configuration.options["accountType"], "pro")
    }

    func testRuntimeConfigurationIssuesMatchProviderRequirements() {
        let deepL = AppConfiguration.default.providers.first { $0.id == "deepl-user" }!
        let libre = AppConfiguration.default.providers.first { $0.id == "libretranslate-user" }!
        let openAI = AppConfiguration.default.providers.first { $0.id == "openai-compatible-user" }!

        XCTAssertEqual(deepL.runtimeConfigurationIssues(secretAvailable: false), ["缺少 API Key"])
        XCTAssertEqual(libre.runtimeConfigurationIssues(secretAvailable: false), [])
        XCTAssertTrue(openAI.runtimeConfigurationIssues(secretAvailable: false).contains("缺少 API Key"))
        XCTAssertTrue(openAI.runtimeConfigurationIssues(secretAvailable: false).contains("缺少模型名称"))
    }

    func testLocalDictionaryReturnsChineseTranslationAndEnglishDefinition() {
        let dictionary = LocalDictionary()
        let chinese = dictionary.lookup(.init(text: "deploy", sourceLanguage: "en", targetLanguage: "zh"))
        let english = dictionary.lookup(.init(text: "deploy", sourceLanguage: "en", targetLanguage: "en"))

        XCTAssertEqual(chinese?.translatedText, "部署")
        XCTAssertEqual(english?.translatedText, "to make software or a service available for use")
        XCTAssertEqual(chinese?.credentialSource, .local)
    }

    func testLocalDictionaryReturnsEnglishForChineseWorkTerms() {
        let dictionary = LocalDictionary()
        let deployment = dictionary.lookup(.init(text: "部署", sourceLanguage: "zh", targetLanguage: "en"))
        let batch = dictionary.lookupEntry("批量")

        XCTAssertEqual(deployment?.translatedText, "deploy")
        XCTAssertEqual(deployment?.detectedSourceLanguage, "zh")
        XCTAssertEqual(batch?.entry.translations["en"], "batch")
    }

    func testMyMemoryProviderParsesResponseAndShowsProvider() async throws {
        let configuration = AppConfiguration.default.providers.first { $0.id == "mymemory-public" }!
        let client = MockHTTPClient { request in
            XCTAssertTrue(request.url?.absoluteString.contains("langpair=en%7Czh") == true)
            let data = #"{"responseData":{"translatedText":"你好"},"responseStatus":200}"#.data(using: .utf8)!
            return (data, Self.response(url: request.url!, statusCode: 200))
        }
        let provider = MyMemoryProvider(configuration: configuration, httpClient: client)
        let result = try await provider.translate(.init(text: "hello", sourceLanguage: "en", targetLanguage: "zh"))

        XCTAssertEqual(result.translatedText, "你好")
        XCTAssertEqual(result.providerName, "MyMemory")
        XCTAssertEqual(result.credentialSource, .builtIn)
    }

    func testMyMemoryAutoDetectsChineseSource() async throws {
        let configuration = AppConfiguration.default.providers.first { $0.id == "mymemory-public" }!
        let client = MockHTTPClient { request in
            XCTAssertTrue(request.url?.absoluteString.contains("langpair=zh%7Cen") == true)
            let data = #"{"responseData":{"translatedText":"Hello"},"responseStatus":200}"#.data(using: .utf8)!
            return (data, Self.response(url: request.url!, statusCode: 200))
        }
        let provider = MyMemoryProvider(configuration: configuration, httpClient: client)
        _ = try await provider.translate(.init(text: "你好", sourceLanguage: "auto", targetLanguage: "en"))
    }

    func testRouterFallsBackAndRecordsFailure() async throws {
        var configuration = AppConfiguration.default
        configuration.providers[configuration.providers.firstIndex { $0.id == "deepl-user" }!].enabled = true // DeepL, but no secret.
        configuration.defaultPresetID = "recommended-quality"

        let client = MockHTTPClient { request in
            let data = #"{"responseData":{"translatedText":"测试成功"},"responseStatus":200}"#.data(using: .utf8)!
            return (data, Self.response(url: request.url!, statusCode: 200))
        }
        let factory = ProviderFactory(httpClient: client, secrets: DictionarySecretResolver(values: [:]))
        let router = TranslationRouter(configuration: configuration, factory: factory)
        let result = try await router.translateDefault(.init(text: "fallback test", sourceLanguage: "en", targetLanguage: "zh"))

        XCTAssertEqual(result.providerID, "mymemory-public")
        XCTAssertTrue(result.fallbackOccurred)
        XCTAssertEqual(result.requestedProviderID, "deepl-user")
        XCTAssertEqual(result.requestedProviderName, "DeepL")
        XCTAssertTrue(result.fallbackReason?.contains("DeepL") == true)
    }

    func testAutomaticLanguageDirectionDoesNotStickBetweenQueries() {
        let chinese = InputAnalyzer.resolveLanguages("请确认 API 响应")
        let english = InputAnalyzer.resolveLanguages("Could you confirm the API response?")
        XCTAssertEqual(chinese.source, "zh")
        XCTAssertEqual(chinese.target, "en")
        XCTAssertEqual(english.source, "en")
        XCTAssertEqual(english.target, "zh")
    }

    func testManualTargetLanguageOverridesAutomaticDirection() {
        let manualTarget = InputAnalyzer.resolveLanguages(
            "Could you confirm this?", sourceLanguage: "auto", targetLanguage: "ja"
        )
        XCTAssertEqual(manualTarget.source, "en")
        XCTAssertEqual(manualTarget.target, "ja")
        let manualPair = InputAnalyzer.resolveLanguages(
            "这个接口", sourceLanguage: "en", targetLanguage: "fr"
        )
        XCTAssertEqual(manualPair.source, "en")
        XCTAssertEqual(manualPair.target, "fr")
    }

    func testTranslationPromptSeparatesContextFromSourceText() {
        let request = TranslationRequest(
            text: "Could you confirm the name?", sourceLanguage: "en",
            targetLanguage: "zh", context: "This is a database column name."
        )
        let prompt = PromptTemplates.translationUserPrompt(request)
        XCTAssertTrue(prompt.contains("<source_text>\nCould you confirm the name?\n</source_text>"))
        XCTAssertTrue(prompt.contains("<context>\nThis is a database column name.\n</context>"))
        XCTAssertTrue(PromptTemplates.translationSystemPrompt(
            sourceLanguage: "en", targetLanguage: "zh"
        ).contains("using <context> solely to resolve ambiguity"))
        XCTAssertFalse(PromptTemplates.translationUserPrompt(.init(
            text: "hello", sourceLanguage: "en", targetLanguage: "zh", context: "  "
        )).contains("<context>"))
    }

    func testTranslationModeDoesNotLookUpDictionaryForWord() {
        let analysis = InputAnalyzer.analyze("deployment", mode: .translation)
        XCTAssertFalse(analysis.shouldLookupDictionary)
        XCTAssertTrue(analysis.shouldTranslate)
    }

    func testSmartModeUnpunctuatedChineseRequestStillTranslates() {
        let text = "确认一下这个接口"
        let analysis = InputAnalyzer.analyze(text, mode: .smart)

        XCTAssertEqual(analysis.detectedLanguage, "zh")
        XCTAssertEqual(analysis.targetLanguage, "en")
        XCTAssertTrue(analysis.shouldTranslate)
        // A short unpunctuated sentence may probe exact dictionary entries;
        // no card is displayed unless an entry actually exists.
        XCTAssertTrue(analysis.shouldLookupDictionary)
        XCTAssertTrue(DictionaryCatalog(sources: BundledDictionaries.makeSources()).lookup(text).isEmpty)
    }

    func testChineseWorkMessageWithEnglishIdentifiersStillDetectsChinese() {
        let analysis = InputAnalyzer.analyze("API response 和文档不一致", mode: .smart)

        XCTAssertEqual(analysis.detectedLanguage, "zh")
        XCTAssertEqual(analysis.targetLanguage, "en")
    }

    func testNewQueryClearsStaleFilterAndSmartDictionaryExpansion() {
        let dictionary = "collins-han-en"
        let group = "\(dictionary)::other"
        var preferences = ResultDisplayPreferences(
            selectedFilterKey: ResultFilterKey.dictionary(dictionary),
            collapsedDictionaryIDs: [dictionary],
            groupExpansion: [group: true],
            groupDetailExpansion: [group: true]
        )
        preferences.resetForNewQuery(summarizeDictionaries: true)
        XCTAssertEqual(preferences.selectedFilterKey, ResultFilterKey.all)
        XCTAssertTrue(preferences.collapsedDictionaryIDs.isEmpty)
        XCTAssertTrue(preferences.groupExpansion.isEmpty)
        XCTAssertTrue(preferences.groupDetailExpansion.isEmpty)

        preferences = ResultDisplayPreferences(
            selectedFilterKey: ResultFilterKey.dictionary(dictionary),
            collapsedDictionaryIDs: [dictionary],
            groupExpansion: [group: true]
        )
        preferences.resetForNewQuery(summarizeDictionaries: false)
        XCTAssertEqual(preferences.selectedFilterKey, ResultFilterKey.all)
        XCTAssertTrue(preferences.collapsedDictionaryIDs.contains(dictionary))
        XCTAssertEqual(preferences.groupExpansion[group], true)
    }

    func testSmartModeChineseShortWordStillTranslates() {
        let analysis = InputAnalyzer.analyze("测试", mode: .smart)
        XCTAssertEqual(analysis.detectedLanguage, "zh")
        XCTAssertEqual(analysis.targetLanguage, "en")
        XCTAssertTrue(analysis.shouldTranslate)
    }

    func testSmartModeRoutesEnglishWordToDictionaryAndTranslation() {
        let analysis = InputAnalyzer.analyze("deployment", mode: .smart)

        XCTAssertEqual(analysis.detectedLanguage, "en")
        XCTAssertEqual(analysis.kind, .word)
        XCTAssertTrue(analysis.shouldLookupDictionary)
        XCTAssertTrue(analysis.shouldTranslate)
    }

    func testSmartModeLooksUpEnglishPhraseAlongsideTranslation() {
        let analysis = InputAnalyzer.analyze("take into account", mode: .smart)

        XCTAssertEqual(analysis.detectedLanguage, "en")
        XCTAssertEqual(analysis.targetLanguage, "zh")
        XCTAssertEqual(analysis.kind, .phrase)
        XCTAssertTrue(analysis.shouldTranslate)
        XCTAssertTrue(analysis.shouldLookupDictionary)
    }

    func testSmartModeLooksUpChinesePhraseAlongsideTranslation() {
        let analysis = InputAnalyzer.analyze("软件开发流程", mode: .smart)

        XCTAssertEqual(analysis.detectedLanguage, "zh")
        XCTAssertEqual(analysis.targetLanguage, "en")
        XCTAssertEqual(analysis.kind, .phrase)
        XCTAssertTrue(analysis.shouldTranslate)
        XCTAssertTrue(analysis.shouldLookupDictionary)
    }

    func testActualEnglishPhraseDictionaryEntryExists() {
        let catalog = DictionaryCatalog(sources: BundledDictionaries.makeSources())
        XCTAssertTrue(catalog.lookup("take into account").contains {
            $0.dictionaryID == "cambridge-en-zh"
        })
    }

    func testActualChineseTermDictionaryEntryExists() {
        let catalog = DictionaryCatalog(sources: BundledDictionaries.makeSources())
        XCTAssertTrue(catalog.lookup("人工智能").contains {
            $0.dictionaryID == "collins-han-en"
        })
    }

    func testSmartModeChineseSentenceOnlyTranslates() {
        let analysis = InputAnalyzer.analyze("我们需要确认这项功能是否已经通过测试。", mode: .smart)

        XCTAssertEqual(analysis.detectedLanguage, "zh")
        XCTAssertEqual(analysis.kind, .sentence)
        XCTAssertTrue(analysis.shouldTranslate)
        XCTAssertFalse(analysis.shouldLookupDictionary)
    }

    func testTranslationModeSkipsDictionaryForPhrases() {
        for term in ["take into account", "软件开发流程"] {
            let analysis = InputAnalyzer.analyze(term, mode: .translation)
            XCTAssertTrue(analysis.shouldTranslate)
            XCTAssertFalse(analysis.shouldLookupDictionary)
        }
    }

    func testSmartModeRoutesEnglishSentenceToChineseTranslationOnly() {
        let analysis = InputAnalyzer.analyze("Could you confirm whether batch queries are supported?", mode: .smart)

        XCTAssertEqual(analysis.detectedLanguage, "en")
        XCTAssertEqual(analysis.targetLanguage, "zh")
        XCTAssertEqual(analysis.kind, .sentence)
        XCTAssertFalse(analysis.shouldLookupDictionary)
        XCTAssertTrue(analysis.shouldTranslate)
    }

    func testDictionaryModeDoesNotCallTranslation() {
        let analysis = InputAnalyzer.analyze("deploy", mode: .dictionary)

        XCTAssertTrue(analysis.shouldLookupDictionary)
        XCTAssertFalse(analysis.shouldTranslate)
    }

    func testDictionaryCatalogPreservesLoadedDictionaryOrder() {
        let first = StubDictionarySource(id: "first", name: "第一本")
        let second = StubDictionarySource(id: "second", name: "第二本")
        let catalog = DictionaryCatalog(sources: [first, second])

        XCTAssertEqual(catalog.lookup("term").map(\.dictionaryName), ["第一本", "第二本"])
    }

    func testBundledDictionariesLoadInExpectedOrder() {
        let sources = BundledDictionaries.makeSources()

        XCTAssertEqual(sources.map(\.displayName), [
            "Cambridge English-Chinese 双解",
            "Collins 汉英大词典",
            "Collins COBUILD 高阶英英"
        ])
        XCTAssertEqual(sources.compactMap(\.entryCount), [63_762, 86_145, 33_261])
    }

    func testBundledDictionariesReturnBilingualAndEnglishDefinitions() {
        let catalog = DictionaryCatalog(sources: BundledDictionaries.makeSources())
        let results = catalog.lookup("apple")

        XCTAssertEqual(results.map(\.dictionaryID), ["cambridge-en-zh", "collins-cobuild-en"])
        XCTAssertTrue(results[0].entry.bodyText?.contains("苹果") == true)
        XCTAssertTrue(results[1].entry.bodyText?.contains("An apple is a round fruit") == true)
    }

    func testBundledHanEnglishDictionaryParsesSensesAndBilingualExamples() throws {
        let catalog = DictionaryCatalog(sources: BundledDictionaries.makeSources())
        let hanEnglish = try XCTUnwrap(catalog.lookup("部署").first { $0.dictionaryID == "collins-han-en" })

        let presentation = DictionaryPresentationParser.parse(hanEnglish)
        XCTAssertEqual(presentation.headword, "部署")
        XCTAssertEqual(presentation.senses.first?.heading, "安排")
        XCTAssertEqual(presentation.senses.first?.definitions.first?.text, "to deploy")
        XCTAssertEqual(
            presentation.senses.first?.definitions.first?.examples.first?.source,
            "部署战役"
        )
        XCTAssertEqual(
            presentation.senses.first?.definitions.first?.examples.first?.translation,
            "make military deployments"
        )
        XCTAssertTrue(presentation.senses.contains {
            $0.heading == "计划" && $0.definitions.first?.text == "plan"
        })
    }

    func testBundledHanEnglishDictionaryPreservesTechnicalMeaning() {
        let catalog = DictionaryCatalog(sources: BundledDictionaries.makeSources())
        let entries = catalog.lookup("接口")
        XCTAssertEqual(entries.map(\.dictionaryID), ["collins-han-en"])
        let presentation = DictionaryPresentationParser.parse(entries[0])
        XCTAssertTrue(presentation.senses.contains {
            $0.definitions.first?.text == "interface"
        })
        XCTAssertTrue(presentation.senses.flatMap(\.definitions).flatMap(\.examples).contains {
            $0.source == "通道接口" && $0.translation == "channel interface"
        })
        let apple = catalog.lookup("苹果")
        XCTAssertEqual(apple.map(\.dictionaryID), ["collins-han-en"])
        XCTAssertEqual(DictionaryPresentationParser.parse(apple[0]).senses.first?.definitions.first?.text, "apple")
        // Words absent from the dictionary remain the responsibility of translation providers.
        XCTAssertTrue(catalog.lookup("测试").isEmpty)
    }

    func testBundledDictionarySuggestionsUsePrefixIndex() {
        let catalog = DictionaryCatalog(sources: BundledDictionaries.makeSources())
        let suggestions = catalog.suggestions(for: "appl", limit: 8)

        XCTAssertTrue(suggestions.contains(where: { $0.lowercased() == "apple" }))
    }

    func testBundledDictionariesResolveCommonInflectedEntries() {
        let results = DictionaryCatalog(sources: BundledDictionaries.makeSources()).lookup("running")

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.entry.bodyText?.isEmpty == false })
    }

    func testBuiltInDictionaryReturnsStructuredLookupResult() {
        let results = LocalDictionary().lookupEntries("deploy")

        XCTAssertEqual(results.first?.dictionaryName, "内置基础词典")
        XCTAssertEqual(results.first?.entry.translations["zh"], "部署")
        XCTAssertEqual(results.first?.entry.englishDefinitions.first, "to make software or a service available for use")
    }

    func testCambridgePresentationSeparatesDefinitionTranslationAndExamples() {
        let result = DictionaryLookupResult(
            dictionaryID: "cambridge-en-zh",
            dictionaryName: "Cambridge",
            entry: LocalDictionaryEntry(
                term: "apple",
                language: "en",
                translations: [:],
                englishDefinitions: [],
                examples: [],
                bodyText: """
                apple
                noun [ C or U ] uk us / ˈæp.l̩ /
                › a round fruit with firm white flesh
                苹果
                to peel an apple 削个苹果
                Related Phrases/Idioms
                the apple of your eye
                """
            )
        )

        let presentation = DictionaryPresentationParser.parse(result)

        XCTAssertEqual(presentation.pronunciation, "/ˈæp.l̩/")
        XCTAssertEqual(presentation.senses.first?.definitions.first?.translation, "苹果")
        XCTAssertEqual(presentation.senses.first?.definitions.first?.examples.first?.source, "to peel an apple")
        XCTAssertEqual(presentation.senses.first?.definitions.first?.examples.first?.translation, "削个苹果")
        XCTAssertEqual(presentation.relatedTerms, ["the apple of your eye"])
    }

    func testCambridgePresentationRemovesOutlineAndSplitsNumberedSenses() {
        let result = DictionaryLookupResult(
            dictionaryID: "cambridge-en-zh",
            dictionaryName: "Cambridge",
            entry: LocalDictionaryEntry(
                term: "run",
                language: "en",
                translations: [:],
                englishDefinitions: [],
                examples: [],
                bodyText: """
                1. verb (GO QUICKLY)
                2. verb (OPERATE)
                1
                run
                verb (GO QUICKLY) uk us / rʌn /
                › to move faster than walking
                跑，奔跑
                I run every day. 我每天跑步。
                2
                run
                verb (OPERATE)
                › to control a business
                经营；管理
                """
            )
        )

        let presentation = DictionaryPresentationParser.parse(result)

        XCTAssertEqual(presentation.senses.count, 2)
        XCTAssertEqual(presentation.senses.map(\.number), ["1", "2"])
        XCTAssertFalse(presentation.senses.first?.heading?.contains("1. verb") == true)
    }

    func testRealCambridgeRunPresentationKeepsSensesAfterRelatedTerms() throws {
        let source = try XCTUnwrap(BundledDictionaries.makeSources().first)
        let result = try XCTUnwrap(source.lookupEntry("run"))

        let presentation = DictionaryPresentationParser.parse(result)

        XCTAssertGreaterThanOrEqual(presentation.senses.count, 19)
        XCTAssertTrue(presentation.senses.contains(where: { $0.number == "10" }))
        XCTAssertTrue(presentation.relatedTerms.contains("run the show"))
    }

    func testDictionarySenseGrouperClassifiesAndPreservesFirstCategoryOrder() {
        let senses = [
            DictionarySense(heading: "verb (MOVE)", definitions: [.init(text: "move quickly")]),
            DictionarySense(heading: "noun [ C ]", definitions: [.init(text: "an act of running")]),
            DictionarySense(heading: "[V-T]", definitions: [.init(text: "operate something")]),
            DictionarySense(heading: "phrasal verb", definitions: [.init(text: "run into")])
        ]

        let groups = DictionarySenseGrouper.group(senses)

        XCTAssertEqual(groups.map(\.category), [.verb, .noun, .phrase])
        XCTAssertEqual(groups.first?.senses.count, 2)
        XCTAssertEqual(groups.last?.title, "短语与固定搭配")
        XCTAssertEqual(DictionarySenseGrouper.category(for: "adverb"), .adverb)
        XCTAssertEqual(DictionarySenseGrouper.category(for: "pronoun"), .pronoun)
    }

    func testRealCambridgeRunPresentationGroupsVerbAndNounSenses() throws {
        let source = try XCTUnwrap(BundledDictionaries.makeSources().first)
        let result = try XCTUnwrap(source.lookupEntry("run"))
        let presentation = DictionaryPresentationParser.parse(result)
        let categories = presentation.senseGroups.map(\.category)

        XCTAssertTrue(categories.contains(.verb))
        XCTAssertTrue(categories.contains(.noun))
        XCTAssertEqual(presentation.senseGroups.flatMap(\.senses).count, presentation.senses.count)
    }

    func testCollinsPresentationSplitsRepeatedGrammarEntries() {
        let result = DictionaryLookupResult(
            dictionaryID: "collins-cobuild-en",
            dictionaryName: "Collins",
            entry: LocalDictionaryEntry(
                term: "hello",
                language: "en",
                translations: [:],
                englishDefinitions: [],
                examples: [],
                bodyText: """
                hello also hallo [CONVENTION]
                You say hello when you meet someone.
                Hello, Trish.
                hello hellos [N-COUNT]
                A hello is a greeting.
                She gave me a warm hello.
                """
            )
        )

        let presentation = DictionaryPresentationParser.parse(result)

        XCTAssertEqual(presentation.senses.count, 2)
        XCTAssertEqual(presentation.senses.first?.heading, "[CONVENTION]")
        XCTAssertEqual(presentation.senses.last?.definitions.first?.text, "A hello is a greeting.")
    }

    func testOpenAIExpressionParsesStructuredJSON() async throws {
        var configuration = AppConfiguration.default.providers.first { $0.id == "openai-compatible-user" }!
        configuration.enabled = true
        configuration.model = "test-model"
        let client = MockHTTPClient { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            let body = #"{"model":"test-model","choices":[{"message":{"content":"{\"primary\":\"Could you confirm this?\",\"alternatives\":[\"Can you confirm this?\"]}"}}]}"#.data(using: .utf8)!
            return (body, Self.response(url: request.url!, statusCode: 200))
        }
        let provider = OpenAICompatibleProvider(
            configuration: configuration,
            httpClient: client,
            secrets: DictionarySecretResolver(values: ["provider.openai-compatible-user.apiKey": "secret"])
        )
        let result = try await provider.optimize(
            .init(
                sourceText: "请确认",
                currentTranslation: "Please confirm",
                sourceLanguage: "zh",
                targetLanguage: "en",
                scene: .teams
            ),
            baseProviderName: "DeepL"
        )

        XCTAssertEqual(result.primaryText, "Could you confirm this?")
        XCTAssertEqual(result.alternatives, ["Can you confirm this?"])
        XCTAssertEqual(result.baseTranslationProviderName, "DeepL")
    }

    private static func response(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }
}

private final class MockHTTPClient: HTTPClientProtocol {
    let handler: (URLRequest) throws -> (Data, HTTPURLResponse)

    init(handler: @escaping (URLRequest) throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try handler(request)
    }
}

private struct StubDictionarySource: DictionarySource {
    let id: String
    let name: String
    var displayName: String { name }

    func lookupEntry(_ term: String) -> DictionaryLookupResult? {
        DictionaryLookupResult(
            dictionaryID: id,
            dictionaryName: name,
            entry: LocalDictionaryEntry(
                term: term,
                language: "en",
                translations: ["zh": name],
                englishDefinitions: [],
                examples: []
            )
        )
    }
}
