//
//  LiveFaultScenarioTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
import ValistreamCore

@Suite("Live fault scenarios")
struct LiveFaultScenarioTests {
    private let media = URL(string: "https://ex.com/live.m3u8")!

    @Test("a stalling playlist warns then escalates to an error")
    func stallingPlaylistWarnsThenErrors() async {
        let harness = LiveSessionHarness(input: media)
        // Only the initial window is ever served; the playlist never changes again.
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
        ])
        harness.start()

        for _ in 0..<6 {
            await harness.step(by: 6, refreshing: media)
        }

        let findings = await harness.session.recordedFindings
        let monitorStates = await harness.session.playlistMonitorStates
        #expect(findings.contains { $0.ruleId == "TOOL.staleness" && $0.severity == .warning })
        #expect(findings.contains { $0.ruleId == "TOOL.staleness" && $0.severity == .error })
        #expect(monitorStates["media"] == .staleError)

        await harness.abortAndFinish()
    }

    @Test("a media-sequence regression is reported as a continuity error")
    func sequenceRegressionIsContinuityError() async {
        let harness = LiveSessionHarness(input: media)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 10, segments: ["s10.ts", "s11.ts", "s12.ts"]))),
            .init(at: .seconds(6), reply: .body(LivePlaylists.window(mediaSequence: 8, segments: ["s8.ts", "s9.ts", "s10.ts"]))),
        ])
        harness.start()

        await harness.step(by: 6, refreshing: media)

        let findings = await harness.session.recordedFindings
        #expect(findings.contains { $0.ruleId == "TOOL.continuity.media-sequence" && $0.severity == .error })

        await harness.abortAndFinish()
    }

    @Test("an inserted discontinuity is info and monitoring continues")
    func discontinuityInsertionIsInfoAndContinues() async {
        let harness = LiveSessionHarness(input: media)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 10, segments: ["s10.ts", "s11.ts"]))),
            .init(at: .seconds(6), reply: .body(LivePlaylists.window(mediaSequence: 11, segments: ["s11.ts", "s12.ts"], discontinuityAt: 1))),
            .init(at: .seconds(12), reply: .body(LivePlaylists.window(mediaSequence: 12, segments: ["s12.ts", "s13.ts"]))),
        ])
        harness.start()

        await harness.step(by: 6, refreshing: media)
        await harness.step(by: 6, refreshing: media)

        let findings = await harness.session.recordedFindings
        let monitorStates = await harness.session.playlistMonitorStates
        #expect(findings.contains { $0.ruleId == "TOOL.continuity.discontinuity-inserted" && $0.severity == .info })
        #expect(findings.contains { $0.severity == .error } == false)
        #expect(monitorStates["media"] == .monitoring)

        await harness.abortAndFinish()
    }

    @Test("the session completes when its time limit expires")
    func timeLimitExpiryCompletesSession() async {
        let harness = LiveSessionHarness(
            input: media,
            config: SessionConfig(timeLimit: .seconds(20), nonInteractive: true)
        )
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
            .init(at: .seconds(6), reply: .body(LivePlaylists.window(mediaSequence: 1, segments: ["s1.ts", "s2.ts", "s3.ts"]))),
        ])
        harness.start()

        await harness.step(by: 6, refreshing: media)
        await harness.advance(by: 30)
        await harness.finish()

        let state = await harness.session.state
        #expect(state == .completed)
    }
}
