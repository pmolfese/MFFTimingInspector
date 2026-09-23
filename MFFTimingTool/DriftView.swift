//
//  DriftView.swift
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
//  Answers "was the clock-drift model stable": a slope-over-time chart with
//  points colored by stage (nothing fit yet, still warming up, stable) and
//  a shaded span for the time before the model's first accepted fit, a
//  residual-error trace, a marked timeline of every state transition
//  (engaged / promoted / stalled / recovered / NTP undersampled / an
//  asynchronous event send failure), and -- when a frame-interval CSV is
//  also loaded -- every dropped display frame on the same axis, since a
//  stall there delays whatever event depended on that flip while the
//  recorded clocks carry on unaffected, which can otherwise look
//  indistinguishable from clock jitter.
//

import SwiftUI
import Charts

struct DriftView: View {
    @EnvironmentObject private var appState: AppState

    private var timeline: DriftTimeline { appState.driftTimeline }
    private var frameDrops: [FrameDropEvent] { appState.frameDropEvents }

    var body: some View {
        if appState.diagnostics.isEmpty && timeline.slopePoints.isEmpty {
            ContentUnavailableView(
                "No diagnostics loaded",
                systemImage: "waveform.path.ecg",
                description: Text("Import a netstation diagnostics .jsonl from the sidebar to see clock drift stability.")
            )
        } else if timeline.slopePoints.isEmpty {
            ContentUnavailableView(
                "No drift fits in this log",
                systemImage: "waveform.path.ecg",
                description: Text("This diagnostics file has no drift_model_engaged/status/promoted records.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sessionSummary
                    slopeChart
                    transitionLegend
                    residualChart
                    transitionsList
                }
                .padding(16)
            }
        }
    }

    // MARK: - Session summary

    private var sessionSummary: some View {
        let stalls = count(.stalled)
        let recoveries = count(.recovered)
        let undersampled = count(.undersampled)
        let failures = count(.eventSendFailure)
        let neverEngaged = timeline.sessions.filter { $0.engagedTime == nil }.count
        let warmupFits = timeline.slopePoints.filter { $0.stage == .warmup }.count
        let mainFits = timeline.slopePoints.filter { $0.stage == .stable }.count

        return HStack(spacing: 18) {
            statTile("sessions", "\(timeline.sessions.count)")
            statTile("stalls", "\(stalls)", isWarning: stalls > 0)
            statTile("recoveries", "\(recoveries)")
            statTile("NTP undersampled", "\(undersampled)", isWarning: undersampled > 0)
            statTile("send failures", "\(failures)", isWarning: failures > 0)
            statTile("warmup fits", "\(warmupFits)")
            statTile("main-model fits", "\(mainFits)")
            if neverEngaged > 0 {
                statTile("never engaged", "\(neverEngaged)", isWarning: true)
            }
            Spacer()
        }
    }

    private func count(_ kind: DriftTransitionKind) -> Int {
        timeline.transitions.filter { $0.kind == kind }.count
    }

