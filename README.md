# VoxCPM2 Server (Python Direct)

FastAPI server for **VoxCPM2** voice cloning and TTS, designed for direct Python deployment on GPU servers (no Docker required).

## Features

- ✅ **5 endpoints**: health, voices, tts, clone, clone-with-preset
- ✅ **Multi-language** support (30 languages including Vietnamese)
- ✅ **Voice library** with multi-preset support
- ✅ **API key auth** for security
- ✅ **Streaming WAV** binary response
- ✅ **Production-ready** logging, error handling, health checks
- ✅ **Compatible with ckey.vn Template 4** (PyTorch 2.5.1 CUDA 12.4)

## Quick Start

### On GPU server (ckey.vn Template 4 - PyTorch)

```bash
# 1. Clone repo
git clone https://github.com/qhanm/voxcpm-server-py.git
cd voxcpm-server-py

# 2. Setup (one-time, ~10 minutes)
chmod +x *.sh
bash setup.sh

# 3. Set API key
export API_KEY="$(openssl rand -hex 32)"
echo "Save this key: $API_KEY"

# 4. Start server (foreground)
bash start.sh

# Or daemon mode
bash start.sh --daemon

# 5. Verify health (in another terminal)
bash health-check.sh
```

### Test from local machine

```bash
python3 test-client.py \
    --server http://gpu-server-ip:8000 \
    --api-key YOUR_API_KEY \
    --reference-audio /path/to/sample.wav
```

## Project Structure

```
voxcpm-server-py/
├── server.py                  # Main FastAPI server
├── test-client.py             # Test client
├── requirements.txt           # Locked Python dependencies
│
├── setup.sh                   # Install + download model
├── start.sh                   # Start server
├── stop.sh                    # Stop daemon
├── health-check.sh            # Wait for server ready
│
├── configs/
│   └── presets.example.json   # Voice preset config example
│
├── utils/
│   └── __init__.py
│
├── docs/
│   ├── deployment.md          # Deployment guide
│   ├── troubleshooting.md     # Common errors & fixes
│   └── api-reference.md       # API documentation
│
├── voice_library/             # Voice library (gitignored)
│   └── voice_001/
│       ├── reference.wav
│       ├── reference.txt
│       └── presets.json
│
├── models/                    # Downloaded model (gitignored, ~5GB)
│   └── VoxCPM2/
│
├── .env.example
├── .gitignore
└── README.md
```

## API Endpoints

### `GET /health`

Health check. **No auth required.**

```bash
curl http://localhost:8000/health
```

### `GET /voices`

List voices in library.

```bash
curl -H "X-API-Key: YOUR_KEY" http://localhost:8000/voices
```

### `POST /tts` - Voice Design

Generate audio from text + voice description (no audio sample needed).

```bash
curl -X POST http://localhost:8000/tts \
    -H "X-API-Key: YOUR_KEY" \
    -F "text=Xin chào, đây là test" \
    -F "voice_description=A warm Vietnamese male voice" \
    -F "cfg_value=2.0" \
    -F "inference_timesteps=15" \
    -o output.wav
```

### `POST /clone` - Voice Cloning

Clone voice from uploaded audio sample.

```bash
curl -X POST http://localhost:8000/clone \
    -H "X-API-Key: YOUR_KEY" \
    -F "text=Đây là giọng được clone" \
    -F "reference_audio=@/path/to/sample.wav" \
    -F "reference_text=Transcript chính xác của file mẫu" \
    -F "style_instruction=warm, slow" \
    -F "cfg_value=2.8" \
    -F "inference_timesteps=25" \
    -o cloned.wav
```

### `POST /clone-with-preset` - Library Voice

Generate audio using voice from library.

```bash
curl -X POST http://localhost:8000/clone-with-preset \
    -H "X-API-Key: YOUR_KEY" \
    -F "text=Sử dụng giọng có sẵn" \
    -F "voice_id=voice_001_male_warm" \
    -F "preset=storytelling" \
    -o output.wav
```

## Voice Library Setup

Each voice is a folder with reference audio + transcripts + presets.json:

```
voice_library/voice_001_male_warm/
├── reference.wav              # Master reference audio (60s)
├── reference.txt              # Transcript of reference.wav
├── presets.json               # Preset configurations
└── presets/
    ├── storytelling.wav       # 30s storytelling sample
    ├── storytelling.txt
    ├── news.wav
    └── news.txt
```

See `configs/presets.example.json` for full preset config example.

## Performance

Tested on **NVIDIA RTX 5060 Ti 16GB** (Template 4 ckey.vn):

| Operation | Time | RTF |
|---|---|---|
| Model load (cold) | 30-45s | - |
| Generate 5s audio | ~3s | 0.6 |
| Generate 30s audio | ~12s | 0.4 |
| Generate 60s audio | ~20s | 0.33 |

VRAM usage: ~7-8GB (model) + 1-2GB (inference buffer).

## Environment Variables

See `.env.example` for full list.

| Variable | Default | Description |
|---|---|---|
| `API_KEY` | (required) | API authentication key |
| `MODEL_PATH` | `./models/VoxCPM2` | Path to model weights |
| `VOICE_LIBRARY_DIR` | `./voice_library` | Voice library folder |
| `PORT` | `8000` | Server port |
| `LOG_LEVEL` | `INFO` | DEBUG / INFO / WARNING / ERROR |
| `LOAD_DENOISER` | `false` | Load denoiser (extra ~1GB VRAM) |

## Deployment Strategies

### 1. Manual (Development)

SSH into GPU server, run setup + start manually.

### 2. SSH Automation (Production)

Backend orchestrator (NestJS) handles:
- Rent GPU via ckey.vn API
- SSH into server
- `git clone` + `bash setup.sh` + `bash start.sh --daemon`
- Health check + register endpoint

See `docs/deployment.md` for full automation guide.

### 3. Cached Deployment (Faster)

Pre-build venv archive + cache on R2/MinIO:
- First setup: 10 minutes
- Subsequent: ~2 minutes (download cache)

## Documentation

- [Deployment Guide](docs/deployment.md)
- [API Reference](docs/api-reference.md)
- [Troubleshooting](docs/troubleshooting.md)

## License

Apache 2.0 (matches VoxCPM2 license)

## Related Projects

- [VoxCPM2 Model](https://github.com/OpenBMB/VoxCPM)
- Backend Orchestrator (NestJS): coming soon
- Frontend Admin (React): coming soon
