// TimelineActions.swift
import SwiftUI

struct TimelineActions {
    var matchTempoToRegion: (_ targetRegionId: UUID) -> Void = { _ in }
    var matchPitchToRegion: (_ targetRegionId: UUID) -> Void = { _ in }
    var autoMatchSelectedRegions: () -> Void = { }
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
