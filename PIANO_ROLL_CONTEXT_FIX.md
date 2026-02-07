# Issue #69 Fix: Piano Roll Context Awareness

## Summary
Added "Reveal in Timeline" feature to Piano Roll panel following professional DAW standards (Logic Pro X, Ableton Live, Cubase). Piano Roll header now shows bar position and provides one-click navigation to scroll the timeline to the edited region.

## Issue
https://github.com/cgcardona/Stori/issues/69

## Root Cause Analysis

The issue was a **UX/context awareness problem**, not a technical bug:

- Piano Roll edits a specific MIDI region (e.g., at bar 20)
- Timeline may be scrolled to a different position (e.g., bar 50)
- User loses spatial context: "Where am I in the arrangement?"
- **No way to quickly navigate back to see the region in timeline context**

This is a **standard DAW workflow issue** - all professional DAWs solve it with "Reveal in Timeline" features.

## Solution (Following Industry Standards)

### What Professional DAWs Do:
- ❌ DON'T sync scroll between Timeline and Piano Roll (different zoom levels/purposes)
- ✅ DO provide "Reveal in Timeline" / "Show in Arrangement" button
- ✅ DO show bar position in editor headers
- ✅ DO offer keyboard shortcuts for quick navigation

### Our Implementation:

#### 1. Bar Position Display (NEW)
Piano Roll header now shows: **"Bars 5-9"** 
- Calculated from region.startBeat and duration
- Tempo-aware (uses project's time signature)
- Works with odd time signatures (3/4, 5/4, 7/8, etc.)

#### 2. "Reveal in Timeline" Button (NEW)
- Icon button with "Reveal" label
- Keyboard shortcut: **⌘L** (industry standard)
- Tooltip: "Scroll timeline to show this region"
- Posts notification for loose coupling

#### 3. ScrollSync.scrollToBeat() Method (NEW)
- Centers region at 30% from left edge (Logic Pro X style)
- Works at any zoom level
- Handles edge cases (start of timeline, large projects)

#### 4. Timeline Notification Listener (NEW)
- Listens for `.revealBeatInTimeline` notification
- Calculates correct pixel offset based on current zoom
- Scrolls timeline to show the requested beat

## Implementation Details

### Files Modified:

1. **`Stori/Core/Utilities/ScrollSyncModel.swift`**
   - Added `scrollToBeat(_ beat:pixelsPerBeat:viewportWidth:)` method
   - Centers beat at 30% from left for optimal context viewing

2. **`Stori/Features/MIDI/MIDISheetViews.swift`**
   - Enhanced `trackRoutingHeader` with bar position display
   - Added "Reveal in Timeline" button with ⌘L shortcut
   - Posts notification for loose coupling
   - Added `onRevealInTimeline` callback parameter (for future direct wiring)

3. **`Stori/Features/Timeline/IntegratedTimelineView.swift`**
   - Added `.onReceive` listener for `.revealBeatInTimeline` notification
   - Calculates pixel offset and calls `scrollSync.scrollToBeat()`

4. **`Stori/Features/VirtualKeyboard/VirtualKeyboardView.swift`**
   - Added `.revealBeatInTimeline` notification name to extension

### Design Decisions:

1. **Notification Pattern**: Used for loose coupling - Piano Roll doesn't need direct reference to Timeline
2. **30% Positioning**: Matches Logic Pro X - provides context before and after the region
3. **Keyboard Shortcut ⌘L**: Industry standard for "Reveal" actions
4. **Bar Display Format**: "Bars 5-9" - clear, concise, professional
5. **No Auto-Scroll**: DON'T automatically sync scroll (users expect independent control)

## User Experience Flow

**Before:**
1. User opens Piano Roll for region at bar 20
2. Timeline scrolled to bar 50
3. User confused: "Where is this region in my arrangement?"
4. Must manually scroll timeline to find it

**After:**
1. User opens Piano Roll for region at bar 20
2. Header shows: "Track Name • Region Name • **Bars 20-24** • [Reveal]"
3. User clicks [Reveal] or presses ⌘L
4. Timeline instantly scrolls to show bar 20 at optimal viewing position

## Tests Added

**File**: `StoriTests/Features/PianoRollContextAwarenessTests.swift`

- ✅ testScrollToBeatCentersAt30Percent
- ✅ testScrollToBeatClampsToZero
- ✅ testScrollToBeatWorksAtDifferentZooms (0.5x, 1x, 2x, 4x)
- ✅ testMultipleScrollToBeatCalls
- ✅ testBarPositionCalculation4_4 (various cases)
- ✅ testBarPositionCalculationOddTime (7/8, 5/4, 3/4)
- ✅ testRevealBeatNotificationTriggersScroll
- ✅ testBarDisplayAtVariousTimeSignatures
- ✅ testScrollToBeatLargeNumbers (long projects)
- ✅ testScrollToBeatDifferentViewportWidths
- ✅ testRegionSpanningMultipleBars

## DRY Principles Followed

- ✅ Reused existing ScrollSyncModel (no new scroll state)
- ✅ Used existing notification system (no new messaging layer)
- ✅ Leveraged existing playhead sync via AudioEngine (no duplication)
- ✅ Bar calculation uses existing TimeSignature model
- ✅ Keyboard shortcut uses SwiftUI's built-in `.keyboardShortcut()`

## Audiophile / Professional Impact

### Before
- Loss of spatial awareness when editing
- Must manually hunt for regions in timeline
- Slows down workflow
- Frustrating for arranging/composition

### After
- Instant context awareness ("Bars 20-24")
- One-click navigation to timeline position
- Matches behavior of Logic Pro X, Cubase, Pro Tools
- Professional, expected workflow

## Follow-Up Opportunities

1. **"Follow Playhead" toggle** - Auto-scroll timeline during playback (may already work via `catchPlayheadEnabled`)
2. **Mini-map in Piano Roll** - Visual indicator showing position in full arrangement
3. **Breadcrumb navigation** - "Timeline > Track Name > Region Name" clickable path
4. **Sync to playhead** - Option to jump timeline to current playhead position

## Verification

✅ **No linter errors** - Clean compilation  
✅ **DRY principles** - Reused existing infrastructure  
✅ **Industry standard** - Matches Logic Pro X / Cubase UX  
✅ **Comprehensive tests** - 11 test cases covering edge cases  
✅ **Keyboard shortcut** - ⌘L (discoverable, standard)  
✅ **Loose coupling** - Notification pattern prevents tight dependencies  

## Status
**READY FOR TESTING**
