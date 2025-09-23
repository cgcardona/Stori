//
//  SelectionManager.swift
//  TellUrStoriDAW
//
//  Multi-region selection state management for Phase 1 multi-selection
//

import Foundation
import SwiftUI

@MainActor
final class SelectionManager: ObservableObject {
    // MARK: [V2-MULTISELECT] Region multi-selection
    @Published var selectedRegionIds: Set<UUID> = []
    @Published var selectionAnchor: UUID? = nil
    @Published var isMarqueeActive: Bool = false
    @Published var marqueeRect: CGRect = .zero

    func isSelected(_ id: UUID) -> Bool { 
        selectedRegionIds.contains(id) 
    }

    func clear() {
        selectedRegionIds.removeAll()
        selectionAnchor = nil
    }

    func selectOnly(_ id: UUID) {
        selectedRegionIds = [id]
        selectionAnchor = id
        print("🔄 SELECTION: Selected only \(id). Count: \(selectedRegionIds.count)")
        print("🔄 SELECTION: Current selection: \(selectedRegionIds)")
    }

    func toggle(_ id: UUID) {
        if selectedRegionIds.contains(id) { 
            selectedRegionIds.remove(id)
            print("🔄 SELECTION: Removed \(id) from selection. Count: \(selectedRegionIds.count)")
        } else { 
            selectedRegionIds.insert(id)
            print("🔄 SELECTION: Added \(id) to selection. Count: \(selectedRegionIds.count)")
        }
        if selectionAnchor == nil { 
            selectionAnchor = id 
        }
        print("🔄 SELECTION: Current selection: \(selectedRegionIds)")
    }

    func selectRange(in orderedIds: [UUID], to id: UUID) {
        guard let anchor = selectionAnchor,
              let a = orderedIds.firstIndex(of: anchor),
              let b = orderedIds.firstIndex(of: id) else {
            print("🔄 SELECTION: Range selection failed - falling back to selectOnly. Anchor: \(selectionAnchor?.uuidString.prefix(8) ?? "nil"), Target: \(id.uuidString.prefix(8))")
            return selectOnly(id)
        }
        let lo = min(a, b), hi = max(a, b)
        selectedRegionIds = Set(orderedIds[lo...hi])
        print("🔄 SELECTION: Selected range from \(anchor.uuidString.prefix(8)) to \(id.uuidString.prefix(8)). Count: \(selectedRegionIds.count)")
        print("🔄 SELECTION: Current selection: \(selectedRegionIds)")
    }

    func selectAll(_ allIds: [UUID]) {
        selectedRegionIds = Set(allIds)
        selectionAnchor = allIds.first
    }
}
