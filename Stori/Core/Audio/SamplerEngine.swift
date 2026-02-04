//
//  SamplerEngine.swift
//  Stori
//
//  Created by TellUrStori on 12/19/25.
//
//  Sample-based instrument engine using Apple's AVAudioUnitSampler.
//  Loads SoundFont (.sf2) files for realistic instrument sounds.
//
//  General MIDI Program Numbers (0-127):
//  0-7: Piano, 8-15: Chromatic Percussion, 16-23: Organ,
//  24-31: Guitar, 32-39: Bass, 40-47: Strings, 48-55: Ensemble,
//  56-63: Brass, 64-71: Reed, 72-79: Pipe, 80-87: Synth Lead,
//  88-95: Synth Pad, 96-103: Synth Effects, 104-111: Ethnic,
//  112-119: Percussive, 120-127: Sound Effects
//

import Foundation
import AVFoundation
import Combine

// MARK: - General MIDI Instrument

/// General MIDI instrument program numbers
enum GMInstrument: Int, CaseIterable, Identifiable {
    // Piano (0-7)
    case acousticGrandPiano = 0
    case brightAcousticPiano = 1
    case electricGrandPiano = 2
    case honkyTonkPiano = 3
    case electricPiano1 = 4
    case electricPiano2 = 5
    case harpsichord = 6
    case clavinet = 7
    
    // Chromatic Percussion (8-15)
    case celesta = 8
    case glockenspiel = 9
    case musicBox = 10
    case vibraphone = 11
    case marimba = 12
    case xylophone = 13
    case tubularBells = 14
    case dulcimer = 15
    
    // Organ (16-23)
    case drawbarOrgan = 16
    case percussiveOrgan = 17
    case rockOrgan = 18
    case churchOrgan = 19
    case reedOrgan = 20
    case accordion = 21
    case harmonica = 22
    case tangoAccordion = 23
    
    // Guitar (24-31)
    case acousticGuitarNylon = 24
    case acousticGuitarSteel = 25
    case electricGuitarJazz = 26
    case electricGuitarClean = 27
    case electricGuitarMuted = 28
    case overdrivenGuitar = 29
    case distortionGuitar = 30
    case guitarHarmonics = 31
    
    // Bass (32-39)
    case acousticBass = 32
    case electricBassFinger = 33
    case electricBassPick = 34
    case fretlessBass = 35
    case slapBass1 = 36
    case slapBass2 = 37
    case synthBass1 = 38
    case synthBass2 = 39
    
    // Strings (40-47)
    case violin = 40
    case viola = 41
    case cello = 42
    case contrabass = 43
    case tremoloStrings = 44
    case pizzicatoStrings = 45
    case orchestralHarp = 46
    case timpani = 47
    
    // Ensemble (48-55)
    case stringEnsemble1 = 48
    case stringEnsemble2 = 49
    case synthStrings1 = 50
    case synthStrings2 = 51
    case choirAahs = 52
    case voiceOohs = 53
    case synthVoice = 54
    case orchestraHit = 55
    
    // Brass (56-63)
    case trumpet = 56
    case trombone = 57
    case tuba = 58
    case mutedTrumpet = 59
    case frenchHorn = 60
    case brassSection = 61
    case synthBrass1 = 62
    case synthBrass2 = 63
    
    // Reed (64-71)
    case sopranoSax = 64
    case altoSax = 65
    case tenorSax = 66
    case baritoneSax = 67
    case oboe = 68
    case englishHorn = 69
    case bassoon = 70
    case clarinet = 71
    
    // Pipe (72-79)
    case piccolo = 72
    case flute = 73
    case recorder = 74
    case panFlute = 75
    case blownBottle = 76
    case shakuhachi = 77
    case whistle = 78
    case ocarina = 79
    
    // Synth Lead (80-87)
    case leadSquare = 80
    case leadSawtooth = 81
    case leadCalliope = 82
    case leadChiff = 83
    case leadCharang = 84
    case leadVoice = 85
    case leadFifths = 86
    case leadBassLead = 87
    
