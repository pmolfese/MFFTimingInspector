# MFF Timing Inspector

A native macOS app for checking EGI/MagStim Neuroscience MFF recording timing
against the diagnostics the `egi_pynetstation` Python package writes while
sending ECI events: does the MFF's own event timeline match what pynetstation
logged sending, was the NTP/drift model stable, and did a dropped display
frame explain an outlier.

It reads, side by side:

- an `.mff` recording's `Events*.xml` tracks (stimulus/ECI codes, DIN pulses)
- pynetstation's JSON-lines diagnostics log (`session_start`, drift-model
  fits and transitions, event send failures)
- a per-trial timing CSV (planned vs. actual send times, per-trial metadata)
- a per-frame interval CSV, if the experiment script logged one

## Requirements

- macOS 14+
- Xcode 16+ (uses Xcode's file-system-synchronized groups; no external
  dependencies, no Swift Package Manager setup required)

## Build and test

```sh
xcodebuild -project MFFTimingTool.xcodeproj -scheme MFFTimingTool -configuration Debug build
xcodebuild -project MFFTimingTool.xcodeproj -scheme MFFTimingTool -configuration Debug test
```

Or just open `MFFTimingTool.xcodeproj` in Xcode and run.

## Layout

```
MFFTimingCore/       core parsing/correlation logic, no UI, unit-testable
MFFTimingTool/        SwiftUI app (Events / Offset Analysis / Drift tabs)
MFFTimingToolTests/    swift-testing tests, plus fixture data under Fixtures/
example_files/         a synthetic .mff for trying the app end to end
```

## A note on the fixture/example data

`MFFTimingToolTests/Fixtures/` and `example_files/` are both gitignored and
not part of the repository.

`Fixtures/` includes `egi_timing.csv`, `netstation_diagnostics.jsonl`, and a
sample of `frame_intervals.csv` copied from a real recording session, used to
validate the timing-correlation logic against real data rather than only
hand-built fixtures. That JSONL file contains a Windows file path revealing a
local project folder name and username (from the machine that ran the
experiment script) that were never scrubbed. `example_files/` holds only a
synthetic `.mff` generated from that same CSV's timing, not real recording
data, but is ignored too since it's regenerable and not something every clone
needs.

Because those directories aren't guaranteed to exist, every test that reads
from them checks `Fixtures.exists(_:)` first (via `@Test(.enabled(if:))`) and
skips itself, rather than crashing the run, when the fixture data isn't
present locally. Clone this repo elsewhere and `MFFTimingToolTests` reports
those as skipped, not failed.

If you need the fixture data to actually run those tests, copy your own
timing CSV / diagnostics JSONL / frame-interval CSV (and, for the MFF-parsing
tests, a small `Events*.xml`) into `MFFTimingToolTests/Fixtures/` under the
filenames each test's `Fixtures.url(...)` call names.
