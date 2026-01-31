//
//  SequencerPresets.swift
//  Stori
//
//  Encyclopedic rhythm library spanning all of human musical history!
//  304 patterns across 27 categories
//
//  Created by Stori on 12/20/24.
//

import SwiftUI

// MARK: - Preset Data Models

struct PresetData: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let description: String
    let bpm: String
    
    // Core Kit (Rows 1-8)
    let kicks: [Int]
    let snares: [Int]
    let closedHats: [Int]
    let openHats: [Int]
    let claps: [Int]
    let lowToms: [Int]
    let midToms: [Int]
    let highToms: [Int]
    
    // Extended Kit (Rows 9-16)
    let crashes: [Int]
    let rides: [Int]
    let rimshots: [Int]
    let cowbells: [Int]
    let shakers: [Int]
    let tambourines: [Int]
    let lowCongas: [Int]
    let highCongas: [Int]
    
    /// Full 16-row initializer
    init(_ name: String, _ description: String, _ bpm: String,
         kicks: [Int] = [], snares: [Int] = [], closedHats: [Int] = [],
         openHats: [Int] = [], claps: [Int] = [], lowToms: [Int] = [],
         midToms: [Int] = [], highToms: [Int] = [],
         crashes: [Int] = [], rides: [Int] = [], rimshots: [Int] = [],
         cowbells: [Int] = [], shakers: [Int] = [], tambourines: [Int] = [],
         lowCongas: [Int] = [], highCongas: [Int] = []) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.bpm = bpm
        // Core Kit
        self.kicks = kicks
        self.snares = snares
        self.closedHats = closedHats
        self.openHats = openHats
        self.claps = claps
        self.lowToms = lowToms
        self.midToms = midToms
        self.highToms = highToms
        // Extended Kit
        self.crashes = crashes
        self.rides = rides
        self.rimshots = rimshots
        self.cowbells = cowbells
        self.shakers = shakers
        self.tambourines = tambourines
        self.lowCongas = lowCongas
        self.highCongas = highCongas
    }
    
    /// Legacy 8-row initializer for backward compatibility
    /// Maps old field names to new structure
    init(legacy name: String, _ description: String, _ bpm: String,
         kicks: [Int] = [], snares: [Int] = [], closedHats: [Int] = [],
         openHats: [Int] = [], claps: [Int] = [], toms: [Int] = [],
         crash: [Int] = [], highTom: [Int] = []) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.bpm = bpm
        // Core Kit - map legacy fields
        self.kicks = kicks
        self.snares = snares
        self.closedHats = closedHats
        self.openHats = openHats
        self.claps = claps
        self.lowToms = toms      // Legacy 'toms' -> lowToms
        self.midToms = []        // New - empty
        self.highToms = highTom  // Legacy 'highTom' -> highToms
        // Extended Kit - map legacy crash, rest empty
        self.crashes = crash     // Legacy 'crash' -> crashes
        self.rides = []
        self.rimshots = []
        self.cowbells = []
        self.shakers = []
        self.tambourines = []
        self.lowCongas = []
        self.highCongas = []
    }
    
    /// 16-row pattern for grid display
    var pattern: [[Bool]] {
        [
            // Core Kit (Rows 1-8)
            stepsToRow(kicks),
            stepsToRow(snares),
            stepsToRow(closedHats),
            stepsToRow(openHats),
            stepsToRow(claps),
            stepsToRow(lowToms),
            stepsToRow(midToms),
            stepsToRow(highToms),
            // Extended Kit (Rows 9-16)
            stepsToRow(crashes),
            stepsToRow(rides),
            stepsToRow(rimshots),
            stepsToRow(cowbells),
            stepsToRow(shakers),
            stepsToRow(tambourines),
            stepsToRow(lowCongas),
            stepsToRow(highCongas)
        ]
    }
    
    private func stepsToRow(_ steps: [Int]) -> [Bool] {
        (0..<16).map { steps.contains($0) }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(bpm)
    }
    
    static func == (lhs: PresetData, rhs: PresetData) -> Bool {
        lhs.name == rhs.name && lhs.bpm == rhs.bpm
    }
}

struct PresetCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let presets: [PresetData]
}

struct PresetGroup: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let categories: [PresetCategory]
}

// MARK: - The Encyclopedic Preset Library

struct SequencerPresetLibrary {
    
    // MARK: - All Preset Groups
    
    static let allGroups: [PresetGroup] = [
        genreGroup,
        eraGroup,
        applicationGroup,
        educationalGroup
    ]
    
    static var allCategories: [PresetCategory] {
        allGroups.flatMap { $0.categories }
    }
    
    static var allPresets: [PresetData] {
        allCategories.flatMap { $0.presets }
    }
    
    static var totalCount: Int {
        allPresets.count
    }
    
    // MARK: - Genre-Based Group
    
    static let genreGroup = PresetGroup(
        name: "Genres",
        icon: "music.note.list",
        categories: [
            electronicCategory,
            drumAndBassCategory,
            hipHopCategory,
            rockAndPopCategory,
            metalAndPunkCategory,
            latinCategory,
            africanCategory,
            caribbeanCategory,
            middleEasternCategory,
            asianCategory,
            funkAndSoulCategory,
            countryAndFolkCategory,
            worldCategory,
            jazzAndBluesCategory,
            ambientCategory,
            industrialCategory
        ]
    )
    
    // MARK: - Era-Based Group
    
    static let eraGroup = PresetGroup(
        name: "Eras",
        icon: "clock.arrow.circlepath",
        categories: [
            eightiesCategory,
            ninetiesCategory,
            twoThousandsCategory,
            modernCategory
        ]
    )
    
    // MARK: - Application-Based Group
    
    static let applicationGroup = PresetGroup(
        name: "Applications",
        icon: "sparkles",
        categories: [
            workoutCategory,
            cinematicCategory,
            lofiCategory,
            gameCategory
        ]
    )
    
    // MARK: - Educational Group
    
    static let educationalGroup = PresetGroup(
        name: "Educational",
        icon: "graduationcap.fill",
        categories: [
            polyrhythmCategory,
            oddTimeCategory,
            rudimentsCategory
        ]
    )
    
    // MARK: - Electronic Category (17 presets)
    
