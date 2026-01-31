# Stori Audio & MIDI Engine Architecture

## Overview

This document visualizes the signal flow and component relationships in Stori's professional-grade audio and MIDI engine.

## Combined Audio & MIDI Engine Flow

```mermaid
flowchart TB
    subgraph Transport["🎛️ Transport Controller"]
        TC[TransportController]
        TC --> |"wall-clock beat calc"| AtomicBeat["Atomic Beat Position<br/>(os_unfair_lock)"]
    end

    subgraph MIDI["🎹 MIDI Engine"]
        direction TB
        MIDIRegions["MIDI Regions<br/>(beats-first)"]
        Scheduler["SampleAccurateMIDIScheduler<br/>(500Hz DispatchSourceTimer)"]
        TimingRef["MIDITimingReference<br/>(hostTime, sampleTime, beat)"]
        MIDIBlocks["Cached AUScheduleMIDIEventBlock<br/>(per-instrument)"]
        
        MIDIRegions --> Scheduler
        AtomicBeat --> |"current beat"| Scheduler
        Scheduler --> |"calculates sample time"| TimingRef
        TimingRef --> |"schedules 50-100ms ahead"| MIDIBlocks
    end

    subgraph Instruments["🎸 Virtual Instruments"]
        Sampler1["SamplerEngine<br/>(AUSampler)"]
        Sampler2["SynthEngine<br/>(Custom Synth)"]
        InstrumentHost["InstrumentPluginHost<br/>(AU Instruments)"]
        
        MIDIBlocks --> |"sample-accurate events"| Sampler1
        MIDIBlocks --> |"sample-accurate events"| Sampler2
        MIDIBlocks --> |"sample-accurate events"| InstrumentHost
    end

    subgraph AudioTracks["🎚️ Audio Tracks (per track)"]
        direction TB
        PlayerNode["AVAudioPlayerNode<br/>(audio regions)"]
        TimePitch["AVAudioUnitTimePitch<br/>(pitch/tempo shift)"]
        
        subgraph PluginChain["Plugin Chain (lazy)"]
            InputMixer["inputMixer"]
            Plugins["PluginInstance(s)<br/>(AU Effects)"]
            OutputMixer["outputMixer"]
            InputMixer --> Plugins --> OutputMixer
        end
        
        EQ["AVAudioUnitEQ<br/>(3-band per-track)"]
        Volume["AVAudioMixerNode<br/>(volume)"]
        Pan["AVAudioMixerNode<br/>(pan)"]
        
        PlayerNode --> TimePitch
        Sampler1 --> |"MIDI track"| TimePitch
        TimePitch --> |"has plugins?"| InputMixer
        TimePitch --> |"no plugins"| EQ
        OutputMixer --> EQ
        EQ --> Volume --> Pan
    end

    subgraph Automation["🎚️ Automation Engine"]
        AutoProc["AutomationProcessor<br/>(O(log n) lookup)"]
        AutoEngine["AutomationEngine<br/>(120Hz DispatchSourceTimer)"]
        
        AtomicBeat --> |"current beat"| AutoEngine
        AutoEngine --> |"batch read"| AutoProc
        AutoProc --> |"smoothed values"| Volume
        AutoProc --> |"smoothed values"| Pan
        AutoProc --> |"smoothed values"| EQ
    end

    subgraph Buses["🚌 Bus Sends"]
        BusSend["Pre/Post Fader Sends"]
        BusNode["BusAudioNode<br/>(effects returns)"]
        
        Pan --> |"configurable"| BusSend
        BusSend --> BusNode
    end

    subgraph MasterBus["🔊 Master Bus"]
        MainMixer["AVAudioMixerNode<br/>(main mixer)"]
        MasterEQ["AVAudioUnitEQ<br/>(3-band master)"]
        Limiter["AVAudioUnitEffect<br/>(PeakLimiter)"]
        OutputNode["AVAudioEngine.outputNode<br/>(hardware)"]
        
        Pan --> MainMixer
        BusNode --> MainMixer
        MainMixer --> MasterEQ --> Limiter --> OutputNode
    end

    subgraph Metering["📊 Metering"]
        TrackMeter["Track Level Tap<br/>(vDSP, ~20ms)"]
        MasterMeter["Master LUFS Meter<br/>(~85ms window)"]
        
        Volume --> |"installTap"| TrackMeter
        MasterEQ --> |"installTap"| MasterMeter
    end

    subgraph Recording["🎙️ Recording"]
        RecordTap["Recording Tap<br/>(input monitoring)"]
        BufferPool["RecordingBufferPool<br/>(lock-free ring buffer)"]
        
        RecordTap --> BufferPool
    end

    subgraph HealthMonitor["🏥 Engine Health"]
        HealthTimer["DispatchSourceTimer<br/>(2s interval)"]
        HealthTimer --> |"checks isRunning"| MainMixer
    end

    style Transport fill:#e1f5fe
    style MIDI fill:#fff3e0
    style Instruments fill:#f3e5f5
    style AudioTracks fill:#e8f5e9
    style Automation fill:#fce4ec
    style Buses fill:#fff8e1
    style MasterBus fill:#ffebee
    style Metering fill:#f5f5f5
    style Recording fill:#e0f2f1
    style HealthMonitor fill:#fafafa
```

