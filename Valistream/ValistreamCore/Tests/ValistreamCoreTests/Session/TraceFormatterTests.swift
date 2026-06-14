//
//  TraceFormatterTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

/// Tests that each `TraceEvent` variant is rendered by `TraceFormatter` as a
/// catalog category-prefixed, ID-based line with no raw URL. (FR-015b, SC-003/005)
@Suite(.tags(.output))
struct TraceFormatterTests {

    private let snapshotLabel = "1080p_avc1_5"
    private let playlistID = "1080p_avc1"



    // MARK: - Fetch intent

    @Test("fetchIntent renders 'Fetch:' prefix with snapshot label, no raw URL")
    func fetchIntentLine() {
        let event = TraceEvent.fetchIntent(snapshotID: snapshotLabel)
        let line = TraceFormatter.format(event)
        #expect(line.hasPrefix("Fetch:"), "Expected 'Fetch:' prefix, got: \(line)")
        #expect(line.contains(snapshotLabel), "Expected snapshot label: \(line)")
        #expect(line.contains("https://") == false, "Must not contain raw URL: \(line)")
        #expect(line.contains("http://") == false, "Must not contain raw URL: \(line)")
    }



    // MARK: - Fetch result

    @Test("fetchResult renders 'Fetch:' prefix with HTTP status and duration, no raw URL")
    func fetchResultLine() {
        let event = TraceEvent.fetchResult(snapshotID: snapshotLabel, httpStatus: 200, durationMs: 42, bytes: 1_320)
        let line = TraceFormatter.format(event)
        #expect(line.hasPrefix("Fetch:"), "Expected 'Fetch:' prefix, got: \(line)")
        #expect(line.contains(snapshotLabel), "Expected snapshot label: \(line)")
        #expect(line.contains("200"), "Expected HTTP status: \(line)")
        #expect(line.contains("42"), "Expected duration ms: \(line)")
        #expect(line.contains("https://") == false, "Must not contain raw URL: \(line)")
    }



    // MARK: - Validation per-playlist

    @Test("validationPlaylistOK renders 'Validation:' prefix with snapshot ID and OK")
    func validationPlaylistOKLine() {
        let event = TraceEvent.validationPlaylistOK(snapshotID: snapshotLabel)
        let line = TraceFormatter.format(event)
        #expect(line.hasPrefix("Validation:"), "Expected 'Validation:' prefix, got: \(line)")
        #expect(line.contains(snapshotLabel), "Expected snapshot label: \(line)")
        #expect(line.contains("OK"), "Expected OK result: \(line)")
        #expect(line.contains("https://") == false)
    }

    @Test("validationPlaylistFail renders 'Validation:' prefix with snapshot ID and counts")
    func validationPlaylistFailLine() {
        let event = TraceEvent.validationPlaylistFail(snapshotID: snapshotLabel, errorCount: 2, warnCount: 1)
        let line = TraceFormatter.format(event)
        #expect(line.hasPrefix("Validation:"), "Expected 'Validation:' prefix, got: \(line)")
        #expect(line.contains(snapshotLabel), "Expected snapshot label: \(line)")
        #expect(line.contains("https://") == false)
    }



    // MARK: - Validation per-rule

    @Test("validationRuleOK renders 'Validation:' prefix with rule ID")
    func validationRuleOKLine() {
        let event = TraceEvent.validationRuleOK(snapshotID: snapshotLabel, ruleID: "RFC8216.4.3.3.1")
        let line = TraceFormatter.format(event)
        #expect(line.hasPrefix("Validation:"), "Expected 'Validation:' prefix, got: \(line)")
        #expect(line.contains(snapshotLabel), "Expected snapshot label: \(line)")
        #expect(line.contains("RFC8216.4.3.3.1"), "Expected rule ID: \(line)")
        #expect(line.contains("https://") == false)
    }

    @Test("validationRuleFail renders 'Validation:' prefix with rule ID")
    func validationRuleFailLine() {
        let event = TraceEvent.validationRuleFail(snapshotID: snapshotLabel, ruleID: "RFC8216.4.3.3.1")
        let line = TraceFormatter.format(event)
        #expect(line.hasPrefix("Validation:"), "Expected 'Validation:' prefix, got: \(line)")
        #expect(line.contains(snapshotLabel), "Expected snapshot label: \(line)")
        #expect(line.contains("RFC8216.4.3.3.1"), "Expected rule ID: \(line)")
        #expect(line.contains("https://") == false)
    }



    // MARK: - Archive write

    @Test("stored renders 'Stored:' prefix with snapshot ID and archive path, no raw URL")
    func storedLine() {
        let event = TraceEvent.stored(snapshotID: snapshotLabel, archivePath: "playlists/1080p_avc1/1080p_avc1_5.m3u8")
        let line = TraceFormatter.format(event)
        #expect(line.hasPrefix("Stored:"), "Expected 'Stored:' prefix, got: \(line)")
        #expect(line.contains(snapshotLabel), "Expected snapshot label: \(line)")
        #expect(line.contains("playlists/"), "Expected archive path prefix: \(line)")
        #expect(line.contains("https://") == false)
    }