    static let electronicCategory = PresetCategory(
        name: "Electronic",
        icon: "bolt.fill",
        color: .cyan,
        presets: [
            PresetData("Four on the Floor", "Classic house beat", "120-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [2, 6, 10, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Techno Minimal", "Hypnotic pulse", "130-140",
                      kicks: [0, 4, 8, 12], closedHats: [2, 6, 10, 14], openHats: [4, 12],
                      rides: [0, 8], shakers: [2, 6, 10, 14]),
            PresetData("Deep House", "Groovy shuffle", "120-125",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14], claps: [4, 12],
                      rides: [1, 5, 9, 13], shakers: Array(0..<16), tambourines: [4, 12]),
            PresetData("Trance", "Driving euphoria", "138-145",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), crashes: [0],
                      rides: Array(0..<16), shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Dubstep", "Heavy half-time", "140",
                      kicks: [0, 7, 14], snares: [8], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [4, 12], shakers: [2, 6, 10, 14]),
            PresetData("EDM Drop", "Festival banger", "128",
                      kicks: [0, 2, 4, 6, 8, 10, 12, 14], claps: [4, 12], crashes: [0],
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], shakers: Array(0..<16)),
            PresetData("Electro Funk", "Robot groove", "115-125",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: Array(0..<16),
                      rimshots: [2, 10], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("UK Garage", "2-step bounce", "130",
                      kicks: [0, 10], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14], openHats: [3, 11],
                      rides: [2, 6, 10, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Hardstyle", "150+ intensity", "150",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), crashes: [0],
                      rides: Array(0..<16), shakers: Array(0..<16)),
            PresetData("Synthwave", "80s revival", "100-120",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], tambourines: [4, 12]),
            PresetData("Future Bass", "Emotional drops", "140-160",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: Array(0..<16), claps: [4, 12],
                      rides: [0, 4, 8, 12], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Psytrance", "Goa vibes", "145",
                      kicks: [0, 4, 8, 12], closedHats: Array(0..<16), openHats: [2, 6, 10, 14],
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], shakers: Array(0..<16)),
            PresetData("Tech House", "Groovy tech", "125",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14], claps: [4, 12],
                      rides: [1, 5, 9, 13], rimshots: [6, 14], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Progressive House", "Building energy", "128",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), crashes: [0],
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Acid House", "303 squelch", "120-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14], openHats: [6, 14],
                      rides: [2, 6, 10, 14], tambourines: [4, 12]),
            PresetData("Minimal Techno", "Berlin minimal", "125-130",
                      kicks: [0, 8], closedHats: [4, 12],
                      rimshots: [2, 10], shakers: [0, 4, 8, 12]),
            PresetData("Bass House", "UK bass energy", "125-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [2, 6, 10, 14], shakers: [0, 2, 4, 6, 8, 10, 12, 14])
        ]
    )
    
    // MARK: - Drum & Bass Category (10 presets)
    
    static let drumAndBassCategory = PresetCategory(
        name: "Drum & Bass",
        icon: "waveform.path.ecg",
        color: .yellow,
        presets: [
            PresetData("Classic DnB", "Two-step foundation", "174",
                      kicks: [0, 10], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], rimshots: [2, 6, 10, 14]),
            PresetData("Liquid", "Smooth roller", "174",
                      kicks: [0, 10], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: Array(0..<16), rimshots: [1, 5, 9, 13]),
            PresetData("Neurofunk", "Dark & techy", "175",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [0, 4, 8, 12], rimshots: [2, 8, 14]),
            PresetData("Jump Up", "Dancefloor energy", "175",
                      kicks: [0, 3, 10], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], rimshots: [3, 7, 11, 15]),
            PresetData("Amen Break", "The legendary loop", "170",
                      kicks: [0, 4, 10], snares: [4, 8, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14], openHats: [6, 14],
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], rimshots: [2, 10]),
            PresetData("Jungle", "Ragga influence", "160-170",
                      kicks: [0, 6, 10], snares: [4, 12, 14], closedHats: Array(0..<16), openHats: [2, 10],
                      rides: Array(0..<16), rimshots: [3, 7, 11], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Halftime", "Slow and heavy", "85",
                      kicks: [0, 10], snares: [8], closedHats: [0, 4, 8, 12],
                      rides: [0, 4, 8, 12], rimshots: [4, 12]),
            PresetData("Roller", "Minimal hypnotic", "174",
                      kicks: [0, 10], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], rimshots: [6, 14]),
            PresetData("Ragga DnB", "Jamaican fusion", "170",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: Array(0..<16), openHats: [3, 11],
                      rides: Array(0..<16), rimshots: [1, 5, 9, 13], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Dancefloor DnB", "Peak time energy", "175",
                      kicks: [0, 3, 10], snares: [4, 12], closedHats: Array(0..<16), crashes: [0],
                      rides: Array(0..<16), rimshots: [2, 6, 10, 14])
        ]
    )
    
    // MARK: - Hip Hop Category (17 presets)
    
    static let hipHopCategory = PresetCategory(
        name: "Hip Hop",
        icon: "headphones",
        color: .purple,
        presets: [
            PresetData("Boom Bap", "90s classic", "85-95",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [2, 6, 10, 14], shakers: [1, 5, 9, 13]),
            PresetData("Trap", "808 heavy", "140",
                      kicks: [0, 3, 6, 10, 14], snares: [4, 12], closedHats: Array(0..<16), openHats: [6, 14],
                      rimshots: [2, 10], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Lo-Fi", "Chill beats", "75-85",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [6, 14], shakers: [2, 6, 10, 14], tambourines: [4, 12]),
            PresetData("UK Drill", "Dark & sliding", "140-145",
                      kicks: [0, 5, 10, 14], snares: [4, 12], closedHats: Array(0..<16),
                      rimshots: [3, 7, 11, 15], shakers: [1, 5, 9, 13]),
            PresetData("NY Drill", "Brooklyn heat", "140",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: Array(0..<16), openHats: [2, 10],
                      rimshots: [1, 5, 9, 13], shakers: Array(0..<16)),
            PresetData("West Coast", "G-Funk bounce", "90-100",
                      kicks: [0, 6, 8, 14], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [2, 10], shakers: [1, 3, 5, 7, 9, 11, 13, 15], tambourines: [6, 14]),
            PresetData("Old School", "Breakbeat roots", "95",
                      kicks: [0, 10], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14], claps: [4, 12],
                      rimshots: [6, 14], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Phonk", "Memphis revival", "130-140",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: Array(0..<16), openHats: [6, 14],
                      rimshots: [2, 6, 10, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Jersey Club", "Baltimore bounce", "130-140",
                      kicks: [0, 2, 4, 6, 8, 10, 12, 14], closedHats: Array(0..<16), claps: [2, 6, 10, 14],
                      rimshots: [1, 5, 9, 13], shakers: Array(0..<16)),
            PresetData("Memphis", "Three 6 style", "130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), openHats: [2, 10],
                      rimshots: [6, 14], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Cloud Rap", "Ethereal vibes", "70-80",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      shakers: [2, 6, 10, 14], tambourines: [4, 12]),
            PresetData("Crunk", "ATL energy", "75-85",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), claps: [4, 12],
                      rimshots: [2, 10], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Hyphy", "Bay Area bounce", "100-110",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: Array(0..<16),
                      rimshots: [2, 6, 10, 14], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Chopped & Screwed", "Houston slow", "60-70",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rimshots: [4, 12], shakers: [2, 6, 10, 14]),
            PresetData("East Coast", "NYC boom", "90",
                      kicks: [0, 4, 10], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [2, 6, 10, 14], shakers: [1, 5, 9, 13]),
            PresetData("Bounce Music", "New Orleans twerk", "95-105",
                      kicks: [0, 2, 4, 6, 8, 10, 12, 14], snares: [4, 12], closedHats: Array(0..<16),
                      rimshots: [3, 7, 11, 15], shakers: Array(0..<16)),
            PresetData("Gfunk", "West Coast synth", "90-100",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [2, 10], shakers: [1, 3, 5, 7, 9, 11, 13, 15], tambourines: [6, 14])
        ]
    )
    
    // MARK: - Rock & Pop Category (14 presets)
    
    static let rockAndPopCategory = PresetCategory(
        name: "Rock & Pop",
        icon: "guitars.fill",
        color: .red,
        presets: [
            PresetData("Basic Rock", "Solid foundation", "120",
                      kicks: [0, 8], snares: [4, 12], closedHats: Array(0..<16), midToms: [10, 11],
                      rides: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Pop Beat", "Radio friendly", "100-120",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], tambourines: [4, 12]),
            PresetData("Ballad", "Slow & emotional", "60-80",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12], midToms: [14, 15],
                      rides: [0, 4, 8, 12]),
            PresetData("Power Pop", "Energetic drive", "140",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), midToms: [11, 15],
                      crashes: [0], rides: Array(0..<16)),
            PresetData("Indie Rock", "Alternative feel", "110-130",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14], midToms: [10],
                      rides: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Prog Rock", "Complex patterns", "120",
                      kicks: [0, 3, 8, 11], snares: [4, 10, 14], closedHats: Array(0..<16),
                      lowToms: [6, 7], midToms: [9, 13], highToms: [2, 15],
                      rides: [0, 4, 8, 12]),
            PresetData("Arena Rock", "Stadium anthem", "130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), midToms: [6, 7, 14, 15],
                      crashes: [0, 8], rides: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Surf Rock", "Beach vibes", "140-160",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], tambourines: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Shoegaze", "Dreamy wash", "100-120",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [0, 4, 8, 12], tambourines: [2, 6, 10, 14]),
            PresetData("Dream Pop", "Ethereal float", "90-110",
                      kicks: [0, 10], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [0, 4, 8, 12], shakers: [2, 6, 10, 14]),
            PresetData("Brit Pop", "UK swagger", "120",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), midToms: [10, 11],
                      rides: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Garage Rock", "Raw energy", "140",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), midToms: [14, 15],
                      crashes: [0], rides: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Math Rock", "Complex rhythms", "140-180",
                      kicks: [0, 3, 7, 11], snares: [4, 12], closedHats: Array(0..<16),
                      midToms: [2, 6, 10, 14], highToms: [3, 7, 11, 15],
                      rides: [1, 5, 9, 13]),
            PresetData("Post-Rock", "Build & release", "100-120",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12], midToms: [14, 15],
                      rides: [0, 4, 8, 12])
        ]
    )
    
    // MARK: - Metal & Punk Category (12 presets)
    
    static let metalAndPunkCategory = PresetCategory(
        name: "Metal & Punk",
        icon: "flame.fill",
        color: .black,
        presets: [
            PresetData("Thrash Metal", "Fast & aggressive", "180-220",
                      kicks: [0, 2, 4, 6, 8, 10, 12, 14], snares: [4, 12], closedHats: Array(0..<16),
                      midToms: [6, 7, 14, 15], rides: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Death Metal", "Blast beats", "200+",
                      kicks: Array(0..<16), snares: [0, 2, 4, 6, 8, 10, 12, 14], closedHats: Array(0..<16),
                      lowToms: [3, 7, 11, 15], midToms: [2, 6, 10, 14], rides: Array(0..<16)),
            PresetData("Black Metal", "Tremolo pulse", "180",
                      kicks: [0, 2, 4, 6, 8, 10, 12, 14], snares: [4, 12], closedHats: Array(0..<16),
                      crashes: [0, 8], rides: Array(0..<16)),
            PresetData("Punk Rock", "Fast & simple", "180",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], rimshots: [2, 6, 10, 14]),
            PresetData("Hardcore", "Breakdown heavy", "160-180",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), midToms: [14, 15],
                      crashes: [0], rides: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Djent", "Polyrhythmic chug", "130",
                      kicks: [0, 3, 6, 10], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      midToms: [2, 6, 10], rides: [0, 4, 8, 12]),
            PresetData("Metalcore", "Breakdown king", "140",
                      kicks: [0, 4, 6, 8, 12, 14], snares: [4, 12], closedHats: Array(0..<16),
                      midToms: [10, 11, 14, 15], rides: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Doom Metal", "Slow & heavy", "60-80",
                      kicks: [0, 8], snares: [4, 12], midToms: [6, 7, 14, 15],
                      crashes: [0], rides: [0, 4, 8, 12]),
            PresetData("Grindcore", "Extreme speed", "220+",
                      kicks: Array(0..<16), snares: Array(0..<16), closedHats: Array(0..<16),
                      rides: Array(0..<16)),
            PresetData("Pop Punk", "Skate vibes", "160-180",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), midToms: [10, 11],
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], rimshots: [6, 14]),
            PresetData("Stoner Metal", "Heavy groove", "70-90",
                      kicks: [0, 8], snares: [4, 12], midToms: [6, 7, 14, 15],
                      crashes: [0], rides: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Post-Hardcore", "Emotional intensity", "140-160",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), midToms: [14, 15],
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], rimshots: [2, 6, 10, 14])
        ]
    )
    
    // MARK: - Latin Category (14 presets)
    
    static let latinCategory = PresetCategory(
        name: "Latin",
        icon: "flame",
        color: .orange,
        presets: [
            PresetData("Salsa", "Cuban fire", "160-220",
                      kicks: [0, 3, 8, 11], snares: [4, 10], closedHats: Array(0..<16), claps: [4, 12],
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], cowbells: [0, 4, 8, 12], tambourines: Array(0..<16),
                      lowCongas: [2, 6, 10, 14], highCongas: [1, 5, 9, 13]),
            PresetData("Cumbia", "Colombian groove", "80-100",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], tambourines: [1, 3, 5, 7, 9, 11, 13, 15],
                      lowCongas: [0, 8], highCongas: [3, 11]),
            PresetData("Merengue", "Dominican fast", "120-160",
                      kicks: [0, 4, 8, 12], snares: [2, 6, 10, 14], closedHats: Array(0..<16),
                      tambourines: Array(0..<16), lowCongas: [0, 4, 8, 12], highCongas: [2, 6, 10, 14]),
            PresetData("Bachata", "Romantic rhythm", "120-140",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], tambourines: [4, 12], lowCongas: [6, 14], highCongas: [2, 10]),
            PresetData("Tango", "Argentine passion", "60-66",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [0, 4, 8, 12], rimshots: [2, 6, 10, 14]),
            PresetData("Bolero", "Slow romance", "80-100",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], tambourines: [4, 12], lowCongas: [0, 8], highCongas: [4, 12]),
            PresetData("Son Cubano", "Traditional Cuban", "160-200",
                      kicks: [0, 3, 8, 11], snares: [4, 10, 14], closedHats: Array(0..<16),
                      cowbells: [0, 3, 6, 9, 12, 15], lowCongas: [2, 6, 10, 14], highCongas: [1, 5, 9, 13]),
            PresetData("Mambo", "Big band Latin", "180-200",
                      kicks: [0, 3, 6, 10, 14], snares: [4, 12], closedHats: Array(0..<16),
                      cowbells: [0, 4, 8, 12], tambourines: Array(0..<16), lowCongas: [1, 5, 9, 13], highCongas: [3, 7, 11, 15]),
            PresetData("Cha Cha", "4-and rhythm", "120",
                      kicks: [0, 4, 10], snares: [4, 8, 12], closedHats: Array(0..<16),
                      cowbells: [10, 11], tambourines: [0, 2, 4, 6, 8, 10, 12, 14], lowCongas: [0, 4], highCongas: [10]),
            PresetData("Rumba", "Afro-Cuban soul", "80-100",
                      kicks: [0, 3, 8, 11], snares: [6, 14], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [1, 5, 9, 13], lowCongas: [0, 3, 6, 9, 12, 15], highCongas: [2, 5, 8, 11, 14]),
            PresetData("Guaracha", "Fast Cuban", "140-160",
                      kicks: [0, 4, 8, 12], snares: [2, 6, 10, 14], closedHats: Array(0..<16),
                      cowbells: [1, 5, 9, 13], tambourines: Array(0..<16), lowCongas: [0, 8], highCongas: [4, 12]),
            PresetData("Norteño", "Tex-Mex polka", "100-120",
                      kicks: [0, 4, 8, 12], snares: [2, 6, 10, 14], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      cowbells: [1, 5, 9, 13], tambourines: [0, 4, 8, 12]),
            PresetData("Banda", "Mexican brass", "120-140",
                      kicks: [0, 4, 8, 12], snares: [2, 6, 10, 14], closedHats: Array(0..<16),
                      cowbells: [0, 4, 8, 12], tambourines: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Vallenato", "Colombian accordion", "100-120",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      cowbells: [1, 5, 9, 13], lowCongas: [2, 6, 10, 14], highCongas: [1, 5, 9, 13])
        ]
    )
    
    // MARK: - African Category (12 presets)
    
    static let africanCategory = PresetCategory(
        name: "African",
        icon: "globe.africa.fill",
        color: Color(red: 0.8, green: 0.6, blue: 0.2),
        presets: [
            PresetData("Afrobeats", "Lagos groove", "100-120",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: Array(0..<16), openHats: [2, 10],
                      rides: [1, 5, 9, 13], shakers: Array(0..<16), lowCongas: [1, 5, 9, 13], highCongas: [3, 7, 11, 15]),
            PresetData("Amapiano", "SA deep house", "110-120",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14], openHats: [6, 14],
                      rides: [2, 6, 10, 14], shakers: Array(0..<16), lowCongas: [0, 8], highCongas: [4, 12]),
            PresetData("Highlife", "Ghanaian classic", "100-120",
                      kicks: [0, 3, 6, 10], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [1, 5, 9, 13], cowbells: [0, 3, 6, 9, 12, 15], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Soukous", "Congolese rumba", "120-140",
                      kicks: [0, 3, 8, 11], snares: [4, 10, 14], closedHats: Array(0..<16),
                      cowbells: [0, 2, 4, 6, 8, 10, 12, 14], shakers: Array(0..<16), lowCongas: [1, 5, 9, 13], highCongas: [3, 7, 11, 15]),
            PresetData("Kwaito", "SA township", "100-110",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [1, 5, 9, 13], shakers: [0, 2, 4, 6, 8, 10, 12, 14], lowCongas: [2, 10], highCongas: [6, 14]),
            PresetData("Gqom", "Durban dark", "120-130",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: Array(0..<16),
                      rimshots: [1, 5, 9, 13], shakers: [1, 3, 5, 7, 9, 11, 13, 15], lowCongas: [3, 11]),
            PresetData("Coupe-Decale", "Ivorian dance", "130-140",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: Array(0..<16),
                      cowbells: [1, 5, 9, 13], shakers: Array(0..<16), lowCongas: [2, 6, 10, 14], highCongas: [1, 5, 9, 13]),
            PresetData("Ndombolo", "Congo dance", "130",
                      kicks: [0, 4, 8, 12], snares: [4, 10, 14], closedHats: Array(0..<16),
                      cowbells: [0, 4, 8, 12], shakers: Array(0..<16), lowCongas: [3, 7, 11, 15], highCongas: [1, 5, 9, 13]),
            PresetData("Jùjú", "Yoruba rhythm", "100-120",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      cowbells: [1, 5, 9, 13], shakers: [0, 2, 4, 6, 8, 10, 12, 14], lowCongas: [0, 3, 6, 9, 12], highCongas: [2, 5, 8, 11, 14]),
            PresetData("Mbalax", "Senegalese beat", "120-140",
                      kicks: [0, 3, 6, 10, 14], snares: [4, 12], closedHats: Array(0..<16),
                      cowbells: [1, 5, 9, 13], shakers: Array(0..<16), lowCongas: [2, 6, 10, 14], highCongas: [1, 5, 9, 13]),
            PresetData("Azonto", "Ghanaian dance", "120-130",
                      kicks: [0, 3, 6, 10], snares: [4, 12], closedHats: Array(0..<16), openHats: [2, 10],
                      cowbells: [1, 5, 9, 13], shakers: Array(0..<16), lowCongas: [0, 4, 8, 12], highCongas: [2, 6, 10, 14]),
            PresetData("Afro-house", "Deep African house", "120-125",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [2, 6, 10, 14], shakers: Array(0..<16), tambourines: [1, 3, 5, 7, 9, 11, 13, 15])
        ]
    )
    
    // MARK: - Caribbean Category (10 presets)
    
    static let caribbeanCategory = PresetCategory(
        name: "Caribbean",
        icon: "sun.max.fill",
        color: Color(red: 0.2, green: 0.8, blue: 0.6),
        presets: [
            PresetData("Reggae", "One drop", "60-90",
                      kicks: [6, 14], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [2, 10], shakers: [1, 3, 5, 7, 9, 11, 13, 15], tambourines: [4, 12]),
            PresetData("Ska", "Upbeat skank", "100-140",
                      kicks: [0, 8], snares: [2, 6, 10, 14], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [4, 12], tambourines: [0, 4, 8, 12]),
            PresetData("Dancehall", "Bashment bounce", "90-110",
                      kicks: [0, 3, 8, 11], snares: [6, 14], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [2, 10], shakers: Array(0..<16), tambourines: [4, 12]),
            PresetData("Soca", "Trinidad carnival", "130-150",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      cowbells: [1, 5, 9, 13], shakers: Array(0..<16), tambourines: Array(0..<16)),
            PresetData("Calypso", "Island storytelling", "100-140",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [2, 6, 10, 14], shakers: [0, 2, 4, 6, 8, 10, 12, 14], tambourines: [4, 12]),
            PresetData("Zouk", "French Caribbean", "100-120",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [1, 5, 9, 13], shakers: [0, 2, 4, 6, 8, 10, 12, 14], tambourines: [4, 12]),
            PresetData("Kompa", "Haitian groove", "100-120",
                      kicks: [0, 3, 8, 11], snares: [6, 14], closedHats: Array(0..<16),
                      rides: [1, 5, 9, 13], tambourines: [0, 2, 4, 6, 8, 10, 12, 14], lowCongas: [2, 10], highCongas: [6, 14]),
            PresetData("Dub", "Heavy bass space", "70-90",
                      kicks: [0, 10], snares: [4, 12], openHats: [2, 6, 10, 14],
                      rimshots: [6, 14], shakers: [2, 6, 10, 14]),
            PresetData("Lovers Rock", "Romantic reggae", "60-80",
                      kicks: [6, 14], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15], tambourines: [4, 12]),
            PresetData("Dembow", "Puerto Rican fire", "100",
                      kicks: [0, 3, 8, 11], snares: [3, 7, 11, 15], closedHats: Array(0..<16),
                      rimshots: [1, 5, 9, 13], shakers: Array(0..<16), tambourines: [0, 4, 8, 12])
        ]
    )
    
    // MARK: - Middle Eastern Category (10 presets)
    
    static let middleEasternCategory = PresetCategory(
        name: "Middle Eastern",
        icon: "moon.stars.fill",
        color: Color(red: 0.6, green: 0.4, blue: 0.8),
        presets: [
            PresetData("Arabic Pop", "Dabke influence", "100-130",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [1, 5, 9, 13], tambourines: Array(0..<16)),
            PresetData("Dabke", "Lebanese line dance", "120-140",
                      kicks: [0, 4, 6, 10, 14], snares: [4, 12], closedHats: Array(0..<16),
                      rimshots: [2, 6, 10, 14], tambourines: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Turkish", "Anatolian rhythm", "100-120",
                      kicks: [0, 3, 8, 11], snares: [6, 14], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [2, 10], tambourines: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Persian", "Iranian classical", "80-120",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rimshots: [2, 6, 10, 14], tambourines: [1, 5, 9, 13]),
            PresetData("Gnawa", "Moroccan trance", "100-120",
                      kicks: [0, 3, 8, 11], snares: [4, 10], closedHats: Array(0..<16),
                      rimshots: [1, 5, 9, 13], shakers: Array(0..<16)),
            PresetData("Chaabi", "Egyptian folk", "90-120",
                      kicks: [0, 4, 8, 12], snares: [4, 10, 14], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [2, 6, 10, 14], tambourines: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Rai", "Algerian modern", "100-130",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: Array(0..<16),
                      rimshots: [1, 5, 9, 13], tambourines: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Khaleeji", "Gulf groove", "100-120",
                      kicks: [0, 3, 6, 10], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [1, 5, 9, 13], tambourines: [0, 4, 8, 12]),
            PresetData("Iraqi Chobi", "Iraqi wedding", "120-140",
                      kicks: [0, 3, 8, 11], snares: [4, 10, 14], closedHats: Array(0..<16),
                      rimshots: [2, 6, 10, 14], tambourines: Array(0..<16)),
            PresetData("Mizrahi", "Israeli pop", "100-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [2, 6, 10, 14], tambourines: [1, 3, 5, 7, 9, 11, 13, 15])
        ]
    )
    
    // MARK: - Asian Category (10 presets)
    
    static let asianCategory = PresetCategory(
        name: "Asian",
        icon: "character.ja",
        color: Color(red: 1.0, green: 0.4, blue: 0.6),
        presets: [
            PresetData("K-Pop", "Korean precision", "100-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), claps: [4, 12],
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14], shakers: Array(0..<16)),
            PresetData("J-Pop", "Japanese energy", "120-140",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [2, 6, 10, 14], rimshots: [1, 5, 9, 13], tambourines: [4, 12]),
            PresetData("Bollywood", "Indian film", "100-140",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [1, 5, 9, 13], shakers: [1, 3, 5, 7, 9, 11, 13, 15], tambourines: Array(0..<16)),
            PresetData("C-Pop", "Chinese modern", "100-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [2, 6, 10, 14], rimshots: [1, 5, 9, 13], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("City Pop", "80s Japanese", "100-120",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], rimshots: [6, 14], tambourines: [4, 12]),
            PresetData("Enka", "Japanese ballad", "60-80",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Thai Pop", "Luk thung rhythm", "100-120",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [1, 5, 9, 13], shakers: [1, 3, 5, 7, 9, 11, 13, 15], tambourines: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Bhangra", "Punjabi energy", "120-140",
                      kicks: [0, 4, 8, 12], snares: [2, 6, 10, 14], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], shakers: Array(0..<16), tambourines: Array(0..<16)),
            PresetData("Gamelan", "Indonesian bells", "60-100",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12], lowToms: [2, 6, 10, 14],
                      rides: [0, 4, 8, 12], rimshots: [2, 6, 10, 14]),
            PresetData("Cantopop", "Hong Kong style", "100-120",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [2, 6, 10, 14], rimshots: [1, 5, 9, 13], shakers: [0, 2, 4, 6, 8, 10, 12, 14])
        ]
    )
    
    // MARK: - Funk & Soul Category (10 presets)
    
    static let funkAndSoulCategory = PresetCategory(
        name: "Funk & Soul",
        icon: "music.mic",
        color: Color(red: 0.8, green: 0.2, blue: 0.4),
        presets: [
            PresetData("Classic Funk", "James Brown pocket", "100-120",
                      kicks: [0, 6, 10, 14], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14], cowbells: [1, 5, 9, 13]),
            PresetData("Neo-Soul", "Modern smoothness", "80-100",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], rimshots: [6, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Motown", "Detroit groove", "100-120",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [2, 6, 10, 14], rimshots: [1, 5, 9, 13], tambourines: [4, 12]),
            PresetData("Northern Soul", "Fast & rare", "120-140",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [2, 6, 10, 14], rimshots: [1, 5, 9, 13], tambourines: [4, 12]),
            PresetData("Philly Soul", "Lush orchestral", "100-120",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15], tambourines: [4, 12]),
            PresetData("Disco", "Four-on-floor glam", "110-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), openHats: [2, 6, 10, 14],
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], cowbells: [0, 4, 8, 12], shakers: Array(0..<16), tambourines: [4, 12]),
            PresetData("Boogie", "80s groove", "100-120",
                      kicks: [0, 6, 10, 14], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 5, 9, 13], rimshots: [2, 6, 10, 14], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("P-Funk", "Parliament groove", "100-110",
                      kicks: [0, 3, 10, 14], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 5, 9, 13], rimshots: [2, 6, 10, 14], cowbells: [0, 4, 8, 12]),
            PresetData("Stax Soul", "Memphis sound", "90-110",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], rimshots: [4, 12], tambourines: [1, 5, 9, 13]),
            PresetData("Nu Funk", "Modern revival", "100-120",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: Array(0..<16), claps: [4, 12],
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14], shakers: Array(0..<16))
        ]
    )
    
    // MARK: - Country & Folk Category (10 presets)
    
    static let countryAndFolkCategory = PresetCategory(
        name: "Country & Folk",
        icon: "banjo",
        color: Color(red: 0.6, green: 0.4, blue: 0.2),
        presets: [
            PresetData("Classic Country", "Nashville sound", "100-120",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [0, 3, 6, 9, 12, 15], rimshots: [2, 10], tambourines: [4, 12]),
            PresetData("Modern Country", "Bro-country beat", "120-140",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), midToms: [10, 11],
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Bluegrass", "Mountain rhythm", "120-160",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], rimshots: [4, 12], tambourines: [1, 5, 9, 13]),
            PresetData("Celtic", "Irish jig", "120-160",
                      kicks: [0, 6, 8, 14], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], tambourines: Array(0..<16)),
            PresetData("Polka", "Eastern European", "100-140",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], tambourines: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Cajun", "Louisiana groove", "100-120",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 5, 9, 13], rimshots: [2, 6, 10, 14], tambourines: [4, 12]),
            PresetData("Appalachian", "Old-time feel", "100-120",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], rimshots: [4, 12], tambourines: [1, 5, 9, 13]),
            PresetData("Zydeco", "Creole rhythm", "100-140",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      crashes: [0], rides: [1, 3, 5, 7, 9, 11, 13, 15], tambourines: Array(0..<16)),
            PresetData("Honky Tonk", "Barroom shuffle", "100-120",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 3, 4, 7, 8, 11, 12, 15],
                      rides: [0, 3, 6, 9, 12, 15], rimshots: [2, 10], tambourines: [4, 12]),
            PresetData("Outlaw Country", "Rebellious edge", "110-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), midToms: [10, 11],
                      rides: [0, 2, 4, 6, 8, 10, 12, 14])
        ]
    )
    
    // MARK: - World Category (15 presets)
    
    static let worldCategory = PresetCategory(
        name: "World",
        icon: "globe.americas.fill",
        color: .green,
        presets: [
            PresetData("Reggaeton", "Dembow rhythm", "90-100",
                      kicks: [0, 3, 8, 11], snares: [3, 7, 11, 15], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [1, 5, 9, 13], cowbells: [0, 4, 8, 12], tambourines: Array(0..<16)),
            PresetData("Afrobeat", "Fela groove", "100-120",
                      kicks: [0, 3, 6, 10], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14], openHats: [2, 10],
                      rides: [1, 5, 9, 13], cowbells: [0, 3, 6, 9, 12, 15], shakers: Array(0..<16), lowCongas: [2, 6, 10, 14], highCongas: [1, 5, 9, 13]),
            PresetData("Samba", "Brazilian carnival", "100-120",
                      kicks: [0, 6, 8, 14], snares: [4, 10, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], shakers: Array(0..<16), tambourines: Array(0..<16), lowCongas: [0, 4, 8, 12], highCongas: [2, 6, 10, 14]),
            PresetData("Bossa Nova", "Smooth Brazilian", "120-140",
                      kicks: [0, 8], snares: [6, 14], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [0, 3, 6, 10, 12], rimshots: [2, 7, 11], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Tarantella", "Italian dance", "140-180",
                      kicks: [0, 4, 8, 12], snares: [2, 6, 10, 14], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], tambourines: Array(0..<16)),
            PresetData("Flamenco", "Spanish passion", "80-120",
                      kicks: [0, 3, 8, 11], snares: [4, 10, 14], closedHats: [0, 4, 8, 12],
                      rides: [1, 5, 9, 13], rimshots: [2, 6, 10, 14], tambourines: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Klezmer", "Jewish celebration", "100-140",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], tambourines: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Balkan", "Eastern European", "120-180",
                      kicks: [0, 3, 6, 10, 14], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 5, 9, 13], rimshots: [2, 6, 10, 14], tambourines: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Greek", "Bouzouki rhythm", "100-140",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [1, 5, 9, 13], tambourines: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Polynesian", "Island pulse", "80-120",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15], lowCongas: [0, 4, 8, 12], highCongas: [2, 6, 10, 14]),
            PresetData("Aboriginal", "Australian pulse", "80-100",
                      kicks: [0, 8], snares: [4, 12], lowToms: [2, 6, 10, 14],
                      rides: [0, 4, 8, 12], rimshots: [2, 6, 10, 14]),
            PresetData("Fado", "Portuguese soul", "60-80",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], rimshots: [4, 12], shakers: [1, 5, 9, 13]),
            PresetData("Taarab", "Swahili romance", "80-100",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [1, 5, 9, 13], tambourines: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Maori", "New Zealand haka", "100-120",
                      kicks: [0, 4, 8, 12], snares: [4, 12], lowToms: Array(0..<16),
                      rides: [0, 4, 8, 12], rimshots: [2, 6, 10, 14]),
            PresetData("Hawaiian", "Slack key groove", "80-100",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15], tambourines: [4, 12])
        ]
    )
    
    // MARK: - Jazz & Blues Category (14 presets)
    
    static let jazzAndBluesCategory = PresetCategory(
        name: "Jazz & Blues",
        icon: "music.quarternote.3",
        color: .orange,
        presets: [
            PresetData("Swing", "Big band feel", "120-160",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 3, 4, 7, 8, 11, 12, 15],
                      rides: Array(0..<16), rimshots: [2, 6, 10, 14]),
            PresetData("Blues Shuffle", "12-bar groove", "80-120",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 3, 4, 7, 8, 11, 12, 15],
                      rides: [0, 3, 6, 9, 12, 15], rimshots: [2, 10]),
            PresetData("Jazz Brush", "Soft touch", "100-140",
                      kicks: [0, 10], snares: [4, 8, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], rimshots: [6, 14]),
            PresetData("Bebop", "Fast & complex", "180-220",
                      kicks: [0, 4, 10], snares: [4, 12], closedHats: Array(0..<16),
                      rides: Array(0..<16), rimshots: [1, 5, 9, 13]),
            PresetData("Funk", "James Brown pocket", "100-120",
                      kicks: [0, 6, 10, 14], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14], cowbells: [1, 5, 9, 13]),
            PresetData("Acid Jazz", "90s groove", "100-120",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], rimshots: [1, 5, 9, 13], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Nu-Jazz", "Modern fusion", "100-120",
                      kicks: [0, 3, 10], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [0, 4, 8, 12], rimshots: [2, 6, 10, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Delta Blues", "Mississippi roots", "60-80",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], rimshots: [4, 12]),
            PresetData("Chicago Blues", "Electric city", "80-120",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 3, 4, 7, 8, 11, 12, 15],
                      rides: [0, 3, 6, 9, 12, 15], rimshots: [2, 10]),
            PresetData("Boogaloo", "Latin jazz funk", "100-120",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 5, 9, 13], cowbells: [0, 3, 6, 9, 12, 15], lowCongas: [2, 6, 10, 14], highCongas: [1, 5, 9, 13]),
            PresetData("Cool Jazz", "West coast smooth", "100-140",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], rimshots: [6, 14]),
            PresetData("Hard Bop", "East coast fire", "120-180",
                      kicks: [0, 4, 10], snares: [4, 12], closedHats: Array(0..<16),
                      rides: Array(0..<16), rimshots: [2, 6, 10, 14]),
            PresetData("Fusion", "Jazz-rock crossover", "120-140",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [0, 2, 4, 6, 8, 10, 12, 14], rimshots: [1, 5, 9, 13]),
            PresetData("Free Jazz", "Avant-garde chaos", "Variable",
                      kicks: [0, 7, 11], snares: [3, 9, 13], closedHats: [1, 5, 10, 14],
                      rides: [2, 6, 10, 14], rimshots: [0, 4, 8, 12])
        ]
    )
    
    // MARK: - Ambient & Experimental Category (8 presets)
    
    static let ambientCategory = PresetCategory(
        name: "Ambient & Experimental",
        icon: "sparkle",
        color: Color(red: 0.4, green: 0.6, blue: 0.8),
        presets: [
            PresetData("Minimal", "Less is more", "90-120",
                      kicks: [0, 8], closedHats: [4, 12],
                      rimshots: [2, 6, 10, 14], shakers: [0, 4, 8, 12]),
            PresetData("Glitch", "Broken beats", "90-140",
                      kicks: [0, 3, 7, 11], snares: [5, 13], closedHats: [1, 6, 9, 14],
                      rimshots: [2, 10], shakers: [0, 4, 8, 12]),
            PresetData("IDM", "Intelligent dance", "100-140",
                      kicks: [0, 5, 10], snares: [3, 7, 12], closedHats: [1, 4, 8, 11, 14],
                      rimshots: [2, 6, 10, 14], shakers: [0, 4, 8, 12]),
            PresetData("Noise", "Chaotic texture", "120",
                      kicks: [0, 2, 5, 7, 10, 13], snares: [1, 4, 8, 11, 15], closedHats: Array(0..<16),
                      rides: [3, 7, 11, 15], rimshots: [1, 5, 9, 13]),
            PresetData("Drone", "Sustained pulse", "60",
                      kicks: [0], snares: [8],
                      rides: [0, 4, 8, 12]),
            PresetData("Musique Concrète", "Found sounds", "100",
                      kicks: [0, 7], snares: [3, 11], lowToms: [5, 13],
                      rimshots: [2, 6, 10, 14]),
            PresetData("Tape Loop", "Analog warmth", "80-100",
                      kicks: [0, 8], closedHats: [2, 6, 10, 14],
                      rides: [0, 4, 8, 12], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Generative", "Random patterns", "100",
                      kicks: [0, 5, 11], snares: [3, 8], closedHats: [1, 4, 7, 10, 13],
                      rides: [2, 6, 10, 14], rimshots: [0, 4, 8, 12])
        ]
    )
    
    // MARK: - Industrial Category (8 presets)
    
    static let industrialCategory = PresetCategory(
        name: "Industrial",
        icon: "gearshape.2.fill",
        color: Color(red: 0.3, green: 0.3, blue: 0.3),
        presets: [
            PresetData("Industrial", "Factory rhythm", "120-140",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      crashes: [0], rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14]),
            PresetData("EBM", "Electronic body", "120-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], rimshots: [1, 5, 9, 13]),
            PresetData("Dark Electro", "Gothic pulse", "120-140",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14]),
            PresetData("Aggrotech", "Aggressive dance", "130-150",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      crashes: [0], rides: Array(0..<16), rimshots: [1, 5, 9, 13]),
            PresetData("Power Noise", "Harsh texture", "140-160",
                      kicks: [0, 2, 4, 6, 8, 10, 12, 14], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: Array(0..<16)),
            PresetData("Witch House", "Slow & dark", "60-80",
                      kicks: [0, 8], snares: [4, 12], openHats: [6, 14],
                      rides: [2, 6, 10, 14], rimshots: [4, 12], shakers: [1, 5, 9, 13]),
            PresetData("Coldwave", "Post-punk chill", "100-120",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], rimshots: [4, 12]),
            PresetData("Rhythmic Noise", "Distorted pulse", "130-150",
                      kicks: Array(0..<16), snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14])
        ]
    )
    
    // MARK: - 80s Beats Category (10 presets)
    
    static let eightiesCategory = PresetCategory(
        name: "80s Beats",
        icon: "tv",
        color: Color(red: 1.0, green: 0.0, blue: 0.5),
        presets: [
            PresetData("New Wave", "Post-punk dance", "100-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [2, 6, 10, 14], rimshots: [1, 5, 9, 13], tambourines: [4, 12]),
            PresetData("Synth-pop", "Electronic pop", "100-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], rimshots: [6, 14], tambourines: [4, 12]),
            PresetData("Italo Disco", "European dance", "115-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], cowbells: [0, 4, 8, 12], tambourines: Array(0..<16)),
            PresetData("Post-Punk", "Dark & angular", "100-140",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], rimshots: [4, 12]),
            PresetData("Hi-NRG", "Fast & gay", "120-140",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], shakers: Array(0..<16), tambourines: [4, 12]),
            PresetData("Miami Bass", "808 boom", "100-130",
                      kicks: [0, 3, 6, 10, 14], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 5, 9, 13], rimshots: [2, 6, 10, 14], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Electro", "Breakdance beat", "100-130",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: Array(0..<16), claps: [4, 12],
                      rides: [1, 5, 9, 13], rimshots: [2, 6, 10, 14], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Freestyle", "Latin electronic", "110-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [2, 6, 10, 14], tambourines: Array(0..<16), lowCongas: [1, 5, 9, 13], highCongas: [3, 7, 11, 15]),
            PresetData("Gothic Rock", "Dark wave", "100-130",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], rimshots: [4, 12]),
            PresetData("Power Ballad", "Arena rock slow", "60-80",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12], midToms: [14, 15],
                      crashes: [0], rides: [0, 4, 8, 12])
        ]
    )
    
    // MARK: - 90s Throwback Category (10 presets)
    
    static let ninetiesCategory = PresetCategory(
        name: "90s Throwback",
        icon: "opticaldisc",
        color: Color(red: 0.0, green: 1.0, blue: 0.8),
        presets: [
            PresetData("Eurodance", "Dancefloor anthem", "130-150",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], shakers: Array(0..<16), tambourines: [4, 12]),
            PresetData("Grunge", "Seattle sound", "100-140",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12], midToms: [10, 11],
                      rides: [2, 6, 10, 14]),
            PresetData("Britpop", "UK swagger", "100-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), midToms: [10, 11],
                      rides: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("90s R&B", "New jack swing", "90-110",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [1, 5, 9, 13], rimshots: [2, 6, 10, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Happy Hardcore", "Fast & euphoric", "160-180",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: Array(0..<16), shakers: Array(0..<16)),
            PresetData("Big Beat", "Breaks & samples", "120-140",
                      kicks: [0, 4, 6, 10], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14]),
            PresetData("Trip Hop", "Bristol downtempo", "80-100",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], rimshots: [4, 12], shakers: [1, 5, 9, 13]),
            PresetData("Garage", "2-step UK", "130",
                      kicks: [0, 10], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14], openHats: [3, 11],
                      rides: [2, 6, 10, 14], rimshots: [1, 5, 9, 13], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Downtempo", "Chill beats", "80-100",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15], tambourines: [4, 12]),
            PresetData("Rave", "Warehouse energy", "140-160",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      crashes: [0], rides: Array(0..<16), shakers: Array(0..<16))
        ]
    )
    
    // MARK: - 2000s Vibes Category (8 presets)
    
    static let twoThousandsCategory = PresetCategory(
        name: "2000s Vibes",
        icon: "iphone.gen1",
        color: Color(red: 0.8, green: 0.8, blue: 0.0),
        presets: [
            PresetData("Moombahton", "Dutch-reggaeton", "108-115",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], cowbells: [0, 4, 8, 12], tambourines: Array(0..<16)),
            PresetData("Fidget House", "Switch style", "125-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14], shakers: Array(0..<16)),
            PresetData("Emo", "Pop-punk feels", "140-180",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), midToms: [10, 11],
                      rides: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Nu-Metal", "Rap-rock fusion", "100-140",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: Array(0..<16), midToms: [14, 15],
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14]),
            PresetData("Electroclash", "Retro-futurism", "110-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], rimshots: [1, 5, 9, 13], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Grime", "UK underground", "140",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14], shakers: Array(0..<16)),
            PresetData("Snap Music", "Laffy Taffy era", "75-85",
                      kicks: [0, 8], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [2, 6, 10, 14], rimshots: [4, 12], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Blog House", "Ed Banger style", "120-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), claps: [4, 12],
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14], shakers: Array(0..<16))
        ]
    )
    
    // MARK: - Modern Trends Category (10 presets)
    
    static let modernCategory = PresetCategory(
        name: "Modern Trends",
        icon: "sparkles.rectangle.stack",
        color: Color(red: 0.9, green: 0.3, blue: 0.9),
        presets: [
            PresetData("Hyperpop", "Maximalist chaos", "140-180",
                      kicks: [0, 2, 4, 6, 8, 10, 12, 14], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: Array(0..<16), shakers: Array(0..<16)),
            PresetData("Drift Phonk", "Cowbell phonk", "140-150",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      crashes: [0, 8], rides: [1, 3, 5, 7, 9, 11, 13, 15], cowbells: Array(0..<16)),
            PresetData("Brazilian Funk", "Baile groove", "130-140",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 5, 9, 13], rimshots: [2, 6, 10, 14], shakers: Array(0..<16), tambourines: [4, 12]),
            PresetData("Reggaeton Moderno", "Bad Bunny era", "95-100",
                      kicks: [0, 3, 8, 11], snares: [3, 7, 11, 15], closedHats: Array(0..<16),
                      rimshots: [1, 5, 9, 13], shakers: [0, 2, 4, 6, 8, 10, 12, 14], tambourines: [4, 12]),
            PresetData("Dembow", "Dominican party", "100-120",
                      kicks: [0, 3, 8, 11], snares: [3, 7, 11, 15], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rimshots: [1, 5, 9, 13], cowbells: [0, 4, 8, 12], tambourines: Array(0..<16)),
            PresetData("Afro-swing", "UK meets Africa", "100-120",
                      kicks: [0, 3, 8, 11], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 5, 9, 13], shakers: Array(0..<16), lowCongas: [2, 6, 10, 14], highCongas: [1, 5, 9, 13]),
            PresetData("Pluggnb", "Plug meets R&B", "130-145",
                      kicks: [0, 6, 10, 14], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Rage Beat", "Playboi Carti era", "150-160",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14], shakers: Array(0..<16)),
            PresetData("Melodic Drill", "Emotional drill", "140",
                      kicks: [0, 5, 10], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14], shakers: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("TikTok Pop", "Viral energy", "100-130",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), claps: [4, 12],
                      rides: [2, 6, 10, 14], rimshots: [1, 5, 9, 13], shakers: Array(0..<16))
        ]
    )
    
    // MARK: - Workout/Fitness Category (8 presets)
    
    static let workoutCategory = PresetCategory(
        name: "Workout/Fitness",
        icon: "figure.run",
        color: Color(red: 1.0, green: 0.4, blue: 0.2),
        presets: [
            PresetData("High Intensity", "HIIT energy", "140-160",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      crashes: [0], rides: Array(0..<16), shakers: Array(0..<16)),
            PresetData("Cardio", "Running pace", "140-150",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], shakers: Array(0..<16)),
            PresetData("Sprint", "Maximum effort", "170-180",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14]),
            PresetData("CrossFit", "Powerful drive", "130-140",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14]),
            PresetData("Yoga Flow", "Gentle rhythm", "80-100",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], shakers: [1, 5, 9, 13]),
            PresetData("Cool Down", "Recovery pace", "90-110",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Power Lift", "Heavy & slow", "70-90",
                      kicks: [0, 8], snares: [4, 12], midToms: [6, 7, 14, 15],
                      crashes: [0], rides: [0, 4, 8, 12]),
            PresetData("Boxing", "Fight rhythm", "130-150",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14])
        ]
    )
    
    // MARK: - Cinematic Category (8 presets)
    
    static let cinematicCategory = PresetCategory(
        name: "Cinematic",
        icon: "film",
        color: Color(red: 0.2, green: 0.2, blue: 0.4),
        presets: [
            PresetData("Epic", "Trailer intensity", "100-130",
                      kicks: [0, 8], snares: [4, 12], lowToms: [2, 6, 10, 14], midToms: [11, 15],
                      crashes: [0], rides: [0, 4, 8, 12]),
            PresetData("Suspense", "Building tension", "80-100",
                      kicks: [0, 8], closedHats: [4, 12],
                      rides: [2, 6, 10, 14], rimshots: [0, 4, 8, 12]),
            PresetData("Action", "Chase sequence", "130-160",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16), midToms: [14, 15],
                      rides: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Sad Scene", "Emotional weight", "60-80",
                      kicks: [0, 8], snares: [4, 12],
                      rides: [2, 6, 10, 14]),
            PresetData("Triumphant", "Victory moment", "100-120",
                      kicks: [0, 4, 8, 12], snares: [4, 12], lowToms: [6, 14], midToms: [10, 11],
                      crashes: [0], rides: [0, 2, 4, 6, 8, 10, 12, 14]),
            PresetData("Chase", "Pursuit rhythm", "140-160",
                      kicks: [0, 2, 4, 6, 8, 10, 12, 14], snares: [4, 12], closedHats: Array(0..<16),
                      midToms: [10, 11, 14, 15], rides: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Horror", "Dread pulse", "60-80",
                      kicks: [0, 8], snares: [12],
                      rides: [4, 12], rimshots: [2, 6, 10, 14]),
            PresetData("Documentary", "Neutral drive", "100-120",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14])
        ]
    )
    
    // MARK: - Lo-Fi & Chill Category (8 presets)
    
    static let lofiCategory = PresetCategory(
        name: "Lo-Fi & Chill",
        icon: "cup.and.saucer.fill",
        color: Color(red: 0.6, green: 0.4, blue: 0.6),
        presets: [
            PresetData("Study Beats", "Focus groove", "75-85",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], rimshots: [6, 14], shakers: [1, 5, 9, 13]),
            PresetData("Sleep", "Gentle pulse", "60-70",
                      kicks: [0, 8], closedHats: [4, 12],
                      rides: [2, 6, 10, 14], shakers: [1, 5, 9, 13]),
            PresetData("Meditation", "Minimal peace", "50-70",
                      kicks: [0], snares: [8],
                      rides: [4, 12], shakers: [2, 6, 10, 14]),
            PresetData("Coffee Shop", "Cafe ambience", "80-90",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], rimshots: [6, 14], shakers: [1, 5, 9, 13]),
            PresetData("Rainy Day", "Melancholy groove", "70-85",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15], tambourines: [4, 12]),
            PresetData("Cozy", "Warm & fuzzy", "75-85",
                      kicks: [0, 6, 10], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], rimshots: [4, 12], shakers: [1, 5, 9, 13]),
            PresetData("Sunset", "Golden hour", "80-100",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [2, 6, 10, 14], shakers: [1, 3, 5, 7, 9, 11, 13, 15], tambourines: [4, 12]),
            PresetData("Late Night", "3am vibes", "70-80",
                      kicks: [0, 10], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], rimshots: [6, 14], shakers: [1, 5, 9, 13])
        ]
    )
    
    // MARK: - Game & 8-bit Category (8 presets)
    
    static let gameCategory = PresetCategory(
        name: "Game & 8-bit",
        icon: "gamecontroller.fill",
        color: Color(red: 0.2, green: 0.8, blue: 0.2),
        presets: [
            PresetData("Chiptune", "8-bit classic", "130-160",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14]),
            PresetData("Boss Battle", "Intense fight", "150-180",
                      kicks: [0, 2, 4, 6, 8, 10, 12, 14], snares: [4, 12], closedHats: Array(0..<16),
                      midToms: [10, 11, 14, 15], rides: [1, 3, 5, 7, 9, 11, 13, 15]),
            PresetData("Platformer", "Jump & run", "140-160",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14]),
            PresetData("RPG Battle", "Turn-based tension", "100-130",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [2, 6, 10, 14], rimshots: [4, 12]),
            PresetData("Racing", "Speed rush", "150-180",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: Array(0..<16), rimshots: [1, 5, 9, 13]),
            PresetData("Victory Fanfare", "Achievement unlock", "120",
                      kicks: [0, 8], snares: [4, 12], lowToms: [2, 6], midToms: [10, 11],
                      crashes: [0], rides: [0, 4, 8, 12]),
            PresetData("Game Over", "Sad ending", "80",
                      kicks: [0, 8], snares: [4, 12],
                      rides: [4, 12]),
            PresetData("Retro Arcade", "Coin-op nostalgia", "140-160",
                      kicks: [0, 4, 8, 12], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14])
        ]
    )
    
    // MARK: - Polyrhythm Category (16 presets)
    
    static let polyrhythmCategory = PresetCategory(
        name: "Polyrhythms",
        icon: "circle.grid.cross.fill",
        color: Color(red: 0.4, green: 0.2, blue: 0.8),
        presets: [
            PresetData("3 over 4", "Cross-rhythm basic", "100",
                      kicks: [0, 4, 8, 12], snares: [0, 5, 10], closedHats: [0, 4, 8, 12],
                      rides: [1, 5, 9, 13], rimshots: [2, 6, 10, 14]),
            PresetData("5 over 4", "Complex pulse", "100",
                      kicks: [0, 4, 8, 12], snares: [0, 3, 6, 9, 12], closedHats: [0, 4, 8, 12],
                      rides: [1, 4, 7, 10, 13], rimshots: [2, 5, 8, 11, 14]),
            PresetData("7 over 4", "Advanced cross", "100",
                      kicks: [0, 4, 8, 12], snares: [0, 2, 4, 7, 9, 11, 14], closedHats: [0, 4, 8, 12],
                      rides: [1, 3, 5, 7, 9, 11, 13], rimshots: [2, 6, 10, 14]),
            PresetData("Hemiola", "3 against 2", "100",
                      kicks: [0, 8], snares: [0, 5, 10], closedHats: Array(0..<16),
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14]),
            PresetData("Euclidean 5", "Even distribution", "100",
                      kicks: [0, 3, 6, 9, 12], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [1, 4, 7, 10, 13], rimshots: [2, 5, 8, 11, 14]),
            PresetData("Euclidean 7", "Seven steps", "100",
                      kicks: [0, 2, 4, 7, 9, 11, 14], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [1, 3, 5, 7, 9, 11, 13], rimshots: [2, 6, 10, 14]),
            PresetData("African Cross", "Traditional poly", "100",
                      kicks: [0, 3, 8, 11], snares: [4, 10], closedHats: Array(0..<16),
                      rides: [1, 5, 9, 13], cowbells: [0, 3, 6, 9, 12], shakers: Array(0..<16)),
            PresetData("Clave Pattern", "Afro-Cuban base", "100",
                      kicks: [0, 3, 7, 10, 12], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [1, 5, 9, 13], cowbells: [0, 3, 7, 10, 12], lowCongas: [2, 6, 10, 14], highCongas: [1, 5, 9, 13]),
            PresetData("6 over 4", "Stable cross-rhythm", "100",
                      kicks: [0, 4, 8, 12], snares: [0, 2, 5, 8, 10, 13], closedHats: [0, 4, 8, 12],
                      rides: [1, 3, 5, 7, 9, 11, 13, 15], rimshots: [2, 6, 10, 14]),
            PresetData("Tresillo", "Cuban foundation", "110",
                      kicks: [0, 3, 6], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 5, 9, 13], cowbells: [0, 3, 6], lowCongas: [2, 5, 8, 11, 14], highCongas: [1, 4, 7, 10, 13]),
            PresetData("Cascara", "Timbale pattern", "100",
                      kicks: [0, 8], snares: [3, 7, 10, 14], closedHats: [0, 3, 6, 7, 10, 11, 14],
                      rides: [1, 5, 9, 13], rimshots: [0, 3, 7, 10, 14], cowbells: [3, 7, 11]),
            PresetData("Bembe 6/8", "West African groove", "120",
                      kicks: [0, 6], snares: [3, 9], closedHats: [0, 3, 5, 6, 9, 11, 12],
                      rides: [2, 5, 8, 11, 14], cowbells: [0, 6], shakers: [0, 3, 6, 9, 12]),
            PresetData("Bossa Nova Bell", "Brazilian 2-3 clave", "130",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 3, 6, 10, 12],
                      rides: [0, 3, 6, 10, 12], rimshots: [2, 7, 11]),
            PresetData("Rumba Clave", "Afro-Cuban son", "100",
                      kicks: [0, 3, 6, 10, 12], snares: [8], closedHats: [0, 4, 8, 12],
                      rides: [1, 5, 9, 13], cowbells: [0, 3, 6, 10, 12], lowCongas: [2, 6, 10, 14], highCongas: [1, 5, 9, 13]),
            PresetData("Soukous", "Central African dance", "140",
                      kicks: [0, 3, 7, 10, 13], snares: [4, 12], closedHats: Array(0..<16),
                      rides: [1, 5, 9, 13], cowbells: [0, 3, 7, 10, 13], shakers: Array(0..<16)),
            PresetData("Fume Fume", "West African swing", "120",
                      kicks: [0, 2, 5, 7, 10, 12, 14], snares: [4, 12], closedHats: [0, 4, 8, 12],
                      rides: [1, 5, 9, 13], cowbells: [0, 2, 5, 7, 10, 12, 14], shakers: [0, 2, 4, 6, 8, 10, 12, 14])
        ]
    )
    
    // MARK: - Odd Time Signatures Category (16 presets)
    
    static let oddTimeCategory = PresetCategory(
        name: "Odd Time Signatures",
        icon: "metronome.fill",
        color: Color(red: 0.8, green: 0.4, blue: 0.2),
        presets: [
            PresetData("7/8 Rock", "Progressive feel", "120",
                      kicks: [0, 7], snares: [3], closedHats: [0, 2, 4, 6, 8, 10, 12],
                      rides: [0, 2, 4, 6, 8, 10, 12], rimshots: [3, 7]),
            PresetData("5/4 Groove", "Take Five style", "170",
                      kicks: [0, 5], snares: [3, 8], closedHats: [0, 2, 4, 6, 8],
                      rides: [0, 2, 4, 6, 8, 10], rimshots: [1, 5, 9, 13]),
            PresetData("9/8 Compound", "Three-three-three", "120",
                      kicks: [0, 6], snares: [3], closedHats: [0, 3, 6, 9, 12],
                      rides: [0, 3, 6, 9, 12], rimshots: [2, 5, 8, 11, 14]),
            PresetData("11/8 Complex", "Asymmetric pulse", "100",
                      kicks: [0, 6], snares: [3, 8], closedHats: [0, 2, 4, 6, 8, 10],
                      rides: [1, 3, 5, 7, 9, 11], rimshots: [2, 6, 10]),
            PresetData("13/8 Math", "Prog complexity", "100",
                      kicks: [0, 6, 10], snares: [3], closedHats: [0, 2, 4, 6, 8, 10, 12],
                      rides: [1, 5, 9, 13], rimshots: [3, 7, 11]),
            PresetData("15/16 Odd", "Near-four feel", "100",
                      kicks: [0, 8], snares: [4, 12], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [1, 3, 5, 7, 9, 11, 13], rimshots: [2, 6, 10, 14]),
            PresetData("Mixed Meter", "Changing time", "100",
                      kicks: [0, 5, 8, 12], snares: [3, 10], closedHats: Array(0..<16),
                      rides: [1, 4, 7, 9, 13], rimshots: [2, 6, 10, 14]),
            PresetData("Aksak", "Balkan 9/8", "180",
                      kicks: [0, 4, 7], snares: [2, 5], closedHats: [0, 2, 4, 5, 7],
                      rides: [1, 3, 6, 8], rimshots: [0, 4, 7]),
            PresetData("6/8 March", "Traditional march feel", "120",
                      kicks: [0, 6, 12], snares: [3, 9], closedHats: [0, 3, 6, 9, 12],
                      rides: [0, 3, 6, 9, 12], rimshots: [2, 5, 8, 11, 14]),
            PresetData("10/8 Afro", "Fela Kuti style", "110",
                      kicks: [0, 5, 8], snares: [3, 12], closedHats: [0, 2, 5, 7, 8, 10, 12, 14],
                      rides: [1, 5, 9, 13], cowbells: [0, 5, 8], shakers: Array(0..<16)),
            PresetData("7/4 Prog", "Money groove", "120",
                      kicks: [0, 7], snares: [4, 11], closedHats: [0, 2, 4, 6, 8, 10, 12],
                      rides: [0, 2, 4, 6, 8, 10, 12], rimshots: [4, 11]),
            PresetData("19/16 Balkan", "2+2+3+2+2+3+2+3", "100",
                      kicks: [0, 4, 9, 13], snares: [2, 7, 11, 16], closedHats: Array(0..<16),
                      rides: [1, 5, 9, 13], rimshots: [0, 4, 9, 13]),
            PresetData("12/8 Shuffle", "Texas shuffle", "90",
                      kicks: [0, 12], snares: [4], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [0, 3, 6, 9, 12], rimshots: [2, 10]),
            PresetData("5/8 Fast", "3+2 division", "160",
                      kicks: [0, 5, 10], snares: [3, 8, 13], closedHats: [0, 3, 5, 8, 10, 13],
                      rides: [1, 4, 6, 9, 11, 14], rimshots: [2, 7, 12]),
            PresetData("11/4 Tool", "Lateralus style", "95",
                      kicks: [0, 5, 11], snares: [3, 8], closedHats: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [1, 5, 9, 13], rimshots: [3, 8]),
            PresetData("21/16 Math", "3+3+3+3+3+3+3", "80",
                      kicks: [0, 6, 12], snares: [3, 9, 15], closedHats: Array(0..<16),
                      rides: [1, 5, 9, 13], rimshots: [0, 6, 12])
        ]
    )
    
    // MARK: - Drum Rudiments Category (11 presets)
    
    static let rudimentsCategory = PresetCategory(
        name: "Drum Rudiments",
        icon: "music.note.tv.fill",
        color: Color(red: 0.6, green: 0.6, blue: 0.6),
        presets: [
            PresetData("Single Stroke", "RLRL basic", "100-160",
                      snares: Array(0..<16),
                      rides: [0, 4, 8, 12], rimshots: [2, 6, 10, 14]),
            PresetData("Double Stroke", "RRLL rolls", "100-160",
                      snares: [0, 1, 4, 5, 8, 9, 12, 13],
                      rides: [0, 4, 8, 12], rimshots: [2, 6, 10, 14]),
            PresetData("Paradiddle", "RLRR LRLL", "100-140",
                      snares: [0, 2, 4, 5, 8, 10, 12, 13],
                      rides: [0, 4, 8, 12], rimshots: [1, 5, 9, 13]),
            PresetData("Flam", "Grace notes", "80-120",
                      kicks: [0, 8], snares: [0, 1, 8, 9],
                      rides: [4, 12], rimshots: [0, 8]),
            PresetData("Drag", "Double grace", "80-120",
                      kicks: [0, 8], snares: [0, 1, 2, 8, 9, 10],
                      rides: [4, 12], rimshots: [0, 8]),
            PresetData("Five Stroke Roll", "RRLLR", "100-140",
                      snares: [0, 1, 2, 3, 4, 8, 9, 10, 11, 12],
                      rides: [0, 4, 8, 12], rimshots: [4, 12]),
            PresetData("Seven Stroke Roll", "RRLLRRL", "100-140",
                      snares: [0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14],
                      rides: [0, 8], rimshots: [6, 14]),
            PresetData("Swiss Triplet", "Flam accent", "80-120",
                      kicks: [0, 6, 12], snares: [0, 2, 4, 6, 8, 10, 12, 14],
                      rides: [0, 6, 12], rimshots: [2, 8, 14]),
            PresetData("Ratamacue", "Triplet rudiment", "80-120",
                      kicks: [0, 8], snares: [0, 2, 3, 4, 8, 10, 11, 12],
                      rides: [0, 4, 8, 12], rimshots: [4, 12]),
            PresetData("Ruff", "Three-stroke ruff", "80-120",
                      kicks: [0, 8], snares: [0, 1, 2, 8, 9, 10],
                      rides: [4, 12], rimshots: [0, 8]),
            PresetData("Paradiddle-diddle", "RLRRLL pattern", "100-140",
                      snares: [0, 2, 4, 5, 6, 8, 10, 12, 13, 14],
                      rides: [0, 4, 8, 12], rimshots: [1, 5, 9, 13])
        ]
    )
}
