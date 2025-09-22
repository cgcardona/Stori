"""
Prompt Builder for MusicGen

Constructs structured prompts from individual components for better
music generation results.
"""

import random
from typing import List, Optional


class PromptBuilder:
    """
    Builder for structured MusicGen prompts.
    
    Combines genre, tempo, mood, instruments, and style references
    into well-formatted prompts that work well with MusicGen.
    """
    
    # Predefined categories for validation and suggestions
    GENRES = [
        "rock", "pop", "jazz", "classical", "electronic", "hip-hop",
        "country", "blues", "reggae", "folk", "metal", "punk", "funk",
        "disco", "house", "techno", "ambient", "dubstep", "trap", "r&b",
        "soul", "gospel", "latin", "world", "experimental", "indie",
        "alternative", "grunge", "progressive", "psychedelic"
    ]
    
    TEMPOS = [
        "very slow", "slow", "medium", "fast", "very fast",
        "60 BPM", "70 BPM", "80 BPM", "90 BPM", "100 BPM",
        "110 BPM", "120 BPM", "130 BPM", "140 BPM", "150 BPM",
        "160 BPM", "170 BPM", "180 BPM", "ballad tempo", "dance tempo"
    ]
    
    MOODS = [
        "happy", "sad", "energetic", "calm", "mysterious", "uplifting",
        "dark", "romantic", "aggressive", "peaceful", "melancholic",
        "euphoric", "dreamy", "intense", "relaxing", "dramatic",
        "nostalgic", "triumphant", "contemplative", "playful", "epic",
        "atmospheric", "groovy", "hypnotic", "emotional", "powerful"
    ]
    
    INSTRUMENTS = [
        # Strings
        "guitar", "electric guitar", "acoustic guitar", "bass", "violin",
        "cello", "piano", "keyboard", "harp", "banjo", "mandolin",
        
        # Percussion
        "drums", "percussion", "timpani", "cymbals", "tambourine",
        "bongos", "congas", "djembe",
        
        # Brass
        "trumpet", "trombone", "french horn", "tuba", "saxophone",
        "clarinet", "flute", "oboe", "bassoon",
        
        # Electronic
        "synthesizer", "synth pad", "lead synth", "bass synth",
        "drum machine", "sampler", "vocoder",
        
        # Vocals
        "vocals", "choir", "harmony", "falsetto", "rap", "spoken word"
    ]
    
    ARTIST_STYLES = [
        "in the style of The Beatles", "like Mozart", "similar to Daft Punk",
        "in the style of Miles Davis", "like Beethoven", "similar to Radiohead",
        "like Pink Floyd", "in the style of Michael Jackson", "similar to Kraftwerk",
        "like Bob Dylan", "in the style of Aretha Franklin", "similar to Aphex Twin",
        "like Johnny Cash", "in the style of Stevie Wonder", "similar to Portishead",
        "like Led Zeppelin", "in the style of Joni Mitchell", "similar to Massive Attack"
    ]
    
    def build_prompt(
        self,
        genre: Optional[str] = None,
        tempo: Optional[str] = None,
        mood: Optional[str] = None,
        artist_style: Optional[str] = None,
        instruments: Optional[List[str]] = None,
        custom_text: Optional[str] = None
    ) -> str:
        """
        Build a structured prompt from components.
        
        Args:
            genre: Music genre
            tempo: Tempo description or BPM
            mood: Mood or emotion
            artist_style: Artist style reference
            instruments: List of instruments to feature
            custom_text: Additional custom description
            
        Returns:
            Formatted prompt string
        """
        parts = []
        
        # Start with custom text if provided
        if custom_text and custom_text.strip():
            parts.append(custom_text.strip())
        
        # Add genre
        if genre and genre.strip():
            genre_clean = genre.strip().lower()
            if genre_clean in [g.lower() for g in self.GENRES]:
                parts.append(f"{genre_clean} music")
            else:
                parts.append(f"{genre_clean} style music")
        
        # Add tempo
        if tempo and tempo.strip():
            tempo_clean = tempo.strip().lower()
            if any(bpm in tempo_clean for bpm in ["bpm", "beats per minute"]):
                parts.append(f"at {tempo_clean}")
            elif tempo_clean in [t.lower() for t in self.TEMPOS]:
                parts.append(f"{tempo_clean} tempo")
            else:
                parts.append(f"at {tempo_clean} pace")
        
        # Add mood
        if mood and mood.strip():
            mood_clean = mood.strip().lower()
            if mood_clean in [m.lower() for m in self.MOODS]:
                parts.append(f"with {mood_clean} mood")
            else:
                parts.append(f"with {mood_clean} feeling")
        
        # Add instruments
        if instruments and len(instruments) > 0:
            # Clean and validate instruments
            valid_instruments = []
            for instrument in instruments:
                if instrument and instrument.strip():
                    clean_inst = instrument.strip().lower()
                    valid_instruments.append(clean_inst)
            
            if valid_instruments:
                if len(valid_instruments) == 1:
                    parts.append(f"featuring {valid_instruments[0]}")
                elif len(valid_instruments) == 2:
                    parts.append(f"featuring {valid_instruments[0]} and {valid_instruments[1]}")
                else:
                    instrument_list = ", ".join(valid_instruments[:-1])
                    parts.append(f"featuring {instrument_list}, and {valid_instruments[-1]}")
        
        # Add artist style
        if artist_style and artist_style.strip():
            style_clean = artist_style.strip()
            if not style_clean.lower().startswith(("in the style", "like", "similar")):
                # Add appropriate prefix if not present
                if "style" in style_clean.lower():
                    parts.append(style_clean)
                else:
                    parts.append(f"in the style of {style_clean}")
            else:
                parts.append(style_clean)
        
        # Join parts with commas
        if not parts:
            return "instrumental music"
        
        prompt = ", ".join(parts)
        
        # Ensure prompt doesn't exceed reasonable length
        if len(prompt) > 500:
            prompt = prompt[:497] + "..."
        
        return prompt
    
    def get_suggestions(self) -> dict:
        """
        Get lists of suggested values for each component.
        
        Returns:
            Dictionary with suggestion lists for each component
        """
        return {
            "genres": self.GENRES,
            "tempos": self.TEMPOS,
            "moods": self.MOODS,
            "instruments": self.INSTRUMENTS,
            "artist_styles": self.ARTIST_STYLES
        }
    
    def validate_components(
        self,
        genre: Optional[str] = None,
        tempo: Optional[str] = None,
        mood: Optional[str] = None,
        instruments: Optional[List[str]] = None
    ) -> dict:
        """
        Validate prompt components and provide suggestions.
        
        Returns:
            Dictionary with validation results and suggestions
        """
        results = {
            "valid": True,
            "warnings": [],
            "suggestions": {}
        }
        
        # Validate genre
        if genre:
            genre_lower = genre.lower()
            if genre_lower not in [g.lower() for g in self.GENRES]:
                results["warnings"].append(f"Genre '{genre}' not in predefined list")
                # Find similar genres
                similar = [g for g in self.GENRES if genre_lower in g.lower() or g.lower() in genre_lower]
                if similar:
                    results["suggestions"]["genre"] = similar[:3]
        
        # Validate tempo
        if tempo:
            tempo_lower = tempo.lower()
            if (tempo_lower not in [t.lower() for t in self.TEMPOS] and 
                not any(bpm in tempo_lower for bpm in ["bpm", "beats"])):
                results["warnings"].append(f"Tempo '{tempo}' not recognized")
        
        # Validate mood
        if mood:
            mood_lower = mood.lower()
            if mood_lower not in [m.lower() for m in self.MOODS]:
                results["warnings"].append(f"Mood '{mood}' not in predefined list")
                # Find similar moods
                similar = [m for m in self.MOODS if mood_lower in m.lower() or m.lower() in mood_lower]
                if similar:
                    results["suggestions"]["mood"] = similar[:3]
        
        # Validate instruments
        if instruments:
            unrecognized = []
            for instrument in instruments:
                if instrument.lower() not in [i.lower() for i in self.INSTRUMENTS]:
                    unrecognized.append(instrument)
            
            if unrecognized:
                results["warnings"].append(f"Unrecognized instruments: {', '.join(unrecognized)}")
        
        return results
    
    def generate_random_prompt(self, complexity: str = "medium") -> dict:
        """
        Generate a completely random prompt with various components.
        
        Args:
            complexity: "simple", "medium", or "complex" - affects number of components
            
        Returns:
            Dictionary with generated components and final prompt
        """
        components = {}
        
        # Always include genre and mood
        components["genre"] = random.choice(self.GENRES)
        components["mood"] = random.choice(self.MOODS)
        
        # Add tempo based on complexity
        if complexity in ["medium", "complex"]:
            components["tempo"] = random.choice(self.TEMPOS)
        
        # Add instruments based on complexity
        if complexity == "simple":
            # 0-1 instruments
            if random.random() < 0.7:  # 70% chance
                components["instruments"] = [random.choice(self.INSTRUMENTS)]
        elif complexity == "medium":
            # 1-2 instruments
            num_instruments = random.choice([1, 2])
            components["instruments"] = random.sample(self.INSTRUMENTS, num_instruments)
        else:  # complex
            # 2-4 instruments
            num_instruments = random.choice([2, 3, 4])
            components["instruments"] = random.sample(self.INSTRUMENTS, num_instruments)
        
        # Add artist style based on complexity
        if complexity == "medium" and random.random() < 0.4:  # 40% chance
            components["artist_style"] = random.choice(self.ARTIST_STYLES)
        elif complexity == "complex" and random.random() < 0.6:  # 60% chance
            components["artist_style"] = random.choice(self.ARTIST_STYLES)
        
        # Add custom descriptive text for complex prompts
        if complexity == "complex" and random.random() < 0.3:  # 30% chance
            custom_phrases = [
                "with rich harmonies", "featuring intricate melodies", "with dynamic arrangements",
                "showcasing virtuosic performance", "with atmospheric textures", "building to a climax",
                "with subtle variations", "featuring call and response", "with polyrhythmic elements",
                "showcasing improvisation", "with lush orchestration", "featuring counterpoint melodies"
            ]
            components["custom_text"] = random.choice(custom_phrases)
        
        # Build the final prompt
        prompt = self.build_prompt(
            genre=components.get("genre"),
            tempo=components.get("tempo"),
            mood=components.get("mood"),
            artist_style=components.get("artist_style"),
            instruments=components.get("instruments"),
            custom_text=components.get("custom_text")
        )
        
        return {
            "prompt": prompt,
            "components": components,
            "complexity": complexity
        }
