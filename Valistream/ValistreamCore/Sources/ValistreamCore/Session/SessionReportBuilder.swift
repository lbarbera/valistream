//
//  SessionReportBuilder.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// Builds the final session report as `report.json` and `report.md` from a snapshot of session
/// state (data-model.md SessionReport, contracts/session-report.schema.json).
public struct SessionReportBuilder: Sendable {
    // MARK: - Nested types

    /// A summary of one playlist's participation in the session.
    public struct PlaylistInfo: Sendable {
        public let id: String
        public let kind: PlaylistKind
        public let role: PlaylistRole?
        public let url: URL
        public let selected: Bool
        public let excludedByChoice: Bool
        public let refreshCount: Int
        public let cadenceAdherence: Double?
        public let stalenessEpisodes: Int

        public init(
            id: String,
            kind: PlaylistKind,
            role: PlaylistRole?,
            url: URL,
            selected: Bool,
            excludedByChoice: Bool = false,
            refreshCount: Int,
            cadenceAdherence: Double? = nil,
            stalenessEpisodes: Int = 0
        ) {
            self.id = id
            self.kind = kind
            self.role = role
            self.url = url
            self.selected = selected
            self.excludedByChoice = excludedByChoice
            self.refreshCount = refreshCount
            self.cadenceAdherence = cadenceAdherence
            self.stalenessEpisodes = stalenessEpisodes
        }
    }

    /// A snapshot of session state needed to build the report.
    public struct SessionSnapshot: Sendable {
        public let id: String
        public let inputURL: URL
        public let startedAt: Date
        public let endedAt: Date
        public let state: SessionState
        public let config: SessionConfig
        public let streamKind: StreamKind?
        public let lowLatencyDetected: Bool
        public let encryptionDetected: Bool
        public let interruption: String?

        public init(
            id: String,
            inputURL: URL,
            startedAt: Date,
            endedAt: Date,
            state: SessionState,
            config: SessionConfig,
            streamKind: StreamKind?,
            lowLatencyDetected: Bool,
            encryptionDetected: Bool,
            interruption: String? = nil
        ) {
            self.id = id
            self.inputURL = inputURL
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.state = state
            self.config = config
            self.streamKind = streamKind
            self.lowLatencyDetected = lowLatencyDetected
            self.encryptionDetected = encryptionDetected
            self.interruption = interruption
        }
    }

    // Private Codable types matching contracts/session-report.schema.json

    private struct Report: Encodable {
        let schemaVersion: Int
        let session: SessionPayload
        let stream: StreamPayload
        let playlists: [PlaylistPayload]
        let findings: [Finding]
        let segmentAudit: SegmentAuditPayload?
        let summary: SummaryPayload
        let artifactIndex: [ArtifactIndexEntry]
    }

    private struct SessionPayload: Encodable {
        let id: String
        let inputUrl: String
        let startedAt: Date
        let endedAt: Date
        let state: String
        let interruption: String?
        let config: ConfigPayload
    }

    private struct ConfigPayload: Encodable {
        let segmentMode: Bool
        let bandwidthTolerance: Double
        let timeLimitSeconds: Double?
        let nonInteractive: Bool
        let outputDir: String
    }

    private struct StreamPayload: Encodable {
        let kind: String
        let lowLatencyDetected: Bool
        let encryptionDetected: Bool
    }

    private struct PlaylistPayload: Encodable {
        let id: String
        let kind: String
        let role: String?
        let url: String
        let selected: Bool
        let excludedByChoice: Bool?
        let refreshCount: Int
        let cadenceAdherence: Double?
        let stalenessEpisodes: Int?
    }

    private struct SummaryPayload: Encodable {
        let countsBySeverity: [String: Int]
        let countsByCategory: [String: Int]
        let countsBySource: [String: Int]
    }

    private struct ArtifactIndexEntry: Encodable {
        let requestId: String
        let url: String
        let bodyPath: String
        let metaPath: String
    }

    private struct SegmentAuditPayload: Encodable {
        let segmentsChecked: Int
        let segmentsExceedingTolerance: Int
        let downloadFailures: Int
        let bytesDownloaded: Int
    }



    // MARK: - Lifecycle

    public init() {}



    // MARK: - Public

    /// Encodes the report as JSON matching `session-report.schema.json` (schemaVersion 1).
    public func buildJSON(
        session: SessionSnapshot,
        playlists: [PlaylistInfo],
        findings: [Finding],
        artifactIndex: [SessionArchive.IndexEntry]
    ) throws -> Data {
        let report = buildReport(session: session, playlists: playlists, findings: findings, artifactIndex: artifactIndex)
        return try Finding.jsonEncoder.encode(report)
    }

