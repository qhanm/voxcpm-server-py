# Troubleshooting Guide

Common errors khi deploy/run VoxCPM2 server và cách fix.

## Setup Errors

### Error: PyTorch not found

```
PyTorch not found. Make sure you're using Template 4
```

**Cause**: Đang dùng template không có PyTorch.

**Fix**: Trên ckey.vn, rent server với **Template 4** (`chieustudio/pytorch-2.5.1-cuda12.4-cudnn9-runtime`).

---

### Error: CUDA not available

```
CUDA not available! Cannot run VoxCPM2 without GPU
```

**Cause**: GPU không được mount vào container, hoặc driver issue.

**Fix**:
```bash
# Verify GPU
nvidia-smi

# Nếu lỗi "command not found" → liên hệ ckey support
# Nếu lỗi "Failed to initialize NVML" → restart container hoặc rent server mới
```

---

### Error: PyTorch version mismatch

```
PyTorch version is 2.4.x, expected 2.5.x
```

**Cause**: Template cũ với PyTorch version không khớp.

**Fix**: 
- Option 1 (recommend): Rent server với template đúng (Template 4)
- Option 2: Force install correct version (rủi ro):
  ```bash
  pip install --upgrade torch==2.5.1+cu124 --index-url https://download.pytorch.org/whl/cu124
  ```

---

### Error: pip install failed

```
ERROR: pip's dependency resolver does not currently take into account...
```

**Cause**: Version conflict giữa packages.

**Fix**:
```bash
# Try clean install
pip install --no-cache-dir --force-reinstall -r requirements.txt

# Or với verbose để xem chi tiết
pip install -v -r requirements.txt
```

---

### Error: Model download failed

```
huggingface_hub.errors.RepositoryNotFoundError
huggingface_hub.errors.HfHubHTTPError
```

**Cause**: Network issue hoặc HuggingFace down.

**Fix**:
```bash
# Test connection
curl -I https://huggingface.co

# Try set HF mirror (faster cho VN)
export HF_ENDPOINT=https://hf-mirror.com
bash setup.sh

# Or download manually
python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('openbmb/VoxCPM2', local_dir='./models/VoxCPM2', resume_download=True)
"
```

---

### Error: libsndfile not found

```
OSError: cannot load library 'libsndfile.so.1'
```

**Cause**: Missing system library.

**Fix**:
```bash
apt-get update
apt-get install -y libsndfile1
```

---

### Error: Out of disk space

```
No space left on device
```

**Cause**: Disk đầy (model 5GB + deps 3GB = ~8GB needed).

**Fix**:
```bash
# Check disk
df -h

# Clean pip cache
pip cache purge

# Clean apt cache
apt-get clean

# Remove unused models nếu có
rm -rf ~/.cache/huggingface/hub/models--*
```

---

## Runtime Errors

### Error: API_KEY environment variable is required

```
✗ API_KEY environment variable is required
```

**Fix**:
```bash
export API_KEY="$(openssl rand -hex 32)"
echo "API_KEY=$API_KEY" >> ~/.bashrc  # Persist
bash start.sh
```

---

### Error: Port 8000 already in use

```
[Errno 98] Address already in use
```

**Cause**: Server cũ đang chạy.

**Fix**:
```bash
# Stop existing
bash stop.sh

# Or find and kill manually
lsof -i :8000
kill <PID>

# Or use different port
PORT=8001 bash start.sh
```

---

### Error: CUDA out of memory

```
torch.cuda.OutOfMemoryError: CUDA out of memory
```

**Cause**: GPU VRAM không đủ cho text dài.

**Fix**:
```bash
# Reduce inference quality
# Trong request: giảm inference_timesteps từ 25 → 15

# Disable denoiser
export LOAD_DENOISER=false

# Restart server
bash stop.sh && bash start.sh --daemon

# Hoặc dùng GPU lớn hơn (RTX 3090 24GB)
```

---

### Error: Model loading timeout

Server stuck ở "Loading VoxCPM2 model..."

**Cause**: Disk slow hoặc model corrupted.

**Fix**:
```bash
# Check model files
ls -lh models/VoxCPM2/

# Should see ~5GB total
# Re-download if corrupted
rm -rf models/VoxCPM2/
bash setup.sh
```

---

### Error: Generation extremely slow

RTF > 1.0 (audio generation chậm hơn realtime).

**Cause**: GPU không được dùng (running on CPU).

