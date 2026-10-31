//
//  DocxWriter.swift
//  Title Capitalizr
//
//  Writes a FormattedEssay as a WordprocessingML (.docx) package: Times New Roman 12,
//  1 inch margins, the running header with a real PAGE field, paragraph indents and
//  spacing as direct formatting, page breaks before Works Cited and true footnotes.
//  Opens in Word, Pages, Google Docs and LibreOffice.
//

import Foundation

enum DocxWriter {
    static let wNS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    static let rNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    static func write(_ essay: FormattedEssay, date: Date = Date()) -> Data {
        var zip = ZipWriter()
        let hasNotes = !essay.footnotes.isEmpty
        zip.add("[Content_Types].xml", contentTypes(hasNotes: hasNotes, firstHeader: !essay.headerOnFirstPage))
        zip.add("_rels/.rels", rootRels)
        zip.add("docProps/core.xml", coreProps(essay, date: date))
        zip.add("docProps/app.xml", appProps)
        zip.add("word/document.xml", documentXML(essay))
        zip.add("word/styles.xml", stylesXML)
        zip.add("word/settings.xml", settingsXML(hasNotes: hasNotes))
        zip.add("word/header1.xml", headerXML(essay.header))
        if !essay.headerOnFirstPage { zip.add("word/header2.xml", emptyHeaderXML) }
        if hasNotes { zip.add("word/footnotes.xml", footnotesXML(essay)) }
        zip.add("word/_rels/document.xml.rels", documentRels(hasNotes: hasNotes, firstHeader: !essay.headerOnFirstPage))
        return zip.finalize(date: date)
    }

    // MARK: Package parts

