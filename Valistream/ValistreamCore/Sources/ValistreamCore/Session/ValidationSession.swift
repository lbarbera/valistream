//
//  ValidationSession.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// Orchestrates one run of the validator against one stream URL (data-model.md ValidationSession).
///
/// The session owns all mutable run state — lifecycle, findings, discovered playlists, per-playlist
/// monitor state — as an actor so the concurrent live-monitoring tasks can update it without data
/// races (research §9). Status and findings flow out through the ``events`` stream for the CLI to
/// render (FR-009). One-shot validation (US1) and live monitoring (US2) are both driven by ``run()``.
public actor ValidationSession {
    // MARK: - Lets & Vars

    public let id: String
    public let inputURL: URL
    public let config: SessionConfig

    /// The live event stream consumed by the presentation layer.
    public nonisolated let events: AsyncStream<SessionEvent>

    private let fetcher: any StreamFetching
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let selectPlaylists: (@Sendable ([PlaylistSelection.Candidate]) async -> [PlaylistSelection.Candidate])?
    private let continuation: AsyncStream<SessionEvent>.Continuation
    private let loader: PlaylistLoader
    private let engine: RuleEngine
    private let classifier = StreamClassifier()
    private let continuityChecker = ContinuityChecker()
    private let stalenessDetector = StalenessDetector()

    private var lifecycle = SessionLifecycle()
    private var findings: [Finding] = []
    private var recordedSignatures: Set<String> = []
    private var monitorStates: [String: MonitorState] = [:]
    private var streamKind: StreamKind?
    private var findingCounter = 0
    private var stopRequested = false



    // MARK: - Lifecycle

    public init(
        inputURL: URL,
        config: SessionConfig,
        fetcher: any StreamFetching,
        id: String? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        selectPlaylists: (@Sendable ([PlaylistSelection.Candidate]) async -> [PlaylistSelection.Candidate])? = nil
    ) {
        self.inputURL = inputURL
        self.config = config
        self.fetcher = fetcher
        self.now = now
        self.sleep = sleep
        self.selectPlaylists = selectPlaylists
        self.id = id ?? Self.makeSessionID(now())
        self.loader = PlaylistLoader(fetcher: fetcher)
        self.engine = RuleEngine(rules: [
            RFC8216MasterRules(),
            RFC8216MediaRules(),
            AppleAuthoringRules(),
        ])
        (self.events, self.continuation) = AsyncStream.makeStream()
    }



    // MARK: - Public

    /// The current lifecycle state.
    public var state: SessionState {
        lifecycle.state
    }

    /// All findings recorded so far, in order.
    public var recordedFindings: [Finding] {
        findings
    }

    /// The stream classification once determined.
    public var classification: StreamKind? {
        streamKind
    }

    /// The latest monitor state per playlist id (FR-009).
    public var playlistMonitorStates: [String: MonitorState] {
        monitorStates
    }

    /// Requests a graceful, user-initiated stop (Ctrl-C). Monitoring unwinds and the session ends in
    /// the `aborted` state with a summary still produced (FR-015). Cancel the task running ``run()``
    /// alongside this call to interrupt in-flight sleeps promptly.
    public func abort() {
        stopRequested = true
    }

    /// Runs the session: fetch the master (or direct media) playlist, fetch every referenced media
    /// playlist, classify the stream, and evaluate all rules (US1). For live/event streams it then
    /// monitors the selected playlists on player-accurate cadence until stopped or the time limit
    /// expires (US2). Findings and status flow out on ``events`` as they occur.
    public func run() async {
        setState(.fetchingMaster)
        let rootLoad = await loader.load(inputURL)
        for violation in rootLoad.deliveryViolations {
            record(violation, resource: inputURL)
        }
        guard let rootPlaylist = rootLoad.playlist else {
            setState(.failed)
            return
        }

        setState(.validatingInitial)

        var references: [PlaylistReference] = []
        var mediaLoads: [LoadedPlaylist] = []
        if case .master(let master) = rootPlaylist {
            references = loader.mediaReferences(in: master)
            for reference in references {
                mediaLoads.append(await loader.load(reference.url, role: reference.role))
            }
        }
        else {
            mediaLoads.append(rootLoad)
        }

        let representativeMedia = mediaLoads.lazy.compactMap { $0.playlist?.media }.first
        let kind = representativeMedia.map { classifier.classify($0) } ?? .vod
        setClassification(kind)

        if case .master = rootPlaylist {
            evaluate(playlist: rootPlaylist, tokens: rootLoad.tokens, resource: inputURL, kind: kind)
        }

        for load in mediaLoads {
            guard let playlist = load.playlist else {
                for violation in load.deliveryViolations {
                    record(violation, resource: load.url)
                }
                continue
            }
            evaluate(playlist: playlist, tokens: load.tokens, resource: load.url, kind: kind)
            if let media = playlist.media {
                for violation in classifier.infoViolations(for: media, tokens: load.tokens) {
                    record(violation, resource: load.url)
                }
            }
        }

        // VOD never monitors — it has ended by definition (FR-005).
        guard kind != .vod else {
            finish()
            return
        }

        setState(.selectingPlaylists)
        let directMediaURL = rootPlaylist.media != nil ? inputURL : nil
        let candidates = PlaylistSelection.candidates(references: references, directMediaURL: directMediaURL)
        let selected: [PlaylistSelection.Candidate]
        if config.nonInteractive == false, let selectPlaylists {
            selected = await selectPlaylists(candidates)
        }
        else {
            selected = PlaylistSelection.resolve(candidates, patterns: config.selectionPatterns)
        }
        guard selected.isEmpty == false else {
            recordSelectionEmptyNote()
            finish()
            return
        }

        let loadedByURL = Dictionary(mediaLoads.map { ($0.url, $0) }, uniquingKeysWith: { _, last in last })

        setState(.monitoring)
        await monitor(selected: selected, loadedByURL: loadedByURL, kind: kind)

        if stopRequested {
            setState(.aborted)
        }
        else {
            finish()
        }
    }



    // MARK: - Internal

    /// Transitions the lifecycle and emits a `stateChanged` event. Invalid transitions are ignored
    /// defensively so a late abort/finish cannot crash the engine.
    func setState(_ target: SessionState) {
        guard (try? lifecycle.transition(to: target)) != nil else { return }
        continuation.yield(.stateChanged(target))
        if target.isTerminal {
            continuation.finish()
        }
    }

    /// Records the stream classification and emits it.
    func setClassification(_ kind: StreamKind) {
        streamKind = kind
        continuation.yield(.streamClassified(kind))
    }

    /// Mints a ``Finding`` from a rule violation, assigning a session-unique id and timestamp,
    /// records it, and emits it on the event stream.
    @discardableResult
    func record(_ violation: RuleViolation, resource: URL, refreshIndex: Int? = nil) -> Finding {
        findingCounter += 1
        let finding = Finding(
            id: "f\(findingCounter)",
            ruleId: violation.ruleId,
            source: violation.source,
            severity: violation.severity,
            category: violation.category,
            resource: resource,
            location: violation.location,
            refreshIndex: refreshIndex,
            observedAt: now(),
            message: violation.message,
            context: violation.context
        )
        findings.append(finding)
        recordedSignatures.insert(Self.signature(violation, resource: resource))
        continuation.yield(.finding(finding))
        return finding
    }

    /// Records a violation only if an identical one has not already been recorded, so re-validating
    /// a structurally unchanged playlist on every refresh does not flood the report.
    func recordIfNew(_ violation: RuleViolation, resource: URL, refreshIndex: Int? = nil) {
        guard recordedSignatures.contains(Self.signature(violation, resource: resource)) == false else {
            return
        }
        record(violation, resource: resource, refreshIndex: refreshIndex)
    }

    /// Updates a playlist's monitor state and emits the change (de-duplicating no-op updates).
    func setMonitorState(_ playlistID: String, _ state: MonitorState) {
        guard monitorStates[playlistID] != state else { return }
        monitorStates[playlistID] = state
        continuation.yield(.monitorStateChanged(playlistID: playlistID, state: state))
    }

    /// The fetcher this session uses (for the flow tasks wired by US1+).
    var streamFetcher: any StreamFetching {
        fetcher
    }



    // MARK: - Private

    /// Monitors every selected playlist concurrently, one structured child task each, until all
    /// stop (endlist, time limit, or abort). The discarding task group propagates cancellation to
    /// every monitor so a Ctrl-C unwinds the whole session cleanly (research §9, FR-015).
    private func monitor(
        selected: [PlaylistSelection.Candidate],
        loadedByURL: [URL: LoadedPlaylist],
        kind: StreamKind
    ) async {
        let deadline = config.timeLimit.map { now().addingTimeInterval($0.seconds) }
        await withDiscardingTaskGroup { group in
            for candidate in selected {
                let initial = loadedByURL[candidate.url]
                group.addTask {
                    await self.monitorPlaylist(candidate, initial: initial, kind: kind, deadline: deadline)
                }
            }
        }
    }

    /// The reload loop for one playlist: sleep on cadence, refetch, re-validate, and check
    /// continuity + staleness against the previous observation (FR-006/FR-007).
    private func monitorPlaylist(
        _ candidate: PlaylistSelection.Candidate,
        initial: LoadedPlaylist?,
        kind: StreamKind,
        deadline: Date?
    ) async {
        guard var previous = initial?.playlist?.media else {
            setMonitorState(candidate.id, .stopped)
            return
        }
        setMonitorState(candidate.id, .monitoring)

        var refreshIndex = 0
        var lastChangedAt = now()
        var lastChanged = true
        var targetDuration = duration(previous.targetDuration)

        while stopRequested == false {
            if previous.hasEndList { break }
            if let deadline, now() >= deadline { break }

            let scheduler = RefreshScheduler(targetDuration: targetDuration)
            let delay = refreshIndex == 0 ? scheduler.initialDelay : scheduler.nextDelay(didChange: lastChanged)
            do {
                try await sleep(delay)
            }
            catch {
                break  // cancelled — graceful stop
            }
            if stopRequested { break }
            if let deadline, now() >= deadline { break }

            refreshIndex += 1
            let load = await loader.load(candidate.url, role: candidate.role)
            for violation in load.deliveryViolations {
                record(violation, resource: candidate.url, refreshIndex: refreshIndex)
            }
            guard let media = load.playlist?.media else {
                lastChanged = false
                evaluateStaleness(candidate, since: lastChangedAt, target: targetDuration, refreshIndex: refreshIndex)
                continue
            }

            evaluateStructural(load: load, kind: kind, refreshIndex: refreshIndex)
            for violation in continuityChecker.check(previous: previous, current: media) {
                record(violation, resource: candidate.url, refreshIndex: refreshIndex)
            }

            let changed = media != previous
            if changed {
                lastChangedAt = now()
                targetDuration = duration(media.targetDuration)
                setMonitorState(candidate.id, .monitoring)
            }
            else {
                evaluateStaleness(candidate, since: lastChangedAt, target: targetDuration, refreshIndex: refreshIndex)
            }
            lastChanged = changed
            previous = media
        }

        setMonitorState(candidate.id, .stopped)
    }

    /// Re-evaluates structural rules and info findings for a refresh, recording only findings not
    /// already seen for this resource.
    private func evaluateStructural(load: LoadedPlaylist, kind: StreamKind, refreshIndex: Int) {
        guard let playlist = load.playlist else { return }
        let context = RuleContext(
            playlist: playlist,
            tokens: load.tokens,
            resource: load.url,
            streamKind: kind,
            refreshIndex: refreshIndex
        )
        for violation in engine.evaluate(context) {
            recordIfNew(violation, resource: load.url, refreshIndex: refreshIndex)
        }
        if let media = playlist.media {
            for violation in classifier.infoViolations(for: media, tokens: load.tokens) {
                recordIfNew(violation, resource: load.url, refreshIndex: refreshIndex)
            }
        }
    }

    /// Records a staleness finding and updates the playlist's monitor state when it has gone
    /// unrefreshed past the liveness thresholds (FR-007).
    private func evaluateStaleness(
        _ candidate: PlaylistSelection.Candidate,
        since lastChangedAt: Date,
        target: Duration,
        refreshIndex: Int
    ) {
        let staleFor = Duration.seconds(now().timeIntervalSince(lastChangedAt))
        guard let violation = stalenessDetector.violation(staleFor: staleFor, targetDuration: target) else {
            return
        }
        record(violation, resource: candidate.url, refreshIndex: refreshIndex)
        setMonitorState(candidate.id, violation.severity == .error ? .staleError : .staleWarning)
    }

    private func recordSelectionEmptyNote() {
        record(
            RuleViolation(
                ruleId: "TOOL.selection-empty",
                source: .tool,
                severity: .info,
                category: .delivery,
                message: "No playlists were selected for monitoring; the session finished after initial validation."
            ),
            resource: inputURL
        )
    }

    private func evaluate(playlist: Playlist, tokens: [M3U8Token], resource: URL, kind: StreamKind) {
        let context = RuleContext(playlist: playlist, tokens: tokens, resource: resource, streamKind: kind)
        for violation in engine.evaluate(context) {
            record(violation, resource: resource)
        }
    }

    private func finish() {
        setState(.finishing)
        setState(.completed)
    }

    /// Cadence baseline used when a media playlist omits `EXT-X-TARGETDURATION`.
    private static let defaultTargetDuration = Duration.seconds(6)

    private func duration(_ seconds: Double?) -> Duration {
        seconds.map { .seconds($0) } ?? Self.defaultTargetDuration
    }

    private static func signature(_ violation: RuleViolation, resource: URL) -> String {
        let line = violation.location?.line.map(String.init) ?? "-"
        return "\(resource.absoluteString)|\(violation.ruleId)|\(line)|\(violation.message)"
    }

    private static func makeSessionID(_ date: Date) -> String {
        let stamp = date.formatted(
            .verbatim(
                "\(year: .extended(minimumLength: 4))\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
                timeZone: .current,
                calendar: .current
            )
        )
        let random = String(UInt32.random(in: 0..<0xFFFF), radix: 16)
        return "\(stamp)-\(random)"
    }
}