    @ViewBuilder
    private func statTile(_ label: String, _ value: String, isWarning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .medium))
                .foregroundStyle(isWarning ? .red : .primary)
        }
    }

    // MARK: - Slope chart

    private var slopeChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Drift slope over time")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(slopeChartCaption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Chart {
                ForEach(timeline.sessions) { session in
                    if let engaged = session.engagedTime {
                        RectangleMark(
                            xStart: .value("Session start", session.startTime),
                            xEnd: .value("Engaged", engaged)
                        )
                        .foregroundStyle(Color.gray.opacity(0.15))
                    }
                }

                ForEach(timeline.transitions) { transition in
                    RuleMark(x: .value("Time", transition.time))
                        .foregroundStyle(color(for: transition.kind))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                ForEach(frameDrops) { drop in
                    RuleMark(x: .value("Time", drop.time))
                        .foregroundStyle(frameDropColor)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 2]))
                }

                ForEach(timeline.slopePoints) { point in
                    PointMark(
                        x: .value("Time", point.time),
                        y: .value("Slope (ms/hour)", point.slopeMsPerHour)
                    )
                    .foregroundStyle(by: .value("Stage", point.stage.label))
                    .symbolSize(22)
                }
            }
            .chartForegroundStyleScale([
                DriftStage.warmup.label: Color.orange,
                DriftStage.stable.label: Color.accentColor,
                DriftStage.unknown.label: Color.gray,
            ])
            .chartYAxisLabel("ms/hour")
            .frame(height: 220)
        }
    }

    private var slopeChartCaption: String {
        var caption = "Shaded region: before the model's first accepted fit. Dashed lines: state transitions"
        caption += frameDrops.isEmpty ? "." : " and dropped frames"
        caption += " (see legend below)."
        return caption
    }

    // MARK: - Transition legend (custom -- RuleMarks use per-mark static
    // colors, not a categorical scale, so Charts won't auto-legend them)

    private var transitionLegend: some View {
        let present = Set(timeline.transitions.map(\.kind))
        return HStack(spacing: 14) {
            ForEach(DriftTransitionKind.allCases.filter { present.contains($0) }, id: \.self) { kind in
                legendEntry(color: color(for: kind), label: legendLabel(for: kind))
            }
            if !frameDrops.isEmpty {
                legendEntry(color: frameDropColor, label: "Dropped frame (\(frameDrops.count))")
            }
            Spacer()
        }
    }

    private func legendEntry(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(color)
                .frame(width: 10, height: 2)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var frameDropColor: Color { .indigo }

    private func color(for kind: DriftTransitionKind) -> Color {
        switch kind {
        case .sessionStart: return .gray
        case .engaged: return .blue
        case .promoted: return .green
        case .stalled: return .red
        case .recovered: return .orange
        case .undersampled: return .yellow
        case .eventSendFailure: return .pink
        }
    }

    // MARK: - Residual chart

    @ViewBuilder
    private var residualChart: some View {
        let residualPoints = timeline.slopePoints.filter { $0.outstandingErrorMs != nil }
        if !residualPoints.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Residual (outstanding level error, ms)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Chart {
                    ForEach(frameDrops) { drop in
                        RuleMark(x: .value("Time", drop.time))
                            .foregroundStyle(frameDropColor)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 2]))
                    }
                    ForEach(residualPoints) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Error (ms)", point.outstandingErrorMs ?? 0)
                        )
                        .foregroundStyle(Color.purple)
                        PointMark(
                            x: .value("Time", point.time),
                            y: .value("Error (ms)", point.outstandingErrorMs ?? 0)
                        )
                        .foregroundStyle(Color.purple)
                        .symbolSize(14)
                    }
                }
                .chartYAxisLabel("ms")
                .frame(height: 120)
            }
        }
    }

    // MARK: - Transitions list

    private var transitionsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transitions")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Table(timeline.transitions) {
                TableColumn("Time") { transition in
                    Text(Formatting.clockTime.string(from: transition.time)).fontDesign(.monospaced)
                }
                .width(90)
                TableColumn("Event") { transition in
                    HStack(spacing: 5) {
                        Circle().fill(color(for: transition.kind)).frame(width: 6, height: 6)
                        Text(label(for: transition))
                    }
                }
                .width(150)
                TableColumn("Detail") { transition in
                    Text(detail(for: transition))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 120, idealHeight: 200)
        }
    }

    private func detail(for transition: DriftTransition) -> String {
        let record = transition.record
        switch transition.kind {
        case .sessionStart:
            return record["ntp_ip"]?.stringValue.map { "ntp_ip: \($0)" } ?? ""
        case .engaged:
            let samples = record["model_samples"]?.displayString ?? "?"
            let span = record["model_span"]?.doubleValue.map { String(format: "%.0fs", $0) } ?? "?"
            return "\(samples) samples over \(span)"
        case .promoted:
            let samples = record["model_samples"]?.displayString ?? "?"
            let span = record["model_span"]?.doubleValue.map { String(format: "%.0fs", $0) } ?? "?"
            return "\(samples) samples over \(span)"
        case .stalled:
            let rejections: String? = record["consecutive_rejections"]?.displayString
                ?? record["drift_consecutive_rejections"]?.displayString
            return rejections.map { "\($0) consecutive rejections" } ?? ""
        case .recovered:
            let duration = record["stall_duration"]?.doubleValue.map { String(format: "%.0fs stalled", $0) } ?? ""
            let rejectedCount: String? = record["rejected_during_stall"]?.displayString
            let rejected = rejectedCount.map { "\($0) rejected" } ?? ""
            return [duration, rejected].filter { !$0.isEmpty }.joined(separator: ", ")
        case .undersampled:
            let collected = record["samples_collected"]?.displayString ?? "?"
            let expected = record["samples_expected"]?.displayString ?? "?"
            return "\(collected) of ~\(expected) expected samples"
        case .eventSendFailure:
            return record["error"]?.stringValue ?? ""
        }
    }

    private func label(for transition: DriftTransition) -> String {
        switch (transition.kind, transition.stage) {
        case (.engaged, .warmup): return "Warmup model engaged"
        case (.engaged, .stable): return "Main model engaged"
        case (.promoted, _): return "Promoted to main model"
        default: return transition.kind.label
        }
    }

    private func legendLabel(for kind: DriftTransitionKind) -> String {
        let matching = timeline.transitions.filter { $0.kind == kind }
        if kind == .engaged {
            let stages = Set(matching.compactMap(\.stage))
            if stages == [.warmup] { return "Warmup model engaged" }
            if stages == [.stable] { return "Main model engaged" }
        }
        if kind == .promoted { return "Promoted to main model" }
        return kind.label
    }
}