    // Synth Pad (88-95)
    case padNewAge = 88
    case padWarm = 89
    case padPolysynth = 90
    case padChoir = 91
    case padBowed = 92
    case padMetallic = 93
    case padHalo = 94
    case padSweep = 95
    
    // Synth Effects (96-103)
    case fxRain = 96
    case fxSoundtrack = 97
    case fxCrystal = 98
    case fxAtmosphere = 99
    case fxBrightness = 100
    case fxGoblins = 101
    case fxEchoes = 102
    case fxSciFi = 103
    
    // Ethnic (104-111)
    case sitar = 104
    case banjo = 105
    case shamisen = 106
    case koto = 107
    case kalimba = 108
    case bagpipe = 109
    case fiddle = 110
    case shanai = 111
    
    // Percussive (112-119)
    case tinkleBell = 112
    case agogo = 113
    case steelDrums = 114
    case woodblock = 115
    case taikoDrum = 116
    case melodicTom = 117
    case synthDrum = 118
    case reverseCymbal = 119
    
    // Sound Effects (120-127)
    case guitarFretNoise = 120
    case breathNoise = 121
    case seashore = 122
    case birdTweet = 123
    case telephoneRing = 124
    case helicopter = 125
    case applause = 126
    case gunshot = 127
    
    // GM Drum Kits (Channel 10) - Extended values for special handling
    // Note: These use program numbers 0, 8, 16, 24, 25, 32, 40, 48 on channel 10
    case standardDrumKit = 1000   // Program 0
    case roomDrumKit = 1008       // Program 8
    case powerDrumKit = 1016      // Program 16
    case electronicDrumKit = 1024 // Program 24
    case tr808DrumKit = 1025      // Program 25
    case jazzDrumKit = 1032       // Program 32
    case brushDrumKit = 1040     // Program 40
    case orchestraDrumKit = 1048  // Program 48
    
    var id: Int { rawValue }
    
