//
//  PromptTemplateModels.swift
//  Stori
//
//  Created by Stori Team
//

import Foundation

struct PromptTemplateData {
    
    struct GenreData {
        let name: String
        let subGenres: [String]
        let typicalInstruments: [String]
        let typicalMoods: [String]
        let defaultBPM: Int
        let bpmRange: ClosedRange<Double>
        let typicalKeys: [String]
    }
    
    static let genres: [String: GenreData] = [
        "Electronic": GenreData(
            name: "Electronic",
            subGenres: ["Deep House", "Techno", "Synthwave", "EDM", "Dubstep", "Trance", "Ambient", "IDM", "Drum & Bass"],
            typicalInstruments: ["Synthesizer", "Drum Machine", "Bass Synth", "Pads", "Sequencer", "Sampler", "Vocoder"],
            typicalMoods: ["Energetic", "Euphoric", "Hypnotic", "Dark", "Chill", "Futuristic", "Atmospheric"],
            defaultBPM: 125,
            bpmRange: 100...150,
            typicalKeys: ["A minor", "C minor", "F minor", "G minor", "D minor"]
        ),
        "Rock": GenreData(
            name: "Rock",
            subGenres: ["Classic Rock", "Punk", "Alternative", "Indie", "Hard Rock", "Psychedelic", "Progressive"],
            typicalInstruments: ["Electric Guitar", "Bass Guitar", "Drums", "Organ", "Piano", "Acoustic Guitar"],
            typicalMoods: ["Energetic", "Rebellious", "Gritty", "Powerful", "Anthemic", "Raw"],
            defaultBPM: 120,
            bpmRange: 90...160,
            typicalKeys: ["E major", "A major", "D major", "G major", "E minor"]
        ),
        "Pop": GenreData(
            name: "Pop",
            subGenres: ["Synth Pop", "Indie Pop", "Electropop", "Ballad", "Dance Pop", "K-Pop"],
            typicalInstruments: ["Synthesizer", "Electric Guitar", "Drums", "Piano", "Bass", "Vocals"],
            typicalMoods: ["Uplifting", "Happy", "Catchy", "Bright", "Romantic", "Melancholic"],
            defaultBPM: 118,
            bpmRange: 90...130,
            typicalKeys: ["C major", "G major", "F major", "A minor", "D major"]
        ),
        "Hip-Hop": GenreData(
            name: "Hip-Hop",
            subGenres: ["Lo-Fi", "Trap", "Boom Bap", "Old School", "Drill", "Jazz Rap"],
            typicalInstruments: ["Drum Machine", "Sampler", "Synthesizer", "808 Bass", "Piano", "Electric Piano"],
            typicalMoods: ["Chill", "Aggressive", "Groovy", "Dark", "Confident", "Mellow"],
            defaultBPM: 90,
            bpmRange: 70...140,
            typicalKeys: ["C minor", "F minor", "A minor", "G minor", "Bb minor"]
        ),
        "Jazz": GenreData(
            name: "Jazz",
            subGenres: ["Bossa Nova", "Swing", "Cool Jazz", "Fusion", "Bebop", "Smooth Jazz"],
            typicalInstruments: ["Saxophone", "Trumpet", "Piano", "Double Bass", "Drums", "Guitar", "Vibraphone"],
            typicalMoods: ["Sophisticated", "Relaxed", "Smooth", "Playful", "Melancholic", "Romantic"],
            defaultBPM: 108,
            bpmRange: 60...160,
            typicalKeys: ["Bb major", "Eb major", "F major", "C minor", "G minor"]
        ),
        "Classical": GenreData(
            name: "Classical",
            subGenres: ["Orchestral", "Chamber", "Piano Solo", "String Quartet", "Baroque", "Romantic"],
            typicalInstruments: ["Violin", "Cello", "Piano", "Viola", "Flute", "Oboe", "Clarinet", "Trumpet", "French Horn", "Timpani"],
            typicalMoods: ["Epic", "Dramatic", "Emotional", "Serene", "Majestic", "Tense"],
            defaultBPM: 80,
            bpmRange: 40...140,
            typicalKeys: ["C minor", "D minor", "G major", "D major", "A minor"]
        ),
        "Country": GenreData(
            name: "Country",
            subGenres: ["Americana", "Bluegrass", "Outlaw Country", "Country Pop", "Folk Country"],
            typicalInstruments: ["Acoustic Guitar", "Pedal Steel", "Fiddle", "Banjo", "Mandolin", "Bass", "Drums"],
            typicalMoods: ["Nostalgic", "Heartfelt", "Warm", "Storytelling", "Rustic", "Upbeat"],
            defaultBPM: 96,
            bpmRange: 70...120,
            typicalKeys: ["G major", "D major", "C major", "A major", "E major"]
        ),
        "Metal": GenreData(
            name: "Metal",
            subGenres: ["Heavy Metal", "Thrash", "Doom", "Power Metal", "Symphonic Metal", "Metalcore"],
            typicalInstruments: ["Distorted Guitar", "Double Kick Drums", "Bass", "Vocals"],
            typicalMoods: ["Aggressive", "Heavy", "Intense", "Dark", "Epic", "Powerful"],
            defaultBPM: 150,
            bpmRange: 110...200,
            typicalKeys: ["E minor", "D minor", "C# minor", "B minor"]
        ),
        "Ambient": GenreData(
            name: "Ambient",
            subGenres: ["Drone", "Soundscape", "Dark Ambient", "Meditative", "Space"],
            typicalInstruments: ["Synthesizer", "Pads", "Field Recordings", "Piano", "Chime"],
            typicalMoods: ["Peaceful", "Ethereal", "Spacious", "Mysterious", "Calm", "Dreamy"],
            defaultBPM: 60,
            bpmRange: 40...90,
            typicalKeys: ["C major", "D major", "A minor", "E minor"]
        ),
        "Folk": GenreData(
            name: "Folk",
            subGenres: ["Indie Folk", "Celtic", "Acoustic", "Traditional"],
            typicalInstruments: ["Acoustic Guitar", "Violin", "Banjo", "Mandolin", "Harmonica", "Accordion"],
            typicalMoods: ["Intimate", "Earthly", "Nostalgic", "Warm", "Storytelling"],
            defaultBPM: 100,
            bpmRange: 70...120,
            typicalKeys: ["G major", "C major", "D major", "A minor"]
        ),
        "Reggae": GenreData(
            name: "Reggae",
            subGenres: ["Roots", "Dub", "Dancehall", "Rocksteady", "Ska"],
            typicalInstruments: ["Electric Guitar", "Bass", "Organ", "Drums", "Percussion", "Horns"],
            typicalMoods: ["Laid-back", "Groovy", "Chill", "Positive", "Sunny"],
            defaultBPM: 90,
            bpmRange: 60...140,
            typicalKeys: ["A minor", "G major", "C major", "D major"]
        ),
        "Blues": GenreData(
            name: "Blues",
            subGenres: ["Delta Blues", "Chicago Blues", "Electric Blues", "Blues Rock"],
            typicalInstruments: ["Electric Guitar", "Harmonica", "Piano", "Bass", "Drums", "Slide Guitar"],
            typicalMoods: ["Soulful", "Gritty", "Melancholic", "Raw", "Expressive"],
            defaultBPM: 100,
            bpmRange: 60...140,
            typicalKeys: ["E major", "A major", "B major", "G major"]
        )
    ]
    
    static let keys = [
        "C major", "G major", "D major", "A major", "E major", "B major", "F# major",
        "F major", "Bb major", "Eb major", "Ab major", "Db major",
        "A minor", "E minor", "B minor", "F# minor", "C# minor", "G# minor", "D# minor",
        "D minor", "G minor", "C minor", "F minor", "Bb minor"
    ]
    
    static let commonChordProgressions: [String: [String]] = [
        "Pop/Rock": ["I-V-vi-IV", "I-vi-IV-V", "vi-IV-I-V", "I-IV-V-IV"],
        "Jazz": ["ii-V-I", "ii-V-I-vi", "I-vi-ii-V", "iii-vi-ii-V"],
        "Blues": ["12-Bar Blues", "I-IV-I-V-IV-I"],
        "Minor": ["i-VI-III-VII", "i-iv-v", "i-VI-iv-V"],
        "Epic": ["vi-IV-I-V", "i-VI-III-VII"],
        "Custom": []
    ]
}

