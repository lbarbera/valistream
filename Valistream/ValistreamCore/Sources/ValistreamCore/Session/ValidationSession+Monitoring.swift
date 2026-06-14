//
//  ValidationSession+Monitoring.swift
//  ValistreamCore
//

import Foundation

extension ValidationSession {

    // MARK: - Live monitoring

    func monitor(
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

    func monitorPlaylist(
        _ candidate: PlaylistSelection.Candidate,
        initial: LoadedPlaylist?,
        kind: StreamKind,
        deadline: Date?
    ) async {
        // Live status, evidence, archive paths, and traces must all show the same presentation
        // ID used by the roster, legend, and report (FR-013-ID). Resolve it once from the registry
        // (populated at discovery in `run()`); fall back to the internal candidate ID only when the
        // playlist was never registered. Without this, monitoring lines leak the candidate ID
        // (`variant-0`, `audio-5`) instead of the presentation ID (`1080p_avc1`, `audio_en`).
        let presentationID = aliasRegistry.alias(for: candidate.url)?.alias ?? candidate.id

        guard var previous = initial?.playlist?.media else {
            setMonitorState(presentationID, .stopped)
            return
        }
        setMonitorState(presentationID, .monitoring)

        var refreshIndex = 0
        var lastChangedAt = now()
        var lastChanged = true
        var targetDuration = duration(previous.targetDuration)

        while stopRequested == false {
            if previous.hasEndList { break }
            if deadlinePassed(deadline) { break }

            let scheduler = RefreshScheduler(targetDuration: targetDuration)
            let delay = refreshIndex == 0 ? scheduler.initialDelay : scheduler.nextDelay(didChange: lastChanged)

            // Verbose: emit refresh-scheduled trace before sleeping (FR-015b).
            if config.verboseEvents {
                let delaySecs = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
                continuation.yield(.trace(.refreshScheduled(playlistID: presentationID, delaySeconds: delaySecs)))
            }

            do {
                try await sleep(delay)
            }
            catch {
                break
            }
            if stopRequested { break }
            if deadlinePassed(deadline) { break }

            refreshIndex += 1
            let snapshotLabel = SnapshotID.label(id: presentationID, index: refreshIndex)

            // Verbose: fetch intent trace (FR-015b).
            if config.verboseEvents {
                continuation.yield(.trace(.fetchIntent(snapshotID: snapshotLabel)))
            }

            let fetchStart = now()
            let load = await loader.load(candidate.url, role: candidate.role)

            // Verbose: fetch result trace.
            if config.verboseEvents {
                let durationMs = Int(now().timeIntervalSince(fetchStart) * 1_000)
                let httpStatus = load.result.metadata.httpStatus ?? 0
                let bytes = load.result.body.count
                continuation.yield(.trace(.fetchResult(
                    snapshotID: snapshotLabel,
                    httpStatus: httpStatus,
                    durationMs: durationMs,
                    bytes: bytes
                )))
            }

            await archiveFetch(load.result, requestURL: load.url, playlistID: presentationID)

            // Verbose: continuity comparison trace (emitted before checking for violations).
            if config.verboseEvents, load.playlist?.media != nil {
                let olderLabel = SnapshotID.label(id: presentationID, index: refreshIndex - 1)
                continuation.yield(.trace(.continuityCompare(
                    olderSnapshotID: olderLabel,
                    newerSnapshotID: snapshotLabel
                )))
            }

            // Verbose: stored trace (after archiveFetch which writes the file).
            if config.verboseEvents, load.result.outcome == .success {
                let archivePath = "playlists/\(presentationID)/\(snapshotLabel).m3u8"
                continuation.yield(.trace(.stored(snapshotID: snapshotLabel, archivePath: archivePath)))
            }

            incrementRefreshCount(presentationID)
            for violation in load.deliveryViolations {
                record(violation, resource: candidate.url, refreshIndex: refreshIndex)
            }
            var changed = false

            // Count findings produced by this refresh cycle (for .refreshCompleted).
            let findingsBefore = recordedFindings.count

            if let media = load.playlist?.media {
                evaluateStructural(load: load, kind: kind, refreshIndex: refreshIndex)
                for violation in continuityChecker.check(previous: previous, current: media) {
                    record(violation, resource: candidate.url, refreshIndex: refreshIndex)
                }
                changed = media != previous
                if changed {
                    lastChangedAt = now()
                    targetDuration = duration(media.targetDuration)
                    setMonitorState(presentationID, .monitoring)
                }
                previous = media

                // Verbose: per-playlist validation outcome.
                if config.verboseEvents {
                    let newFindings = recordedFindings.count - findingsBefore
                    if newFindings == 0 {
                        continuation.yield(.trace(.validationPlaylistOK(snapshotID: snapshotLabel)))
                    }
                    else {
                        let errors = recordedFindings.suffix(newFindings).count { $0.severity == .error }
                        let warns = recordedFindings.suffix(newFindings).count { $0.severity == .warning }
                        continuation.yield(.trace(.validationPlaylistFail(
                            snapshotID: snapshotLabel,
                            errorCount: errors,
                            warnCount: warns
                        )))
                    }
                }
            }
            lastChanged = changed
            if changed == false {
                evaluateStaleness(candidate, since: lastChangedAt, target: targetDuration, refreshIndex: refreshIndex)
            }

            // Emit per-refresh status line (normal+ tier, FR-015a, T021).
            let findingsThisRefresh = recordedFindings.count - findingsBefore
            let errorsThisRefresh = recordedFindings.suffix(findingsThisRefresh).count { $0.severity == .error }
            let warnsThisRefresh = recordedFindings.suffix(findingsThisRefresh).count { $0.severity == .warning }
            continuation.yield(.refreshCompleted(
                playlistID: presentationID,
                index: refreshIndex,
                errors: errorsThisRefresh,
                warnings: warnsThisRefresh
            ))

            let totalRefreshes = sessionRefreshTotal
            continuation.yield(.activity(ActivityProgress(
                activity: "monitoring live",
                completed: refreshIndex,
                refreshes: refreshIndex,
                aliasInScope: presentationID,
                sessionRefreshTotal: totalRefreshes
            )))

            // T038: write both reports atomically after each refresh cycle (FR-021, FR-022).
            await writeReport(interruption: nil)
        }

        setMonitorState(presentationID, .stopped)
    }

    /// Reports whether the monitoring deadline has passed, flagging `timeLimitExpired` if so.
    private func deadlinePassed(_ deadline: Date?) -> Bool {
        guard let deadline, now() >= deadline else { return false }
        timeLimitExpired = true
        return true
    }

    // MARK: - Rule evaluation

    func evaluateStructural(load: LoadedPlaylist, kind: StreamKind, refreshIndex: Int) {
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

    func evaluateStaleness(
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
        // Match the presentation ID used by every other monitoring event (FR-013-ID), not the
        // internal candidate ID.
        let presentationID = aliasRegistry.alias(for: candidate.url)?.alias ?? candidate.id
        setMonitorState(presentationID, violation.severity == .error ? .staleError : .staleWarning)
    }
}
