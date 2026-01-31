//
//  IntentEngine.swift
//  Stori
//
//  Intent Engine V2 - Musical goal recognition and quick actions
//

import Foundation

/// Recognized musical goals from Intent Engine V2
enum MusicalGoal: String, CaseIterable, Identifiable {
    // Emotional Qualities
    case emotional = "emotional"
    case dreamy = "dreamy"
    case aggressive = "aggressive"
    case melancholic = "melancholic"
    case uplifting = "uplifting"
    
    // Energy States
    case energetic = "energetic"
    case calm = "calm"
    case tense = "tense"
    case relaxed = "relaxed"
    
    // Aesthetic Qualities
    case dark = "dark"
    case bright = "bright"
    case warm = "warm"
    case cold = "cold"
    case vintage = "vintage"
    case modern = "modern"
    
    // Production Styles
    case cinematic = "cinematic"
    case intimate = "intimate"
    case epic = "epic"
    case minimal = "minimal"
    case dense = "dense"
    
    // Spatial Qualities
    case spacious = "spacious"
    case tight = "tight"
    case wide = "wide"
    case focused = "focused"
    
    var id: String { rawValue }
    
    /// Display name for UI
    var displayName: String {
        rawValue.capitalized
    }
    
    /// Icon for visual representation
    var icon: String {
        switch self {
        // Emotional
        case .emotional: return "heart.fill"
        case .dreamy: return "cloud.fill"
        case .aggressive: return "bolt.fill"
        case .melancholic: return "cloud.rain.fill"
        case .uplifting: return "arrow.up.heart.fill"
        
        // Energy
        case .energetic: return "flame.fill"
        case .calm: return "leaf.fill"
        case .tense: return "exclamationmark.triangle.fill"
        case .relaxed: return "bed.double.fill"
        
        // Aesthetic
        case .dark: return "moon.fill"
        case .bright: return "sun.max.fill"
        case .warm: return "thermometer.sun.fill"
        case .cold: return "snowflake"
        case .vintage: return "camera.fill"
        case .modern: return "sparkles"
        
        // Production
        case .cinematic: return "film.fill"
        case .intimate: return "person.fill"
        case .epic: return "mountain.2.fill"
        case .minimal: return "minus.circle.fill"
        case .dense: return "square.grid.3x3.fill"
        
        // Spatial
        case .spacious: return "arrow.up.left.and.arrow.down.right"
        case .tight: return "arrow.down.right.and.arrow.up.left"
        case .wide: return "arrow.left.and.right"
        case .focused: return "scope"
        }
    }
    
    /// Example prompt for this goal
    var examplePrompt: String {
        "Make it \(rawValue)"
    }
    
    /// Category for grouping in UI
    var category: GoalCategory {
        switch self {
        case .emotional, .dreamy, .aggressive, .melancholic, .uplifting:
            return .emotional
        case .energetic, .calm, .tense, .relaxed:
            return .energy
        case .dark, .bright, .warm, .cold, .vintage, .modern:
            return .aesthetic
        case .cinematic, .intimate, .epic, .minimal, .dense:
            return .production
        case .spacious, .tight, .wide, .focused:
            return .spatial
        }
    }
}

enum GoalCategory: String, CaseIterable {
    case emotional = "Emotional"
    case energy = "Energy"
    case aesthetic = "Aesthetic"
    case production = "Production"
    case spatial = "Spatial"
    
    var icon: String {
        switch self {
        case .emotional: return "heart.fill"
        case .energy: return "bolt.fill"
        case .aesthetic: return "paintbrush.fill"
        case .production: return "slider.horizontal.3"
        case .spatial: return "square.3.layers.3d"
        }
    }
    
    var goals: [MusicalGoal] {
        MusicalGoal.allCases.filter { $0.category == self }
    }
}

/// Metrics for Intent Engine performance tracking
struct IntentEngineMetrics {
    var totalRequests: Int = 0
    var intentEngineUsed: Int = 0
    var llmFallbackUsed: Int = 0
    var totalIntentEngineTime: TimeInterval = 0
    var totalLLMTime: TimeInterval = 0
    
    var intentEngineAdoptionRate: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(intentEngineUsed) / Double(totalRequests)
    }
    
    var averageIntentEngineTime: TimeInterval {
        guard intentEngineUsed > 0 else { return 0 }
        return totalIntentEngineTime / Double(intentEngineUsed)
    }
    
    var averageLLMTime: TimeInterval {
        guard llmFallbackUsed > 0 else { return 0 }
        return totalLLMTime / Double(llmFallbackUsed)
    }
    
    var speedImprovement: Double {
        guard averageLLMTime > 0 else { return 0 }
        return (averageLLMTime - averageIntentEngineTime) / averageLLMTime
    }
    
    mutating func recordIntentEngine(duration: TimeInterval) {
        totalRequests += 1
        intentEngineUsed += 1
        totalIntentEngineTime += duration
    }
    
    mutating func recordLLMFallback(duration: TimeInterval) {
        totalRequests += 1
        llmFallbackUsed += 1
        totalLLMTime += duration
    }
}
