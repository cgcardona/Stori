# 🎵 TellUrStori MusicGen Service

AI-powered music generation backend using Meta's AudioCraft MusicGen for the TellUrStori DAW.

## 🚀 Features

- **AI Music Generation**: Meta's AudioCraft MusicGen integration
- **RESTful API**: FastAPI-based service with async support
- **WebSocket Support**: Real-time generation progress updates
- **Prompt Builder**: Structured prompt creation from components
- **Background Processing**: Async job queue for long-running generations
- **Health Monitoring**: Comprehensive health checks and metrics
- **Docker Support**: Containerized deployment with GPU support

## 📋 Requirements

### System Requirements
- Python 3.11+
- CUDA-compatible GPU (recommended)
- 8GB+ RAM (16GB+ recommended)
- 10GB+ free disk space for models

### Dependencies
- PyTorch 2.0+
- AudioCraft 1.3.0+
- FastAPI 0.104+
- Redis (for caching and job queue)

## 🛠️ Installation

### Option 1: Docker (Recommended)

```bash
# Clone the repository
git clone <repository-url>
cd musicgen-service

# Start with Docker Compose
docker-compose up -d

# Check service health
curl http://localhost:8000/health
```

### Option 2: Local Development

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Start Redis (required)
redis-server

# Run the service
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

## 🎯 API Usage

### Generate Music

```bash
# Start a generation job
curl -X POST "http://localhost:8000/api/v1/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "upbeat electronic music with synthesizer and drums",
    "duration": 30.0,
    "temperature": 1.0
  }'

# Response
{
  "job_id": "gen_abc123456789",
  "status": "queued",
  "message": "Generation job started",
  "created_at": "2024-12-01T10:00:00Z"
}
```

### Check Status

```bash
# Get job status
curl "http://localhost:8000/api/v1/status/gen_abc123456789"

# Response
{
  "job_id": "gen_abc123456789",
  "status": "completed",
  "progress": 1.0,
  "message": "Generation completed successfully",
  "audio_url": "/api/v1/download/gen_abc123456789",
  "duration": 30.0
}
```

### Download Audio

```bash
# Download generated audio
curl "http://localhost:8000/api/v1/download/gen_abc123456789" \
  --output generated_music.wav
```

### Build Structured Prompts

```bash
# Build prompt from components
curl -X POST "http://localhost:8000/api/v1/prompt/build" \
  -H "Content-Type: application/json" \
  -d '{
    "genre": "electronic",
    "tempo": "fast",
    "mood": "energetic",
    "instruments": ["synthesizer", "drums"],
    "artist_style": "similar to Daft Punk"
  }'

# Response
{
  "structured_prompt": "electronic music, fast tempo, energetic mood, featuring synthesizer and drums, similar to Daft Punk",
  "components": {
    "genre": "electronic music",
    "tempo": "fast tempo",
    "mood": "energetic mood",
    "instruments": "featuring synthesizer and drums",
    "artist_style": "similar to Daft Punk"
  }
}
```

## 🔧 Configuration

### Environment Variables

```bash
# Service Configuration
PYTHONPATH=/app
PYTHONUNBUFFERED=1

# Redis Configuration
REDIS_URL=redis://localhost:6379

# Model Configuration
MUSICGEN_MODEL_SIZE=medium  # small, medium, large
MUSICGEN_DEVICE=cuda        # cuda, cpu, auto

# Generation Limits
MAX_DURATION=120            # Maximum generation duration in seconds
MAX_CONCURRENT_JOBS=5       # Maximum concurrent generation jobs
```

### Model Sizes

| Model | Parameters | VRAM Required | Generation Speed |
|-------|------------|---------------|------------------|
| Small | 300M | 2GB | Fast |
| Medium | 1.5B | 6GB | Moderate |
| Large | 3.3B | 12GB | Slow |

## 📊 API Endpoints