    // MARK: - Refresh scheduling / cadence

    @Test("refreshScheduled renders 'Refresh:' prefix with playlist ID, no raw URL")
    func refreshScheduledLine() {
        let event = TraceEvent.refreshScheduled(playlistID: playlistID, delaySeconds: 6.0)
        let line = TraceFormatter.format(event)
        #expect(line.hasPrefix("Refresh:"), "Expected 'Refresh:' prefix, got: \(line)")
        #expect(line.contains(playlistID), "Expected playlist ID: \(line)")
        #expect(line.contains("https://") == false)
    }

    @Test("refreshDrift renders 'Refresh:' prefix with playlist ID")
    func refreshDriftLine() {
        let event = TraceEvent.refreshDrift(playlistID: playlistID, driftSeconds: 1.5)
        let line = TraceFormatter.format(event)
        #expect(line.hasPrefix("Refresh:"), "Expected 'Refresh:' prefix, got: \(line)")
        #expect(line.contains(playlistID), "Expected playlist ID: \(line)")
        #expect(line.contains("https://") == false)
    }



    // MARK: - Continuity comparison

    @Test("continuityCompare renders 'Compare:' prefix with both snapshot IDs, no raw URL")
    func continuityCompareLine() {
        let event = TraceEvent.continuityCompare(olderSnapshotID: "1080p_avc1_4", newerSnapshotID: "1080p_avc1_5")
        let line = TraceFormatter.format(event)
        #expect(line.hasPrefix("Compare:"), "Expected 'Compare:' prefix, got: \(line)")
        #expect(line.contains("1080p_avc1_4"), "Expected older snapshot ID: \(line)")
        #expect(line.contains("1080p_avc1_5"), "Expected newer snapshot ID: \(line)")
        #expect(line.contains("https://") == false)
    }



    // MARK: - Rendition lifecycle

    @Test("renditionAdded renders 'Lifecycle:' prefix with playlist ID, no raw URL")
    func renditionAddedLine() {
        let event = TraceEvent.renditionAdded(playlistID: playlistID)
        let line = TraceFormatter.format(event)
        #expect(line.hasPrefix("Lifecycle:"), "Expected 'Lifecycle:' prefix, got: \(line)")
        #expect(line.contains(playlistID), "Expected playlist ID: \(line)")
        #expect(line.contains("https://") == false)
    }

    @Test("renditionDropped renders 'Lifecycle:' prefix with playlist ID, no raw URL")
    func renditionDroppedLine() {
        let event = TraceEvent.renditionDropped(playlistID: playlistID)
        let line = TraceFormatter.format(event)
        #expect(line.hasPrefix("Lifecycle:"), "Expected 'Lifecycle:' prefix, got: \(line)")
        #expect(line.contains(playlistID), "Expected playlist ID: \(line)")
        #expect(line.contains("https://") == false)
    }



    // MARK: - SC-003 zero raw URL invariant across all variants

    @Test("no TraceEvent variant emits a raw URL", arguments: Self.allSampleEvents)
    func noRawURLInAnyVariant(event: TraceEvent) {
        let line = TraceFormatter.format(event)
        #expect(line.contains("https://") == false, "TraceFormatter emitted raw https:// URL in line: \(line)")
        #expect(line.contains("http://") == false, "TraceFormatter emitted raw http:// URL in line: \(line)")
    }

    /// All `TraceEvent` variants with sample values for the parameterized test.
    static let allSampleEvents: [TraceEvent] = [
        .fetchIntent(snapshotID: "1080p_avc1_5"),
        .fetchResult(snapshotID: "1080p_avc1_5", httpStatus: 200, durationMs: 25, bytes: 1_300),
        .validationPlaylistOK(snapshotID: "1080p_avc1_5"),
        .validationPlaylistFail(snapshotID: "1080p_avc1_5", errorCount: 1, warnCount: 0),
        .validationRuleOK(snapshotID: "1080p_avc1_5", ruleID: "RFC8216.4.3.3.1"),
        .validationRuleFail(snapshotID: "1080p_avc1_5", ruleID: "RFC8216.4.3.3.1"),
        .stored(snapshotID: "1080p_avc1_5", archivePath: "playlists/1080p_avc1/1080p_avc1_5.m3u8"),
        .refreshScheduled(playlistID: "1080p_avc1", delaySeconds: 6.0),
        .refreshDrift(playlistID: "1080p_avc1", driftSeconds: 1.2),
        .continuityCompare(olderSnapshotID: "1080p_avc1_4", newerSnapshotID: "1080p_avc1_5"),
        .renditionAdded(playlistID: "1080p_avc1"),
        .renditionDropped(playlistID: "1080p_avc1"),
    ]
}
