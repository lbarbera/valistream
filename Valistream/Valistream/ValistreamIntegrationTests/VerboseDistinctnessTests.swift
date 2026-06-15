//
//  VerboseDistinctnessTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

/// Asserts FR-015, SC-005: `--verbose` adds ≥5 trace categories absent at normal;
/// all verbose (trace) lines are ID-based (no raw URLs).
@Suite("Verbose distinctness from normal tier", .timeLimit(.minutes(1)))
struct VerboseDistinctnessTests {

    private let masterURL = URL(string: "https://cdn.example.com/live/master.m3u8")!
    private let mediaURL  = URL(string: "https://cdn.example.com/live/v1080/index.m3u8")!

    @Test("verbose tier produces .trace events; normal tier does not")
    func verboseTierHasTraceEventsNormalDoesNot() async throws {
        let verboseEvents = await collectEvents(verbose: true)
        let normalEvents = await collectEvents(verbose: false)

        let verboseTraceCount = verboseEvents.count(where: { if case .trace = $0 { return true }; return false })
        let normalTraceCount = normalEvents.count(where: { if case .trace = $0 { return true }; return false })

        #expect(verboseTraceCount > 0, "Verbose session should produce .trace events")
        #expect(normalTraceCount == 0, "Normal session should produce no .trace events")
    }

