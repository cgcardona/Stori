"""
API Response Models

Pydantic models for API responses.
"""

from typing import Optional, Dict, Any, List
from datetime import datetime
from enum import Enum
from pydantic import BaseModel, Field


class GenerationStatus(str, Enum):
    """Status of a generation job."""
    QUEUED = "queued"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class GenerationResponse(BaseModel):
    """Response model for generation requests."""
    
    job_id: str = Field(..., description="Unique job identifier")
    status: GenerationStatus = Field(..., description="Current job status")
    message: str = Field(..., description="Status message")
    created_at: datetime = Field(..., description="Job creation timestamp")
    estimated_completion: Optional[datetime] = Field(
        None, 
        description="Estimated completion time"
    )
    
    class Config:
        schema_extra = {
            "example": {
                "job_id": "gen_123456789",
                "status": "processing",
                "message": "Generation in progress",
                "created_at": "2024-12-01T10:00:00Z",
                "estimated_completion": "2024-12-01T10:01:00Z"
            }
        }


class GenerationStatusResponse(BaseModel):
    """Response model for job status queries."""
    
    job_id: str = Field(..., description="Job identifier")
    status: GenerationStatus = Field(..., description="Current status")
    progress: float = Field(
        default=0.0,
        ge=0.0,
        le=1.0,
        description="Progress percentage (0.0-1.0)"
    )
    message: str = Field(..., description="Status message")
    created_at: datetime = Field(..., description="Job creation timestamp")
    started_at: Optional[datetime] = Field(None, description="Processing start time")
    completed_at: Optional[datetime] = Field(None, description="Completion time")
    error_message: Optional[str] = Field(None, description="Error message if failed")
    
    # Generation parameters
    prompt: Optional[str] = Field(None, description="Original prompt")
    duration: Optional[float] = Field(None, description="Requested duration")
    
    # Results (when completed)
    audio_url: Optional[str] = Field(None, description="Download URL for generated audio")
    file_size: Optional[int] = Field(None, description="File size in bytes")
    actual_duration: Optional[float] = Field(None, description="Actual audio duration")


class GenerationResultResponse(BaseModel):
    """Response model for completed generation results."""
    
    job_id: str = Field(..., description="Job identifier")
    prompt: str = Field(..., description="Original prompt")
    audio_url: str = Field(..., description="Download URL")
    duration: float = Field(..., description="Audio duration in seconds")
    file_size: int = Field(..., description="File size in bytes")
    sample_rate: int = Field(..., description="Audio sample rate")
    format: str = Field(default="wav", description="Audio format")
    created_at: datetime = Field(..., description="Generation timestamp")
    
    # Metadata
    generation_params: Dict[str, Any] = Field(
        default_factory=dict,
        description="Parameters used for generation"
    )


class PromptBuilderResponse(BaseModel):
    """Response model for prompt builder."""
    
    structured_prompt: str = Field(..., description="Generated structured prompt")
    components: Dict[str, Optional[str]] = Field(
        ...,
        description="Individual prompt components"
    )
    
    class Config:
        schema_extra = {
            "example": {
                "structured_prompt": "electronic music, fast tempo, energetic mood, featuring synthesizer and drums, similar to Daft Punk, with a futuristic vibe",
                "components": {
                    "genre": "electronic music",
                    "tempo": "fast tempo",
                    "mood": "energetic mood",
                    "instruments": "featuring synthesizer and drums",
                    "artist_style": "similar to Daft Punk",
                    "custom_text": "with a futuristic vibe"
                }
            }
        }


class BatchGenerationResponse(BaseModel):
    """Response model for batch generation requests."""
    
    batch_id: str = Field(..., description="Unique batch identifier")
    job_ids: List[str] = Field(..., description="Individual job identifiers")
    total_jobs: int = Field(..., description="Total number of jobs in batch")
    status: str = Field(..., description="Batch status")
    created_at: datetime = Field(..., description="Batch creation timestamp")


class HealthResponse(BaseModel):
    """Response model for health check."""
    
    status: str = Field(..., description="Service status")
    version: str = Field(..., description="Service version")
    model_info: Dict[str, Any] = Field(..., description="Model information")
    system_info: Dict[str, Any] = Field(..., description="System information")
    uptime: float = Field(..., description="Service uptime in seconds")


class ErrorResponse(BaseModel):
    """Response model for errors."""
    
    error: str = Field(..., description="Error type")
    message: str = Field(..., description="Error message")
    detail: Optional[str] = Field(None, description="Detailed error information")
    job_id: Optional[str] = Field(None, description="Related job ID if applicable")
