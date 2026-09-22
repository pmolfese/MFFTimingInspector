//
//  Fixtures.swift
//  MFFTimingToolTests
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

import Foundation

/// Resolves read-only test fixtures under `MFFTimingToolTests/Fixtures/`.
///
/// That directory is gitignored (some of its contents were copied from a real
/// recording session -- see README.md), so it only exists on machines that
/// have it locally. Fixtures are located relative to this source file rather
/// than via a bundle resource lookup.
enum Fixtures {

    /// Absolute URL of the `MFFTimingToolTests/Fixtures/` directory.
    static let directory: URL = {
        URL(fileURLWithPath: #filePath)        // <repo>/MFFTimingToolTests/Fixtures.swift
            .deletingLastPathComponent()        // <repo>/MFFTimingToolTests
            .appendingPathComponent("Fixtures")
    }()

    /// Whether a named fixture is present locally. Tests that depend on a
    /// fixture should gate themselves on this via `@Test(.enabled(if:))`
    /// rather than calling `url(_:)` unconditionally -- `url(_:)` crashes
    /// the whole test process on a missing file (via `precondition`, which
    /// can't be caught), which is fine for a clear local failure but wrong
    /// for "this machine just doesn't have the gitignored fixture data,"
    /// which should skip, not crash the run.
    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
    }

    /// Returns the URL of a named fixture, verifying it exists so tests fail
    /// with a clear message rather than an opaque read error.
    static func url(_ name: String) -> URL {
        let url = directory.appendingPathComponent(name)
        precondition(
            FileManager.default.fileExists(atPath: url.path),
            "Missing test fixture \(name) at \(url.path)"
        )
        return url
    }
}