    var name: String {
        switch self {
        // Piano
        case .acousticGrandPiano: return "Acoustic Grand Piano"
        case .brightAcousticPiano: return "Bright Acoustic Piano"
        case .electricGrandPiano: return "Electric Grand Piano"
        case .honkyTonkPiano: return "Honky-Tonk Piano"
        case .electricPiano1: return "Electric Piano 1"
        case .electricPiano2: return "Electric Piano 2"
        case .harpsichord: return "Harpsichord"
        case .clavinet: return "Clavinet"
        // Chromatic Percussion
        case .celesta: return "Celesta"
        case .glockenspiel: return "Glockenspiel"
        case .musicBox: return "Music Box"
        case .vibraphone: return "Vibraphone"
        case .marimba: return "Marimba"
        case .xylophone: return "Xylophone"
        case .tubularBells: return "Tubular Bells"
        case .dulcimer: return "Dulcimer"
        // Organ
        case .drawbarOrgan: return "Drawbar Organ"
        case .percussiveOrgan: return "Percussive Organ"
        case .rockOrgan: return "Rock Organ"
        case .churchOrgan: return "Church Organ"
        case .reedOrgan: return "Reed Organ"
        case .accordion: return "Accordion"
        case .harmonica: return "Harmonica"
        case .tangoAccordion: return "Tango Accordion"
        // Guitar
        case .acousticGuitarNylon: return "Acoustic Guitar (Nylon)"
        case .acousticGuitarSteel: return "Acoustic Guitar (Steel)"
        case .electricGuitarJazz: return "Electric Guitar (Jazz)"
        case .electricGuitarClean: return "Electric Guitar (Clean)"
        case .electricGuitarMuted: return "Electric Guitar (Muted)"
        case .overdrivenGuitar: return "Overdriven Guitar"
        case .distortionGuitar: return "Distortion Guitar"
        case .guitarHarmonics: return "Guitar Harmonics"
        // Bass
        case .acousticBass: return "Acoustic Bass"
        case .electricBassFinger: return "Electric Bass (Finger)"
        case .electricBassPick: return "Electric Bass (Pick)"
        case .fretlessBass: return "Fretless Bass"
        case .slapBass1: return "Slap Bass 1"
        case .slapBass2: return "Slap Bass 2"
        case .synthBass1: return "Synth Bass 1"
        case .synthBass2: return "Synth Bass 2"
        // Strings
        case .violin: return "Violin"
        case .viola: return "Viola"
        case .cello: return "Cello"
        case .contrabass: return "Contrabass"
        case .tremoloStrings: return "Tremolo Strings"
        case .pizzicatoStrings: return "Pizzicato Strings"
        case .orchestralHarp: return "Orchestral Harp"
        case .timpani: return "Timpani"
        // Ensemble
        case .stringEnsemble1: return "String Ensemble 1"
        case .stringEnsemble2: return "String Ensemble 2"
        case .synthStrings1: return "Synth Strings 1"
        case .synthStrings2: return "Synth Strings 2"
        case .choirAahs: return "Choir Aahs"
        case .voiceOohs: return "Voice Oohs"
        case .synthVoice: return "Synth Voice"
        case .orchestraHit: return "Orchestra Hit"
        // Brass
        case .trumpet: return "Trumpet"
        case .trombone: return "Trombone"
        case .tuba: return "Tuba"
        case .mutedTrumpet: return "Muted Trumpet"
        case .frenchHorn: return "French Horn"
        case .brassSection: return "Brass Section"
        case .synthBrass1: return "Synth Brass 1"
        case .synthBrass2: return "Synth Brass 2"
        // Reed
        case .sopranoSax: return "Soprano Sax"
        case .altoSax: return "Alto Sax"
        case .tenorSax: return "Tenor Sax"
        case .baritoneSax: return "Baritone Sax"
        case .oboe: return "Oboe"
        case .englishHorn: return "English Horn"
        case .bassoon: return "Bassoon"
        case .clarinet: return "Clarinet"
        // Pipe
        case .piccolo: return "Piccolo"
        case .flute: return "Flute"
        case .recorder: return "Recorder"
        case .panFlute: return "Pan Flute"
        case .blownBottle: return "Blown Bottle"
        case .shakuhachi: return "Shakuhachi"
        case .whistle: return "Whistle"
        case .ocarina: return "Ocarina"
        // Synth Lead
        case .leadSquare: return "Lead (Square)"
        case .leadSawtooth: return "Lead (Sawtooth)"
        case .leadCalliope: return "Lead (Calliope)"
        case .leadChiff: return "Lead (Chiff)"
        case .leadCharang: return "Lead (Charang)"
        case .leadVoice: return "Lead (Voice)"
        case .leadFifths: return "Lead (Fifths)"
        case .leadBassLead: return "Lead (Bass + Lead)"
        // Synth Pad
        case .padNewAge: return "Pad (New Age)"
        case .padWarm: return "Pad (Warm)"
        case .padPolysynth: return "Pad (Polysynth)"
        case .padChoir: return "Pad (Choir)"
        case .padBowed: return "Pad (Bowed)"
        case .padMetallic: return "Pad (Metallic)"
        case .padHalo: return "Pad (Halo)"
        case .padSweep: return "Pad (Sweep)"
        // Synth Effects
        case .fxRain: return "FX (Rain)"
        case .fxSoundtrack: return "FX (Soundtrack)"
        case .fxCrystal: return "FX (Crystal)"
        case .fxAtmosphere: return "FX (Atmosphere)"
        case .fxBrightness: return "FX (Brightness)"
        case .fxGoblins: return "FX (Goblins)"
        case .fxEchoes: return "FX (Echoes)"
        case .fxSciFi: return "FX (Sci-Fi)"
        // Ethnic
        case .sitar: return "Sitar"
        case .banjo: return "Banjo"
        case .shamisen: return "Shamisen"
        case .koto: return "Koto"
        case .kalimba: return "Kalimba"
        case .bagpipe: return "Bagpipe"
        case .fiddle: return "Fiddle"
        case .shanai: return "Shanai"
        // Percussive
        case .tinkleBell: return "Tinkle Bell"
        case .agogo: return "Agogo"
        case .steelDrums: return "Steel Drums"
        case .woodblock: return "Woodblock"
        case .taikoDrum: return "Taiko Drum"
        case .melodicTom: return "Melodic Tom"
        case .synthDrum: return "Synth Drum"
        case .reverseCymbal: return "Reverse Cymbal"
        // Sound Effects
        case .guitarFretNoise: return "Guitar Fret Noise"
        case .breathNoise: return "Breath Noise"
        case .seashore: return "Seashore"
        case .birdTweet: return "Bird Tweet"
        case .telephoneRing: return "Telephone Ring"
        case .helicopter: return "Helicopter"
        case .applause: return "Applause"
        case .gunshot: return "Gunshot"
        // GM Drum Kits
        case .standardDrumKit: return "Standard Drum Kit"
        case .roomDrumKit: return "Room Drum Kit"
        case .powerDrumKit: return "Power Drum Kit"
        case .electronicDrumKit: return "Electronic Drum Kit"
        case .tr808DrumKit: return "TR-808 Drum Kit"
        case .jazzDrumKit: return "Jazz Drum Kit"
        case .brushDrumKit: return "Brush Drum Kit"
        case .orchestraDrumKit: return "Orchestra Drum Kit"
        }
    }
    
