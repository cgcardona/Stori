"""
API Request Models

Pydantic models for validating incoming API requests.
"""

from typing import List, Optional
from pydantic import BaseModel, Field, validator


class GenerationRequest(BaseModel):
    """Request model for music generation."""
    
    prompt: str = Field(
        ...,
        min_length=1,
        max_length=500,
        description="Text description of the music to generate"
    )
    duration: float = Field(
        default=30.0,
        ge=5.0,
        le=120.0,
        description="Duration of generated audio in seconds (5-120s)"
    )
    temperature: float = Field(
        default=1.0,
        ge=0.1,
        le=2.0,
        description="Sampling temperature (0.1-2.0, higher = more random)"
    )
    top_k: int = Field(
        default=250,
        ge=1,
        le=1000,
        description="Top-k sampling parameter"
    )
    top_p: float = Field(
        default=0.0,
        ge=0.0,
        le=1.0,
        description="Top-p sampling parameter"
    )
    cfg_coef: float = Field(
        default=3.0,
        ge=1.0,
        le=10.0,
        description="Classifier-free guidance coefficient"
    )
    seed: Optional[int] = Field(
        default=None,
        ge=0,
        le=2**32-1,
        description="Random seed for deterministic generation (0 to 4294967295). If None, uses random seed."
    )
    
    @validator('prompt')
    def validate_prompt(cls, v):
        """Validate and clean the prompt."""
        if not v or not v.strip():
            raise ValueError("Prompt cannot be empty")
        return v.strip()


class PromptBuilderRequest(BaseModel):
    """Request model for building structured prompts."""
    
    genre: Optional[str] = Field(
        None,
        description="Music genre (e.g., 'rock', 'jazz', 'electronic')"
    )
    tempo: Optional[str] = Field(
        None,
        description="Tempo description (e.g., 'fast', 'slow', '120 BPM')"
    )
    mood: Optional[str] = Field(
        None,
        description="Mood or emotion (e.g., 'happy', 'sad', 'energetic')"
    )
    instruments: Optional[List[str]] = Field(
        None,
        description="List of instruments to feature"
    )
    artist_style: Optional[str] = Field(
        None,
        description="Artist style reference (e.g., 'in the style of The Beatles')"
    )
    custom_text: Optional[str] = Field(
        None,
        max_length=200,
        description="Additional custom description"
    )
    
    class Config:
        json_schema_extra = {
            "example": {
                "genre": "electronic",
                "tempo": "fast",
                "mood": "energetic",
                "instruments": ["synthesizer", "drums"],
                "artist_style": "similar to Daft Punk",
                "custom_text": "with a futuristic vibe"
            }
        }


class BatchGenerationRequest(BaseModel):
    """Request model for batch music generation."""
    
    requests: List[GenerationRequest] = Field(
        ...,
        min_items=1,
        max_items=10,
        description="List of generation requests (max 10)"
    )
    
    @validator('requests')
    def validate_requests(cls, v):
        """Validate batch requests."""
        if len(v) > 10:
            raise ValueError("Maximum 10 requests per batch")
        return v
