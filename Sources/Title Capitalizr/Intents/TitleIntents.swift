//
//  TitleIntents.swift
//  Title Capitalizr
//
//  Shortcuts and Siri actions (Pro): Capitalize Title, Convert Text and Open in Title Capitalizr.
//

import AppIntents
import Foundation
import TitleCaseKit

enum GuideOption: String, AppEnum {
    case plain, ap, apa, chicago, mla, bluebook, ama, nyt, wikipedia, sentence

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Style Guide"
    static var caseDisplayRepresentations: [GuideOption: DisplayRepresentation] = [
        .plain: "Title Case",
        .ap: "AP",
        .apa: "APA 7",
        .chicago: "Chicago",
        .mla: "MLA 9",
        .bluebook: "Bluebook",
        .ama: "AMA",
        .nyt: "New York Times",
        .wikipedia: "Wikipedia",
        .sentence: "Sentence case",
    ]

    var guide: StyleGuide { StyleGuide(rawValue: rawValue) ?? .plain }
}

enum ToolOption: String, AppEnum {
    case upper, lower, sentence, capitalizeEach, camel, pascal, snake, kebab, slug, smartPunctuation, straightPunctuation, trimSpaces, removeLineBreaks

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Text Tool"
    static var caseDisplayRepresentations: [ToolOption: DisplayRepresentation] = [
        .upper: "UPPERCASE",
        .lower: "lowercase",
        .sentence: "Sentence case",
        .capitalizeEach: "Capitalize Each Word",
        .camel: "camelCase",
        .pascal: "PascalCase",
        .snake: "snake_case",
        .kebab: "kebab-case",
        .slug: "URL slug",
        .smartPunctuation: "Smart quotes and dashes",
        .straightPunctuation: "Straight quotes",
        .trimSpaces: "Trim spaces",
        .removeLineBreaks: "Remove line breaks",
    ]

    var tool: TextTool { TextTool(rawValue: rawValue) ?? .upper }
}

struct ProRequiredError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "Shortcuts actions are part of Title Capitalizr Pro. Open Title Capitalizr to see the plans."
    }
}

enum IntentGate {
    @MainActor
    static func requirePro() async throws {
        let store = ProStore.shared
        if !store.isPro { await store.refresh() }
        guard store.isPro else { throw ProRequiredError() }
    }
}

struct CapitalizeTitleIntent: AppIntent {
    static var title: LocalizedStringResource = "Capitalize Title"
    static var description = IntentDescription("Converts text to title case or sentence case in the style guide you choose. Each line is converted on its own.")

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Style Guide", default: .apa)
    var guide: GuideOption

    static var parameterSummary: some ParameterSummary {
        Summary("Capitalize \(\.$text) in \(\.$guide)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try await IntentGate.requirePro()
        let dict = LibraryStore.shared.dictionary
        let g = guide.guide
        let out = BatchConverter.convert(text, options: BatchOptions(), transform: { TitleCaseEngine.apply($0, guide: g, dictionary: dict) })
        if !text.contains("\n") { LibraryStore.shared.record(input: text, output: out, guide: g) }
        return .result(value: out)
    }
}

struct ConvertTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Convert Text"
    static var description = IntentDescription("Applies a text tool: UPPERCASE, lowercase, sentence case, camelCase, snake_case, kebab-case, a URL slug, smart quotes, trimmed spaces or joined lines.")

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Tool", default: .upper)
    var tool: ToolOption

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$text) to \(\.$tool)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try await IntentGate.requirePro()
        return .result(value: tool.tool.apply(text))
    }
}

struct OpenInTitleCapitalizrIntent: AppIntent {
    static var title: LocalizedStringResource = "Open in Title Capitalizr"
    static var description = IntentDescription("Opens Title Capitalizr with the text, ready to convert.")
    static var openAppWhenRun = true

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        SharedVault.update { $0.pendingInput = text }
        LibraryStore.shared.reload()
        return .result()
    }
}

struct TitleCapitalizrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CapitalizeTitleIntent(),
                    phrases: ["Capitalize a title with \(.applicationName)", "Title case with \(.applicationName)"],
                    shortTitle: "Capitalize Title", systemImageName: "textformat")
        AppShortcut(intent: ConvertTextIntent(),
                    phrases: ["Convert text with \(.applicationName)"],
                    shortTitle: "Convert Text", systemImageName: "wrench.and.screwdriver")
        AppShortcut(intent: OpenInTitleCapitalizrIntent(),
                    phrases: ["Open text in \(.applicationName)"],
                    shortTitle: "Open in Title Capitalizr", systemImageName: "square.and.arrow.down")
    }
}