    var category: GMCategory {
        switch rawValue {
        case 0...7: return .piano
        case 8...15: return .chromaticPercussion
        case 16...23: return .organ
        case 24...31: return .guitar
        case 32...39: return .bass
        case 40...47: return .strings
        case 48...55: return .ensemble
        case 56...63: return .brass
        case 64...71: return .reed
        case 72...79: return .pipe
        case 80...87: return .synthLead
        case 88...95: return .synthPad
        case 96...103: return .synthEffects
        case 104...111: return .ethnic
        case 112...119: return .percussive
        case 120...127: return .soundEffects
        case 1000...1999: return .drums  // GM Drum Kits (channel 10)
        default: return .piano
        }
    }
    
    var icon: String {
        category.icon
    }
}

// MARK: - GM Category

enum GMCategory: String, CaseIterable, Identifiable {
    case piano = "Piano"
    case chromaticPercussion = "Chromatic Percussion"
    case organ = "Organ"
    case guitar = "Guitar"
    case bass = "Bass"
    case strings = "Strings"
    case ensemble = "Ensemble"
    case brass = "Brass"
    case reed = "Reed"
    case pipe = "Pipe"
    case synthLead = "Synth Lead"
    case synthPad = "Synth Pad"
    case synthEffects = "Synth Effects"
    case ethnic = "Ethnic"
    case percussive = "Percussive"
    case soundEffects = "Sound Effects"
    case drums = "Drums"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .piano: return "pianokeys"
        case .chromaticPercussion: return "bell.fill"
        case .organ: return "music.note.house.fill"
        case .guitar: return "guitars.fill"
        case .bass: return "waveform.path"
        case .strings: return "music.quarternote.3"
        case .ensemble: return "person.3.fill"
        case .brass: return "horn.fill"
        case .reed: return "wind"
        case .pipe: return "lungs.fill"
        case .synthLead: return "waveform"
        case .synthPad: return "waveform.badge.plus"
        case .synthEffects: return "sparkles"
        case .ethnic: return "globe"
        case .percussive: return "circle.hexagongrid.fill"
        case .soundEffects: return "speaker.wave.3.fill"
        case .drums: return "music.note.list"
        }
    }
    
    var instruments: [GMInstrument] {
        GMInstrument.allCases.filter { $0.category == self }
    }
}

// MARK: - Sampler Engine

/// Sample-based instrument engine using Apple's AVAudioUnitSampler.
/// Provides access to 128 General MIDI instruments via SoundFont files.
class SamplerEngine {
    
    // MARK: - Properties
    