### Generation Endpoints
- `POST /api/v1/generate` - Start music generation
- `GET /api/v1/status/{job_id}` - Get job status
- `GET /api/v1/download/{job_id}` - Download generated audio
- `DELETE /api/v1/jobs/{job_id}` - Cancel generation job
- `GET /api/v1/jobs` - List recent jobs

### Prompt Builder
- `POST /api/v1/prompt/build` - Build structured prompt

### Health & Monitoring
- `GET /health` - Comprehensive health check
- `GET /health/ready` - Readiness probe
- `GET /health/live` - Liveness probe

### WebSocket
- `WS /ws` - Real-time updates and communication

## 🐳 Docker Deployment

### Production Deployment

```yaml
# docker-compose.prod.yml
version: '3.8'
services:
  musicgen-service:
    image: tellurstoridaw/musicgen-service:latest
    ports:
      - "8000:8000"
    environment:
      - MUSICGEN_MODEL_SIZE=medium
      - MAX_CONCURRENT_JOBS=3
    volumes:
      - ./generated_audio:/app/generated_audio
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

### GPU Support

Ensure NVIDIA Docker runtime is installed:

```bash
# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update && sudo apt-get install -y nvidia-docker2
sudo systemctl restart docker
```

## 🧪 Testing

```bash
# Run tests
pytest tests/ -v

# Run with coverage
pytest tests/ --cov=app --cov-report=html

# Load testing
locust -f tests/load_test.py --host=http://localhost:8000
```

## 📈 Performance Tuning

### GPU Optimization
- Use appropriate model size for available VRAM
- Enable mixed precision training if supported
- Monitor GPU memory usage and adjust batch sizes

### CPU Optimization
- Increase worker processes for CPU-only deployment
- Use appropriate number of threads for audio processing
- Monitor CPU usage and memory consumption

### Caching Strategy
- Cache frequently requested prompts
- Implement LRU eviction for generated audio files
- Use Redis for job state management

## 🔍 Monitoring

### Health Checks
```bash
# Service health
curl http://localhost:8000/health

# Kubernetes probes
curl http://localhost:8000/health/ready
curl http://localhost:8000/health/live
```

### Metrics
- Generation success/failure rates
- Average generation time by model size
- GPU/CPU utilization
- Memory usage patterns
- Queue depth and processing times

## 🚨 Troubleshooting

### Common Issues

**Model Loading Fails**
```bash
# Check CUDA availability
python -c "import torch; print(torch.cuda.is_available())"

# Check disk space for models
df -h

# Check memory usage
free -h
```

**Generation Timeout**
- Reduce duration or use smaller model
- Check GPU memory availability
- Monitor system resources during generation

**Audio Quality Issues**
- Adjust temperature and sampling parameters
- Try different prompt formulations
- Ensure proper audio format conversion

### Logs
```bash
# Docker logs
docker-compose logs -f musicgen-service

# Application logs
tail -f /app/logs/musicgen.log
```

## 🤝 Integration with DAW

The MusicGen service integrates with the TellUrStori DAW through:

1. **HTTP API**: RESTful endpoints for generation requests
2. **WebSocket**: Real-time progress updates
3. **Audio Format**: WAV files compatible with DAW timeline
4. **Metadata**: Generation parameters and prompt information

### Swift Client Integration

```swift
// Example Swift client usage
let client = MusicGenClient(baseURL: "http://localhost:8000")

let request = GenerationRequest(
    prompt: "upbeat electronic music",
    duration: 30.0
)

let jobID = try await client.generateMusic(request)
let status = try await client.getStatus(jobID)
let audioURL = try await client.downloadAudio(jobID)
```

## 📄 License

This project is part of the TellUrStori V2 DAW system. See the main project license for details.

## 🆘 Support

For issues and questions:
1. Check the troubleshooting section above
2. Review logs for error messages
3. Ensure system requirements are met
4. Check GPU/CUDA compatibility

---

**Ready to generate amazing AI music! 🎵✨**
