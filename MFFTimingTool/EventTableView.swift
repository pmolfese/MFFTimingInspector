//
//  EventTableView.swift
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

import SwiftUI

struct EventTableView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.mffEvents.isEmpty {
            ContentUnavailableView(
                "No MFF loaded",
                systemImage: "doc.badge.plus",
                description: Text("Open an .mff recording from the sidebar to see its events.")
            )
        } else {
            VStack(spacing: 0) {
                filterBar
                Divider()
                Table(appState.filteredMatchedEvents, selection: $appState.selection) {
                    TableColumn("#") { match in
                        Text("\(match.mffEvent.index)")
                    }
                    .width(36)

                    TableColumn("Code") { match in
                        Text(match.mffEvent.code)
                            .fontDesign(.monospaced)
                    }
                    .width(60)

                    TableColumn("MFF time") { match in
                        Text(Formatting.clockTime.string(from: match.mffEvent.beginDate))
                            .fontDesign(.monospaced)
                    }
                    .width(110)

                    TableColumn("Trial #") { match in
                        Text(match.trial?.trialIndex.map(String.init) ?? "—")
                    }
                    .width(60)

                    TableColumn("Δ send→MFF") { match in
                        deltaText(match.deltaSeconds)
                    }
                    .width(100)

                    TableColumn("Send result") { match in
                        sendResultBadge(for: match.trial)
                    }
                    .width(110)
                }
            }
        }
    }

    private var codeCounts: [String: Int] {
        Dictionary(grouping: appState.mffEvents, by: \.code).mapValues(\.count)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            Button("All") { appState.eventCodeFilter = Set(appState.uniqueEventCodes) }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            Button("None") { appState.eventCodeFilter = [] }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

            Divider().frame(height: 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(appState.uniqueEventCodes, id: \.self) { code in
                        codeChip(code)
                    }
                }
            }

            Spacer()

            Text("\(appState.filteredMatchedEvents.count) / \(appState.mffEvents.count) shown")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func codeChip(_ code: String) -> some View {
        let isOn = appState.eventCodeFilter.contains(code)
        let count = codeCounts[code] ?? 0
        return Button {
            if isOn {
                appState.eventCodeFilter.remove(code)
            } else {
                appState.eventCodeFilter.insert(code)
            }
        } label: {
            Text("\(code) (\(count))")
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isOn ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12))
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func deltaText(_ delta: Double?) -> some View {
        if let delta {
            Text(Formatting.milliseconds(fromSeconds: delta))
                .foregroundStyle(abs(delta) > 0.05 ? Color.orange : .primary)
        } else {
            Text("no match")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func sendResultBadge(for trial: TrialRecord?) -> some View {
        if let trial {
            if trial.isSendFailure {
                Label(trial.sendError ?? "failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else {
                Text(trial.sendResult ?? "—")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }
}
