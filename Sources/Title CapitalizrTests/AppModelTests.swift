//
//  AppModelTests.swift
//  Title CapitalizrTests
//
//  History and favourites, Pro gating of guides and tools, the All Access entitlement ids,
//  deep links and the Apple Intelligence "unavailable" path.
//

import XCTest
@testable import Title_Capitalizr
import TitleCaseKit

final class AppModelTests: XCTestCase {

    func testHistoryRecordsNewestFirstAndMergesDuplicates() {
        var s = SharedSnapshot()
        s.record(input: "the lord of the rings", output: "The Lord of the Rings", guide: .mla)
        s.record(input: "a war between the worlds", output: "A War Between the Worlds", guide: .apa)
        XCTAssertEqual(s.history.map(\.output), ["A War Between the Worlds", "The Lord of the Rings"])
        s.history[1].favorite = true
        s.record(input: "THE LORD OF THE RINGS", output: "The Lord of the Rings", guide: .mla)
        XCTAssertEqual(s.history.count, 2)
        XCTAssertEqual(s.history[0].output, "The Lord of the Rings")
        XCTAssertTrue(s.history[0].favorite, "re-recording keeps the favourite flag")
    }

    func testHistoryIgnoresEmptyInput() {
        var s = SharedSnapshot()
        s.record(input: "   ", output: "", guide: .mla)
        XCTAssertTrue(s.history.isEmpty)
    }

    func testHistoryTrimKeepsFavourites() {
        var s = SharedSnapshot()
        s.record(input: "keep me", output: "Keep Me", guide: .mla)
        s.history[0].favorite = true
        for i in 0..<(SharedSnapshot.historyLimit + 20) { s.record(input: "title \(i)", output: "Title \(i)", guide: .apa) }
        XCTAssertEqual(s.history.count, SharedSnapshot.historyLimit)
        XCTAssertTrue(s.history.contains { $0.output == "Keep Me" && $0.favorite })
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        var s = SharedSnapshot()
        s.record(input: "iphone review", output: "iPhone Review", guide: .ap)
        s.dictionary = CustomDictionary(words: ["iPhone", "NASA"])
        s.isPro = true
        let back = try JSONDecoder().decode(SharedSnapshot.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testFreeTierGuidesAndTools() {
        XCTAssertEqual(Set(StyleGuide.allCases.filter(\.isFree)), [.plain, .mla, .apa])
        XCTAssertEqual(Set(TextTool.allCases.filter(\.isFree)), [.upper, .lower, .sentence, .trimSpaces, .removeLineBreaks])
    }

    func testEntitlementPolicyIncludesAllAccess() {
        let now = Date()
        XCTAssertTrue(ProEntitlementPolicy.isPro([.init(productID: ProProductID.allAccessAnnual, expirationDate: now.addingTimeInterval(60), revocationDate: nil)], now: now))
        XCTAssertTrue(ProEntitlementPolicy.isPro([.init(productID: ProProductID.allAccessMonthly, expirationDate: now.addingTimeInterval(60), revocationDate: nil)], now: now))
        XCTAssertFalse(ProEntitlementPolicy.isPro([.init(productID: ProProductID.allAccessMonthly, expirationDate: now.addingTimeInterval(-60), revocationDate: nil)], now: now))
    }

    func testPaywallOrderPutsAllAccessFirst() {
        let ids = OrchestrPaywall.orderedProductIDs(bundle: nil, bundleId: "com.johnseong.titlecapitalizr", own: ProProductID.own)
        XCTAssertEqual(ids, [ProProductID.allAccessAnnual, ProProductID.allAccessMonthly, ProProductID.yearly, ProProductID.lifetime])
        XCTAssertEqual(OrchestrPaywall.kind(of: ProProductID.allAccessAnnual), .allaccess)
        XCTAssertEqual(OrchestrPaywall.kind(of: ProProductID.lifetime), .own)
        XCTAssertFalse(OrchestrPaywall.subtitle(.allaccess).contains("·"))
        XCTAssertFalse(OrchestrPaywall.subtitle(.allaccess).contains("•"))
    }

    func testDeepLinks() {
        XCTAssertEqual(TCLink.open(guide: .chicago, mode: "title").absoluteString, "titlecapitalizr://open?guide=chicago&mode=title")
        let id = UUID()
        XCTAssertEqual(TCLink.entry(id).host, "history")
    }

    @MainActor
    func testPolishReportsUnavailableModelClearly() async {
        let smart = SmartCapitalizer(availabilityProvider: { .unavailable(reason: "Apple Intelligence is still downloading its model. Try again later.") })
        let polish = await smart.polishHeadline("scientists find water on mars", style: .ap)
        XCTAssertEqual(polish, .unavailable("Apple Intelligence is still downloading its model. Try again later."))
        let fix = await smart.fixGrammar("a apple a day", style: .ap)
        if case .unavailable(let why) = fix { XCTAssertFalse(why.isEmpty) } else { XCTFail("expected unavailable") }
        let empty = await smart.polishHeadline("  ", style: .ap)
        XCTAssertEqual(empty, .unchanged)
    }

    func testAppEnumsMirrorEngineCases() {
        XCTAssertEqual(GuideOption.allCases.map(\.rawValue), StyleGuide.allCases.map(\.rawValue))
        XCTAssertEqual(ToolOption.allCases.map(\.rawValue), TextTool.allCases.map(\.rawValue))
    }
}
