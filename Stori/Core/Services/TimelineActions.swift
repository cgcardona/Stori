// TimelineActions.swift
import SwiftUI

struct TimelineActions: Sendable {
    var matchTempoToRegion: @Sendable (_ targetRegionId: UUID) -> Void = { _ in }
    var matchPitchToRegion: @Sendable (_ targetRegionId: UUID) -> Void = { _ in }
    var autoMatchSelectedRegions: @Sendable () -> Void = { }
    
    // 🎵 Audio Analysis Actions
    var analyzeRegion: @Sendable (_ regionId: UUID) -> Void = { _ in }
    
    // 🎧 Audio Export Actions
    var exportOriginalAudio: @Sendable (_ regionId: UUID) -> Void = { _ in }
    var exportProcessedAudio: @Sendable (_ regionId: UUID) -> Void = { _ in }
    var exportAudioComparison: @Sendable (_ regionId: UUID) -> Void = { _ in }
}

private struct TimelineActionsKey: EnvironmentKey {
    static let defaultValue = TimelineActions() // no-op defaults
}

extension EnvironmentValues {
    var timelineActions: TimelineActions {
        get { self[TimelineActionsKey.self] }
        set { self[TimelineActionsKey.self] = newValue }
    }
}
