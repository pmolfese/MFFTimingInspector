//
//  OffsetAnalysisView.swift
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
//  Generalizes the old CLI's --code/--din/--pair offset report: pick any set
//  of "primary" codes and any set of "reference" codes (typically DIN
//  channels) and get a paired-offset table plus summary stats and a jitter
//  distribution -- one event code against one DIN, several codes pooled
//  against one DIN, or several codes against several DINs at once.
//
//  Selection state (primary/reference codes, pair mode, jitter center) lives
//  on AppState rather than as @State here, so switching to the Events tab
//  and back doesn't lose it.
//

import SwiftUI
import Charts

struct OffsetAnalysisView: View {
    @EnvironmentObject private var appState: AppState

    private var uniqueCodes: [String] {
        Array(Set(appState.mffEvents.map(\.code))).sorted()
    }

    /// Codes seen only on DIN-like tracks (Events_DIN*.xml, Events_MR_Pulse.xml)
    /// -- powers the "DIN-like" quick-select rather than requiring every
    /// reference code to be picked by hand.
    private var dinLikeCodes: Set<String> {
        Set(
            appState.mffEvents
                .filter { MFFTrackClassifier.isDINLike(sourceFile: $0.sourceFile) }
                .map(\.code)
        )
    }

    private var summary: OffsetSummary? {
        if let restored = appState.restoredOffsetSummary { return restored }
        guard !appState.offsetPrimarySelection.isEmpty, !appState.offsetReferenceSelection.isEmpty else { return nil }
        return OffsetAnalysis.computeOffsets(
            events: appState.mffEvents,
            primaryCodes: appState.offsetPrimarySelection,
            referenceCodes: appState.offsetReferenceSelection,
            pairMode: appState.offsetPairMode
        )
    }