    /// The AVAudioUnitSampler that does the heavy lifting
    private(set) var sampler: AVAudioUnitSampler
    
    /// Audio engine (can be shared or standalone)
    private var audioEngine: AVAudioEngine?
    private var ownsEngine: Bool = false
    
    /// Currently loaded instrument
    private(set) var currentInstrument: GMInstrument = .acousticGrandPiano
    
    /// SoundFont URL
    private var soundFontURL: URL?
    
    /// Whether the sampler is ready to play
    private(set) var isReady: Bool = false
    
    /// Whether the engine is running
    private(set) var isRunning: Bool = false
    
    /// Active notes (for tracking)
    private var activeNotes: Set<UInt8> = []
    
    // MARK: - Initialization
    
    /// Create a sampler that attaches to an existing audio engine
    /// The sampler node is attached to the provided engine, ensuring single-engine routing
    /// The caller (AudioEngine) is responsible for routing to the correct destination
    /// - Parameters:
    ///   - engine: The AVAudioEngine to attach to
    ///   - connectToMixer: If true, connects directly to mainMixerNode (for preview engines)
    ///   - deferAttachment: If true, don't attach yet - call attachToEngine() after loading samples
    init(attachTo engine: AVAudioEngine, connectToMixer: Bool = false, deferAttachment: Bool = false) {
        self.sampler = AVAudioUnitSampler()
        self.audioEngine = engine
        self.ownsEngine = false
        
        // Defer attachment to avoid crashes when loading samples on a running engine
        if !deferAttachment {
            engine.attach(sampler)
            
            // Connect to mainMixerNode for standalone preview engines
            // For DAW tracks, AudioEngine handles routing through plugin chain
            if connectToMixer {
                engine.connect(sampler, to: engine.mainMixerNode, format: nil)
            }
        }
    }
    
    /// Attach the sampler to the engine (call after loading samples if deferAttachment was true)
    func attachToEngine() {
        guard let engine = audioEngine else { return }
        if sampler.engine == nil {
            engine.attach(sampler)
        }
    }
    
    /// Factory method for creating a standalone preview sampler (NOT for DAW track use!)
    /// This creates its own isolated AVAudioEngine for preview purposes only (e.g., Piano Roll)
    /// NEVER use this for DAW track instruments - use init(attachTo:) instead
    static func createPreviewSampler() -> SamplerEngine {
        let previewEngine = AVAudioEngine()
        let sampler = SamplerEngine(attachTo: previewEngine, connectToMixer: true)
        sampler.ownsEngine = true  // This sampler owns its engine
        return sampler
    }
    
    // MARK: - Lifecycle
    
    /// Start the audio engine (only for standalone mode)
    func start() throws {
        if ownsEngine {
            if audioEngine == nil {
                audioEngine = AVAudioEngine()
            }
            
            guard let engine = audioEngine else { return }
            
            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
            
            try engine.start()
            isRunning = true
        } else {
            // Already attached to external engine
            isRunning = true
        }
    }
    
    /// Stop the audio engine (only for standalone mode)
    func stop() {
        if ownsEngine {
            audioEngine?.stop()
        }
        allNotesOff()
        isRunning = false
    }
    
    // MARK: - SoundFont Loading

    /// Maximum SoundFont file size (300 MB) to prevent memory exhaustion.
    private static let maxSoundFontFileSize: Int64 = 300_000_000

