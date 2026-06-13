//
//  SessionArchiveTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite(.tags(.archive))
struct SessionArchiveTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "SessionArchiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeResult(url: URL, body: String, status: Int = 200) -> FetchResult {
        FetchResult(
            url: url,
            body: Data(body.utf8),
            metadata: ResponseMetadata(
                requestHeaders: [:],
                requestStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
                responseEndedAt: Date(timeIntervalSince1970: 1_700_000_001),
                remoteAddress: nil,
                remotePort: nil,
                httpStatus: status,
                responseHeaders: [:],
                negotiatedProtocol: nil,
                redirectChain: []
            ),
            outcome: .success
        )
    }



    // MARK: - Init

    @Test("creates the session folder on init")
    func createsFolderOnInit() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let archive = try SessionArchive(sessionID: "test-001", outputDir: tmp)
        let folder = archive.sessionFolder

        #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
        #expect(folder.lastPathComponent == "test-001")
    }



    // MARK: - Store

    @Test("stores body at playlists/<id>/000000.m3u8 on first store")
    func storesBodyAtZeroPaddedPath() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let archive = try SessionArchive(sessionID: "s1", outputDir: tmp)
        let url = URL(string: "https://ex.com/v.m3u8")!
        let body = "#EXTM3U\n#EXT-X-ENDLIST\n"
        let result = makeResult(url: url, body: body)

        let record = try await archive.store(result: result, playlistID: "variant-0")

        let bodyPath = archive.sessionFolder.appending(path: "playlists/variant-0/000000.m3u8")
        #expect(FileManager.default.fileExists(atPath: bodyPath.path(percentEncoded: false)))
        let written = try Data(contentsOf: bodyPath)
        #expect(written == Data(body.utf8))
        #expect(record.bodyPath == "playlists/variant-0/000000.m3u8")
    }

    @Test("body is stored byte-exact")
    func bodyByteExact() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let archive = try SessionArchive(sessionID: "s2", outputDir: tmp)
        let bytes = Data([0xFF, 0x00, 0xAB, 0xCD])
        let result = FetchResult(
            url: URL(string: "https://ex.com/seg.ts")!,
            body: bytes,
            metadata: ResponseMetadata(
                requestHeaders: [:],
                requestStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
                responseEndedAt: Date(timeIntervalSince1970: 1_700_000_001),
                remoteAddress: nil,
                remotePort: nil,
                httpStatus: 200,
                responseHeaders: [:],
                negotiatedProtocol: nil,
                redirectChain: []
            ),
            outcome: .success
        )

        try await archive.store(result: result, playlistID: "p1")

        let bodyPath = archive.sessionFolder.appending(path: "playlists/p1/000000.m3u8")
        let written = try Data(contentsOf: bodyPath)
        #expect(written == bytes)
    }

    @Test("sidecar meta.json contains all ArtifactRecord fields")
    func sidecarContainsAllFields() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let archive = try SessionArchive(sessionID: "s3", outputDir: tmp)
        let url = URL(string: "https://ex.com/m.m3u8")!
        let result = makeResult(url: url, body: "#EXTM3U\n")

        let record = try await archive.store(result: result, playlistID: "media")

        let metaPath = archive.sessionFolder.appending(path: "playlists/media/000000.meta.json")
        #expect(FileManager.default.fileExists(atPath: metaPath.path(percentEncoded: false)))
        let metaData = try Data(contentsOf: metaPath)
        let decoded = try Finding.jsonDecoder.decode(ArtifactRecord.self, from: metaData)
        #expect(decoded.requestId == record.requestId)
        #expect(decoded.url == url)
        #expect(decoded.bodyPath == "playlists/media/000000.meta.json".replacingOccurrences(of: ".meta.json", with: ".m3u8"))
        #expect(decoded.bodyBytes == Data("#EXTM3U\n".utf8).count)
    }

    @Test("second store for same playlist increments to 000001.m3u8")
    func secondStoreIncrementsIndex() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let archive = try SessionArchive(sessionID: "s4", outputDir: tmp)
        let url = URL(string: "https://ex.com/live.m3u8")!

        try await archive.store(result: makeResult(url: url, body: "body0"), playlistID: "live")
        let record1 = try await archive.store(result: makeResult(url: url, body: "body1"), playlistID: "live")

        #expect(record1.bodyPath == "playlists/live/000001.m3u8")
        let body1Path = archive.sessionFolder.appending(path: "playlists/live/000001.m3u8")
        let written = try Data(contentsOf: body1Path)
        #expect(written == Data("body1".utf8))
    }

    @Test("different playlists get separate folders")
    func differentPlaylistsSeparateFolders() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let archive = try SessionArchive(sessionID: "s5", outputDir: tmp)
        let url = URL(string: "https://ex.com/p.m3u8")!

        try await archive.store(result: makeResult(url: url, body: "a"), playlistID: "variant-0")
        try await archive.store(result: makeResult(url: url, body: "b"), playlistID: "audio-0")

        let v0 = archive.sessionFolder.appending(path: "playlists/variant-0/000000.m3u8")
        let a0 = archive.sessionFolder.appending(path: "playlists/audio-0/000000.m3u8")
        #expect(FileManager.default.fileExists(atPath: v0.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: a0.path(percentEncoded: false)))
    }

    @Test("artifactIndex accumulates entries across stores")
    func artifactIndexAccumulates() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let archive = try SessionArchive(sessionID: "s6", outputDir: tmp)
        let url = URL(string: "https://ex.com/p.m3u8")!

        try await archive.store(result: makeResult(url: url, body: "a"), playlistID: "p1")
        try await archive.store(result: makeResult(url: url, body: "b"), playlistID: "p2")
        try await archive.store(result: makeResult(url: url, body: "c"), playlistID: "p1")

        let index = await archive.artifactIndex
        #expect(index.count == 3)
        #expect(index[0].requestId == "r1")
        #expect(index[1].requestId == "r2")
        #expect(index[2].requestId == "r3")
    }

    @Test("requestId counter is monotonically increasing across playlists")
    func requestIdMonotonic() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let archive = try SessionArchive(sessionID: "s7", outputDir: tmp)
        let url = URL(string: "https://ex.com/p.m3u8")!

        let r1 = try await archive.store(result: makeResult(url: url, body: "x"), playlistID: "master")
        let r2 = try await archive.store(result: makeResult(url: url, body: "y"), playlistID: "variant-0")
        #expect(r1.requestId == "r1")
        #expect(r2.requestId == "r2")
    }
}