    @Test("verbose tier adds at least 5 distinct trace categories absent at normal")
    func verboseAddsAtLeast5Categories() async throws {
        let verboseEvents = await collectEvents(verbose: true)
        var verboseCategories = Set<String>()
        for event in verboseEvents {
            if case .trace(let traceEvent) = event {
                verboseCategories.insert(categoryPrefix(of: traceEvent))
            }
        }
        // SC-005: ≥5 distinct categories (Fetch, Validation, Stored, Refresh, Compare, Lifecycle)
        #expect(
            verboseCategories.count >= 5,
            "Expected ≥5 distinct trace categories, got \(verboseCategories.count): \(verboseCategories)"
        )
    }

    @Test("all trace event lines are ID-based (no raw URLs in formatted output)")
    func traceEventLinesAreIDBasedNoRawURL() async throws {
        let events = await collectEvents(verbose: true)
        for event in events {
            if case .trace(let traceEvent) = event {
                let line = TraceFormatter.format(traceEvent)
                #expect(
                    line.contains("https://") == false,
                    "Trace line contains raw URL: \(line)"
                )
                #expect(
                    line.contains("http://") == false,
                    "Trace line contains raw URL: \(line)"
                )
            }
        }
    }

    @Test("verbose tier produces both .rosterReady and .refreshCompleted events")
    func verboseHasRosterAndRefreshCompleted() async throws {
        let events = await collectEvents(verbose: true)
        let hasRoster = events.contains(where: { if case .rosterReady = $0 { return true }; return false })
        let hasRefresh = events.contains(where: { if case .refreshCompleted = $0 { return true }; return false })
        #expect(hasRoster, "Verbose session should emit .rosterReady")
        #expect(hasRefresh, "Verbose session should emit .refreshCompleted after a refresh cycle")
    }



    // MARK: - Private helpers

    private func collectEvents(verbose: Bool) async -> [SessionEvent] {
        let harness = LiveSessionHarness(
            input: masterURL,
            config: SessionConfig(nonInteractive: true, verboseEvents: verbose)
        )
        harness.fetcher.stub(masterURL, body: masterPlaylist)
        harness.fetcher.stub(mediaURL, body: liveMedia)
        harness.start()

        var events: [SessionEvent] = []
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await event in harness.session.events {
                    events.append(event)
                }
            }
            group.addTask {
                // Drive one refresh cycle so refreshCompleted + cadence traces are emitted.
                await harness.step(by: 6, refreshing: self.mediaURL)
                await harness.abortAndFinish()
            }
        }

        return events
    }

    /// Returns the category prefix of a `TraceEvent` for distinctness counting.
    private func categoryPrefix(of event: TraceEvent) -> String {
        String(TraceFormatter.format(event).prefix(while: { $0 != ":" }))
    }



    // MARK: - T043: Category rendering and visual subordination

    @Test("verbose trace lines contain category labels for all rendered categories")
    func traceLinesContainCategoryLabels() async throws {
        let events = await collectEvents(verbose: true)
        // Collect the formatted text of each trace event.
        var categoryLabels = Set<String>()
        for event in events {
            if case .trace(let traceEvent) = event {
                let line = TraceFormatter.format(traceEvent)
                // Category label is everything before the first ":"
                let label = String(line.prefix(while: { $0 != ":" }))
                if label.isEmpty == false {
                    categoryLabels.insert(label)
                }
            }
        }
        // We expect at least: Fetch, Validation, Refresh, Compare, Stored (five categories).
        let expectedCategories: Set<String> = ["Fetch", "Validation", "Refresh", "Compare", "Stored"]
        let missing = expectedCategories.subtracting(categoryLabels)
        #expect(missing.isEmpty,
                "Missing category labels in verbose output: \(missing); found: \(categoryLabels)")
    }

    @Test("verbose trace lines are rendered nested under playlist/snapshot context (T27/T28)")
    func traceRenderingIsNestedUnderContext() async throws {
        let recorder = OutputRecorder()
        let mode = TerminalOutputMode(
            isTTY: false,
            noColorEnv: false,
            noColorFlag: false,
            termIsDumb: false,
            environment: ["LANG": "en_US.UTF-8"],
            verbosity: .verbose
        )
        var renderer = StatusRenderer(
            writer: TerminalWriter(
                mode: mode,
                terminalWidth: 120,
                output: recorder.writeStandardOutput,
                errorOutput: recorder.writeStandardError
            ),
            json: false,
            timeZone: .gmt
        )
        let at = Date(timeIntervalSince1970: 1_750_000_000)
        let snapshotID = "video-1080p_1"

        // Emit two trace events for the same snapshot.
        renderer.render(TimestampedEvent(at: at, event: .trace(.fetchIntent(snapshotID: snapshotID))))
        renderer.render(TimestampedEvent(at: at, event: .trace(.validationPlaylistOK(snapshotID: snapshotID))))

        let output = recorder.standardOutput
        let lines = output.split(separator: "\n").map(String.init)

        // Context header: a line containing the snapshotID must appear (T27).
        let contextLines = lines.filter { $0.contains(snapshotID) }
        #expect(contextLines.isEmpty == false,
                "Context label \(snapshotID) should appear in output")

        // Trace category lines must follow the context header in the rendered output (T27 nesting).
        let fetchLineIndex  = lines.firstIndex(where: { $0.contains("Fetch:") })
        let validLineIndex  = lines.firstIndex(where: { $0.contains("Validation:") })
        let contextLineIndex = lines.firstIndex(where: { $0.contains(snapshotID) && !$0.contains("Fetch:") && !$0.contains("Validation:") })
        if let ctx = contextLineIndex, let fetch = fetchLineIndex {
            #expect(fetch > ctx, "Fetch trace line should follow the context header")
        }
        if let fetch = fetchLineIndex, let valid = validLineIndex {
            #expect(valid > fetch, "Validation trace line should follow the Fetch trace line")
        }
        #expect(fetchLineIndex != nil, "Fetch trace line should be present")
        #expect(validLineIndex != nil, "Validation trace line should be present")
    }

    @Test("verbose trace lines use .metadata (dim) role — subordinate to result lines")
    func traceUsesMetadataRoleSubordinateToResults() async throws {
        // When color is disabled, metadata-role lines carry no ANSI codes, which also
        // means they don't carry severity-coloring (red/green/yellow) — subordinate by design.
        let recorder = OutputRecorder()
        let plainMode = TerminalOutputMode(
            isTTY: false,
            noColorEnv: true,   // disable color
            noColorFlag: false,
            termIsDumb: false,
            environment: [:],
            verbosity: .verbose
        )
        var renderer = StatusRenderer(
            writer: TerminalWriter(
                mode: plainMode,
                terminalWidth: 120,
                output: recorder.writeStandardOutput,
                errorOutput: recorder.writeStandardError
            ),
            json: false,
            timeZone: .gmt
        )
        let at = Date(timeIntervalSince1970: 1_750_000_000)
        let snapshotID = "video-1080p_1"

        renderer.render(TimestampedEvent(at: at, event: .trace(.validationPlaylistOK(snapshotID: snapshotID))))
        renderer.render(TimestampedEvent(
            at: at,
            event: .refreshCompleted(playlistID: "video-1080p", index: 1, errors: 0, warnings: 0)
        ))

        let output = recorder.standardOutput
        // In plain mode there are no ANSI escape codes at all.
        #expect(output.contains("\u{1B}") == false,
                "Plain output should contain no ANSI escape codes")
        // The result line uses a success marker, trace lines do not.
        #expect(output.contains("✓ OK") || output.contains("[OK]"),
                "Result line should have success marker")
        // Trace lines should NOT have success/error/warning markers.
        let traceLines = output.split(separator: "\n").filter { $0.contains("Validation:") }
        for line in traceLines {
            #expect(line.contains("✓") == false && line.contains("[OK]") == false,
                    "Trace lines should not carry result markers: \"\(line)\"")
        }
    }

    @Test("verbose trace context header reappears after a non-trace block breaks the stream")
    func traceContextHeaderReappearsAfterBlockBreak() async throws {
        let recorder = OutputRecorder()
        let mode = TerminalOutputMode(
            isTTY: false,
            noColorEnv: false,
            noColorFlag: false,
            termIsDumb: false,
            environment: ["LANG": "en_US.UTF-8"],
            verbosity: .verbose
        )
        var renderer = StatusRenderer(
            writer: TerminalWriter(
                mode: mode,
                terminalWidth: 120,
                output: recorder.writeStandardOutput,
                errorOutput: recorder.writeStandardError
            ),
            json: false,
            timeZone: .gmt
        )
        let at = Date(timeIntervalSince1970: 1_750_000_000)
        let snapshotID = "video-1080p_1"

        // First trace block for snapshotID — should emit context header.
        renderer.render(TimestampedEvent(at: at, event: .trace(.fetchIntent(snapshotID: snapshotID))))
        // Non-trace block breaks the context.
        renderer.render(TimestampedEvent(
            at: at,
            event: .refreshCompleted(playlistID: "video-1080p", index: 1, errors: 0, warnings: 0)
        ))
        // Same snapshotID again — context header should reappear because the context was reset.
        renderer.render(TimestampedEvent(at: at, event: .trace(.validationPlaylistOK(snapshotID: snapshotID))))

        let output = recorder.standardOutput
        // The snapshotID should appear at least twice (once as context header before each trace group).
        let occurrences = output.components(separatedBy: snapshotID).count - 1
        #expect(occurrences >= 2,
                "Context label \(snapshotID) should appear at least twice in: \(output)")
    }

    // MARK: - Fixtures

    private let masterPlaylist = """
        #EXTM3U
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,CODECS="avc1.640028",RESOLUTION=1920x1080
        v1080/index.m3u8
        """

    private let liveMedia = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:100
        #EXTINF:6.0,
        seg100.ts
        #EXTINF:6.0,
        seg101.ts
        """
}
