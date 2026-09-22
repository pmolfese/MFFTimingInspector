//
//  SourceInspectorView.swift
//  MFFTimingToolApp
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
//  A standalone window for "let me actually look at this raw file": every
//  row of the imported diagnostics/trial/frame-interval source, with every
//  field of the selected row spelled out -- for checking a source against
//  the original file rather than trusting the derived Events/Offset/Drift
//  views. Opened from a loaded row in the sidebar.
//

import SwiftUI

enum SourceWindowKind: String, Codable, Hashable {
    case diagnostics
    case trials
    case frames

    var title: String {
        switch self {
        case .diagnostics: return "Diagnostics (.jsonl)"
        case .trials: return "Trial log (.csv)"
        case .frames: return "Frame intervals (.csv)"
        }
    }
}

private struct RawRow: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
}

struct SourceInspectorView: View {
    @EnvironmentObject private var appState: AppState
    let kind: SourceWindowKind

    @State private var rows: [RawRow] = []
    /// id -> position in the underlying array. Built once alongside `rows`
    /// so selecting a row is an O(1) lookup, not a linear `.first(where:)`
    /// scan -- with 200k+ frame-interval rows that scan would itself be a
    /// per-click freeze, the same class of bug as the event correlator's.
    @State private var lookup: [Int: Int] = [:]
    @State private var selection: Int?

    var body: some View {
        NavigationSplitView {
            List(rows, selection: $selection) { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                    Text(row.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .tag(row.id)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            detailPane
        }
        .navigationTitle(rows.isEmpty ? kind.title : "\(kind.title) — \(rows.count) records")
        .frame(minWidth: 640, minHeight: 420)
        .task { loadRows() }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selection, let fields = fields(for: selection) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(fields, id: \.0) { key, value in
                        HStack(alignment: .top, spacing: 6) {
                            Text(key)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 160, alignment: .leading)
                            Text(value)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(12)
            }
        } else {
            ContentUnavailableView("Select a record", systemImage: "list.bullet.rectangle")
        }
    }

    private func loadRows() {
        var newLookup: [Int: Int] = [:]
        switch kind {
        case .diagnostics:
            newLookup.reserveCapacity(appState.diagnostics.count)
            rows = appState.diagnostics.enumerated().map { position, record in
                newLookup[record.index] = position
                let time = record.date.map { Formatting.clockTime.string(from: $0) } ?? "—"
                return RawRow(id: record.index, title: record.recordType, subtitle: time)
            }
        case .trials:
            newLookup.reserveCapacity(appState.trials.count)
            rows = appState.trials.enumerated().map { position, trial in
                newLookup[trial.index] = position
                let title = [trial.recordType, trial.eventCode].compactMap { $0 }.joined(separator: " · ")
                let subtitle = trial.trialIndex.map { "trial \($0)" } ?? ""
                return RawRow(id: trial.index, title: title, subtitle: subtitle)
            }
        case .frames:
            newLookup.reserveCapacity(appState.frames.count)
            rows = appState.frames.enumerated().map { position, frame in
                newLookup[frame.frameIndex] = position
                return RawRow(id: frame.frameIndex, title: "#\(frame.frameIndex)", subtitle: String(format: "%.2f ms", frame.intervalMs))
            }
        }
        lookup = newLookup
    }

    private func fields(for id: Int) -> [(String, String)]? {
        guard let position = lookup[id] else { return nil }
        switch kind {
        case .diagnostics:
            let record = appState.diagnostics[position]
            return record.fields.keys.sorted().map { ($0, record.fields[$0]!.displayString) }
        case .trials:
            let trial = appState.trials[position]
            return trial.rawFields.keys.sorted().map { ($0, trial.rawFields[$0] ?? "") }
        case .frames:
            let frame = appState.frames[position]
            return [
                ("frameIndex", "\(frame.frameIndex)"),
                ("elapsedSeconds", Formatting.seconds(frame.elapsedSeconds)),
                ("psychopyTimeSeconds", frame.psychopyTimeSeconds.map { Formatting.seconds($0) } ?? "—"),
                ("packageTimeSeconds", frame.packageTimeSeconds.map { Formatting.seconds($0) } ?? "—"),
                ("intervalMs", String(format: "%.3f", frame.intervalMs)),
                ("expectedFrames", "\(frame.expectedFrames)"),
                ("estimatedMissedFrames", "\(frame.estimatedMissedFrames)"),
                ("isLongFrame", frame.isLongFrame ? "true" : "false"),
            ]
        }
    }
}