    static func contentTypes(hasNotes: Bool, firstHeader: Bool) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
        <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>\
        <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>\
        \(firstHeader ? #"<Override PartName="/word/header2.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>"# : "")\
        \(hasNotes ? #"<Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>"# : "")\
        <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>\
        <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>\
        </Types>
        """
    }

    static let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>\
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>\
        </Relationships>
        """

    static func documentRels(hasNotes: Bool, firstHeader: Bool) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>\
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>\
        \(firstHeader ? #"<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header2.xml"/>"# : "")\
        \(hasNotes ? #"<Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" Target="footnotes.xml"/>"# : "")\
        </Relationships>
        """
    }

    static func coreProps(_ essay: FormattedEssay, date: Date) -> String {
        let iso = ISO8601DateFormatter().string(from: date)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
        <dc:title>\(escape(essay.title))</dc:title>\
        <dc:creator>\(escape(essay.heading.name))</dc:creator>\
        <dcterms:created xsi:type="dcterms:W3CDTF">\(iso)</dcterms:created>\
        <dcterms:modified xsi:type="dcterms:W3CDTF">\(iso)</dcterms:modified>\
        </cp:coreProperties>
        """
    }

    static let appProps = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Title Capitalizr</Application></Properties>
        """

    static let stylesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="\(wNS)">\
        <w:docDefaults>\
        <w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/><w:szCs w:val="24"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault>\
        <w:pPrDefault><w:pPr><w:spacing w:before="0" w:after="0" w:line="480" w:lineRule="auto"/></w:pPr></w:pPrDefault>\
        </w:docDefaults>\
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>\
        <w:style w:type="character" w:default="1" w:styleId="DefaultParagraphFont"><w:name w:val="Default Paragraph Font"/><w:uiPriority w:val="1"/><w:semiHidden/></w:style>\
        <w:style w:type="paragraph" w:styleId="Header"><w:name w:val="header"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:line="240" w:lineRule="auto"/><w:jc w:val="right"/></w:pPr></w:style>\
        <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:jc w:val="center"/></w:pPr></w:style>\
        <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:outlineLvl w:val="0"/></w:pPr></w:style>\
        <w:style w:type="paragraph" w:styleId="Bibliography"><w:name w:val="Bibliography"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="720" w:hanging="720"/></w:pPr></w:style>\
        <w:style w:type="paragraph" w:styleId="FootnoteText"><w:name w:val="footnote text"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:line="240" w:lineRule="auto"/><w:ind w:firstLine="720"/></w:pPr><w:rPr><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:style>\
        <w:style w:type="character" w:styleId="FootnoteReference"><w:name w:val="footnote reference"/><w:rPr><w:vertAlign w:val="superscript"/></w:rPr></w:style>\
        </w:styles>
        """

    static func settingsXML(hasNotes: Bool) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:settings xmlns:w="\(wNS)">\
        <w:defaultTabStop w:val="720"/>\
        <w:characterSpacingControl w:val="doNotCompress"/>\
        \(hasNotes ? #"<w:footnotePr><w:footnote w:id="-1"/><w:footnote w:id="0"/></w:footnotePr>"# : "")\
        <w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>\
        </w:settings>
        """
    }

    static func headerXML(_ header: RunningHeader) -> String {
        let prefix: String
        switch header {
        case .lastNameAndPage(let name): prefix = run(TextRun(name + " "))
        case .pageNumber: prefix = ""
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:hdr xmlns:w="\(wNS)" xmlns:r="\(rNS)"><w:p><w:pPr><w:pStyle w:val="Header"/><w:jc w:val="right"/></w:pPr>\
        \(prefix)\
        <w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>\
        <w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r>\
        </w:p></w:hdr>
        """
    }

    static let emptyHeaderXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:hdr xmlns:w="\(wNS)" xmlns:r="\(rNS)"><w:p><w:pPr><w:pStyle w:val="Header"/></w:pPr></w:p></w:hdr>
        """

    static func footnotesXML(_ essay: FormattedEssay) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:footnotes xmlns:w="\(wNS)" xmlns:r="\(rNS)">\
        <w:footnote w:type="separator" w:id="-1"><w:p><w:pPr><w:spacing w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:separator/></w:r></w:p></w:footnote>\
        <w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:pPr><w:spacing w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>
        """
        for id in essay.footnotes.keys.sorted() {
            let runs = essay.footnotes[id] ?? []
            xml += "<w:footnote w:id=\"\(id)\"><w:p><w:pPr><w:pStyle w:val=\"FootnoteText\"/></w:pPr>"
            xml += "<w:r><w:rPr><w:rStyle w:val=\"FootnoteReference\"/></w:rPr><w:footnoteRef/></w:r><w:r><w:t xml:space=\"preserve\"> </w:t></w:r>"
            xml += runs.map(run).joined()
            xml += "</w:p></w:footnote>"
        }
        xml += "</w:footnotes>"
        return xml
    }

    // MARK: Document body

    static func documentXML(_ essay: FormattedEssay) -> String {
        var body = ""
        for p in essay.paragraphs { body += paragraph(p) }
        let firstHeader = essay.headerOnFirstPage ? "" : #"<w:headerReference w:type="first" r:id="rId4"/>"#
        let titlePg = essay.headerOnFirstPage ? "" : "<w:titlePg/>"
        body += """
        <w:sectPr><w:headerReference w:type="default" r:id="rId3"/>\(firstHeader)\
        <w:pgSz w:w="12240" w:h="15840"/>\
        <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>\
        \(titlePg)</w:sectPr>
        """
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="\(wNS)" xmlns:r="\(rNS)"><w:body>\(body)</w:body></w:document>
        """
    }

    static func twips(_ inches: Double) -> Int { Int((inches * 1440).rounded()) }

    static func paragraph(_ p: LayoutParagraph) -> String {
        var ppr = ""
        switch p.role {
        case .title: ppr += #"<w:pStyle w:val="Title"/>"#
        case .sectionHeading: ppr += #"<w:pStyle w:val="Heading1"/>"#
        case .reference: ppr += #"<w:pStyle w:val="Bibliography"/>"#
        default: break
        }
        if p.role == .referencesHeading || p.role == .sectionHeading { ppr += "<w:keepNext/>" }
        if p.pageBreakBefore { ppr += "<w:pageBreakBefore/>" }
        let line = Int((p.lineSpacing * 240).rounded())
        let after = Int((p.spaceAfter * 20).rounded())
        ppr += #"<w:spacing w:before="0" w:after="\#(after)" w:line="\#(line)" w:lineRule="auto"/>"#
        if p.hangingIndent > 0 {
            ppr += #"<w:ind w:left="\#(twips(p.leftIndent))" w:hanging="\#(twips(p.hangingIndent))"/>"#
        } else {
            ppr += #"<w:ind w:left="\#(twips(p.leftIndent))" w:firstLine="\#(twips(p.firstLineIndent))"/>"#
        }
        switch p.alignment {
        case .left: ppr += #"<w:jc w:val="left"/>"#
        case .center: ppr += #"<w:jc w:val="center"/>"#
        case .right: ppr += #"<w:jc w:val="right"/>"#
        }
        return "<w:p><w:pPr>\(ppr)</w:pPr>\(p.runs.map(run).joined())</w:p>"
    }

    static func run(_ r: TextRun) -> String {
        if let id = r.footnoteID {
            return #"<w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:footnoteReference w:id="\#(id)"/></w:r>"#
        }
        var rpr = ""
        if r.bold { rpr += "<w:b/><w:bCs/>" }
        if r.italic { rpr += "<w:i/><w:iCs/>" }
        if r.underline { rpr += #"<w:u w:val="single"/>"# }
        let props = rpr.isEmpty ? "" : "<w:rPr>\(rpr)</w:rPr>"
        // Tabs and line breaks become their own elements.
        var content = ""
        var buffer = ""
        func flush() {
            if !buffer.isEmpty { content += #"<w:t xml:space="preserve">\#(escape(buffer))</w:t>"#; buffer = "" }
        }
        for ch in r.text {
            if ch == "\t" { flush(); content += "<w:tab/>" }
            else if ch == "\n" { flush(); content += "<w:br/>" }
            else { buffer.append(ch) }
        }
        flush()
        return "<w:r>\(props)\(content)</w:r>"
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                // Drop control characters XML 1.0 forbids.
                if scalar.value < 0x20, scalar != "\t", scalar != "\n", scalar != "\r" { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