## Threading Model

```mermaid
flowchart LR
    subgraph MainActor["🧵 MainActor (UI Thread)"]
        AudioEngine["AudioEngine<br/>(@Observable)"]
        TransportUI["Transport State"]
        MixerUI["Mixer Controls"]
        ProjectState["Project State"]
    end

    subgraph HighPriority["⚡ High Priority Queues (.userInteractive)"]
        MIDIQueue["com.stori.midi.scheduler<br/>(500Hz timer)"]
        AutoQueue["com.stori.automation<br/>(120Hz timer)"]
        PositionQueue["com.stori.transport.position<br/>(60Hz timer)"]
    end

    subgraph AudioThread["🔴 Audio Render Thread (real-time)"]
        RenderCallback["AVAudioEngine render"]
        LevelTaps["Level metering taps"]
        RecordTaps["Recording taps"]
    end

    subgraph Background["🔵 Background Queues"]
        HealthQueue["com.stori.engine.health<br/>(.utility)"]
        PluginLoad["Plugin loading<br/>(.userInitiated)"]
    end

    subgraph AtomicState["🔒 Thread-Safe State (os_unfair_lock)"]
        BeatPosition["atomicBeatPosition"]
        LevelData["level data"]
        AutoData["automation snapshots"]
        MIDIBlockCache["MIDI block cache"]
    end

    MainActor <--> |"@MainActor isolation"| TransportUI
    MainActor <--> MixerUI
    MainActor <--> ProjectState

    MIDIQueue --> |"reads"| BeatPosition
    AutoQueue --> |"reads"| BeatPosition
    AutoQueue --> |"batch reads"| AutoData
    PositionQueue --> |"updates"| BeatPosition

    AudioThread --> |"writes"| LevelData
    MainActor --> |"reads"| LevelData

    HighPriority --> |"schedules events"| AudioThread

    style MainActor fill:#e3f2fd
    style HighPriority fill:#fff3e0
    style AudioThread fill:#ffebee
    style Background fill:#f5f5f5
    style AtomicState fill:#e8f5e9
```

## Key Design Decisions

### Beats-First Architecture
All positions are stored and calculated in **musical time (beats)**, not seconds. Conversion to seconds/samples only happens at the AVAudioEngine boundary.

### Sample-Accurate MIDI
MIDI events are scheduled with calculated **future sample times** using `AUScheduleMIDIEventBlock`. The scheduler runs at 500Hz and pushes events 50-100ms ahead, allowing the Audio Unit to fire events at exactly the right sample.

### Real-Time Safety
- No allocations on audio thread
- No locks that block audio (only `os_unfair_lock` with immediate return)
- All timers use `DispatchSourceTimer` (immune to main thread blocking)
- Batch reads for automation (O(1) lock acquisitions per update cycle)

### Graceful Degradation
- Master limiter prevents clipping at output
- Plugin greylist for crash detection
- Health monitoring with automatic recovery
- RAII patterns for state consistency

## Signal Flow Summary

```
Audio Track: PlayerNode → TimePitch → [PluginChain] → EQ → Volume → Pan → MainMixer
MIDI Track:  Sampler → TimePitch → [PluginChain] → EQ → Volume → Pan → MainMixer
Bus Return:  BusInput → [BusPlugins] → Volume → Pan → MainMixer
Master:      MainMixer → MasterEQ → MasterLimiter → OutputNode → Hardware
```