**Fix**:
```bash
# Verify CUDA
python3 -c "
import torch
print('CUDA available:', torch.cuda.is_available())
print('Current device:', torch.cuda.current_device())
print('Device name:', torch.cuda.get_device_name(0))
"

# Should show GPU info, not CPU
```

---

### Error: Voice not found

```
{"detail":"Voice 'xxx' not found in library"}
```

**Cause**: Voice không tồn tại trong `voice_library/`.

**Fix**:
```bash
# Check what voices exist
curl -H "X-API-Key: $API_KEY" http://localhost:8000/voices

# Verify folder structure
ls voice_library/

# Each voice needs:
# voice_library/<voice_id>/presets.json
# voice_library/<voice_id>/reference.wav
```

---

### Error: Reference audio file not found

```
{"detail":"Reference audio file not found: ..."}
```

**Cause**: `presets.json` reference file không tồn tại.

**Fix**:
```bash
# Check preset config
cat voice_library/<voice_id>/presets.json

# Verify referenced files exist
ls voice_library/<voice_id>/
```

---

### Error: Generated audio is silent / corrupted

**Cause**: 
- Reference audio quality kém
- cfg_value quá thấp/cao
- Text language không match reference

**Fix**:
```bash
# Test với simple settings
curl -X POST http://localhost:8000/clone \
    -H "X-API-Key: $API_KEY" \
    -F "text=Test simple sentence" \
    -F "reference_audio=@/path/to/clean_audio.wav" \
    -F "cfg_value=2.5" \
    -F "inference_timesteps=20" \
    -o test.wav

# Check file
file test.wav  # Should show: WAV audio
```

Yêu cầu reference audio:
- Format: WAV, 16kHz+
- Duration: 5-60 giây
- Clean: không nhiễu, 1 người nói
- Quality: ≥48kHz tốt nhất

---

## Network Errors

### Error: Cannot connect from outside

```
curl: (7) Failed to connect to <ip> port 8000
```

**Cause**: Port không được forward, hoặc firewall block.

**Fix**:

Trên ckey.vn:
1. Vào dashboard, xem "Port forwards" của container
2. Map external port → internal 8000
3. Connect qua external IP + external port

Test:
```bash
# From local machine
curl http://<gpu-public-ip>:<external-port>/health
```

---

### Error: SSL/TLS issues

Nếu dùng HTTPS với reverse proxy:

**Fix**: Setup nginx/caddy phía trước, server chạy HTTP local.

---

## Performance Issues

### Slow first request

**Cause**: Cold start, model warm-up.

**Fix**: Send 1 dummy request sau khi server start, các request sau sẽ nhanh hơn.

```bash
# Warm-up after start
curl -X POST http://localhost:8000/tts \
    -H "X-API-Key: $API_KEY" \
    -F "text=Warm up" \
    -o /dev/null
```

---

### Memory leak over time

VRAM tăng dần mỗi request.

**Fix**: Restart server periodically:
```bash
# Cron job mỗi 24h
0 4 * * * cd /app && bash stop.sh && sleep 5 && bash start.sh --daemon
```

---

## Debug Commands

### Check everything

```bash
echo "=== System ==="
uname -a
df -h /
free -h

echo "=== Python ==="
python3 --version
pip --version

echo "=== PyTorch ==="
python3 -c "
import torch
print('Version:', torch.__version__)
print('CUDA:', torch.cuda.is_available())
print('Device:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU')
"

echo "=== GPU ==="
nvidia-smi

echo "=== Server ==="
ps aux | grep uvicorn | grep -v grep
ss -tlnp | grep 8000

echo "=== Logs ==="
tail -20 /var/log/voxcpm-server.log 2>/dev/null || echo "No log file"
```

### Verbose mode

```bash
# Run server with debug logs
LOG_LEVEL=DEBUG bash start.sh

# Trace Python errors
PYTHONFAULTHANDLER=1 python3 -m uvicorn server:app --log-level debug
```

---

## Getting Help

Nếu vẫn không fix được:

1. **Check logs đầy đủ**: `tail -100 /var/log/voxcpm-server.log`
2. **Run health check**: `bash health-check.sh`
3. **Verify environment** với debug commands above
4. **Search VoxCPM GitHub**: https://github.com/OpenBMB/VoxCPM/issues
5. **Liên hệ ckey.vn support** nếu vấn đề về infrastructure

Khi báo lỗi, include:
- Output `nvidia-smi`
- Output `python3 --version` + `pip list`
- Last 50 lines log
- Exact error message
- Steps to reproduce
