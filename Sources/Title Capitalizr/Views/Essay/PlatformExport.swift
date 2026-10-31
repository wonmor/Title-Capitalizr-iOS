//
//  PlatformExport.swift
//  Title Capitalizr
//
//  The live PDF preview and the platform-specific ways to hand a file over:
//  share sheet, Save to Files and "Open in Google Docs" on iOS; save panel,
//  Finder drag and a Google Drive hand-off on macOS.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - PDF preview

#if os(macOS)
struct PDFPreview: NSViewRepresentable {
    let data: Data?

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        configure(v)
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        if context.coordinator.lastData != data {
            context.coordinator.lastData = data
            v.document = data.flatMap(PDFDocument.init(data:))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastData: Data? }

    private func configure(_ v: PDFView) {
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displaysPageBreaks = true
        v.backgroundColor = NSColor(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF2 / 255, alpha: 1)
    }
}
#else
struct PDFPreview: UIViewRepresentable {
    let data: Data?

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displaysPageBreaks = true
        v.pageShadowsEnabled = false
        v.backgroundColor = UIColor(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF2 / 255, alpha: 1)
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if context.coordinator.lastData != data {
            context.coordinator.lastData = data
            v.document = data.flatMap(PDFDocument.init(data:))
            v.autoScales = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastData: Data? }
}
#endif

/// A static image of one page, used for the free first-page preview.
struct PDFPageImage: View {
    let data: Data?
    var page = 0

    var body: some View {
        if let data, let doc = PDFDocument(data: data), let p = doc.page(at: page) {
            let size = p.bounds(for: .mediaBox).size
            #if os(macOS)
            Image(nsImage: p.thumbnail(of: CGSize(width: size.width * 2, height: size.height * 2), for: .mediaBox))
                .resizable().aspectRatio(size, contentMode: .fit)
            #else
            Image(uiImage: p.thumbnail(of: CGSize(width: size.width * 2, height: size.height * 2), for: .mediaBox))
                .resizable().aspectRatio(size, contentMode: .fit)
            #endif
        } else {
            Bauhaus.Palette.groundSoft.aspectRatio(8.5 / 11, contentMode: .fit)
        }
    }
}

// MARK: - Hand-off

enum PlatformExport {
    static func contentType(_ format: ExportFormat) -> UTType {
        switch format {
        case .docx: return UTType(filenameExtension: "docx") ?? .data
        case .pdf: return .pdf
        case .rtf: return .rtf
        case .txt: return .plainText
        }
    }

    #if os(iOS)
    static var topViewController: UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }

    static func share(_ urls: [URL]) {
        guard let vc = topViewController else { return }
        let sheet = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = vc.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.maxY - 80, width: 1, height: 1)
        vc.present(sheet, animated: true)
    }

    static func saveToFiles(_ urls: [URL]) {
        guard let vc = topViewController else { return }
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        vc.present(picker, animated: true)
    }

    static var googleDocsInstalled: Bool {
        guard let url = URL(string: "googledocs://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
    #endif

    #if os(macOS)
    /// Shows a save panel and writes the data. Returns the saved URL.
    @MainActor
    @discardableResult
    static func save(_ data: Data, suggestedName: String, format: ExportFormat) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [contentType(format)]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    /// Saves the .docx, reveals it in Finder and opens Google Drive, where it opens in Google Docs.
    @MainActor
    static func handOffToGoogleDocs(_ data: Data, suggestedName: String) {
        guard let url = save(data, suggestedName: suggestedName, format: .docx) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        if let drive = URL(string: "https://drive.google.com/drive/my-drive") { NSWorkspace.shared.open(drive) }
    }
    #endif
}
