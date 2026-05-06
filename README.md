# VoxCPM2 Server (Python Direct)

FastAPI server for **VoxCPM2** voice cloning and TTS, designed for direct Python deployment on GPU servers (no Docker required).

## Features

- ✅ **5 endpoints**: health, voices, tts, clone, clone-with-preset
- ✅ **Multi-language** support (30 languages including Vietnamese)
- ✅ **Voice library** with multi-preset support
- ✅ **API key auth** (auto-generated, secure)
- ✅ **Streaming WAV** binary response
- ✅ **Production-ready** logging, error handling, health checks
- ✅ **Auto-load .env** file (no manual export needed)
- ✅ **Compatible with ckey.vn Template 4** (PyTorch 2.5.1 CUDA 12.4)

## Quick Start

### On GPU server (ckey.vn Template 4)

```bash
# 1. Clone repo
git clone https://github.com/qhanm/voxcpm-server-py.git
cd voxcpm-server-py

# 2. Make scripts executable
chmod +x *.sh

# 3. Setup (one-time, ~10 minutes)
# This will:
# - Auto-create .env file with random API_KEY
# - Install Python dependencies
# - Download VoxCPM2 model (5GB)
bash setup.sh

# 4. Start server (daemon mode)
bash start.sh --daemon

# 5. Verify health
bash health-check.sh

# 6. View API key (save for backend integration)
grep API_KEY .env
```

### Test from local machine

```bash
# Install requests
pip install requests

# Run test client
python3 test-client.py \
    --server http://gpu-server-ip:8000 \
    --api-key "$(grep API_KEY .env | cut -d= -f2)"
```

## Environment Setup

Server tự động đọc `.env` file. Có 3 cách setup:

### Cách 1: Auto-generated (recommend)

```bash
bash init-env.sh
```

→ Tạo `.env` với API_KEY random + defaults.

### Cách 2: Manual

```bash
cp .env.example .env
# Edit .env, đặt API_KEY mạnh
nano .env
```

### Cách 3: Runtime override (backend orchestrator)

```bash
# Export trước khi run, không cần .env
export API_KEY="your-key-from-backend"
bash start.sh
```

→ Xem chi tiết: [docs/env-management.md](docs/env-management.md)

## Project Structure

```
voxcpm-server-py/
├── server.py                  # Main FastAPI server (auto-loads .env)
├── test-client.py             # Test client
├── requirements.txt           # Locked Python dependencies
│
├── init-env.sh                # Generate .env with random API_KEY
├── setup.sh                   # Install + download model
├── start.sh                   # Start server (auto-loads .env)
├── stop.sh                    # Stop daemon
├── health-check.sh            # Wait for server ready
│
├── configs/
│   └── presets.example.json   # Voice preset config example
│
├── docs/
│   ├── deployment.md          # Deployment guide
│   ├── env-management.md      # Environment configuration ⭐
│   ├── troubleshooting.md     # Common errors & fixes
│   └── api-reference.md       # API documentation
│
├── voice_library/             # Voice library (gitignored)
├── models/                    # Downloaded model (gitignored, ~5GB)
│
├── .env.example               # Env template
├── .gitignore
└── README.md
```

## API Endpoints

### `GET /health` (no auth)

```bash
curl http://localhost:8000/health
```

### `GET /voices`

```bash
API_KEY=$(grep API_KEY .env | cut -d= -f2)
curl -H "X-API-Key: $API_KEY" http://localhost:8000/voices
```

### `POST /tts` - Voice Design

```bash
curl -X POST http://localhost:8000/tts \
    -H "X-API-Key: $API_KEY" \
    -F "text=Xin chào, đây là test" \
    -F "voice_description=A warm Vietnamese male voice" \
    -o output.wav
```

### `POST /clone` - Voice Cloning

```bash
curl -X POST http://localhost:8000/clone \
    -H "X-API-Key: $API_KEY" \
    -F "text=Đây là giọng được clone" \
    -F "reference_audio=@/path/to/sample.wav" \
    -F "reference_text=Transcript chính xác" \
    -F "style_instruction=warm, slow" \
    -o cloned.wav
```

### `POST /clone-with-preset`

```bash
curl -X POST http://localhost:8000/clone-with-preset \
    -H "X-API-Key: $API_KEY" \
    -F "text=Sử dụng giọng có sẵn" \
    -F "voice_id=voice_001" \
    -F "preset=storytelling" \
    -o output.wav
```

→ Full API reference: [docs/api-reference.md](docs/api-reference.md)

## Performance

Tested on **NVIDIA RTX 5060 Ti 16GB**:

| Operation | Time | RTF |
|---|---|---|
| Model load (cold) | 30-45s | - |
| Generate 5s audio | ~3s | 0.6 |
| Generate 30s audio | ~12s | 0.4 |
| Generate 60s audio | ~20s | 0.33 |

VRAM usage: ~7-8GB (model) + 1-2GB (inference buffer).

## Voice Library Setup

```
voice_library/voice_001_male_warm/
├── reference.wav              # Master reference audio (60s)
├── reference.txt              # Transcript
├── presets.json               # Preset configs
└── presets/
    ├── storytelling.wav
    └── storytelling.txt
```

→ See `configs/presets.example.json` for full config.

## Deployment Strategies

### Manual (Development)

```bash
git clone ...
cd voxcpm-server-py
bash setup.sh
bash start.sh --daemon
```

### Automated (Production via NestJS Backend)

Backend NestJS:
1. Rents GPU via ckey.vn API
2. SSH into server
3. `git clone` + `bash setup.sh`
4. Inject API_KEY env + `bash start.sh --daemon`
5. Health check + register

→ See [docs/deployment.md](docs/deployment.md)

### Cached (Faster, ~3-5 min)

Pre-build venv archive on R2/MinIO:
- First setup: 10 minutes
- Subsequent: ~3-5 minutes (download cache)

## Documentation

- [Deployment Guide](docs/deployment.md) - Manual + automated deploy
- [Environment Management](docs/env-management.md) - Env vars workflow
- [API Reference](docs/api-reference.md) - Endpoints + parameters
- [Troubleshooting](docs/troubleshooting.md) - Common errors

## Security

- ✅ API_KEY required for all endpoints (except /health)
- ✅ Strong random keys (32 bytes / 64 hex chars)
- ✅ `.env` file mode 600 (owner only)
- ✅ `.env` not committed to Git
- ✅ Default placeholder rejected
- ✅ Short keys warned (recommend ≥32 chars)

## License

Apache 2.0 (matches VoxCPM2 license)

## Related Projects

- [VoxCPM2 Model](https://github.com/OpenBMB/VoxCPM)
- [VoxCPM2 HuggingFace](https://huggingface.co/openbmb/VoxCPM2)
- Backend Orchestrator (NestJS): coming soon
- Frontend Admin (React): coming soon
