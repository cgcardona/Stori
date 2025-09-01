"""
Health Check Routes

Endpoints for monitoring service health and status.
"""

import time
import psutil
import torch
from fastapi import APIRouter, Request
from app.api.models.responses import HealthResponse

router = APIRouter()

# Track service start time
start_time = time.time()


@router.get("/", response_model=HealthResponse)
async def health_check(request: Request):
    """
    Get service health status and system information.
    
    Returns comprehensive health information including:
    - Service status and uptime
    - Model information and GPU status
    - System resource usage
    - Memory and CPU statistics
    """
    # Get MusicGen engine from app state
    musicgen_engine = getattr(request.app.state, 'musicgen_engine', None)
    
    # Calculate uptime
    uptime = time.time() - start_time
    
    # Get model information
    model_info = {}
    if musicgen_engine:
        model_info = musicgen_engine.get_model_info()
    else:
        model_info = {
            "status": "not_initialized",
            "error": "MusicGen engine not available"
        }
    
    # Get system information
    system_info = {
        "cpu_percent": psutil.cpu_percent(interval=1),
        "memory_percent": psutil.virtual_memory().percent,
        "memory_available_gb": psutil.virtual_memory().available / (1024**3),
        "disk_usage_percent": psutil.disk_usage('/').percent,
        "python_version": f"{psutil.version_info}",
    }
    
    # Add GPU information if available
    if torch.cuda.is_available():
        system_info.update({
            "gpu_available": True,
            "gpu_count": torch.cuda.device_count(),
            "gpu_memory_allocated_gb": torch.cuda.memory_allocated() / (1024**3),
            "gpu_memory_reserved_gb": torch.cuda.memory_reserved() / (1024**3),
        })
    else:
        system_info["gpu_available"] = False
    
    # Determine overall status
    status = "healthy"
    if not musicgen_engine or not musicgen_engine.is_initialized:
        status = "degraded"
    elif system_info["memory_percent"] > 90 or system_info["cpu_percent"] > 90:
        status = "warning"
    
    return HealthResponse(
        status=status,
        version="1.0.0",
        model_info=model_info,
        system_info=system_info,
        uptime=uptime
    )


@router.get("/ready")
async def readiness_check(request: Request):
    """
    Kubernetes-style readiness probe.
    
    Returns 200 if service is ready to handle requests,
    503 if service is not ready.
    """
    musicgen_engine = getattr(request.app.state, 'musicgen_engine', None)
    
    if musicgen_engine and musicgen_engine.is_initialized:
        return {"status": "ready"}
    else:
        from fastapi import HTTPException
        raise HTTPException(status_code=503, detail="Service not ready")


@router.get("/live")
async def liveness_check():
    """
    Kubernetes-style liveness probe.
    
    Returns 200 if service is alive and responding.
    """
    return {"status": "alive", "timestamp": time.time()}
