//
//  MFFEvent.swift
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
//  Ports the Events*.xml parser and nearest/next/previous pairing logic from
//  Tools/mffTimingTool (EVA) so both the CLI and this GUI read MFF timing
//  identically.
//

import Foundation

struct MFFEvent: Identifiable, Hashable, Sendable {
    let index: Int
    let sourceFile: String
    let beginDate: Date
    let rawBeginTime: String
    /// Offset from the recording's own start, in microseconds, as stored in the XML.
    let relativeBeginTimeMicroseconds: Int?
    let durationMicroseconds: Int?
    let code: String
    let label: String?
    let eventDescription: String?
    let sourceDevice: String?
    let keys: [String: String]

    var id: Int { index }

    /// `relativeBeginTimeMicroseconds` converted to seconds, when present.
    var relativeBeginTimeSeconds: Double? {
        relativeBeginTimeMicroseconds.map { Double($0) / 1_000_000 }
    }
}

enum PairMode: String, Sendable {
    case nearest
    case next
    case previous
}

enum MFFTimingError: LocalizedError, Sendable {
    case invalidMFF(URL)
    case noEventFiles(URL)
    case unreadableXML(URL, String)

    var errorDescription: String? {
        switch self {
        case .invalidMFF(let url):
            return "Input is not a readable MFF directory: \(url.path)"
        case .noEventFiles(let url):
            return "No Events*.xml files found in \(url.path)"
        case .unreadableXML(let url, let message):
            return "Could not parse \(url.lastPathComponent): \(message)"
        }
    }
}

final class MFFEventXMLParser: NSObject, XMLParserDelegate {
    private let sourceFile: String
    private var events: [MFFEvent] = []
    private var currentEvent: PartialEvent?
    private var currentText = ""
    private var currentKeyCode: String?
    private var parseError: Error?

    private struct PartialEvent {
        var beginTime: String?
        var relativeBeginTime: Int?
        var duration: Int?
        var code: String?
        var label: String?
        var eventDescription: String?
        var sourceDevice: String?
        var keys: [String: String] = [:]
    }

    init(sourceFile: String) {
        self.sourceFile = sourceFile
    }

    func parse(url: URL, startingIndex: Int) throws -> [MFFEvent] {
        guard let parser = XMLParser(contentsOf: url) else {
            throw MFFTimingError.unreadableXML(url, "XMLParser could not open the file.")
        }
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription
                ?? parseError?.localizedDescription
                ?? "Unknown XML parser error."
            throw MFFTimingError.unreadableXML(url, message)
        }

        return events.enumerated().map { offset, event in
            MFFEvent(
                index: startingIndex + offset,
                sourceFile: event.sourceFile,
                beginDate: event.beginDate,
                rawBeginTime: event.rawBeginTime,
                relativeBeginTimeMicroseconds: event.relativeBeginTimeMicroseconds,
                durationMicroseconds: event.durationMicroseconds,
                code: event.code,
                label: event.label,
                eventDescription: event.eventDescription,
                sourceDevice: event.sourceDevice,
                keys: event.keys
            )
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = localName(elementName)
        currentText = ""
        if name == "event" {
            currentEvent = PartialEvent()
            currentKeyCode = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = localName(elementName)
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard currentEvent != nil else {
            currentText = ""
            return
        }

        switch name {
        case "beginTime":
            currentEvent?.beginTime = text
        case "relativeBeginTime":
            currentEvent?.relativeBeginTime = Int(text)
        case "duration":
            currentEvent?.duration = Int(text)
        case "code":
            currentEvent?.code = text
        case "label":
            currentEvent?.label = nonEmpty(text)
        case "description":
            currentEvent?.eventDescription = nonEmpty(text)
        case "sourceDevice":
            currentEvent?.sourceDevice = nonEmpty(text)
        case "keyCode":
            currentKeyCode = text
        case "data":
            if let currentKeyCode, !currentKeyCode.isEmpty {
                currentEvent?.keys[currentKeyCode] = text
            }
        case "key":
            currentKeyCode = nil
        case "event":
            do {
                if let event = try buildEvent() {
                    events.append(event)
                }
            } catch {
                parseError = error
                parser.abortParsing()
            }
            currentEvent = nil
            currentKeyCode = nil
        default:
            break
        }

        currentText = ""
    }

    private func buildEvent() throws -> MFFEvent? {
        guard let currentEvent else { return nil }
        guard let rawBeginTime = nonEmpty(currentEvent.beginTime),
              let beginDate = parseMFFDate(rawBeginTime),
              let code = nonEmpty(currentEvent.code) else {
            return nil
        }

        return MFFEvent(
            index: events.count + 1,
            sourceFile: sourceFile,
            beginDate: beginDate,
            rawBeginTime: rawBeginTime,
            relativeBeginTimeMicroseconds: currentEvent.relativeBeginTime,
            durationMicroseconds: currentEvent.duration,
            code: code,
            label: currentEvent.label,
            eventDescription: currentEvent.eventDescription,
            sourceDevice: currentEvent.sourceDevice,
            keys: currentEvent.keys
        )
    }
}

enum MFFEventLoader {
    static func eventFiles(in mffURL: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: mffURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw MFFTimingError.invalidMFF(mffURL)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: mffURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let files = contents
            .filter { $0.lastPathComponent.hasPrefix("Events") && $0.pathExtension.lowercased() == "xml" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard !files.isEmpty else {
            throw MFFTimingError.noEventFiles(mffURL)
        }
        return files
    }

    static func loadEvents(from mffURL: URL) throws -> [MFFEvent] {
        var allEvents: [MFFEvent] = []
        for fileURL in try eventFiles(in: mffURL) {
            let parser = MFFEventXMLParser(sourceFile: fileURL.lastPathComponent)
            let parsed = try parser.parse(url: fileURL, startingIndex: allEvents.count + 1)
            allEvents.append(contentsOf: parsed)
        }

        let sorted = allEvents.sorted { left, right in
            if left.beginDate == right.beginDate {
                return left.sourceFile.localizedStandardCompare(right.sourceFile) == .orderedAscending
            }
            return left.beginDate < right.beginDate
        }

        return sorted.enumerated().map { offset, event in
            MFFEvent(
                index: offset + 1,
                sourceFile: event.sourceFile,
                beginDate: event.beginDate,
                rawBeginTime: event.rawBeginTime,
                relativeBeginTimeMicroseconds: event.relativeBeginTimeMicroseconds,
                durationMicroseconds: event.durationMicroseconds,
                code: event.code,
                label: event.label,
                eventDescription: event.eventDescription,
                sourceDevice: event.sourceDevice,
                keys: event.keys
            )
        }
    }

    static func match(event: MFFEvent, candidates: [MFFEvent], mode: PairMode) -> MFFEvent? {
        switch mode {
        case .nearest:
            return candidates.min {
                abs($0.beginDate.timeIntervalSince(event.beginDate)) < abs($1.beginDate.timeIntervalSince(event.beginDate))
            }
        case .next:
            return candidates
                .filter { $0.beginDate >= event.beginDate }
                .min { $0.beginDate < $1.beginDate }
        case .previous:
            return candidates
                .filter { $0.beginDate <= event.beginDate }
                .max { $0.beginDate < $1.beginDate }
        }
    }
}

func parseMFFDate(_ text: String) -> Date? {
    let formatterWithFraction = ISO8601DateFormatter()
    formatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatterWithFraction.date(from: text) {
        return date
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
}

private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private func localName(_ name: String) -> String {
    name.split(separator: ":").last.map(String.init) ?? name
}
