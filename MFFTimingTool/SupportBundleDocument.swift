//
//  SupportBundleDocument.swift
//  MFFTimingToolApp
//
//  A compact, shareable diagnostic snapshot. It contains the normal saved
//  project plus only the source values needed to reproduce correlation and
//  import problems; raw EEG samples and arbitrary source columns are omitted.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct SupportBundleSnapshot: Codable, Sendable {
    static let currentFormatVersion = 2

    let v: Int
    let created: Double
    let app: String
    let build: String
    let os: String
    let p: TimingProjectSnapshot
    let src: Sources
    let cfg: Configuration
    let e: [Event]
    let tr: [Trial]
    let dg: Diagnostics
    let fr: FrameSummary?
    let warnings: [String]

    struct Sources: Codable, Sendable {
        let mff: String?
        let trials: String?
        let diagnostics: String?
        let frames: String?
    }

    struct Configuration: Codable, Sendable {
        let primary: [String]
        let reference: [String]
        let pairMode: String
        let jitterCenter: String
        let showFrames: Bool
        let timeAxis: String
    }

    struct Event: Codable, Sendable {
        let t: Double
        let r: Int?
        let c: String
        let s: String
    }

    struct Trial: Codable, Sendable {
        let p: Double?
        let l: Double?
        let c: String?
        let r: String
        let y: String?
        let result: String?
        let error: String?
    }

    struct Diagnostic: Codable, Sendable {
        let r: String
        let t: Double?
        /// A deliberately small whitelist of fields used by the drift chart
        /// and transition Detail column. Optional for version-1 bundles.
        let f: [String: JSONValue]?
        let message: String?
    }

    struct Diagnostics: Codable, Sendable {
        let records: [Diagnostic]
        let parseErrors: [String]
    }

    struct FrameSummary: Codable, Sendable {
        let count: Int
        let long: Int
        let missed: Int
    }
}

struct SupportBundleDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let bundle: SupportBundleSnapshot

    init(bundle: SupportBundleSnapshot) {
        self.bundle = bundle
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        bundle = try Self.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Self.encode(bundle))
    }

    static func load(from url: URL) throws -> SupportBundleSnapshot {
        try decode(Data(contentsOf: url))
    }

    static func save(_ bundle: SupportBundleSnapshot, to url: URL) throws {
        try encode(bundle).write(to: url, options: .atomic)
    }

    private static func encode(_ bundle: SupportBundleSnapshot) throws -> Data {
        try JSONEncoder().encode(bundle)
    }

    private static func decode(_ data: Data) throws -> SupportBundleSnapshot {
        let bundle = try JSONDecoder().decode(SupportBundleSnapshot.self, from: data)
        guard bundle.v <= SupportBundleSnapshot.currentFormatVersion else {
            throw TimingProjectError.unsupportedSupportBundleVersion(bundle.v)
        }
        return bundle
    }
}
