//
//  PlaylistAliasTests.swift
//  ValistreamCoreTests
//

import Testing
@testable import ValistreamCore
import Foundation

@Suite(.tags(.session))
struct PlaylistAliasTests {
    private func url(_ path: String) -> URL {
        URL(string: "https://ex.com/\(path)")!
    }

    // MARK: - Descriptive aliases from attributes

    @Test("video-1080p from RESOLUTION 1920x1080")
    func videoFromResolution() {
        var reg = AliasRegistry()
        let a = reg.alias(for: url("v.m3u8"), role: .video, attributes: ["RESOLUTION": "1920x1080"])
        #expect(a.alias == "video-1080p")
    }

    @Test("audio-en from LANGUAGE=en")
    func audioFromLanguage() {
        var reg = AliasRegistry()
        let a = reg.alias(for: url("a.m3u8"), role: .audio, attributes: ["LANGUAGE": "en"])
        #expect(a.alias == "audio-en")
    }

    @Test("subs-fr from subtitles LANGUAGE=fr")
    func subsFromLanguage() {
        var reg = AliasRegistry()
        let a = reg.alias(for: url("s.m3u8"), role: .subtitles, attributes: ["LANGUAGE": "fr"])
        #expect(a.alias == "subs-fr")
    }

    @Test("iframe-720p from RESOLUTION 1280x720")
    func iframeFromResolution() {
        var reg = AliasRegistry()
        let a = reg.alias(for: url("i.m3u8"), role: .iframe, attributes: ["RESOLUTION": "1280x720"])
        #expect(a.alias == "iframe-720p")
    }

    @Test("audio-english via NAME when no LANGUAGE")
    func audioFromName() {
        var reg = AliasRegistry()
        let a = reg.alias(for: url("a.m3u8"), role: .audio, attributes: ["NAME": "English"])
        #expect(a.alias == "audio-english")
    }

    @Test("LANGUAGE takes precedence over NAME for audio")
    func languagePrecedence() {
        var reg = AliasRegistry()
        let a = reg.alias(for: url("a.m3u8"), role: .audio, attributes: ["LANGUAGE": "de", "NAME": "German"])
        #expect(a.alias == "audio-de")
    }

    // MARK: - Indexed fallback

    @Test("V1 fallback when video has no RESOLUTION")
    func videoIndexedFallback() {
        var reg = AliasRegistry()
        let a = reg.alias(for: url("v.m3u8"), role: .video, attributes: [:])
        #expect(a.alias == "V1")
    }

    @Test("A1 fallback when audio has no LANGUAGE or NAME")
    func audioIndexedFallback() {
        var reg = AliasRegistry()
        let a = reg.alias(for: url("a.m3u8"), role: .audio, attributes: [:])
        #expect(a.alias == "A1")
    }

    @Test("S1 fallback when subtitles has no LANGUAGE or NAME")
    func subsIndexedFallback() {
        var reg = AliasRegistry()
        let a = reg.alias(for: url("s.m3u8"), role: .subtitles, attributes: [:])
        #expect(a.alias == "S1")
    }

    @Test("I1 fallback when iframe has no RESOLUTION")
    func iframeIndexedFallback() {
        var reg = AliasRegistry()
        let a = reg.alias(for: url("i.m3u8"), role: .iframe, attributes: [:])
        #expect(a.alias == "I1")
    }

    @Test("M1 fallback for master role")
    func masterIndexedFallback() {
        var reg = AliasRegistry()
        let a = reg.alias(for: url("master.m3u8"), role: .master, attributes: [:])
        #expect(a.alias == "M1")
    }

    @Test("indexed counter increments: V1, V2 for two videos without resolution")
    func indexedCounterIncrements() {
        var reg = AliasRegistry()
        let a1 = reg.alias(for: url("v1.m3u8"), role: .video, attributes: [:])
        let a2 = reg.alias(for: url("v2.m3u8"), role: .video, attributes: [:])
        #expect(a1.alias == "V1")
        #expect(a2.alias == "V2")
    }

    // MARK: - Dedup suffix

    @Test("video-1080p-2 for second 1080p variant — deterministic dedup")
    func dedupSuffix() {
        var reg = AliasRegistry()
        let a1 = reg.alias(for: url("v1.m3u8"), role: .video, attributes: ["RESOLUTION": "1920x1080"])
        let a2 = reg.alias(for: url("v2.m3u8"), role: .video, attributes: ["RESOLUTION": "1920x1080"])
        #expect(a1.alias == "video-1080p")
        #expect(a2.alias == "video-1080p-2")
    }

    @Test("dedup suffix increments beyond -2 for third collision")
    func dedupSuffixBeyondTwo() {
        var reg = AliasRegistry()
        reg.alias(for: url("v1.m3u8"), role: .video, attributes: ["RESOLUTION": "1920x1080"])
        reg.alias(for: url("v2.m3u8"), role: .video, attributes: ["RESOLUTION": "1920x1080"])
        let a3 = reg.alias(for: url("v3.m3u8"), role: .video, attributes: ["RESOLUTION": "1920x1080"])
        #expect(a3.alias == "video-1080p-3")
    }

    // MARK: - Stability

    @Test("same URL always returns same alias (idempotent)")
    func stability() {
        var reg = AliasRegistry()
        let u = url("v.m3u8")
        let a1 = reg.alias(for: u, role: .video, attributes: ["RESOLUTION": "1920x1080"])
        let a2 = reg.alias(for: u, role: .video, attributes: ["RESOLUTION": "1920x1080"])
        #expect(a1.alias == a2.alias)
        #expect(a1 == a2)
    }

    @Test("alias(for:) lookup returns registered alias")
    func lookup() {
        var reg = AliasRegistry()
        let u = url("v.m3u8")
        reg.alias(for: u, role: .video, attributes: ["RESOLUTION": "1280x720"])
        #expect(reg.alias(for: u)?.alias == "video-720p")
    }

    @Test("alias(for:) returns nil for unregistered URL")
    func lookupMiss() {
        let reg = AliasRegistry()
        #expect(reg.alias(for: url("unknown.m3u8")) == nil)
    }

    @Test("all returns aliases in registration order")
    func orderedAll() {
        var reg = AliasRegistry()
        reg.alias(for: url("a.m3u8"), role: .audio, attributes: ["LANGUAGE": "en"])
        reg.alias(for: url("v.m3u8"), role: .video, attributes: ["RESOLUTION": "1920x1080"])
        #expect(reg.all.map { $0.alias } == ["audio-en", "video-1080p"])
    }

    // MARK: - AliasRole bridge

    @Test("AliasRole(from:) maps all PlaylistRole cases")
    func aliasRoleBridge() {
        #expect(AliasRole(from: .variant)   == .video)
        #expect(AliasRole(from: .audio)     == .audio)
        #expect(AliasRole(from: .subtitles) == .subtitles)
        #expect(AliasRole(from: .iframe)    == .iframe)
    }
}