    /// Load a SoundFont file
    /// - Parameter url: Path to the .sf2 file
    func loadSoundFont(at url: URL) throws {
        guard url.pathExtension.lowercased() == "sf2" else {
            throw SamplerError.loadFailed("Not a SoundFont file")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        guard fileSize <= Self.maxSoundFontFileSize else {
            throw SamplerError.loadFailed("SoundFont too large (max \(Self.maxSoundFontFileSize / 1_000_000) MB)")
        }

        self.soundFontURL = url

        // Load the default instrument (piano)
        try loadInstrument(.acousticGrandPiano)

        isReady = true
    }
    
    /// Load a specific GM instrument from the SoundFont
    /// - Parameter instrument: The GM instrument to load
    ///
    /// ARCHITECTURE NOTE: This method uses `loadSoundBankInstrument` directly without
    /// recreating the sampler node. Previous implementations recreated the sampler when
    /// switching instruments, but this broke DAW track routing where samplers are connected
    /// to track plugin chains (not mainMixerNode). Apple's API is designed to support
    /// program changes without node recreation.
    func loadInstrument(_ instrument: GMInstrument) throws {
        guard let url = soundFontURL else {
            throw SamplerError.noSoundFontLoaded
        }
        
        // Stop any playing notes before switching instruments
        if isReady && currentInstrument != instrument {
            allNotesOff()
        }
        
        // General MIDI uses bank 0 (MSB=0x79 for melodic, 0x78 for drums)
        let program: UInt8
        let bankMSB: UInt8
        let bankLSB: UInt8 = 0
        if instrument.rawValue >= 1000 {
            // GM Drum Kits (channel 10): bank 0x78, program 0–127
            bankMSB = 0x78
            program = UInt8(instrument.rawValue - 1000)
        } else {
            bankMSB = 0x79  // GM melodic bank
            program = UInt8(instrument.rawValue)
        }
        
        // Load the instrument directly - Apple's API supports switching programs
        // without recreating the sampler node. This preserves the audio graph routing
        // which is critical for DAW track configurations where samplers are connected
        // to track plugin chains rather than mainMixerNode.
        try sampler.loadSoundBankInstrument(
            at: url,
            program: program,
            bankMSB: bankMSB,
            bankLSB: bankLSB
        )
        
        // Clear cached MIDI block since the underlying AU may have changed
        cachedMIDIBlock = nil
        
        currentInstrument = instrument
    }
    
    /// Load instrument by program number
    func loadProgram(_ program: Int) throws {
        guard let instrument = GMInstrument(rawValue: program) else {
            throw SamplerError.invalidProgram(program)
        }
        try loadInstrument(instrument)
    }
    
    // MARK: - Note Control
    
    /// Trigger a note on
    func noteOn(pitch: UInt8, velocity: UInt8) {
        guard isReady else { return }
        
        // Clamp MIDI values to valid range (0-127)
        let safePitch = min(pitch, 127)
        let safeVelocity = min(velocity, 127)
        
        sampler.startNote(safePitch, withVelocity: safeVelocity, onChannel: 0)
        activeNotes.insert(safePitch)
    }
    
    /// Trigger a note off
    func noteOff(pitch: UInt8) {
        let safePitch = min(pitch, 127)
        sampler.stopNote(safePitch, onChannel: 0)
        activeNotes.remove(safePitch)
    }
    
    /// Stop all notes
    func allNotesOff() {
        // Send MIDI CC 123 (All Notes Off) to ensure ALL notes stop,
        // even if they weren't tracked in activeNotes (e.g., from scheduler)
        sampler.sendController(123, withValue: 0, onChannel: 0)
        
        // Also explicitly stop tracked notes for good measure
        for pitch in activeNotes {
            sampler.stopNote(pitch, onChannel: 0)
        }
        activeNotes.removeAll()
    }
    
    /// Send a control change
    func controlChange(controller: UInt8, value: UInt8) {
        // Clamp MIDI values to valid range (0-127)
        let safeController = min(controller, 127)
        let safeValue = min(value, 127)
        sampler.sendController(safeController, withValue: safeValue, onChannel: 0)
    }
    
    /// Send pitch bend
    func pitchBend(value: UInt16) {
        sampler.sendPitchBend(value, onChannel: 0)
    }
    
    // MARK: - DSP State Management
    
    /// Reset the sampler's DSP state without reloading the SoundFont.
    /// This is a lightweight operation that clears render buffers and stale state
    /// after engine.reset() without the overhead of reloading the entire instrument.
    ///
    /// ARCHITECTURE NOTE: This is the proper fix for sampler corruption after graph rebuilds.
    /// Previously, the workaround was to reload the entire SoundFont which was expensive.
    /// The underlying issue is that engine.reset() can leave the sampler's internal
    /// render pipeline in an inconsistent state. This method:
    /// 1. Resets the AU unit state (clears render buffers)
    /// 2. Clears the cached MIDI block (forces refresh)
    /// 3. Turns off any lingering notes
    func resetDSPState() {
        // 1. Reset the underlying AUAudioUnit state
        // This clears render buffers and any stale DSP pipeline state
        sampler.auAudioUnit.reset()
        
        // 2. Clear cached MIDI block (it may point to stale memory after reset)
        cachedMIDIBlock = nil
        
        // 3. Stop any notes that might be stuck
        allNotesOff()
        
        // Note: We do NOT reload the SoundFont - that's expensive and unnecessary.
        // The instrument data is already loaded in the sampler.
    }
    
    /// 🔥 FIX 1: Full render resource reset for sampler
    /// Use this when plugin chain topology changes (insert/remove plugin).
    /// `reset()` alone does NOT clear allocated render resources or cached sample rate converters.
    /// This method deallocates render resources and reloads the instrument to guarantee a clean state.
    func fullRenderReset() {
        // Stop any playing notes first
        allNotesOff()
        
        // Clear cached MIDI block
        cachedMIDIBlock = nil
        
        // Deallocate render resources - this clears any cached sample rate converters
        sampler.auAudioUnit.deallocateRenderResources()
        
        // Reload the current instrument to restore proper state
        do {
            try loadInstrument(currentInstrument)
        } catch {
        }
    }
    
    // MARK: - Sample-Accurate MIDI (Professional Timing)
    
    /// Cached scheduleMIDIEventBlock for sample-accurate timing
    private var cachedMIDIBlock: AUScheduleMIDIEventBlock?
    
    /// Get or cache the MIDI scheduling block from the underlying AUAudioUnit
    /// This block is thread-safe and can be called from any thread for sample-accurate MIDI
    var midiEventBlock: AUScheduleMIDIEventBlock? {
        if cachedMIDIBlock == nil {
            cachedMIDIBlock = sampler.auAudioUnit.scheduleMIDIEventBlock
        }
        return cachedMIDIBlock
    }
    
    /// Send raw MIDI data with sample-accurate timing
    /// - Parameters:
    ///   - status: MIDI status byte (e.g., 0x90 for note on, 0x80 for note off)
    ///   - data1: First data byte (e.g., pitch)
    ///   - data2: Second data byte (e.g., velocity)
    ///   - sampleTime: Sample time for the event (AUEventSampleTimeImmediate for now)
    func sendMIDI(status: UInt8, data1: UInt8, data2: UInt8, atSampleTime sampleTime: AUEventSampleTime = AUEventSampleTimeImmediate) {
        // Clamp data bytes to valid MIDI range (0-127)
        let safeData1 = min(data1, 127)
        let safeData2 = min(data2, 127)
        
        guard let midiBlock = midiEventBlock else {
            // Fallback to immediate methods if MIDI block not available
            let statusNibble = status & 0xF0
            if statusNibble == 0x90 && safeData2 > 0 {
                noteOn(pitch: safeData1, velocity: safeData2)
            } else if statusNibble == 0x80 || (statusNibble == 0x90 && safeData2 == 0) {
                noteOff(pitch: safeData1)
            } else if statusNibble == 0xB0 {
                controlChange(controller: safeData1, value: safeData2)
            } else if statusNibble == 0xE0 {
                let bendValue = UInt16(safeData1) | (UInt16(safeData2) << 7)
                pitchBend(value: bendValue)
            }
            return
        }
        
        // Use sample-accurate scheduling with clamped values
        var midiData: [UInt8] = [status, safeData1, safeData2]
        midiBlock(sampleTime, 0, 3, &midiData)
        
        // Track active notes for cleanup
        let statusNibble = status & 0xF0
        if statusNibble == 0x90 && safeData2 > 0 {
            activeNotes.insert(safeData1)
        } else if statusNibble == 0x80 || (statusNibble == 0x90 && safeData2 == 0) {
            activeNotes.remove(safeData1)
        }
    }
    
    // MARK: - Volume Control
    
    /// Set the sampler volume (0.0 - 1.0 linear scale)
    /// Converts to decibels for AVAudioUnitSampler.masterGain
    func setVolume(_ volume: Float) {
        // Convert linear (0.0-1.0) to decibels
        // masterGain range is approximately -90 to +12 dB
        // 0.0 linear -> -80 dB (effectively silent)
        // 1.0 linear -> 0 dB (unity gain)
        let dB: Float
        if volume <= 0.0001 {
            dB = -80.0  // Effectively mute
        } else {
            dB = 20.0 * log10(volume)
            // Clamp to reasonable range
        }
        sampler.masterGain = max(-80.0, min(12.0, dB))
    }
    
    /// Set stereo pan (-1.0 to 1.0)
    func setPan(_ pan: Float) {
        sampler.stereoPan = pan
    }
}

// MARK: - Sampler Errors

enum SamplerError: Error, LocalizedError {
    case noSoundFontLoaded
    case invalidProgram(Int)
    case soundFontNotFound(String)
    case loadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noSoundFontLoaded:
            return "No SoundFont file has been loaded"
        case .invalidProgram(let program):
            return "Invalid MIDI program number: \(program)"
        case .soundFontNotFound(let name):
            return "SoundFont file not found: \(name)"
        case .loadFailed(let reason):
            return "Failed to load SoundFont: \(reason)"
        }
    }
}

