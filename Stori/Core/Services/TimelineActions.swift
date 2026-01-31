// TimelineActions.swift
import SwiftUI

struct TimelineActions {
    var matchTempoToRegion: (_ targetRegionId: UUID) -> Void = { _ in }
    var matchPitchToRegion: (_ targetRegionId: UUID) -> Void = { _ in }
    var autoMatchSelectedRegions: () -> Void = { }
    
    // 🎵 Audio Analysis Actions
    var analyzeRegion: (_ regionId: UUID) -> Void = { _ in }
    
    // 🎧 Audio Export Actions
    var exportOriginalAudio: (_ regionId: UUID) -> Void = { _ in }
    var exportProcessedAudio: (_ regionId: UUID) -> Void = { _ in }
    var exportAudioComparison: (_ regionId: UUID) -> Void = { _ in }
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