    /// Renders a human-readable Markdown report.
    public func buildMarkdown(
        session: SessionSnapshot,
        playlists: [PlaylistInfo],
        findings: [Finding]
    ) -> String {
        var md = "# Valistream Session Report\n\n"
        md += "**Session ID**: \(session.id)  \n"
        md += "**Stream**: \(session.inputURL.absoluteString)  \n"
        md += "**Started**: \(session.startedAt.formatted(.iso8601))  \n"
        md += "**Ended**: \(session.endedAt.formatted(.iso8601))  \n"
        md += "**State**: \(session.state.rawValue)  \n"
        if let interruption = session.interruption {
            md += "**Interruption**: \(interruption)  \n"
        }
        md += "\n"

        md += "## Stream\n\n"
        md += "- **Kind**: \(session.streamKind?.rawValue ?? "unknown")\n"
        md += "- **Low-Latency HLS**: \(session.lowLatencyDetected ? "detected" : "not detected")\n"
        md += "- **Encryption**: \(session.encryptionDetected ? "detected" : "not detected")\n\n"

        let errors = findings.count { $0.severity == .error }
        let warnings = findings.count { $0.severity == .warning }
        let infos = findings.count { $0.severity == .info }
        md += "## Summary\n\n"
        md += "| Severity | Count |\n|----------|-------|\n"
        md += "| error | \(errors) |\n"
        md += "| warning | \(warnings) |\n"
        md += "| info | \(infos) |\n\n"

        md += "## Playlists\n\n"
        for playlist in playlists {
            let selectedLabel = playlist.selected ? "selected" : (playlist.excludedByChoice ? "excluded" : "not selected")
            md += "- **\(playlist.id)** (\(playlist.kind.rawValue)) — \(playlist.url.absoluteString)\n"
            md += "  - \(selectedLabel), refreshes: \(playlist.refreshCount)"
            if playlist.stalenessEpisodes > 0 {
                md += ", staleness episodes: \(playlist.stalenessEpisodes)"
            }
            md += "\n"
        }
        md += "\n"

        if findings.isEmpty == false {
            md += "## Findings\n\n"
            for finding in findings {
                md += "- **[\(finding.severity.rawValue)]** `\(finding.ruleId)` \(finding.message)\n"
                md += "  - Resource: \(finding.resource.absoluteString)\n"
            }
        }

        return md
    }



    // MARK: - Private

    private func buildReport(
        session: SessionSnapshot,
        playlists: [PlaylistInfo],
        findings: [Finding],
        artifactIndex: [SessionArchive.IndexEntry]
    ) -> Report {
        let configPayload = ConfigPayload(
            segmentMode: session.config.segmentMode,
            bandwidthTolerance: session.config.bandwidthTolerance,
            timeLimitSeconds: session.config.timeLimit.map { $0.seconds },
            nonInteractive: session.config.nonInteractive,
            outputDir: session.config.outputDir.path(percentEncoded: false)
        )

        let sessionPayload = SessionPayload(
            id: session.id,
            inputUrl: session.inputURL.absoluteString,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            state: session.state.rawValue,
            interruption: session.interruption,
            config: configPayload
        )

        let streamPayload = StreamPayload(
            kind: session.streamKind?.rawValue ?? "vod",
            lowLatencyDetected: session.lowLatencyDetected,
            encryptionDetected: session.encryptionDetected
        )

        let playlistPayloads = playlists.map { info in
            PlaylistPayload(
                id: info.id,
                kind: info.kind.rawValue,
                role: info.role?.rawValue,
                url: info.url.absoluteString,
                selected: info.selected,
                excludedByChoice: info.excludedByChoice ? true : nil,
                refreshCount: info.refreshCount,
                cadenceAdherence: info.cadenceAdherence,
                stalenessEpisodes: info.stalenessEpisodes > 0 ? info.stalenessEpisodes : nil
            )
        }

        let countsBySeverity = Dictionary(grouping: findings, by: { $0.severity.rawValue })
            .mapValues { $0.count }
        let countsByCategory = Dictionary(grouping: findings, by: { $0.category.rawValue })
            .mapValues { $0.count }
        let countsBySource = Dictionary(grouping: findings, by: { $0.source.rawValue })
            .mapValues { $0.count }

        let artifactPayloads = artifactIndex.map { entry in
            ArtifactIndexEntry(
                requestId: entry.requestId,
                url: entry.url.absoluteString,
                bodyPath: entry.bodyPath,
                metaPath: entry.metaPath
            )
        }

        return Report(
            schemaVersion: 1,
            session: sessionPayload,
            stream: streamPayload,
            playlists: playlistPayloads,
            findings: findings,
            segmentAudit: nil,
            summary: SummaryPayload(
                countsBySeverity: countsBySeverity,
                countsByCategory: countsByCategory,
                countsBySource: countsBySource
            ),
            artifactIndex: artifactPayloads
        )
    }
}
