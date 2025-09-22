"""
MusicGen Engine Wrapper

Provides a clean interface to Meta's AudioCraft MusicGen model with
async support and proper resource management.
"""

import asyncio
import logging
import os
import torch
import torchaudio
from typing import Optional, Tuple, Dict, Any
from pathlib import Path

try:
    # Try Hugging Face transformers approach first
    from transformers import MusicgenForConditionalGeneration, AutoProcessor
    TRANSFORMERS_AVAILABLE = True
except ImportError:
    TRANSFORMERS_AVAILABLE = False

try:
    # Fallback to AudioCraft if available
    from audiocraft.models import MusicGen
    from audiocraft.data.audio import audio_write
    AUDIOCRAFT_AVAILABLE = True
except ImportError:
    # Neither available - use mock
    MusicGen = None
    audio_write = None
    AUDIOCRAFT_AVAILABLE = False

logger = logging.getLogger(__name__)


class MusicGenEngine:
    """
    Wrapper for Meta's AudioCraft MusicGen model with async support.
    
    Provides music generation capabilities with proper resource management,
    GPU optimization, and async/await patterns for integration with FastAPI.
    """
    
    def __init__(self, model_size: str = "small"):
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
        
        if TRANSFORMERS_AVAILABLE:
            logger.info("🤗 Loading MusicGen from Hugging Face transformers...")
            # Load model in thread pool to avoid blocking
            loop = asyncio.get_event_loop()
            self.model, self.processor = await loop.run_in_executor(
                None, 
                self._load_hf_model
            )
            self.sample_rate = self.model.config.audio_encoder.sampling_rate
            logger.info(f"✅ Hugging Face MusicGen model loaded successfully")
        elif AUDIOCRAFT_AVAILABLE:
            logger.info("🎵 Loading MusicGen from AudioCraft...")
            # Load model in thread pool to avoid blocking
            loop = asyncio.get_event_loop()
            self.model = await loop.run_in_executor(
                None, 
                self._load_audiocraft_model
            )
            self.sample_rate = self.model.sample_rate
            logger.info(f"✅ AudioCraft MusicGen model loaded successfully")
        else:
            logger.warning("⚠️ No MusicGen implementation available - using mock")
            self.model = MockMusicGenModel()
            self.processor = None
            self.sample_rate = 44100
        
        self.is_initialized = True
        logger.info(f"✅ MusicGen engine ready (sample rate: {self.sample_rate})")
    
    def _load_hf_model(self):
        """Load MusicGen model from Hugging Face (runs in thread pool)."""
        try:
            model_name = f"facebook/musicgen-{self.model_size}"
            
            # Set up cache directory
            cache_dir = os.getenv('HF_HOME', os.path.expanduser('~/.cache/huggingface'))
            logger.info(f"📁 Using Hugging Face cache directory: {cache_dir}")
            
            # First try to load from cache
            try:
                logger.info(f"🔍 Checking for cached {model_name}...")
                model = MusicgenForConditionalGeneration.from_pretrained(
                    model_name, 
                    local_files_only=True,
                    cache_dir=cache_dir
                )
                processor = AutoProcessor.from_pretrained(
                    model_name, 
                    local_files_only=True,
                    cache_dir=cache_dir
                )
                logger.info(f"✅ Loaded {model_name} from cache")
                
            except Exception as cache_error:
                # Cache miss - download from Hugging Face
                logger.info(f"📥 Cache miss ({cache_error}) - downloading {model_name} from Hugging Face...")
                model = MusicgenForConditionalGeneration.from_pretrained(
                    model_name,
                    cache_dir=cache_dir
                )
                processor = AutoProcessor.from_pretrained(
                    model_name,
                    cache_dir=cache_dir
                )
                logger.info(f"✅ Downloaded and cached {model_name} to {cache_dir}")
            
            # Move to appropriate device
            model = model.to(self.device)
            
            logger.info(f"✅ Successfully loaded {model_name}")
            return model, processor
            
        except Exception as e:
            logger.error(f"Failed to load Hugging Face MusicGen model: {e}")
            # Return mock model as fallback
            return MockMusicGenModel(), None
    
    def _load_audiocraft_model(self):
        """Load MusicGen model from AudioCraft (runs in thread pool)."""
        try:
            model = MusicGen.get_pretrained(f"facebook/musicgen-{self.model_size}")
            model.set_generation_params(duration=30)  # Default 30 seconds
            return model
        except Exception as e:
            logger.error(f"Failed to load AudioCraft MusicGen model: {e}")
            # Return mock model as fallback
            return MockMusicGenModel()
    
    async def generate_music(
        self,
        prompt: str,
        duration: float = 30.0,
        temperature: float = 1.0,
        top_k: int = 250,
        top_p: float = 0.0,
        cfg_coef: float = 3.0,
        seed: Optional[int] = None,
        progress_callback=None
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
            seed: Random seed for deterministic generation (optional)
            
        Returns:
            Tuple of (audio_tensor, sample_rate)
        """
        if not self.is_initialized:
            await self.initialize()
        
        logger.info(f"🎵 Generating music: '{prompt}' ({duration}s)")
        
        # Generate in thread pool to avoid blocking
        loop = asyncio.get_event_loop()
        
        # Start a progress simulation task if callback provided
        progress_task = None
        if progress_callback:
            progress_task = asyncio.create_task(
                self._simulate_progress(progress_callback, duration)
            )
        
        try:
            audio_tensor = await loop.run_in_executor(
                None,
                self._generate_audio,
                prompt,
                duration,
                temperature,
                top_k,
                top_p,
                cfg_coef,
                seed
            )
        finally:
            # Cancel progress simulation
            if progress_task:
                progress_task.cancel()
                try:
                    await progress_task
                except asyncio.CancelledError:
                    pass
        
        logger.info("✅ Music generation complete")
        return audio_tensor, self.sample_rate
    
    async def _simulate_progress(self, progress_callback, duration: float):
        """Simulate smooth progress during generation."""
        try:
            # Estimate generation time based on duration (roughly 2-4x real-time)
            estimated_time = max(duration * 2, 10)  # At least 10 seconds
            
            # Progress from 0.3 to 0.75 over the estimated time
            start_progress = 0.3
            end_progress = 0.75
            steps = 20  # Number of progress updates
            
            for i in range(steps):
                await asyncio.sleep(estimated_time / steps)
                progress = start_progress + (end_progress - start_progress) * (i + 1) / steps
                progress_callback(progress)
                
        except asyncio.CancelledError:
            # Generation completed, final progress will be set by caller
            pass
    
    def _generate_audio(self, prompt: str, duration: float, temperature: float, 
                       top_k: int, top_p: float, cfg_coef: float, seed: Optional[int] = None) -> torch.Tensor:
        """Generate audio (runs in thread pool)."""
        logger.info(f"🎵 _generate_audio called with prompt='{prompt}', duration={duration}")
        
        # Set deterministic seed for reproducible generation
        if seed is not None:
            import random
            import numpy as np
            import os
            
            # Set all random seeds for deterministic generation
            torch.manual_seed(seed)
            torch.cuda.manual_seed_all(seed)  # For GPU generation
            random.seed(seed)
            np.random.seed(seed)
            
            # Set environment variables for deterministic behavior
            os.environ['PYTHONHASHSEED'] = str(seed)
            
            # Ensure deterministic behavior for PyTorch
            torch.backends.cudnn.deterministic = True
            torch.backends.cudnn.benchmark = False
            torch.use_deterministic_algorithms(True, warn_only=True)
            
            logger.info(f"🎲 Set comprehensive deterministic seed: {seed}")
        else:
            # Generate random seed for logging
            import time
            random_seed = int(time.time() * 1000000) % (2**32)
            logger.info(f"🎲 Using random seed: {random_seed}")
        
        try:
            with torch.no_grad():
                if TRANSFORMERS_AVAILABLE and hasattr(self.model, 'generate') and self.processor is not None:
                    # Hugging Face transformers model
                    logger.info("🤗 Using Hugging Face MusicGen model")
                    logger.info(f"📊 Model device: {self.device}, Sample rate: {self.sample_rate}")
                    
                    # Process the prompt
                    logger.info("📝 Processing prompt with tokenizer...")
                    inputs = self.processor(
                        text=[prompt],
                        padding=True,
                        return_tensors="pt",
                    ).to(self.device)
                    logger.info(f"✅ Prompt processed, input shape: {inputs.input_ids.shape}")
                    
                    # Calculate max_new_tokens based on duration and sample rate
                    # Note: MusicGen uses compressed tokens, not raw audio samples
                    # Use a much smaller token count for reasonable generation time
                    max_new_tokens = min(int(duration * 50), 1024)  # ~50 tokens per second, max 1024
                    logger.info(f"🔢 Calculated max_new_tokens: {max_new_tokens} (duration={duration}s, capped for performance)")
                    
                    # Generate audio
                    logger.info("🚀 Starting model.generate() - this may take a while...")
                    logger.info(f"⚙️ Generation params: guidance_scale={cfg_coef}, temperature={temperature}, top_k={top_k}, top_p={top_p}")
                    
                    audio_values = self.model.generate(
                        **inputs,
                        do_sample=True,
                        guidance_scale=cfg_coef,
                        max_new_tokens=max_new_tokens,
                        temperature=temperature,
                        top_k=top_k,
                        top_p=top_p if top_p > 0 else None,
                    )
                    
                    logger.info(f"✅ Model generation complete! Audio shape: {audio_values.shape}")
                    
                    # Return audio tensor
                    result = audio_values[0].cpu()
                    logger.info(f"🎵 Returning audio tensor with shape: {result.shape}")
                    return result
                    
                elif AUDIOCRAFT_AVAILABLE and hasattr(self.model, 'generate'):
                    # AudioCraft model
                    logger.info("🎵 Using AudioCraft MusicGen model")
                    
                    # Set generation parameters
                    self.model.set_generation_params(
                        duration=duration,
                        temperature=temperature,
                        top_k=top_k,
                        top_p=top_p,
                        cfg_coef=cfg_coef
                    )
                    
                    wav = self.model.generate([prompt])
                    return wav[0].cpu()  # Return first (and only) generated sample
                    
                else:
                    # Mock model
                    logger.info("🔧 Using mock MusicGen model")
                    self.model.set_generation_params(duration=duration)
                    return self.model.generate(prompt)
                    
        except Exception as e:
            logger.error(f"Audio generation failed: {e}")
            # Return silence as fallback
            duration_samples = int(duration * self.sample_rate)
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
            # Always use torchaudio for deterministic saving
            # AudioCraft's audio_write adds non-deterministic PEAK metadata
            
            # Ensure tensor is 2D with shape [channels, samples]
            if audio_tensor.dim() == 1:
                audio_tensor = audio_tensor.unsqueeze(0)  # Add channel dimension
            elif audio_tensor.dim() == 2 and audio_tensor.shape[0] > audio_tensor.shape[1]:
                # If shape is [samples, channels], transpose to [channels, samples]
                audio_tensor = audio_tensor.transpose(0, 1)
            
            # Use torchaudio.save for deterministic output
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
        self.duration = 30.0  # Default duration
    
    def set_generation_params(self, duration=None, **kwargs):
        """Mock parameter setting."""
        if duration is not None:
            self.duration = duration
    
    def generate(self, prompt: str) -> torch.Tensor:
        """Generate mock audio (sine wave)."""
        duration = self.duration
        sample_rate = self.sample_rate
        
        # Generate a simple sine wave as placeholder
        t = torch.linspace(0, duration, int(duration * sample_rate))
        frequency = 440.0  # A4 note
        audio = 0.3 * torch.sin(2 * torch.pi * frequency * t)
        
        # Return as 2D tensor: [batch_size, samples] -> [1, samples]
        return audio.unsqueeze(0)
