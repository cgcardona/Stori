"""
Music Generation Routes

API endpoints for music generation using MusicGen.
"""

import uuid
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, Any

from fastapi import APIRouter, Request, HTTPException, BackgroundTasks
from fastapi.responses import FileResponse

from app.api.models.requests import GenerationRequest, PromptBuilderRequest
from app.api.models.responses import (
    GenerationResponse, 
    GenerationStatusResponse, 
    PromptBuilderResponse,
    GenerationStatus
)
from app.core.prompt_builder import PromptBuilder

router = APIRouter()
logger = logging.getLogger(__name__)

# In-memory job storage (use Redis in production)
jobs: Dict[str, Dict[str, Any]] = {}

# Initialize prompt builder
prompt_builder = PromptBuilder()


@router.post("/generate", response_model=GenerationResponse)
async def generate_music(
    request: GenerationRequest,
    background_tasks: BackgroundTasks,
    app_request: Request
):
    """
    Start a music generation job.
    
    Creates a new generation job and returns immediately with job ID.
    The actual generation runs in the background.
    """
    # Generate unique job ID
    job_id = f"gen_{uuid.uuid4().hex[:12]}"
    
    # Get generation service from app state
    generation_service = getattr(app_request.app.state, 'generation_service', None)
    if not generation_service:
        raise HTTPException(
            status_code=503, 
            detail="Generation service not available"
        )
    
    # Create job record
    job_data = {
        "job_id": job_id,
        "status": GenerationStatus.QUEUED,
        "prompt": request.prompt,
        "duration": request.duration,
        "temperature": request.temperature,
        "top_k": request.top_k,
        "top_p": request.top_p,
        "cfg_coef": request.cfg_coef,
        "created_at": datetime.utcnow(),
        "progress": 0.0,
        "message": "Job queued for processing"
    }
    
    jobs[job_id] = job_data
    
    # Start background generation
    background_tasks.add_task(
        process_generation_job,
        job_id,
        request,
        generation_service
    )
    
    logger.info(f"🎵 Started generation job {job_id}: '{request.prompt}'")
    
    return GenerationResponse(
        job_id=job_id,
        status=GenerationStatus.QUEUED,
        message="Generation job started",
        created_at=job_data["created_at"]
    )


@router.get("/status/{job_id}", response_model=GenerationStatusResponse)
async def get_generation_status(job_id: str):
    """
    Get the status of a generation job.
    
    Returns current status, progress, and results if completed.
    """
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    
    job_data = jobs[job_id]
    
    return GenerationStatusResponse(
        job_id=job_id,
        status=job_data["status"],
        progress=job_data.get("progress", 0.0),
        message=job_data.get("message", ""),
        created_at=job_data["created_at"],
        started_at=job_data.get("started_at"),
        completed_at=job_data.get("completed_at"),
        error_message=job_data.get("error_message"),
        prompt=job_data.get("prompt"),
        duration=job_data.get("duration"),
        audio_url=job_data.get("audio_url"),
        file_size=job_data.get("file_size"),
        actual_duration=job_data.get("actual_duration")
    )


@router.get("/download/{job_id}")
async def download_generated_audio(job_id: str):
    """
    Download the generated audio file.
    
    Returns the audio file as a downloadable response.
    """
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    
    job_data = jobs[job_id]
    
    if job_data["status"] != GenerationStatus.COMPLETED:
        raise HTTPException(
            status_code=400, 
            detail=f"Job not completed (status: {job_data['status']})"
        )
    
    audio_path = job_data.get("audio_path")
    if not audio_path or not Path(audio_path).exists():
        raise HTTPException(status_code=404, detail="Audio file not found")
    
    return FileResponse(
        path=audio_path,
        media_type="audio/wav",
        filename=f"{job_id}.wav"
    )


@router.post("/prompt/build", response_model=PromptBuilderResponse)
async def build_prompt(request: PromptBuilderRequest):
    """
    Build a structured prompt from components.
    
    Takes individual components (genre, tempo, mood, etc.) and
    constructs a well-formatted prompt for music generation.
    """
    try:
        structured_prompt = prompt_builder.build_prompt(
            genre=request.genre,
            tempo=request.tempo,
            mood=request.mood,
            artist_style=request.artist_style,
            instruments=request.instruments,
            custom_text=request.custom_text
        )
        
        # Build components dict for response
        components = {}
        if request.genre:
            components["genre"] = f"{request.genre} music"
        if request.tempo:
            components["tempo"] = f"{request.tempo} tempo"
        if request.mood:
            components["mood"] = f"{request.mood} mood"
        if request.instruments:
            components["instruments"] = f"featuring {', '.join(request.instruments)}"
        if request.artist_style:
            components["artist_style"] = request.artist_style
        if request.custom_text:
            components["custom_text"] = request.custom_text
        
        return PromptBuilderResponse(
            structured_prompt=structured_prompt,
            components=components
        )
        
    except Exception as e:
        logger.error(f"Prompt building failed: {e}")
        raise HTTPException(status_code=400, detail=str(e))


