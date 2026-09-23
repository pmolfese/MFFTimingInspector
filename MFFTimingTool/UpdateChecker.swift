//
//  UpdateChecker.swift
//  MFFTimingToolApp
//
//  Checks the public GitHub Releases API on explicit user request. It does
//  not run in the background or collect any application data.
//

import Combine
import Foundation

struct UpdateCheckResult: Identifiable, Sendable {
    enum Outcome: Sendable {
        case updateAvailable(version: String, releaseName: String?, url: URL)
        case upToDate(currentVersion: String)
        case noPublishedRelease
        case failed(message: String)
    }

    let id = UUID()
    let outcome: Outcome
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let releasesPage = URL(string: "https://github.com/pmolfese/MFFTimingInspector/releases")!

    @Published private(set) var isChecking = false
    @Published var result: UpdateCheckResult?

    private let latestReleaseAPI = URL(string: "https://api.github.com/repos/pmolfese/MFFTimingInspector/releases/latest")!

    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        result = nil
        defer { isChecking = false }

        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MFFTimingInspector-UpdateChecker", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw UpdateCheckError.invalidResponse
            }

            if http.statusCode == 404 {
                result = UpdateCheckResult(outcome: .noPublishedRelease)
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                throw UpdateCheckError.httpStatus(http.statusCode)
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            guard let isNewer = Self.isVersion(release.tagName, newerThan: current) else {
                throw UpdateCheckError.invalidVersion(release.tagName)
            }

            if isNewer {
                result = UpdateCheckResult(
                    outcome: .updateAvailable(
                        version: release.tagName,
                        releaseName: release.name,
                        url: release.htmlURL
                    )
                )
            } else {
                result = UpdateCheckResult(outcome: .upToDate(currentVersion: current))
            }
        } catch {
            result = UpdateCheckResult(outcome: .failed(message: error.localizedDescription))
        }
    }

    /// Numeric comparison accepts conventional GitHub tags such as `v1.2.3`
    /// as well as the bundle form `1.2.3`. Missing components compare as zero.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool? {
        guard let candidateParts = versionParts(candidate),
              let currentParts = versionParts(current) else { return nil }
        let count = max(candidateParts.count, currentParts.count)
        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart { return candidatePart > currentPart }
        }
        return false
    }

    private static func versionParts(_ version: String) -> [Int]? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.first == "v" || trimmed.first == "V" ? String(trimmed.dropFirst()) : trimmed
        let core = withoutPrefix.split(separator: "-", maxSplits: 1).first.map(String.init) ?? withoutPrefix
        let components = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return nil }
        let values = components.compactMap { Int($0) }
        return values.count == components.count ? values : nil
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
    }
}

private enum UpdateCheckError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case invalidVersion(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case .httpStatus(let status):
            return "GitHub returned HTTP status \(status)."
        case .invalidVersion(let version):
            return "The latest release tag “\(version)” is not a numeric version."
        }
    }
}
