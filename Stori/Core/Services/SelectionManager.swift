//
//  SelectionManager.swift
//  Stori
//
//  Multi-region selection state management for Phase 1 multi-selection
//

import Foundation
import SwiftUI
import Combine
import Observation

// PERFORMANCE: Using @Observable for fine-grained SwiftUI updates
// Only views that read specific properties will re-render when those properties change
@Observable
@MainActor
final class SelectionManager {
    // MARK: - Audio Region Multi-Selection
    var selectedRegionIds: Set<UUID> = []
    var selectionAnchor: UUID? = nil
    var isMarqueeActive: Bool = false
    var marqueeRect: CGRect = .zero
    
    // MARK: - MIDI Region Selection
    // Separate from audio to allow independent selection without cascade re-renders
    var selectedMIDIRegionId: UUID? = nil


    // MARK: - Audio Region Methods
    
    func isSelected(_ id: UUID) -> Bool { 
        selectedRegionIds.contains(id) 
    }

    func clear() {
        // Only update if needed to avoid unnecessary observer triggers
        if !selectedRegionIds.isEmpty {
            selectedRegionIds.removeAll()
        }
        if selectionAnchor != nil {
            selectionAnchor = nil
        }
    }
    
    /// Clear all selections (both audio and MIDI)
    func clearAll() {
        if !selectedRegionIds.isEmpty {
            selectedRegionIds.removeAll()
        }
        if selectionAnchor != nil {
            selectionAnchor = nil
        }
        if selectedMIDIRegionId != nil {
            selectedMIDIRegionId = nil
        }
    }

    func selectOnly(_ id: UUID) {
        // Only update if needed to avoid unnecessary observer triggers
        if selectedRegionIds != [id] {
            selectedRegionIds = [id]
            selectionAnchor = id
        }
        // Only clear MIDI selection if it's set
        if selectedMIDIRegionId != nil {
            selectedMIDIRegionId = nil
        }
    }

    func toggle(_ id: UUID) {
        if selectedRegionIds.contains(id) { 
            selectedRegionIds.remove(id)
        } else { 
            selectedRegionIds.insert(id)
            // Clear MIDI selection when audio is selected
            selectedMIDIRegionId = nil
        }
        if selectionAnchor == nil { 
            selectionAnchor = id 
        }
    }

    func selectRange(in orderedIds: [UUID], to id: UUID) {
        guard let anchor = selectionAnchor,
              let a = orderedIds.firstIndex(of: anchor),
              let b = orderedIds.firstIndex(of: id) else {
            return selectOnly(id)
        }
        let lo = min(a, b), hi = max(a, b)
        selectedRegionIds = Set(orderedIds[lo...hi])
        // Clear MIDI selection when audio is selected
        selectedMIDIRegionId = nil
    }

    func selectAll(_ allIds: [UUID]) {
        selectedRegionIds = Set(allIds)
        selectionAnchor = allIds.first
        // Clear MIDI selection when audio is selected
        selectedMIDIRegionId = nil
    }
    
    // MARK: - MIDI Region Methods
    
    func isMIDISelected(_ id: UUID) -> Bool {
        selectedMIDIRegionId == id
    }
    
    func selectMIDIRegion(_ id: UUID) {
        // Only update if changed to avoid unnecessary observer triggers
        guard selectedMIDIRegionId != id else { return }
        
        selectedMIDIRegionId = id
        
        // Only clear audio selection if it's not already empty
        // This avoids triggering selectedRegionIds observers unnecessarily
        if !selectedRegionIds.isEmpty {
            selectedRegionIds.removeAll()
            selectionAnchor = nil
        }
    }
    
    func clearMIDISelection() {
        // Only update if needed to avoid unnecessary observer triggers
        if selectedMIDIRegionId != nil {
            selectedMIDIRegionId = nil
        }
    }
    
    // MARK: - Cleanup
}