@router.delete("/jobs/{job_id}")
async def cancel_generation_job(job_id: str):
    """
    Cancel a generation job.
    
    Cancels a queued or processing job. Completed jobs cannot be cancelled.
    """
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    
    job_data = jobs[job_id]
    
    if job_data["status"] in [GenerationStatus.COMPLETED, GenerationStatus.FAILED]:
        raise HTTPException(
            status_code=400, 
            detail=f"Cannot cancel {job_data['status']} job"
        )
    
    # Update job status
    job_data["status"] = GenerationStatus.CANCELLED
    job_data["message"] = "Job cancelled by user"
    job_data["completed_at"] = datetime.utcnow()
    
    logger.info(f"🚫 Cancelled generation job {job_id}")
    
    return {"message": "Job cancelled successfully"}


@router.get("/jobs")
async def list_jobs(limit: int = 50, status: str = None):
    """
    List recent generation jobs.
    
    Returns a list of recent jobs, optionally filtered by status.
    """
    filtered_jobs = []
    
    for job_data in jobs.values():
        if status and job_data["status"] != status:
            continue
        filtered_jobs.append({
            "job_id": job_data["job_id"],
            "status": job_data["status"],
            "prompt": job_data["prompt"][:100] + "..." if len(job_data["prompt"]) > 100 else job_data["prompt"],
            "created_at": job_data["created_at"],
            "duration": job_data.get("duration")
        })
    
    # Sort by creation time (newest first)
    filtered_jobs.sort(key=lambda x: x["created_at"], reverse=True)
    
    return {
        "jobs": filtered_jobs[:limit],
        "total": len(filtered_jobs)
    }


async def process_generation_job(
    job_id: str, 
    request: GenerationRequest, 
    generation_service
):
    """
    Background task to process a generation job.
    
    This runs the actual music generation and updates job status.
    """
    try:
        # Update job status to processing
        jobs[job_id].update({
            "status": GenerationStatus.PROCESSING,
            "started_at": datetime.utcnow(),
            "message": "Generating music...",
            "progress": 0.1
        })
        
        logger.info(f"🎵 Processing generation job {job_id}")
        
        # Update progress to show we're starting AI generation
        jobs[job_id].update({
            "progress": 0.3,
            "message": "AI model processing prompt..."
        })
        
        # Create progress callback
        def update_progress(progress: float):
            jobs[job_id]["progress"] = progress
            jobs[job_id]["message"] = f"AI generating music... {int(progress * 100)}%"
        
        # Generate music
        logger.info(f"🎵 Calling generation_service.generate_music for job {job_id}")
        logger.info(f"📝 Prompt: '{request.prompt}', Duration: {request.duration}s")
        
        audio_tensor, sample_rate = await generation_service.generate_music(
            prompt=request.prompt,
            duration=request.duration,
            temperature=request.temperature,
            top_k=request.top_k,
            top_p=request.top_p,
            cfg_coef=request.cfg_coef,
            progress_callback=update_progress
        )
        
        logger.info(f"✅ Generation service returned audio tensor: {audio_tensor.shape} @ {sample_rate}Hz")
        
        # Update progress
        jobs[job_id]["progress"] = 0.8
        jobs[job_id]["message"] = "Saving audio file..."
        
        # Save audio file
        output_dir = Path("generated_audio")
        output_dir.mkdir(exist_ok=True)
        audio_path = output_dir / f"{job_id}.wav"
        
        await generation_service.save_audio(audio_tensor, audio_path, sample_rate)
        
        # Get file info
        file_size = audio_path.stat().st_size
        # Handle tensor dimensions safely
        if audio_tensor.dim() == 1:
            actual_duration = len(audio_tensor) / sample_rate
        elif audio_tensor.dim() == 2:
            actual_duration = audio_tensor.shape[-1] / sample_rate  # Use last dimension (samples)
        else:
            actual_duration = request.duration  # Fallback to requested duration
        
        # Update job as completed
        jobs[job_id].update({
            "status": GenerationStatus.COMPLETED,
            "completed_at": datetime.utcnow(),
            "message": "Generation completed successfully",
            "progress": 1.0,
            "audio_path": str(audio_path),
            "audio_url": f"/api/v1/download/{job_id}",
            "file_size": file_size,
            "actual_duration": actual_duration
        })
        
        logger.info(f"✅ Completed generation job {job_id}")
        
    except Exception as e:
        logger.error(f"❌ Generation job {job_id} failed: {e}")
        
        # Update job as failed
        jobs[job_id].update({
            "status": GenerationStatus.FAILED,
            "completed_at": datetime.utcnow(),
            "message": "Generation failed",
            "error_message": str(e),
            "progress": 0.0
        })