// MARK: - SoundFont Manager

/// Manages SoundFont files and provides access to available instruments
class SoundFontManager {
    
    // MARK: - Singleton
    
    static let shared = SoundFontManager()
    
    // MARK: - Properties
    
    /// Available SoundFonts
    private(set) var availableSoundFonts: [SoundFontInfo] = []
    
    /// Currently loaded SoundFont
    private(set) var currentSoundFont: SoundFontInfo?
    
    /// Path to look for SoundFonts
    private let soundFontDirectories: [URL]
    
    // MARK: - Initialization
    
    private init() {
        // Look in app bundle and Application Support
        var directories: [URL] = []
        
        // App bundle
        if let bundleURL = Bundle.main.resourceURL {
            directories.append(bundleURL)
            directories.append(bundleURL.appendingPathComponent("SoundFonts"))
        }
        
        // Application Support
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let soundFontDir = appSupport.appendingPathComponent("Stori/SoundFonts")
            directories.append(soundFontDir)
        }
        
        // Documents folder (for user-added SoundFonts)
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            directories.append(documents)
        }
        
        self.soundFontDirectories = directories
    }
    
    // MARK: - Discovery
    
    /// Scan for available SoundFont files
    func discoverSoundFonts() {
        availableSoundFonts.removeAll()
        
        for directory in soundFontDirectories {
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
                
                for url in contents where url.pathExtension.lowercased() == "sf2" {
                    if let info = SoundFontInfo(url: url) {
                        availableSoundFonts.append(info)
                    }
                }
            } catch {
                // Directory doesn't exist or isn't readable - that's fine
                continue
            }
        }
    }
    
    /// Get URL for any available SoundFont (from Application Support)
    /// Returns the first available SoundFont, or nil if none installed.
    func anySoundFontURL() -> URL? {
        // Refresh the list if empty (might have just downloaded)
        if availableSoundFonts.isEmpty {
            discoverSoundFonts()
        }
        
        // Return the first available SoundFont
        return availableSoundFonts.first?.url
    }
    
    /// Check if any SoundFont is available
    var hasSoundFont: Bool {
        anySoundFontURL() != nil
    }
}

// MARK: - SoundFont Info

struct SoundFontInfo: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let fileSize: Int64
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    init?(url: URL) {
        guard url.pathExtension.lowercased() == "sf2" else { return nil }
        
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            self.fileSize = attributes[.size] as? Int64 ?? 0
        } catch {
            self.fileSize = 0
        }
    }
}

