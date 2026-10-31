//
//  EssayFormatterTests.swift
//  Title CapitalizrTests
//
//  Docx reader and writer, MLA / APA / Chicago rules, citation checks, the PDF, RTF
//  and text exports, and a full round trip: sample .docx in, formatted .docx out,
//  unzipped and inspected.
//

import XCTest
import PDFKit
@testable import Title_Capitalizr

final class EssayFormatterTests: XCTestCase {

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sample-essay", withExtension: "docx"))
        return try Data(contentsOf: url)
    }

    private func analyzedSample() throws -> (SourceDocument, EssayStructure) {
        let doc = try DocxReader.read(data: fixture(), fileName: "sample-essay")
        return (doc, EssayAnalyzer.analyze(doc))
    }

    private func format(_ s: EssayStructure, style: EssayStyle, disabled: Set<String> = []) -> EssayFormatter.Output {
        EssayFormatter.format(.init(structure: s, heading: s.heading, title: s.title, style: style, disabledFixes: disabled))
    }

    // MARK: Zip

    func testZipWriterRoundTripsThroughReader() throws {
        var w = ZipWriter()
        w.add("a.txt", "hello")
        w.add("dir/b.xml", "<x>ü</x>")
        let zip = try ZipArchive(data: w.finalize())
        XCTAssertEqual(zip.entryNames, ["a.txt", "dir/b.xml"])
        XCTAssertEqual(try zip.string(for: "dir/b.xml"), "<x>ü</x>")
        XCTAssertEqual(CRC32.checksum(Array("123456789".utf8)), 0xCBF4_3926)
    }

    func testZipReaderRejectsNonZip() {
        XCTAssertThrowsError(try ZipArchive(data: Data("not a zip at all, sorry".utf8)))
    }

    // MARK: Docx reader

    func testDocxReaderKeepsParagraphsItalicsStylesAndFootnotes() throws {
        let doc = try DocxReader.read(data: fixture(), fileName: "sample-essay")
        XCTAssertEqual(doc.paragraphs.first?.text, "Jane Q. Doe")
        let title = try XCTUnwrap(doc.paragraphs.first { $0.hint == .title })
        XCTAssertEqual(title.text, "the long road: a short history of the bicycle")
        let first = doc.paragraphs[5]
        XCTAssertTrue(first.runs.contains { $0.italic && $0.text == "Two Wheels" })
        XCTAssertTrue(first.runs.contains { $0.footnoteID == 1 })
        XCTAssertEqual(doc.footnotes[1]?.plainText, "All sources in this sample are invented placeholders.")
        XCTAssertEqual(doc.paragraphs[8].hint, .quote, "whole-paragraph indent reads as a block quote")
        XCTAssertEqual(doc.paragraphs.first { $0.text.hasPrefix("Lopez, Maria") }?.hint, .normal, "hanging indent is not a quote")
        XCTAssertEqual(doc.paragraphs.first { $0.text == "Works Cited" }?.hint, .centered)
    }

    // MARK: Analyzer

    func testAnalyzerFindsHeadingTitleBodyAndWorksCited() throws {
        let (_, s) = try analyzedSample()
        XCTAssertEqual(s.heading.name, "Jane Q. Doe")
        XCTAssertEqual(s.heading.instructor, "Professor Alan Rivera")
        XCTAssertEqual(s.heading.course, "ENGL 101")
        XCTAssertEqual(s.heading.date, "October 30, 2026")
        XCTAssertNotNil(s.parsedDate)
        XCTAssertEqual(s.title, "the long road: a short history of the bicycle")
        XCTAssertEqual(s.body.count, 4)
        XCTAssertEqual(s.references.count, 3)
        XCTAssertEqual(s.detectedReferencesHeading, "Works Cited")
        XCTAssertFalse(s.uncertain.contains(.title))
        XCTAssertFalse(s.uncertain.contains(.name))
        XCTAssertEqual(s.heading.lastName, "Doe")
    }

    func testAnalyzerPlainTextHeadingWithoutStyles() {
        let text = """
        Sam Lee
        Ms. Park
        History 12
        3 May 2026
        Why Canals Mattered
        Canals moved goods across the region for a century before railways arrived and made them slow by comparison.
        Bibliography
        Zed, Ann. Canals. Example Press, 1999.
        """
        let s = EssayAnalyzer.analyze(PlainTextReader.read(text))
        XCTAssertEqual(s.heading.name, "Sam Lee")
        XCTAssertEqual(s.heading.instructor, "Ms. Park")
        XCTAssertEqual(s.heading.course, "History 12")
        XCTAssertEqual(s.heading.date, "3 May 2026")
        XCTAssertEqual(s.title, "Why Canals Mattered")
        XCTAssertEqual(s.body.count, 1)
        XCTAssertEqual(s.references.map(\.text), ["Zed, Ann. Canals. Example Press, 1999."])
    }

    func testAnalyzerKeepsSectionHeadingAfterTitleInBody() {
        var doc = PlainTextReader.read("A Name\nProf. X\nENGL 1\n1 May 2026\n")
        doc.paragraphs.append(SourceParagraph(text: "Bridges of the North", hint: .centered))
        doc.paragraphs.append(SourceParagraph(text: "Introduction", hint: .heading(1)))
        doc.paragraphs.append(SourceParagraph(text: String(repeating: "Bridges carried people over rivers. ", count: 6)))
        let s = EssayAnalyzer.analyze(doc)
        XCTAssertEqual(s.title, "Bridges of the North")
        XCTAssertEqual(s.body.first?.text, "Introduction")
    }

    func testDateParsingAndMLAFormat() throws {
        let d = try XCTUnwrap(DateParsing.parse("October 30, 2026"))
        XCTAssertEqual(DateParsing.format(d, style: .mla9), "30 October 2026")
        XCTAssertEqual(DateParsing.format(d, style: .apa7), "October 30, 2026")
        XCTAssertEqual(DateParsing.format(try XCTUnwrap(DateParsing.parse("10/30/2026")), style: .mla9), "30 October 2026")
        XCTAssertNil(DateParsing.parse("ENGL 101"))
    }

    // MARK: MLA rules

    func testMLAHeadingTitleIndentsAndHeader() throws {
        let (_, s) = try analyzedSample()
        let out = format(s, style: .mla9)
        let e = out.essay
        XCTAssertEqual(e.header, .lastNameAndPage("Doe"))
        XCTAssertTrue(e.headerOnFirstPage)
        let headings = e.paragraphs.filter { $0.role == .heading }.map(\.text)
        XCTAssertEqual(headings, ["Jane Q. Doe", "Professor Alan Rivera", "ENGL 101", "30 October 2026"])
        let title = try XCTUnwrap(e.paragraphs.first { $0.role == .title })
        XCTAssertEqual(title.text, "The Long Road: A Short History of the Bicycle")
        XCTAssertEqual(title.alignment, .center)
        XCTAssertTrue(e.paragraphs.allSatisfy { $0.lineSpacing == 2.0 }, "MLA is double-spaced throughout")
        let body = e.paragraphs.filter { $0.role == .body }
        XCTAssertEqual(body.count, 3)
        XCTAssertTrue(body.allSatisfy { $0.firstLineIndent == 0.5 && $0.hangingIndent == 0 })
        XCTAssertFalse(body[0].text.hasPrefix("\t"), "typed tab indent removed")
        XCTAssertFalse(body[1].text.contains("  "), "double space collapsed")
        let quote = try XCTUnwrap(e.paragraphs.first { $0.role == .blockQuote })
        XCTAssertEqual(quote.leftIndent, 0.5)
        XCTAssertEqual(quote.firstLineIndent, 0)
    }

    func testMLAWorksCitedSortedWithHangingIndentOnNewPage() throws {
        let (_, s) = try analyzedSample()
        let e = format(s, style: .mla9).essay
        let heading = try XCTUnwrap(e.paragraphs.first { $0.role == .referencesHeading })
        XCTAssertEqual(heading.text, "Works Cited")
        XCTAssertEqual(heading.alignment, .center)
        XCTAssertTrue(heading.pageBreakBefore)
        let refs = e.paragraphs.filter { $0.role == .reference }
        XCTAssertEqual(refs.map { String($0.text.prefix(6)) }, ["Lopez,", "Okafor", "Smith,"])
        XCTAssertTrue(refs.allSatisfy { $0.hangingIndent == 0.5 && $0.leftIndent == 0.5 && $0.lineSpacing == 2 })
        XCTAssertTrue(refs[0].runs.contains { $0.italic && $0.text.contains("Journal of Imaginary Transport") }, "italics kept")
        XCTAssertFalse(refs[0].text.contains("https://"), "MLA 9 drops the URL scheme")
        XCTAssertTrue(refs[2].text.hasSuffix("2001."), "missing period added")
    }

    func testWorksCitedSortIgnoresArticlesCaseAndAccents() {
        let entries = ["The Zebra Book. 2000.", "apple, Ann. 1999.", "Émile, B. 2001.", "A Moon. 2002."]
        let sorted = entries.sorted { EssayFormatter.sortKey($0) < EssayFormatter.sortKey($1) }
        XCTAssertEqual(sorted, ["apple, Ann. 1999.", "Émile, B. 2001.", "A Moon. 2002.", "The Zebra Book. 2000."])
    }

    func testMLACitationFixesAreListedAndCanBeSwitchedOff() throws {
        let (_, s) = try analyzedSample()
        let out = format(s, style: .mla9)
        let body = out.essay.paragraphs.filter { $0.role == .body }.map(\.text)
        XCTAssertTrue(body[0].contains("(Smith 12)."), body[0])
        XCTAssertTrue(body[1].contains("flight\" (Lopez 45)."), body[1])
        XCTAssertTrue(body[2].contains("(Okafor 7)"), body[2])
        let fixes = out.issues.filter { $0.kind == .fix }
        XCTAssertTrue(fixes.contains { $0.original == "(Smith, 12)" && $0.replacement == "(Smith 12)" })
        XCTAssertTrue(fixes.contains { $0.original == "(Okafor p. 7)" })
        // Switching every fix off leaves the text alone.
        let off = format(s, style: .mla9, disabled: Set(fixes.map(\.id)))
        let raw = off.essay.paragraphs.filter { $0.role == .body }.map(\.text)
        XCTAssertTrue(raw[0].contains("(Smith, 12)"))
        XCTAssertTrue(raw[2].contains("(Okafor p. 7)"))
        // Footnote survives and is renumbered.
        XCTAssertEqual(out.essay.footnotes[1]?.plainText, "All sources in this sample are invented placeholders.")
    }

    func testCitationWarningsForMissingAndUncitedSources() {
        var s = EssayStructure()
        s.heading = HeadingFields(name: "A B", instructor: "Dr. C", course: "ENGL 1", date: "1 May 2026")
        s.title = "Test"
        s.body = [SourceParagraph(text: "Wheels turn (Nobody 4) and roll on (Smith 9).")]
        s.references = [SourceParagraph(text: "Smith, H. Book. Press, 2000."), SourceParagraph(text: "Unused, Q. Other. Press, 2001.")]
        let issues = EssayFormatter.format(.init(structure: s, heading: s.heading, title: s.title, style: .mla9)).issues
        XCTAssertTrue(issues.contains { $0.kind == .warning && $0.message.contains("\"Nobody\" is cited") })
        XCTAssertTrue(issues.contains { $0.kind == .warning && $0.message.contains("\"Unused\" is in Works Cited") })
        XCTAssertFalse(issues.contains { $0.message.contains("\"Smith\" is cited") })
    }

    func testAPAAndChicagoCitationRules() {
        var s = EssayStructure()
        s.body = [SourceParagraph(text: "Roads improved (Smith 2019) and later (Jones, 2020, p. 4).")]
        s.references = [SourceParagraph(text: "Smith, H. (2019). Roads. Press."), SourceParagraph(text: "Jones, K. (2020). Later. Press.")]
        let apa = EssayFormatter.format(.init(structure: s, heading: HeadingFields(), title: "roads and the city", style: .apa7))
        XCTAssertTrue(apa.essay.paragraphs.first { $0.role == .body }!.text.contains("(Smith, 2019)"))
        let ad = EssayFormatter.format(.init(structure: s, heading: HeadingFields(), title: "roads", style: .chicagoAuthorDate))
        XCTAssertTrue(ad.essay.paragraphs.first { $0.role == .body }!.text.contains("(Jones 2020, p. 4)"))
    }

    // MARK: APA / Chicago layout

    func testAPATitlePageAndReferences() throws {
        let (_, s) = try analyzedSample()
        let e = format(s, style: .apa7).essay
        XCTAssertEqual(e.header, .pageNumber)
        let titlePage = e.paragraphs.filter { $0.role == .titlePage }
        XCTAssertEqual(titlePage.first?.text, "The Long Road: A Short History of the Bicycle")
        XCTAssertTrue(titlePage.first?.runs.allSatisfy(\.bold) ?? false)
        let repeatTitle = try XCTUnwrap(e.paragraphs.first { $0.role == .title })
        XCTAssertTrue(repeatTitle.pageBreakBefore)
        XCTAssertEqual(e.paragraphs.first { $0.role == .referencesHeading }?.text, "References")
        XCTAssertTrue(e.paragraphs.contains { $0.role == .heading } == false)
    }

    func testChicagoHidesHeaderOnTitlePageAndSingleSpacesBibliography() throws {
        let (_, s) = try analyzedSample()
        let e = format(s, style: .chicagoNotes).essay
        XCTAssertFalse(e.headerOnFirstPage)
        XCTAssertEqual(e.paragraphs.first { $0.role == .referencesHeading }?.text, "Bibliography")
        XCTAssertTrue(e.paragraphs.filter { $0.role == .reference }.allSatisfy { $0.lineSpacing == 1 && $0.spaceAfter == 12 })
        XCTAssertTrue(e.paragraphs.first { $0.role == .body }?.pageBreakBefore ?? false)
    }

    // MARK: Title case engine

    func testTitleCaseEngine() {
        XCTAssertEqual(TitleCaser.apply("the long road: a short history of the bicycle", style: .mla), "The Long Road: A Short History of the Bicycle")
        XCTAssertEqual(TitleCaser.apply("life with NASA and the iPhone", style: .mla), "Life with NASA and the iPhone")
        XCTAssertEqual(TitleCaser.apply("a war between the worlds", style: .apa), "A War Between the Worlds")
        XCTAssertEqual(TitleCaser.apply("a war between the worlds", style: .mla), "A War between the Worlds")
        XCTAssertEqual(TitleCaser.apply("THE SELF-ESTEEM OF MICE", style: .mla), "The Self-Esteem of Mice")
        XCTAssertEqual(TitleCaser.apply("what it's all about", style: .mla), "What It's All About")
        XCTAssertEqual(TitleCaser.apply("going up to the top", style: .mla), "Going Up to the Top")
    }

    // MARK: Writers

    func testDocxWriterProducesValidWordprocessingML() throws {
        let (_, s) = try analyzedSample()
        let essay = format(s, style: .mla9).essay
        let data = DocxWriter.write(essay)
        let zip = try ZipArchive(data: data)
        for part in ["[Content_Types].xml", "_rels/.rels", "word/document.xml", "word/styles.xml", "word/settings.xml",
                     "word/header1.xml", "word/footnotes.xml", "word/_rels/document.xml.rels", "docProps/core.xml"] {
            XCTAssertTrue(zip.contains(part), part)
            let xml = try zip.data(for: part)
            let parser = XMLParser(data: xml)
            XCTAssertTrue(parser.parse(), "\(part) is not well-formed: \(String(describing: parser.parserError))")
        }
        let doc = try zip.string(for: "word/document.xml")
        XCTAssertTrue(doc.contains(#"<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440""#))
        XCTAssertTrue(doc.contains(#"<w:ind w:left="720" w:hanging="720"/>"#), "hanging indent")
        XCTAssertTrue(doc.contains(#"<w:ind w:left="0" w:firstLine="720"/>"#), "first-line indent")
        XCTAssertTrue(doc.contains(#"w:line="480""#), "double spacing")
        XCTAssertTrue(doc.contains("<w:pageBreakBefore/>"), "Works Cited on a new page")
        XCTAssertTrue(doc.contains(#"<w:footnoteReference w:id="1"/>"#))
        XCTAssertTrue(doc.contains("<w:i/><w:iCs/></w:rPr><w:t xml:space=\"preserve\">Two Wheels</w:t>"))
        let header = try zip.string(for: "word/header1.xml")
        XCTAssertTrue(header.contains("Doe "))
        XCTAssertTrue(header.contains(#"<w:instrText xml:space="preserve"> PAGE </w:instrText>"#))
        XCTAssertTrue(header.contains(#"<w:jc w:val="right"/>"#))
        let styles = try zip.string(for: "word/styles.xml")
        XCTAssertTrue(styles.contains(#"w:ascii="Times New Roman""#))
        XCTAssertTrue(styles.contains(#"<w:sz w:val="24"/>"#))
        XCTAssertTrue(try zip.string(for: "word/_rels/document.xml.rels").contains("footnotes.xml"))
    }

    /// Sample docx in, formatted docx out, then read back with the same reader.
    func testRoundTripDocxInDocxOut() throws {
        let (_, s) = try analyzedSample()
        let essay = format(s, style: .mla9).essay
        let back = try DocxReader.read(data: DocxWriter.write(essay), fileName: "out")
        let texts = back.paragraphs.map(\.text)
        XCTAssertEqual(Array(texts.prefix(5)), ["Jane Q. Doe", "Professor Alan Rivera", "ENGL 101", "30 October 2026",
                                                 "The Long Road: A Short History of the Bicycle"])
        XCTAssertTrue(texts.contains("Works Cited"))
        XCTAssertEqual(back.footnotes[1]?.plainText, "All sources in this sample are invented placeholders.")
        let reanalyzed = EssayAnalyzer.analyze(back)
        XCTAssertEqual(reanalyzed.heading.name, "Jane Q. Doe")
        XCTAssertEqual(reanalyzed.references.count, 3)
        XCTAssertEqual(reanalyzed.title, "The Long Road: A Short History of the Bicycle")
        // Formatting again is stable: no further fixes.
        let again = format(reanalyzed, style: .mla9)
        XCTAssertEqual(again.issues.filter { $0.kind == .fix }.count, 0, again.issues.filter { $0.kind == .fix }.map(\.message).joined(separator: "; "))
    }

    func testChicagoDocxHasFirstPageHeaderSuppressed() throws {
        let (_, s) = try analyzedSample()
        let zip = try ZipArchive(data: DocxWriter.write(format(s, style: .chicagoNotes).essay))
        XCTAssertTrue(try zip.string(for: "word/document.xml").contains("<w:titlePg/>"))
        XCTAssertTrue(zip.contains("word/header2.xml"))
        XCTAssertTrue(try zip.string(for: "[Content_Types].xml").contains("header2.xml"))
    }

    func testPDFRendererProducesPagesWithRunningHeaderAndReadsBack() throws {
        let (_, s) = try analyzedSample()
        let essay = format(s, style: .mla9).essay
        let result = PDFEssayRenderer.render(essay)
        XCTAssertGreaterThanOrEqual(result.pageCount, 2, "Works Cited starts a new page")
        let pdf = try XCTUnwrap(PDFDocument(data: result.data))
        XCTAssertEqual(pdf.pageCount, result.pageCount)
        let page1 = try XCTUnwrap(pdf.page(at: 0)?.string)
        XCTAssertTrue(page1.contains("Doe 1"))
        XCTAssertTrue(page1.contains("The Long Road: A Short History of the Bicycle"))
        let last = try XCTUnwrap(pdf.page(at: pdf.pageCount - 1)?.string)
        XCTAssertTrue(last.contains("Works Cited"))
        // First-page-only preview for free users.
        XCTAssertEqual(PDFEssayRenderer.render(essay, maxPages: 1).pageCount, 1)
        // The PDF reader rebuilds the structure from our own output.
        let back = try PDFEssayReader.read(pdf, fileName: "out")
        let re = EssayAnalyzer.analyze(back)
        XCTAssertEqual(re.heading.name, "Jane Q. Doe")
        XCTAssertEqual(re.title, "The Long Road: A Short History of the Bicycle")
        XCTAssertEqual(re.references.count, 3)
    }

    func testRTFAndTextExports() throws {
        let (_, s) = try analyzedSample()
        let essay = format(s, style: .mla9).essay
        let rtf = String(decoding: RTFEssayWriter.write(essay), as: UTF8.self)
        XCTAssertTrue(rtf.hasPrefix("{\\rtf1"))
        XCTAssertTrue(rtf.contains("{\\header"))
        XCTAssertTrue(rtf.contains("\\chpgn"))
        XCTAssertTrue(rtf.contains("\\pagebb"))
        XCTAssertTrue(rtf.contains("\\li720\\fi-720"))
        let attributed = try NSAttributedString(data: RTFEssayWriter.write(essay), options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        XCTAssertTrue(attributed.string.contains("The Long Road: A Short History of the Bicycle"))
        XCTAssertTrue(attributed.string.contains("Works Cited"))
        let txt = PlainTextEssayWriter.write(essay)
        XCTAssertTrue(txt.hasPrefix("Jane Q. Doe\n"))
        XCTAssertTrue(txt.contains("\n\tThe bicycle began"))
        XCTAssertTrue(txt.contains("[1]"))
    }

    func testExportFileNames() throws {
        let (_, s) = try analyzedSample()
        let essay = format(s, style: .mla9).essay
        XCTAssertEqual(ExportNaming.fileName(for: essay, format: .docx), "Doe_The-Long-Road-A-Short-History-of-the-Bicycle_MLA.docx")
        XCTAssertEqual(ExportNaming.fileName(lastName: "", title: "", style: .apa7, ext: "pdf"), "Essay_APA.pdf")
        XCTAssertEqual(ExportNaming.fileName(lastName: "Núñez", title: "Río: ¿Qué?", style: .chicagoNotes, ext: "rtf"), "Nunez_Rio-Que_Chicago.rtf")
    }

    /// Writes every export of the sample for checking in Word, Pages and textutil.
    /// Runs only when TC_EXPORT=1 (TEST_RUNNER_TC_EXPORT=1 for xcodebuild); files go to the
    /// test host's temporary folder (inside the app container on macOS), printed to the log.
    func testWriteSampleExportsForExternalValidation() throws {
        guard ProcessInfo.processInfo.environment["TC_EXPORT"] == "1" else { throw XCTSkip("TC_EXPORT not set") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TCExports").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        print("TC_EXPORT_PATH=\(dir)")
        let (_, s) = try analyzedSample()
        for style in EssayStyle.allCases {
            let essay = format(s, style: style).essay
            for f in ExportFormat.allCases {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(ExportNaming.fileName(for: essay, format: f))
                try f.data(for: essay).write(to: url)
            }
        }
    }

    // MARK: Google Docs

    func testGoogleDocsLinkParsing() {
        XCTAssertEqual(GoogleDocsLink.parse("https://docs.google.com/document/d/1AbCdEfGhIjKlMnOp_qrs-TUV/edit?usp=sharing"), .document(id: "1AbCdEfGhIjKlMnOp_qrs-TUV"))
        XCTAssertEqual(GoogleDocsLink.parse("https://docs.google.com/document/u/0/d/1AbCdEfGhIjKlMnOp/edit"), .document(id: "1AbCdEfGhIjKlMnOp"))
        XCTAssertEqual(GoogleDocsLink.parse("https://drive.google.com/file/d/1AbCdEfGhIjKlMnOp/view"), .driveFile(id: "1AbCdEfGhIjKlMnOp"))
        XCTAssertNil(GoogleDocsLink.parse("https://example.com/document/d/1AbCdEfGhIjKlMnOp"))
        XCTAssertNil(GoogleDocsLink.parse("not a link"))
        XCTAssertEqual(GoogleDocsLink.exportURL(for: .document(id: "1AbCdEfGhIjKlMnOp")).absoluteString,
                       "https://docs.google.com/document/d/1AbCdEfGhIjKlMnOp/export?format=docx")
    }

    func testGoogleDocsResponseClassification() {
        let pk = Data([0x50, 0x4B, 0x03, 0x04, 0x00])
        XCTAssertEqual(GoogleDocsLink.classify(status: 200, finalURL: nil, data: pk), .success(pk))
        XCTAssertEqual(GoogleDocsLink.classify(status: 200, finalURL: URL(string: "https://accounts.google.com/ServiceLogin"), data: Data("<html>".utf8)), .failure(.notShared))
        XCTAssertEqual(GoogleDocsLink.classify(status: 200, finalURL: nil, data: Data("<html>".utf8)), .failure(.notShared))
        XCTAssertEqual(GoogleDocsLink.classify(status: 404, finalURL: nil, data: Data()), .failure(.notFound))
    }

    // MARK: Importer and paywall policy

    func testImporterSniffsAndRejects() {
        XCTAssertThrowsError(try EssayImporter.read(data: Data("x".utf8), fileExtension: "pages", fileName: "a")) { error in
            XCTAssertTrue((error as? EssayImportError)?.errorDescription?.contains("Export To > Word") ?? false)
        }
        XCTAssertNoThrow(try EssayImporter.read(data: Data("{\\rtf1\\ansi Hello there.\\par}".utf8), fileExtension: "dat", fileName: "a"))
    }

    func testProEntitlementPolicy() {
        let now = Date()
        XCTAssertFalse(ProEntitlementPolicy.isPro([], now: now))
        XCTAssertTrue(ProEntitlementPolicy.isPro([.init(productID: ProProductID.lifetime, expirationDate: nil, revocationDate: nil)], now: now))
        XCTAssertFalse(ProEntitlementPolicy.isPro([.init(productID: ProProductID.yearly, expirationDate: now.addingTimeInterval(-1), revocationDate: nil)], now: now))
        XCTAssertTrue(ProEntitlementPolicy.isPro([.init(productID: ProProductID.yearly, expirationDate: now.addingTimeInterval(60), revocationDate: nil)], now: now))
        XCTAssertFalse(ProEntitlementPolicy.isPro([.init(productID: ProProductID.lifetime, expirationDate: nil, revocationDate: now)], now: now))
        XCTAssertFalse(ProEntitlementPolicy.isPro([.init(productID: "other", expirationDate: nil, revocationDate: nil)], now: now))
    }
}
