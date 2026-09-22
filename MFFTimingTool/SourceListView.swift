//
//  SourceListView.swift
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

struct SourceListView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List {
            Section("Sources") {
                sourceRow(
                    icon: "doc.text",
                    title: appState.mffURL?.lastPathComponent ?? "Open MFF…",
                    subtitle: appState.mffEvents.isEmpty ? nil : "\(appState.mffEvents.count) events",
                    isLoaded: appState.mffURL != nil,
                    onImport: { appState.isImportingMFF = true }
                )

                sourceRow(
                    icon: "curlybraces",
                    title: appState.diagnosticsSourceName ?? "Import diagnostics (.jsonl)…",
                    subtitle: appState.diagnostics.isEmpty ? nil : "\(appState.diagnostics.count) records",
                    isLoaded: appState.diagnosticsSourceName != nil,
                    onImport: { appState.isImportingDiagnostics = true },
                    onInspect: { openWindow(id: "sourceInspector", value: SourceWindowKind.diagnostics) }
                )

                sourceRow(
                    icon: "tablecells",
                    title: appState.trialSourceName ?? "Import trial log (.csv)…",
                    subtitle: appState.trials.isEmpty ? nil : "\(appState.trials.count) rows",
                    isLoaded: appState.trialSourceName != nil,
                    onImport: { appState.isImportingTrialCSV = true },
                    onInspect: { openWindow(id: "sourceInspector", value: SourceWindowKind.trials) }
                )

                sourceRow(
                    icon: "waveform.path",
                    title: appState.frameSourceName ?? "Import frame intervals (.csv)…",
                    subtitle: frameSubtitle,
                    isLoaded: appState.frameSourceName != nil,
                    onImport: { appState.isImportingFrameIntervals = true },
                    onInspect: { openWindow(id: "sourceInspector", value: SourceWindowKind.frames) }
                )

                Text("Or drag files/folders anywhere in this window")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let anchor = appState.anchorPackageTime {
                Section("Alignment") {
                    LabeledContent("Recording start", value: Formatting.seconds(anchor) + " s")
                        .font(.caption)
                }
            }

            if let errorMessage = appState.errorMessage {
                Section("Last error") {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var frameSubtitle: String? {
        guard let summary = appState.frameSummary else { return nil }
        return "\(summary.frameCount) frames, \(summary.longFrameCount) long"
    }

    /// When loaded and `onInspect` is given, the row opens the raw record
    /// browser instead of re-prompting for a file; a small trailing button
    /// still re-opens the file picker to replace the source.
    @ViewBuilder
    private func sourceRow(
        icon: String,
        title: String,
        subtitle: String?,
        isLoaded: Bool,
        onImport: @escaping () -> Void,
        onInspect: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Button(action: isLoaded ? (onInspect ?? onImport) : onImport) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(isLoaded ? Color.accentColor : .secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 12))
                            .foregroundStyle(isLoaded ? .primary : .secondary)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isLoaded && onInspect != nil ? "Open in a new window" : "Choose a file")

            if isLoaded, onInspect != nil {
                Button(action: onImport) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Replace with a different file")
            }
        }
    }
}
