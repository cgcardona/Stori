"""
MusicGen Engine Wrapper

Provides a clean interface to Meta's AudioCraft MusicGen model with
async support and proper resource management.
"""

import asyncio
import logging
import torch
import torchaudio
from typing import Optional, Tuple, Dict, Any
from pathlib import Path

try:
    from audiocraft.models import MusicGen
    from audiocraft.data.audio import audio_write
except ImportError:
    # Fallback for development without AudioCraft installed
    MusicGen = None
    audio_write = None

logger = logging.getLogger(__name__)


class MusicGenEngine:
    """
    Wrapper for Meta's AudioCraft MusicGen model with async support.
    
    Provides music generation capabilities with proper resource management,
    GPU optimization, and async/await patterns for integration with FastAPI.
    """
    
    def __init__(self, model_size: str = "medium"):
        """
        Initialize MusicGen engine.
        
        Args:
            model_size: Size of the model to load ("small", "medium", "large")
        """
        self.model_size = model_size
        self.model: Optional[Any] = None
        self.sample_rate: int = 32000  # Default MusicGen sample rate
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.is_initialized = False
        
        logger.info(f"Initializing MusicGen engine with {model_size} model on {self.device}")
    
    async def initialize(self):
        """Initialize the MusicGen model asynchronously."""
        if self.is_initialized:
            return
        
        if MusicGen is None:
            logger.warning("AudioCraft not available - using mock implementation")
            self.model = MockMusicGenModel()
            self.sample_rate = 44100
        else:
            # Load model in thread pool to avoid blocking
            loop = asyncio.get_event_loop()
            self.model = await loop.run_in_executor(
                None, 
                self._load_model
            )
            self.sample_rate = self.model.sample_rate
        
        self.is_initialized = True
        logger.info(f"✅ MusicGen model loaded successfully (sample rate: {self.sample_rate})")
    
    def _load_model(self):
        """Load the MusicGen model (runs in thread pool)."""
        try:
            model = MusicGen.get_pretrained(f"facebook/musicgen-{self.model_size}")
            model.set_generation_params(duration=30)  # Default 30 seconds
            return model
        except Exception as e:
            logger.error(f"Failed to load MusicGen model: {e}")
            # Return mock model as fallback
            return MockMusicGenModel()
    
    async def generate_music(
        self,
        prompt: str,
        duration: float = 30.0,
        temperature: float = 1.0,
        top_k: int = 250,
        top_p: float = 0.0,
        cfg_coef: float = 3.0
    ) -> Tuple[torch.Tensor, int]:
        """
        Generate music from text prompt.
        
        Args:
            prompt: Text description of the music to generate
            duration: Length of generated audio in seconds
            temperature: Sampling temperature (higher = more random)
            top_k: Top-k sampling parameter
            top_p: Top-p sampling parameter
            cfg_coef: Classifier-free guidance coefficient
            
        Returns:
            Tuple of (audio_tensor, sample_rate)
        """
        if not self.is_initialized:
            await self.initialize()
        
        logger.info(f"🎵 Generating music: '{prompt}' ({duration}s)")
        
        # Set generation parameters
        if hasattr(self.model, 'set_generation_params'):
            self.model.set_generation_params(
                duration=duration,
                temperature=temperature,
                top_k=top_k,
                top_p=top_p,
                cfg_coef=cfg_coef
            )
        
        # Generate in thread pool to avoid blocking
        loop = asyncio.get_event_loop()
        audio_tensor = await loop.run_in_executor(
            None,
            self._generate_audio,
            prompt
        )
        
        logger.info("✅ Music generation complete")
        return audio_tensor, self.sample_rate
    
    def _generate_audio(self, prompt: str) -> torch.Tensor:
        """Generate audio (runs in thread pool)."""
        try:
            with torch.no_grad():
                if hasattr(self.model, 'generate'):
                    # Real MusicGen model
                    wav = self.model.generate([prompt])
                    return wav[0].cpu()  # Return first (and only) generated sample
                else:
                    # Mock model
                    return self.model.generate(prompt)
        except Exception as e:
            logger.error(f"Audio generation failed: {e}")
            # Return silence as fallback
            duration_samples = int(30 * self.sample_rate)
            return torch.zeros(1, duration_samples)
    
    async def save_audio(
        self, 
        audio_tensor: torch.Tensor, 
        output_path: Path,
        sample_rate: Optional[int] = None
    ) -> Path:
        """
        Save generated audio to file.
        
        Args:
            audio_tensor: Generated audio tensor
            output_path: Path to save the audio file
            sample_rate: Sample rate (uses model default if None)
            
        Returns:
            Path to saved audio file
        """
        if sample_rate is None:
            sample_rate = self.sample_rate
        
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Save in thread pool to avoid blocking
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(
            None,
            self._save_audio_sync,
            audio_tensor,
            output_path,
            sample_rate
        )
        
        logger.info(f"💾 Audio saved to: {output_path}")
        return output_path
    
    def _save_audio_sync(self, audio_tensor: torch.Tensor, output_path: Path, sample_rate: int):
        """Save audio synchronously (runs in thread pool)."""
        try:
            if audio_write is not None:
                # Use AudioCraft's audio_write function
                audio_write(
                    str(output_path.with_suffix('')),  # Remove extension, audio_write adds it
                    audio_tensor,
                    sample_rate,
                    strategy="loudness"
                )
            else:
                # Fallback using torchaudio
                torchaudio.save(str(output_path), audio_tensor, sample_rate)
        except Exception as e:
            logger.error(f"Failed to save audio: {e}")
            raise
    
    async def cleanup(self):
        """Clean up resources."""
        if self.model and hasattr(self.model, 'cpu'):
            self.model.cpu()
        
        # Clear CUDA cache if using GPU
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        
        self.is_initialized = False
        logger.info("🧹 MusicGen engine cleaned up")
    
    def get_model_info(self) -> Dict[str, Any]:
        """Get information about the loaded model."""
        return {
            "model_size": self.model_size,
            "sample_rate": self.sample_rate,
            "device": self.device,
            "is_initialized": self.is_initialized,
            "cuda_available": torch.cuda.is_available(),
            "cuda_memory": torch.cuda.get_device_properties(0).total_memory if torch.cuda.is_available() else None
        }


class MockMusicGenModel:
    """Mock MusicGen model for development without AudioCraft."""
    
    def __init__(self):
        self.sample_rate = 44100
    
    def set_generation_params(self, **kwargs):
        """Mock parameter setting."""
        pass
    
    def generate(self, prompt: str) -> torch.Tensor:
        """Generate mock audio (sine wave)."""
        duration = 30  # seconds
        sample_rate = self.sample_rate
        
        # Generate a simple sine wave as placeholder
        t = torch.linspace(0, duration, int(duration * sample_rate))
        frequency = 440.0  # A4 note
        audio = 0.3 * torch.sin(2 * torch.pi * frequency * t)
        
        return audio.unsqueeze(0)  # Add batch dimension
