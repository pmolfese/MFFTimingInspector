//
//  SourceClassifier.swift
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
//  Identifies what a dropped/opened file or folder is, so drag-and-drop can
//  sort a handful of mixed files into the right slot without asking. An MFF
//  is a folder; the diagnostics log is JSON-lines; the two CSVs share an
//  extension but not a schema, so those are told apart by sniffing the
//  header row rather than the filename.
//

import Foundation

enum SourceKind: Sendable, Equatable {
    case mff
    case diagnosticsJSONL
    case trialCSV
    case frameIntervalCSV
    case unknown
}

enum SourceClassifier {
    static func classify(_ url: URL) -> SourceKind {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .unknown
        }

        if isDirectory.boolValue {
            return classifyDirectory(url)
        }

        switch url.pathExtension.lowercased() {
        case "jsonl":
            return .diagnosticsJSONL
        case "csv":
            return classifyCSV(url)
        default:
            return .unknown
        }
    }

    private static func classifyDirectory(_ url: URL) -> SourceKind {
        if url.pathExtension.lowercased() == "mff" {
            return .mff
        }
        // A recording folder without the conventional ".mff" extension is
        // still recognizable by its contents.
        let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        let hasEventsXML = contents.contains {
            $0.lastPathComponent.hasPrefix("Events") && $0.pathExtension.lowercased() == "xml"
        }
        return hasEventsXML ? .mff : .unknown
    }

    private static func classifyCSV(_ url: URL) -> SourceKind {
        guard let header = firstLine(of: url)?.lowercased() else { return .unknown }
        if header.contains("frame_index") && header.contains("interval_ms") {
            return .frameIntervalCSV
        }
        if header.contains("record_type") && header.contains("package_time") {
            return .trialCSV
        }
        return .unknown
    }

    /// Reads only a bounded prefix -- header rows are short, and these CSVs
    /// can run to hundreds of thousands of lines.
    private static func firstLine(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8192), let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(String.init)
    }
}
