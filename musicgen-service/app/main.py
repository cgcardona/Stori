"""
TellUrStori MusicGen Service - Main Application

FastAPI application for AI music generation using Meta's AudioCraft MusicGen.
"""

import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.routes import generation, health
from app.core.musicgen_engine import MusicGenEngine
from app.services.generation_service import GenerationService

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global instances
musicgen_engine = None
generation_service = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager for startup and shutdown."""
    global musicgen_engine, generation_service
    
    logger.info("🎵 Starting TellUrStori MusicGen Service...")
    
    try:
        # Initialize MusicGen engine
        logger.info("Loading MusicGen model...")
        musicgen_engine = MusicGenEngine(model_size="small")
        await musicgen_engine.initialize()
        
        # Initialize generation service
        generation_service = GenerationService(musicgen_engine)
        
        # Store in app state for access in routes
        app.state.musicgen_engine = musicgen_engine
        app.state.generation_service = generation_service
        
        logger.info("✅ MusicGen service ready!")
        
    except Exception as e:
        logger.error(f"❌ Failed to initialize MusicGen service: {e}")
        raise
    
    yield
    
    # Cleanup
    logger.info("🔄 Shutting down MusicGen service...")
    if musicgen_engine:
        await musicgen_engine.cleanup()
    logger.info("✅ Shutdown complete")


# Create FastAPI application
app = FastAPI(
    title="TellUrStori MusicGen Service",
    description="AI-powered music generation using Meta's AudioCraft MusicGen",
    version="1.0.0",
    lifespan=lifespan
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API routes
app.include_router(health.router, prefix="/health", tags=["health"])
app.include_router(generation.router, prefix="/api/v1", tags=["generation"])


@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Global exception handler for unhandled errors."""
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"error": "Internal server error", "detail": str(exc)}
    )


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time generation updates."""
    await websocket.accept()
    logger.info("WebSocket connection established")
    
    try:
        while True:
            # Keep connection alive and handle messages
            data = await websocket.receive_text()
            logger.info(f"Received WebSocket message: {data}")
            
            # Echo back for now - will implement generation updates later
            await websocket.send_text(f"Echo: {data}")
            
    except WebSocketDisconnect:
        logger.info("WebSocket connection closed")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        await websocket.close()


@app.get("/")
async def root():
    """Root endpoint with service information."""
    return {
        "service": "TellUrStori MusicGen Service",
        "version": "1.0.0",
        "status": "running",
        "endpoints": {
            "health": "/health",
            "generate": "/api/v1/generate",
            "status": "/api/v1/status/{job_id}",
            "download": "/api/v1/download/{job_id}",
            "websocket": "/ws"
        }
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )
