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
            if deadlinePassed(deadline) { break }

            let scheduler = RefreshScheduler(targetDuration: targetDuration)
            let delay = refreshIndex == 0 ? scheduler.initialDelay : scheduler.nextDelay(didChange: lastChanged)

            // Verbose: emit refresh-scheduled trace before sleeping (FR-015b).
            if config.verboseEvents {
                let delaySecs = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
                continuation.yield(.trace(.refreshScheduled(playlistID: candidate.id, delaySeconds: delaySecs)))
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
            let snapshotLabel = SnapshotID.label(id: candidate.id, index: refreshIndex)

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

            await archiveFetch(load.result, playlistID: candidate.id)

            // Verbose: continuity comparison trace (emitted before checking for violations).
            if config.verboseEvents, load.playlist?.media != nil {
                let olderLabel = SnapshotID.label(id: candidate.id, index: refreshIndex - 1)
                continuation.yield(.trace(.continuityCompare(
                    olderSnapshotID: olderLabel,
                    newerSnapshotID: snapshotLabel
                )))
            }

            // Verbose: stored trace (after archiveFetch which writes the file).
            if config.verboseEvents, load.result.outcome == .success {
                let archivePath = "playlists/\(candidate.id)/\(snapshotLabel).m3u8"
                continuation.yield(.trace(.stored(snapshotID: snapshotLabel, archivePath: archivePath)))
            }

            incrementRefreshCount(candidate.id)
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
                    setMonitorState(candidate.id, .monitoring)
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
                playlistID: candidate.id,
                index: refreshIndex,
                errors: errorsThisRefresh,
                warnings: warnsThisRefresh
            ))

            let alias = aliasRegistry.alias(for: candidate.url)?.alias ?? candidate.id
            let totalRefreshes = sessionRefreshTotal
            continuation.yield(.activity(ActivityProgress(
                activity: "monitoring live",
                completed: refreshIndex,
                refreshes: refreshIndex,
                aliasInScope: alias,
                sessionRefreshTotal: totalRefreshes
            )))

            // T038: write both reports atomically after each refresh cycle (FR-021, FR-022).
            await writeReport(interruption: nil)
        }

        setMonitorState(candidate.id, .stopped)
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
        setMonitorState(candidate.id, violation.severity == .error ? .staleError : .staleWarning)
    }
}
