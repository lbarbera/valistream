//
//  SessionArchive.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// Writes session artifacts to disk: verbatim playlist bodies and JSON metadata sidecars
/// (data-model.md Archive Layout, research §10).
///
/// Every store call is actor-isolated so concurrent monitoring tasks write without races.
/// The session folder is created on init; subsequent stores add content incrementally so
/// a crash or abort leaves everything written so far intact.
public actor SessionArchive {
    // MARK: - Nested types

    /// One entry in the artifact index: request id, final URL, and relative body/meta paths.
    public struct IndexEntry: Sendable, Equatable {
        public let requestId: String
        public let url: URL
        public let bodyPath: String
        public let metaPath: String

        public init(requestId: String, url: URL, bodyPath: String, metaPath: String) {
            self.requestId = requestId
            self.url = url
            self.bodyPath = bodyPath
            self.metaPath = metaPath
        }
    }



    // MARK: - Lets & Vars

    /// The created session folder — stable after init, accessible without actor isolation.
    public nonisolated let sessionFolder: URL

    /// Accumulated request index; grows as artifacts are stored.
    public private(set) var artifactIndex: [IndexEntry] = []

    private var requestCounter = 0
    private var refreshCounts: [String: Int] = [:]



    // MARK: - Lifecycle

    public init(sessionID: String, outputDir: URL) throws {
        self.sessionFolder = outputDir.appending(path: sessionID, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionFolder, withIntermediateDirectories: true)
    }



    // MARK: - Public

    /// Archives one playlist fetch: writes the verbatim body and a JSON sidecar.
    ///
    /// Body at `playlists/<playlistID>/NNNNNN.m3u8`; sidecar at
    /// `playlists/<playlistID>/NNNNNN.meta.json`. Returns the populated `ArtifactRecord` whose
    /// `bodyPath` is relative to the session folder.
    @discardableResult
    public func store(result: FetchResult, playlistID: String) throws -> ArtifactRecord {
        requestCounter += 1
        let requestId = "r\(requestCounter)"
        let refreshIndex = refreshCounts[playlistID, default: 0]
        refreshCounts[playlistID] = refreshIndex + 1

        let paddedIndex = String(format: "%06d", refreshIndex)
        let playlistDir = sessionFolder.appending(path: "playlists/\(playlistID)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: playlistDir, withIntermediateDirectories: true)

        let bodyRelPath = "playlists/\(playlistID)/\(paddedIndex).m3u8"
        let metaRelPath = "playlists/\(playlistID)/\(paddedIndex).meta.json"

        try result.body.write(to: sessionFolder.appending(path: bodyRelPath))
        let record = ArtifactRecord(requestId: requestId, bodyPath: bodyRelPath, result: result)
        let metaData = try Finding.jsonEncoder.encode(record)
        try metaData.write(to: sessionFolder.appending(path: metaRelPath))

        artifactIndex.append(IndexEntry(requestId: requestId, url: result.url, bodyPath: bodyRelPath, metaPath: metaRelPath))
        return record
    }
}