    var body: some View {
        if appState.mffEvents.isEmpty && summary == nil {
            ContentUnavailableView(
                "No MFF loaded",
                systemImage: "arrow.left.arrow.right",
                description: Text("Open or drop an .mff recording to compare event codes.")
            )
        } else {
            // Two columns spanning the full height, 2:1 -- not a full-width
            // controls row above a table+stats row, so the stats column
            // reads as a standing sidebar next to the selectors+table
            // (which stay aligned, sharing the left column) rather than a
            // narrow strip that only starts where the table happens to.
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        if !appState.mffEvents.isEmpty {
                            controls
                            Divider()
                        }
                        if let summary {
                            offsetOverTimeChart(summary)
                            Divider()
                            resultsTable(summary)
                        } else {
                            ContentUnavailableView(
                                "Pick codes to compare",
                                systemImage: "checklist",
                                description: Text("Select one or more primary codes and one or more reference codes.")
                            )
                        }
                    }
                    .frame(width: geometry.size.width * 2 / 3)

                    Divider()

                    ScrollView {
                        if let summary {
                            distributionPanel(summary)
                        }
                    }
                    .frame(width: geometry.size.width / 3, height: geometry.size.height, alignment: .top)
                }
            }
        }
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 16) {
            codeSelector(title: "Primary (e.g. stimulus)", selection: $appState.offsetPrimarySelection)
            codeSelector(title: "Reference (e.g. DIN)", selection: $appState.offsetReferenceSelection)

            VStack(alignment: .leading, spacing: 6) {
                Text("Pair mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Pair mode", selection: $appState.offsetPairMode) {
                    Text("Nearest").tag(PairMode.nearest)
                    Text("Next").tag(PairMode.next)
                    Text("Previous").tag(PairMode.previous)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            // Without this, the whole row expands to fill the window: each
            // codeSelector's header has its own Spacer to push its buttons
            // right, and that inner Spacer's "infinite" width request
            // bubbles up through its VStack, so the selectors -- and
            // everything after them -- got spread across the full width
            // once this view stopped sharing the window with the Inspector.
            Spacer()
        }
        .padding(12)
    }

    @ViewBuilder
    private func codeSelector(title: String, selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !dinLikeCodes.isEmpty {
                    Button("DIN-like") { selection.wrappedValue = dinLikeCodes }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
                Button("All") { selection.wrappedValue = Set(uniqueCodes) }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                Button("None") { selection.wrappedValue = [] }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
            List(uniqueCodes, id: \.self, selection: selection) { code in
                Text(code).fontDesign(.monospaced).font(.system(size: 12))
            }
            .frame(width: 220, height: 140)
            .listStyle(.bordered)
        }
        .frame(width: 220)
    }

    // MARK: - Offset-over-time chart

    /// A scatter, not a connected line: with a few thousand pairs, a line
    /// would zigzag through every millisecond of jitter and read as noise.
    /// A point cloud shows both a slow session-wide drift and individual
    /// outliers more clearly. Dropped frames (if a frame-interval CSV is
    /// loaded) are marked on the same time axis, so an outlier can be
    /// checked against "did the display just stall right here" -- the
    /// mechanism this can actually explain, unlike the NTP-based drift model.
    /// Tapping a point selects the nearest pair, highlighted here and in the
    /// results table below.
    @ViewBuilder
    private func offsetOverTimeChart(_ summary: OffsetSummary) -> some View {
        let frameDrops = appState.frameDropEventsOnMFFClock
        let hasFrameIntervals = !appState.frameIntervalSeriesOnMFFClock.isEmpty
        let showIntervals = hasFrameIntervals && appState.offsetShowFrameIntervals

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Offset over time")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if !frameDrops.isEmpty {
                    Text("· \(frameDrops.count) dropped frames marked")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if appState.recordingStartDate != nil {
                    Picker("Time axis", selection: $appState.offsetTimeAxisMode) {
                        ForEach(TimeAxisMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                if hasFrameIntervals {
                    Toggle("Show frame intervals", isOn: $appState.offsetShowFrameIntervals)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                }
            }
            offsetChart(summary, frameDrops: frameDrops)
            if showIntervals {
                frameIntervalChart()
            }
        }
        .padding(12)
    }

    /// "Since start" is a display transform only -- elapsed = date minus the
    /// recording's own start, a fixed offset -- so the underlying marks stay
    /// in `Date` and only the axis label formatting changes. That's simpler
    /// and cheaper than replotting every mark in a different unit whenever
    /// the toggle flips.
    private func timeAxisLabel(for date: Date) -> String {
        switch appState.offsetTimeAxisMode {
        case .absolute:
            return Formatting.clockTime.string(from: date)
        case .elapsed:
            guard let start = appState.recordingStartDate else { return Formatting.clockTime.string(from: date) }
            return Formatting.elapsed(date.timeIntervalSince(start))
        }
    }

    private func offsetChart(_ summary: OffsetSummary, frameDrops: [FrameDropEvent]) -> some View {
        let timeDomain = offsetTimeDomain(summary)
        return Chart {
            ForEach(frameDrops) { drop in
                RuleMark(x: .value("Time", drop.time))
                    .foregroundStyle(Color.indigo.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 2]))
            }
            ForEach(summary.pairs) { pair in
                if let delta = pair.deltaMilliseconds {
                    let isSelected = pair.id == appState.offsetSelectedPairID
                    PointMark(
                        x: .value("Time", pair.primaryEvent.beginDate),
                        y: .value("Offset (ms)", delta)
                    )
                    .symbolSize(isSelected ? 60 : 8)
                    .foregroundStyle(isSelected ? Color.red : Color.accentColor.opacity(0.6))
                }
            }
        }
        .chartXScale(domain: timeDomain)
        .chartYAxisLabel("ms")
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                if let date = value.as(Date.self) {
                    AxisValueLabel(timeAxisLabel(for: date))
                }
            }
        }
        .frame(height: 150)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                selectNearestPair(at: value.location, proxy: proxy, geometry: geometry, in: summary)
                            }
                    )
            }
        }
    }

    /// Y is clipped to a few multiples of the median interval, not
    /// auto-scaled: a single dropped frame can be 20-30x the nominal ~6-7ms
    /// interval, and on a linear axis sized to fit that one point, the
    /// entire baseline -- and any real jitter in it -- collapses to a flat
    /// line one pixel off the bottom. A z-score wouldn't fix this; it's the
    /// same shape of skew in different units. Genuine outliers still show
    /// (clipped at the top edge), and are already marked exactly by the
    /// dashed lines above.
    ///
    /// X is deliberately its own auto-scaled domain, not forced to match the
    /// offset chart above: frame-interval logging often only runs for a
    /// short burst near the start of a recording (not continuously through
    /// it), so forcing both charts to share the offset chart's full-session
    /// width would squeeze that whole burst into a few pixels at the left
    /// edge -- which is what actually happened before this was reverted.
    private func frameIntervalChart() -> some View {
        let series = appState.frameIntervalSeriesOnMFFClock
        let yDomain = clippedIntervalDomain(series)
        let timeSpan = series.first.flatMap { first in series.last.map { last in last.time.timeIntervalSince(first.time) } }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Frame interval (ms) — different scale, downsampled, clipped to show baseline jitter\(timeSpanNote(timeSpan))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Chart(series) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Interval (ms)", point.intervalMs)
                )
                .foregroundStyle(Color.teal)
            }
            .chartYAxisLabel("ms")
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisTick()
                    if let date = value.as(Date.self) {
                        AxisValueLabel(timeAxisLabel(for: date))
                    }
                }
            }
            .frame(height: 90)
        }
    }

    /// Auxiliary marks must never determine this domain. In particular, a
    /// stale MFF calendar and experiment-local frame times can be days apart;
    /// allowing both to auto-scale collapses an hours-long offset series into
    /// a single pixel. A small pad keeps endpoint points fully visible.
    private func offsetTimeDomain(_ summary: OffsetSummary) -> ClosedRange<Date> {
        let dates = summary.pairs.compactMap { pair in
            pair.deltaMilliseconds == nil ? nil : pair.primaryEvent.beginDate
        }
        guard let first = dates.min(), let last = dates.max() else {
            let now = Date()
            return now.addingTimeInterval(-1)...now.addingTimeInterval(1)
        }
        let pad = max(1, last.timeIntervalSince(first) * 0.01)
        return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
    }

    /// Flags when the frame-interval log covers noticeably less time than
    /// the offset chart above it, since the two x-axes no longer share a
    /// width and that's easy to miss at a glance otherwise.
    private func timeSpanNote(_ span: TimeInterval?) -> String {
        guard let span, span < 120 else { return "" }
        return String(format: " (covers %.0fs, not the full session)", span)
    }

    private func clippedIntervalDomain(_ series: [FrameIntervalPoint]) -> ClosedRange<Double> {
        let values = series.map(\.intervalMs).sorted()
        guard !values.isEmpty else { return 0...1 }
        let median = values[values.count / 2]
        let cap = max(median * 4, median + 20)
        return 0...cap
    }

    private func selectNearestPair(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy, in summary: OffsetSummary) {
        let origin = geometry[proxy.plotAreaFrame].origin
        let locationInPlot = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        guard let date: Date = proxy.value(atX: locationInPlot.x) else { return }
        guard let nearest = SortedMatch.find(
            in: summary.pairs,
            nearestTo: date.timeIntervalSinceReferenceDate,
            mode: .nearest,
            key: { $0.primaryEvent.beginDate.timeIntervalSinceReferenceDate }
        ) else { return }
        appState.offsetSelectedPairID = nearest.id
    }

    /// A `List`, not a `Table`: `Table`'s selection can be set
    /// programmatically (the chart tap does that), but it doesn't scroll the
    /// selected row into view -- clicking a point off-screen in the table
    /// would highlight a row you can't see. `List` supports
    /// `ScrollViewReader.scrollTo`, which `Table` doesn't expose, so this
    /// trades native resizable columns (never used here) for a selection
    /// that's actually reachable.
    private func resultsTable(_ summary: OffsetSummary) -> some View {
        // Same checkbox as the chart above, not a second toggle: showing the
        // frame-interval trace and showing what it implies about each row
        // are the same question asked twice, and a second on/off control
        // for the same data would just be one more thing to keep in sync.
        let showFrameColumn = appState.offsetShowFrameIntervals && !appState.frameDropEvents.isEmpty
        let sortedDrops = appState.frameDropEvents.sorted { $0.time < $1.time }

        return VStack(spacing: 0) {
            HStack(spacing: 20) {
                statTile("matched", "\(summary.matchedCount)")
                if summary.unmatchedCount > 0 {
                    statTile("unmatched", "\(summary.unmatchedCount)", isWarning: true)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            resultsColumnHeader(showFrameColumn: showFrameColumn)
            Divider()
            ScrollViewReader { proxy in
                List(summary.pairs, selection: $appState.offsetSelectedPairID) { pair in
                    resultsRow(pair, nearestDrop: showFrameColumn ? nearestFrameDrop(to: pair.primaryEvent.beginDate, in: sortedDrops) : nil, showFrameColumn: showFrameColumn)
                }
                .listStyle(.plain)
                .onChange(of: appState.offsetSelectedPairID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    /// The dropped frame nearest `date` in time, plus the signed delta
    /// (positive: the drop happened after `date`). `drops` must already be
    /// sorted by time -- an O(log n) lookup via `SortedMatch`, since this
    /// runs once per visible row.
    private func nearestFrameDrop(to date: Date, in drops: [FrameDropEvent]) -> (FrameDropEvent, TimeInterval)? {
        guard let drop = SortedMatch.find(
            in: drops,
            nearestTo: date.timeIntervalSinceReferenceDate,
            mode: .nearest,
            key: { $0.time.timeIntervalSinceReferenceDate }
        ) else { return nil }
        return (drop, drop.time.timeIntervalSince(date))
    }

    private func resultsColumnHeader(showFrameColumn: Bool) -> some View {
        HStack(spacing: 0) {
            Text("Primary code").frame(width: 90, alignment: .leading)
            Text("Primary time").frame(width: 110, alignment: .leading)
            Text("Reference code").frame(width: 100, alignment: .leading)
            Text("Reference time").frame(width: 110, alignment: .leading)
            Text("Offset").frame(width: 90, alignment: .leading)
            if showFrameColumn {
                Text("Nearest drop").frame(width: 140, alignment: .leading)
            }
            Spacer()
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func resultsRow(_ pair: OffsetPair, nearestDrop: (FrameDropEvent, TimeInterval)?, showFrameColumn: Bool) -> some View {
        HStack(spacing: 0) {
            Text(pair.primaryEvent.code)
                .fontDesign(.monospaced)
                .frame(width: 90, alignment: .leading)
            Text(Formatting.clockTime.string(from: pair.primaryEvent.beginDate))
                .fontDesign(.monospaced)
                .frame(width: 110, alignment: .leading)
            Text(pair.referenceEvent?.code ?? "—")
                .fontDesign(.monospaced)
                .frame(width: 100, alignment: .leading)
            Text(pair.referenceEvent.map { Formatting.clockTime.string(from: $0.beginDate) } ?? "—")
                .fontDesign(.monospaced)
                .frame(width: 110, alignment: .leading)
            Group {
                if let delta = pair.deltaMilliseconds {
                    Text(String(format: "%.1f ms", delta))
                } else {
                    Text("no match").foregroundStyle(.red)
                }
            }
            .frame(width: 90, alignment: .leading)
            if showFrameColumn {
                nearestDropCell(nearestDrop)
                    .frame(width: 140, alignment: .leading)
            }
            Spacer()
        }
        .font(.system(size: 12))
    }

    /// Within 1s: this dropped frame plausibly explains something about this
    /// row, so it's called out. Beyond that, still shown (never hidden --
    /// the number is honest either way) but muted, since a frame drop
    /// minutes away isn't a meaningful correlation.
    @ViewBuilder
    private func nearestDropCell(_ nearestDrop: (FrameDropEvent, TimeInterval)?) -> some View {
        if let (drop, delta) = nearestDrop {
            let isClose = abs(delta) <= 1.0
            HStack(spacing: 4) {
                Text(Formatting.signedDuration(delta))
                    .fontDesign(.monospaced)
                if isClose {
                    Text("(\(drop.estimatedMissedFrames) missed)")
                        .font(.system(size: 10))
                }
            }
            .foregroundStyle(isClose ? Color.indigo : .secondary)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func statTile(_ label: String, _ value: String, isWarning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .medium))
                .foregroundStyle(isWarning ? .red : .primary)
        }
    }

    // MARK: - Distribution panel (stats, jitter buckets, histogram)

    @ViewBuilder
    private func distributionPanel(_ summary: OffsetSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            statsGrid(summary)

            if summary.matchedCount > 0 {
                Divider()
                jitterSection(summary)
                Divider()
                histogramSection(summary)
            }
        }
        .padding(12)
    }

    private func statsGrid(_ summary: OffsetSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Offset stats (ms)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            statRow("Mean", Formatting.milliseconds(fromMs: summary.meanMs, digits: 2))
            statRow("Median", Formatting.milliseconds(fromMs: summary.medianMs, digits: 2))
            statRow("Mode", summary.modeMs.map { "\($0) ms" } ?? "—")
            statRow("Minimum", Formatting.milliseconds(fromMs: summary.minMs, digits: 2))
            statRow("Maximum", Formatting.milliseconds(fromMs: summary.maxMs, digits: 2))
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, design: .monospaced))
        }
    }

    private func jitterSection(_ summary: OffsetSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Jitter from")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Jitter center", selection: $appState.offsetJitterCenter) {
                    ForEach(JitterCenter.allCases) { center in
                        Text(center.rawValue).tag(center)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            let buckets = summary.jitterBuckets(center: appState.offsetJitterCenter)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                ForEach(buckets) { bucket in
                    GridRow {
                        Text(bucket.isOverflow ? "+/-\(bucket.distanceMs)+" : "+/-\(bucket.distanceMs)")
                            .font(.system(size: 11, design: .monospaced))
                        Text("\(bucket.count)")
                            .font(.system(size: 11, design: .monospaced))
                            .gridColumnAlignment(.trailing)
                        Text(String(format: "%.1f%%", bucket.percent))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
        }
    }

    private func histogramSection(_ summary: OffsetSummary) -> some View {
        let bins = summary.histogramBins()
        return VStack(alignment: .leading, spacing: 6) {
            Text("Distribution")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if bins.isEmpty {
                Text("No matched offsets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(bins) { bin in
                    BarMark(
                        x: .value("Offset (ms)", bin.binMs),
                        y: .value("Count", bin.count)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .frame(height: 140)
                .chartXAxisLabel("ms", alignment: .center)
            }
        }
    }
}
