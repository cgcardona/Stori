"""
Generation Service

High-level service for managing music generation workflows.
"""

import logging
from typing import Tuple, Optional
from pathlib import Path
import torch

from app.core.musicgen_engine import MusicGenEngine

logger = logging.getLogger(__name__)


class GenerationService:
    """
    High-level service for music generation operations.
    
    Provides a clean interface for the API layer to interact with
    the MusicGen engine and handle generation workflows.
    """
    
    def __init__(self, musicgen_engine: MusicGenEngine):
        """
        Initialize the generation service.
        
        Args:
            musicgen_engine: Initialized MusicGen engine instance
        """
        self.engine = musicgen_engine
        self.logger = logging.getLogger(__name__)
    
    async def generate_music(
        self,
        prompt: str,
        duration: float = 30.0,
        temperature: float = 1.0,
        top_k: int = 250,
        top_p: float = 0.0,
        cfg_coef: float = 3.0,
        progress_callback=None
    ) -> Tuple[torch.Tensor, int]:
        """
        Generate music from a text prompt.
        
        Args:
            prompt: Text description of the music to generate
            duration: Length of generated audio in seconds
            temperature: Sampling temperature (higher = more random)
            top_k: Top-k sampling parameter
            top_p: Top-p sampling parameter
            cfg_coef: Classifier-free guidance coefficient
            
        Returns:
            Tuple of (audio_tensor, sample_rate)
            
        Raises:
            Exception: If generation fails
        """
        try:
            self.logger.info(f"🎵 Starting generation: '{prompt}' ({duration}s)")
            
            # Validate parameters
            self._validate_generation_params(
                prompt, duration, temperature, top_k, top_p, cfg_coef
            )
            
            # Generate music using the engine
            audio_tensor, sample_rate = await self.engine.generate_music(
                prompt=prompt,
                duration=duration,
                temperature=temperature,
                top_k=top_k,
                top_p=top_p,
                cfg_coef=cfg_coef,
                progress_callback=progress_callback
            )
            
            # Validate output
            if audio_tensor is None or len(audio_tensor.shape) == 0:
                raise ValueError("Generated audio tensor is empty")
            
            self.logger.info(f"✅ Generation complete: {audio_tensor.shape} @ {sample_rate}Hz")
            
            return audio_tensor, sample_rate
            
        except Exception as e:
            self.logger.error(f"❌ Generation failed: {e}")
            raise
    
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
            sample_rate: Sample rate (uses engine default if None)
            
        Returns:
            Path to saved audio file
            
        Raises:
            Exception: If saving fails
        """
        try:
            saved_path = await self.engine.save_audio(
                audio_tensor, output_path, sample_rate
            )
            
            self.logger.info(f"💾 Audio saved successfully: {saved_path}")
            return saved_path
            
        except Exception as e:
            self.logger.error(f"❌ Failed to save audio: {e}")
            raise
    
    def _validate_generation_params(
        self,
        prompt: str,
        duration: float,
        temperature: float,
        top_k: int,
        top_p: float,
        cfg_coef: float
    ):
        """
        Validate generation parameters.
        
        Raises:
            ValueError: If any parameter is invalid
        """
        if not prompt or not prompt.strip():
            raise ValueError("Prompt cannot be empty")
        
        if duration <= 0 or duration > 300:  # Max 5 minutes
            raise ValueError("Duration must be between 0 and 300 seconds")
        
        if temperature <= 0 or temperature > 5:
            raise ValueError("Temperature must be between 0 and 5")
        
        if top_k < 1 or top_k > 2000:
            raise ValueError("top_k must be between 1 and 2000")
        
        if top_p < 0 or top_p > 1:
            raise ValueError("top_p must be between 0 and 1")
        
        if cfg_coef < 0 or cfg_coef > 20:
            raise ValueError("cfg_coef must be between 0 and 20")
    
    def get_engine_info(self) -> dict:
        """
        Get information about the underlying engine.
        
        Returns:
            Dictionary with engine information
        """
        return self.engine.get_model_info()
    
    async def health_check(self) -> dict:
        """
        Perform a health check on the generation service.
        
        Returns:
            Dictionary with health status information
        """
        try:
            engine_info = self.get_engine_info()
            
            # Test a quick generation to verify functionality
            test_prompt = "simple test tone"
            test_audio, test_sr = await self.engine.generate_music(
                prompt=test_prompt,
                duration=1.0,  # Very short test
                temperature=1.0
            )
            
            return {
                "status": "healthy",
                "engine_info": engine_info,
                "test_generation": {
                    "success": True,
                    "audio_shape": list(test_audio.shape),
                    "sample_rate": test_sr
                }
            }
            
        except Exception as e:
            self.logger.error(f"Health check failed: {e}")
            return {
                "status": "unhealthy",
                "error": str(e),
                "engine_info": self.get_engine_info()
            }
