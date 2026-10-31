//
//  GoogleDocsFetcher.swift
//  Title Capitalizr
//
//  Downloads a Google Doc as .docx through its public export URL. This only works
//  for documents shared as "Anyone with the link"; private documents redirect to a
//  Google sign-in page, which is reported with instructions to export the .docx by
//  hand. No Google account, OAuth or API key is involved.
//

import Foundation

enum GoogleDocsError: LocalizedError, Equatable {
    case notAGoogleDocsLink
    case notShared
    case notFound
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notAGoogleDocsLink:
            return "That doesn't look like a Google Docs link. It should look like docs.google.com/document/d/..."
        case .notShared:
            return "This Google Doc isn't shared publicly. In Google Docs choose Share > General access > Anyone with the link, or choose File > Download > Microsoft Word (.docx) and drop the file here."
        case .notFound:
            return "Google Docs couldn't open this document. Check the link, and make sure it's shared as \"Anyone with the link\". Otherwise choose File > Download > Microsoft Word (.docx) in Google Docs and drop the file here."
        case .network(let message):
            return "Couldn't download the Google Doc: \(message)"
        }
    }
}

enum GoogleDocsLink {
    enum Target: Equatable {
        case document(id: String)
        /// A .docx uploaded to Google Drive (not converted to a Google Doc).
        case driveFile(id: String)
    }

    static func parse(_ text: String) -> Target? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: s), let host = url.host?.lowercased() else { return nil }
        let parts = url.pathComponents
        func id(after marker: String) -> String? {
            guard let i = parts.firstIndex(of: marker), i + 1 < parts.count else { return nil }
            let candidate = parts[i + 1]
            return isValidID(candidate) ? candidate : nil
        }
        if host == "docs.google.com", parts.contains("document"), let id = id(after: "d") {
            return .document(id: id)
        }
        if host == "drive.google.com" {
            if let id = id(after: "d") { return .driveFile(id: id) }
            if let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value, isValidID(q) {
                return .driveFile(id: q)
            }
        }
        return nil
    }

    static func isValidID(_ id: String) -> Bool {
        id.count >= 10 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } && id.allSatisfy(\.isASCII)
    }

    static func exportURL(for target: Target) -> URL {
        switch target {
        case .document(let id):
            return URL(string: "https://docs.google.com/document/d/\(id)/export?format=docx")!
        case .driveFile(let id):
            return URL(string: "https://drive.google.com/uc?export=download&id=\(id)")!
        }
    }

    /// Decides whether a download really is a .docx, or a sign-in / error page.
    static func classify(status: Int, finalURL: URL?, data: Data) -> Result<Data, GoogleDocsError> {
        if status == 404 { return .failure(.notFound) }
        if status == 401 || status == 403 { return .failure(.notShared) }
        if let host = finalURL?.host?.lowercased(), host.contains("accounts.google.com") { return .failure(.notShared) }
        guard (200..<300).contains(status) else { return .failure(.network("HTTP \(status)")) }
        guard data.starts(with: [0x50, 0x4B, 0x03, 0x04]) else { return .failure(.notShared) }
        return .success(data)
    }
}

struct GoogleDocsFetcher {
    var session: URLSession = .shared

    func fetch(_ link: String) async throws -> SourceDocument {
        guard let target = GoogleDocsLink.parse(link) else { throw GoogleDocsError.notAGoogleDocsLink }
        var request = URLRequest(url: GoogleDocsLink.exportURL(for: target))
        request.timeoutInterval = 30
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GoogleDocsError.network(error.localizedDescription)
        }
        let http = response as? HTTPURLResponse
        switch GoogleDocsLink.classify(status: http?.statusCode ?? 200, finalURL: response.url, data: data) {
        case .failure(let e):
            throw e
        case .success(let docx):
            var name = "Google Doc"
            if let disposition = http?.value(forHTTPHeaderField: "Content-Disposition"),
               let range = disposition.range(of: "filename=\"") {
                let rest = disposition[range.upperBound...]
                if let end = rest.firstIndex(of: "\"") {
                    name = (String(rest[..<end]) as NSString).deletingPathExtension
                }
            }
            return try DocxReader.read(data: docx, fileName: name, kind: .googleDocs)
        }
    }
}
