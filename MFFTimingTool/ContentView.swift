//
//  ContentView.swift
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
import UniformTypeIdentifiers

private extension UTType {
    static let jsonLines = UTType(filenameExtension: "jsonl", conformingTo: .json) ?? .json
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updateChecker: UpdateChecker
    @Environment(\.openURL) private var openURL
    @State private var isDropTargeted = false

    var body: some View {
        // A single sidebar + content NavigationSplitView, always -- the tab
        // picker is the first thing in "content", so it visually governs
        // everything below it, on every tab. Events needs its own
        // table/inspector split; that split is an HSplitView living inside
        // the tab body, not a third NavigationSplitView column, so the tab
        // bar stays the whole region's parent instead of only spanning the
        // table's half while the inspector sits beside it unrelated (which
        // is what a separate "detail" column looked like).
        NavigationSplitView {
            sidebar
        } detail: {
            contentColumn
        }
        .fileImporter(isPresented: $appState.isImportingMFF, allowedContentTypes: [.folder]) { result in
            handle(result) { appState.openMFF(url: $0) }
        }
        .fileImporter(isPresented: $appState.isImportingTrialCSV, allowedContentTypes: [.commaSeparatedText]) { result in
            handle(result) { appState.importTrialCSV(url: $0) }
        }
        .fileImporter(isPresented: $appState.isImportingDiagnostics, allowedContentTypes: [.jsonLines]) { result in
            handle(result) { appState.importDiagnostics(url: $0) }
        }
        .fileImporter(isPresented: $appState.isImportingFrameIntervals, allowedContentTypes: [.commaSeparatedText]) { result in
            handle(result) { appState.importFrameIntervals(url: $0) }
        }
        .fileImporter(isPresented: $appState.isOpeningProject, allowedContentTypes: [.json]) { result in
            handle(result) { appState.openProject(url: $0) }
        }
        .fileExporter(
            isPresented: $appState.isExportingProject,
            document: appState.projectExportDocument,
            contentType: .json,
            defaultFilename: appState.suggestedProjectFilename
        ) { result in
            appState.finishExport(result)
        }
        .fileExporter(
            isPresented: $appState.isExportingSupportBundle,
            document: appState.supportBundleExportDocument,
            contentType: .json,
            defaultFilename: appState.suggestedSupportBundleFilename
        ) { result in
            appState.finishSupportBundleExport(result)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadDroppedURLs(from: providers)
            return true
        }
        .alert(item: $updateChecker.result) { result in
            updateAlert(for: result.outcome)
        }
    }

    private func updateAlert(for outcome: UpdateCheckResult.Outcome) -> Alert {
        switch outcome {
        case .updateAvailable(let version, let releaseName, let url):
            let title = releaseName.flatMap { $0.isEmpty ? nil : $0 } ?? version
            return Alert(
                title: Text("Update Available"),
                message: Text("\(title) is available on GitHub."),
                primaryButton: .default(Text("View Release")) { openURL(url) },
                secondaryButton: .cancel(Text("Later"))
            )
        case .upToDate(let currentVersion):
            return Alert(
                title: Text("MFF Timing Inspector Is Up to Date"),
                message: Text("You’re running version \(currentVersion)."),
                dismissButton: .default(Text("OK"))
            )
        case .noPublishedRelease:
            return Alert(
                title: Text("No Published Releases"),
                message: Text("This GitHub repository does not have a published release yet."),
                primaryButton: .default(Text("View Releases")) { openURL(UpdateChecker.releasesPage) },
                secondaryButton: .cancel(Text("OK"))
            )
        case .failed(let message):
            return Alert(
                title: Text("Couldn’t Check for Updates"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var sidebar: some View {
        SourceListView()
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
    }

    private var contentColumn: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $appState.contentTab) {
                ForEach(ContentTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch appState.contentTab {
            case .events:
                HSplitView {
                    EventTableView()
                        .frame(minWidth: 380, idealWidth: 520)
                    InspectorView()
                        .frame(minWidth: 380, idealWidth: 520)
                }
            case .offsetAnalysis:
                OffsetAnalysisView()
            case .drift:
                DriftView()
            }
        }
    }

    private func handle(_ result: Result<URL, Error>, action: (URL) -> Void) {
        switch result {
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            action(url)
        case .failure(let error):
            appState.errorMessage = error.localizedDescription
        }
    }

    /// Resolves every dropped item to a file URL first (NSItemProvider
    /// loading is async and can complete in any order), then hands the whole
    /// batch to AppState at once so multiple files dropped together are
    /// sorted into their slots together.
    private func loadDroppedURLs(from providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var resolved: [URL] = []
        let lock = NSLock()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    resolved.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard !resolved.isEmpty else { return }
            appState.importDroppedURLs(resolved)
        }
    }
}
