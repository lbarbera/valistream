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
