//
//  PlaylistAlias.swift
//  ValistreamCore
//

import Foundation

/// Role a playlist plays in a stream — drives alias derivation (FR-024–026).
public enum AliasRole: String, Sendable, Equatable, CaseIterable {
    case video
    case audio
    case subtitles
    case iframe
    case master
    case unknown
}

/// A short, stable, human-meaningful label standing in for a full playlist URL
/// throughout the human-readable report (FR-024–026).
public struct PlaylistAlias: Sendable, Equatable {
    public let alias: String
    public let url: URL
    public let role: AliasRole
    public let attributes: [String: String]

    public init(alias: String, url: URL, role: AliasRole, attributes: [String: String]) {
        self.alias = alias
        self.url = url
        self.role = role
        self.attributes = attributes
    }
}

/// Session-scoped owner of the `[URL: PlaylistAlias]` map.
///
/// Assigns aliases on first sight; guarantees stability (same URL → same alias) and uniqueness
/// within a session (deterministic dedup suffix on collision).
public struct AliasRegistry: Sendable {
    private var byURL: [URL: PlaylistAlias] = [:]
    private var usedAliases: Set<String> = []
    private var roleCounters: [AliasRole: Int] = [:]
    private var ordered: [PlaylistAlias] = []

    public init() {}

    /// Idempotent — the same `url` always returns the same alias for this registry instance.
    @discardableResult
    public mutating func alias(for url: URL, role: AliasRole, attributes: [String: String] = [:]) -> PlaylistAlias {
        if let existing = byURL[url] { return existing }
        let candidate = descriptiveAlias(role: role, attributes: attributes).map { deduplicate($0) }
            ?? indexedAlias(role: role)
        usedAliases.insert(candidate)
        let entry = PlaylistAlias(alias: candidate, url: url, role: role, attributes: attributes)
        byURL[url] = entry
        ordered.append(entry)
        return entry
    }

    /// Returns the alias registered for `url`, or `nil` if not yet registered.
    public func alias(for url: URL) -> PlaylistAlias? {
        byURL[url]
    }

    /// All registered aliases in registration order.
    public var all: [PlaylistAlias] { ordered }

    // MARK: - Private

    private func descriptiveAlias(role: AliasRole, attributes: [String: String]) -> String? {
        switch role {
        case .video:     return resolutionAlias(prefix: "video", attributes: attributes)
        case .iframe:    return resolutionAlias(prefix: "iframe", attributes: attributes)
        case .audio:     return languageAlias(prefix: "audio", attributes: attributes)
        case .subtitles: return languageAlias(prefix: "subs", attributes: attributes)
        case .master, .unknown: return nil
        }
    }

    // Derives "prefix-Np" from the RESOLUTION attribute (e.g. "1920x1080" yields "1080p"), or nil.
    private func resolutionAlias(prefix: String, attributes: [String: String]) -> String? {
        guard let res = attributes["RESOLUTION"] else { return nil }
        let height = res.split(separator: "x").last.map(String.init) ?? res
        return "\(prefix)-\(height)p"
    }

    // Derives "prefix-id" from the LANGUAGE (preferred) or NAME attribute, normalized, or nil.
    private func languageAlias(prefix: String, attributes: [String: String]) -> String? {
        guard let id = attributes["LANGUAGE"] ?? attributes["NAME"] else { return nil }
        return "\(prefix)-\(normalized(id))"
    }

    private mutating func indexedAlias(role: AliasRole) -> String {
        let prefix: String
        switch role {
        case .video:     prefix = "V"
        case .audio:     prefix = "A"
        case .subtitles: prefix = "S"
        case .iframe:    prefix = "I"
        case .master:    prefix = "M"
        case .unknown:   prefix = "P"
        }
        let n = roleCounters[role, default: 0] + 1
        roleCounters[role] = n
        return deduplicate("\(prefix)\(n)")
    }

    private func deduplicate(_ base: String) -> String {
        guard usedAliases.contains(base) else { return base }
        var n = 2
        while usedAliases.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    private func normalized(_ s: String) -> String {
        s.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: "-")
    }
}

// MARK: - PlaylistRole bridge

extension AliasRole {
    /// Maps a `PlaylistRole` (from HLS playlist metadata) to the corresponding `AliasRole`.
    public init(from role: PlaylistRole) {
        switch role {
        case .variant:   self = .video
        case .audio:     self = .audio
        case .subtitles: self = .subtitles
        case .iframe:    self = .iframe
        }
    }
}
