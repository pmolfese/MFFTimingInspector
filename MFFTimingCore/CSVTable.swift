//
//  CSVTable.swift
//  MFFTimingCore
//
//  Developed by P. Molfese, Center for Multimodal Neuroimaging (CMN),
//  National Institute of Mental Health (NIMH), National Institutes of Health (NIH).
//  https://cmn.nimh.nih.gov
//
//  This software is a "work of the United States Government" prepared by a federal
//  employee as part of official duties. As such, it is not subject to copyright
//  protection within the United States (17 U.S.C. § 105). International copyrights
//  may apply.
//
//  A minimal RFC4180-ish CSV reader: no external dependencies, handles quoted
//  fields (with embedded commas/newlines/escaped quotes) since a send_error
//  message could contain any of those, even though today's fixtures don't.
//

import Foundation

struct CSVTable: Sendable {
    let headers: [String]
    /// Each row keyed by header name, preserving column order via `headers`.
    let rows: [[String: String]]

    enum CSVError: LocalizedError, Sendable {
        case unreadable(URL, String)
        case empty(URL)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url, let message):
                return "Could not read \(url.lastPathComponent): \(message)"
            case .empty(let url):
                return "\(url.lastPathComponent) has no header row."
            }
        }
    }

    static func parse(contentsOf url: URL) throws -> CSVTable {
        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CSVError.unreadable(url, error.localizedDescription)
        }
        return try parse(contents, sourceURL: url)
    }

    static func parse(_ contents: String, sourceURL: URL) throws -> CSVTable {
        let records = splitRecords(contents)
        guard let headerRecord = records.first else {
            throw CSVError.empty(sourceURL)
        }
        let headers = headerRecord
        let rows: [[String: String]] = records.dropFirst().compactMap { fields in
            guard !(fields.count == 1 && fields[0].isEmpty) else { return nil }
            var row: [String: String] = [:]
            row.reserveCapacity(headers.count)
            for (offset, header) in headers.enumerated() {
                row[header] = offset < fields.count ? fields[offset] : ""
            }
            return row
        }
        return CSVTable(headers: headers, rows: rows)
    }

    /// Splits raw CSV text into records of fields, honoring RFC4180 quoting.
    ///
    /// Iterates `unicodeScalars`, not `Character`s: a CRLF line ending is a
    /// single Swift `Character` (extended grapheme cluster), so comparing
    /// grapheme-clustered characters against bare `"\r"`/`"\n"` would never
    /// match inside a CRLF sequence and silently swallow every line break in
    /// a Windows-authored file (as these fixtures are).
    private static func splitRecords(_ contents: String) -> [[String]] {
        var records: [[String]] = []
        var fields: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        let scalars = Array(contents.unicodeScalars)
        var index = 0

        func endField() {
            fields.append(String(field))
            field = String.UnicodeScalarView()
        }
        func endRecord() {
            endField()
            records.append(fields)
            fields = []
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(scalar)
                }
            } else {
                switch scalar {
                case "\"":
                    inQuotes = true
                case ",":
                    endField()
                case "\r":
                    break
                case "\n":
                    endRecord()
                default:
                    field.append(scalar)
                }
            }
            index += 1
        }
        if !field.isEmpty || !fields.isEmpty {
            endRecord()
        }
        return records
    }
}
