# Deployment Guide

Hướng dẫn deploy VoxCPM2 Server lên GPU server (ckey.vn Template 4 - PyTorch 2.5.1 CUDA 12.4).

## Yêu cầu

- GPU server với:
  - NVIDIA GPU (RTX 30 series trở lên, ≥10GB VRAM)
  - CUDA 12.4+
  - PyTorch 2.5.1+ pre-installed
  - Python 3.10+
  - SSH access
  - Internet connection
- Disk space: tối thiểu 15GB free
- Network: tối thiểu 50 Mbps download

## Method 1: Manual Deployment (Development)

### Bước 1: Rent GPU server

Trên ckey.vn:
1. Chọn GPU phù hợp (RTX 30+, ≥10GB VRAM)
2. Chọn template: **Template 4 - PyTorch 2.5.1 CUDA 12.4**
3. Đặt SSH password
4. Confirm rent

Hoặc qua API:
```bash
curl "https://ckey.vn/api/thuegpu3?key=YOUR_KEY&id=GPU_ID&templates=4&password=YOUR_PASS"
```

### Bước 2: SSH vào server

```bash
ssh root@<gpu-ip> -p <ssh-port>
```

### Bước 3: Verify environment

```bash
# Check PyTorch
python3 -c "import torch; print(torch.__version__, torch.cuda.is_available())"
# Expected: 2.5.1+cu124 True

# Check GPU
nvidia-smi

# Check disk
df -h /
```

### Bước 4: Clone + setup

```bash
# Clone (replace with your repo URL)
git clone https://github.com/qhanm/voxcpm-server-py.git /app
cd /app

# Make scripts executable
chmod +x *.sh

# Run setup (~10 minutes - mostly model download)
bash setup.sh
```

Setup script sẽ:
1. Verify PyTorch + CUDA (~5s)
2. Install system deps - libsndfile, ffmpeg (~30s)
3. Install Python deps (~1-2 minutes)
4. Verify imports (~5s)
5. Download VoxCPM2 model 5GB (~5-10 minutes)

### Bước 5: Start server

```bash
# Generate API key
export API_KEY="$(openssl rand -hex 32)"
echo "Save this: $API_KEY"

# Start daemon
bash start.sh --daemon

# Verify
bash health-check.sh
```

### Bước 6: Test

```bash
# From server itself
curl http://localhost:8000/health

# From local machine (use server's public IP + port)
curl http://<gpu-public-ip>:8000/health
```

### Bước 7: Open port (nếu cần)

ckey.vn thường có port forwarding. Check:
```bash
# Trên ckey UI: xem "Port forwards" của container
# Hoặc API: GET /api/infogpu3?key=...&id=...
```

Map: `external_port` → `8000` (container port)

## Method 2: Automated Deployment (Production)

### Architecture

```
[Backend NestJS]
    ↓ Bull Queue: gpu-deploy
[Worker]
    ↓ 1. Call ckey API
[ckey.vn]
    ↓ Provision GPU
[GPU Server]
    ↓ 2. SSH + git clone
[Code]
    ↓ 3. SSH + bash setup.sh
[Setup complete]
    ↓ 4. SSH + bash start.sh --daemon
[Server running]
    ↓ 5. Health check
[Ready, register IP+port]
```

### Implementation trong NestJS

Xem file `backend-app/src/modules/gpu/deploy.service.ts`:

```typescript
async deployVoxcpm(session: GpuSession) {
  const ssh = new NodeSSH();
  
  await ssh.connect({
    host: session.ipAddress,
    port: session.sshPort,
    username: 'root',
    password: session.sshPassword,
  });
  
  // Step 1: Clone repo
  await this.execAndLog(ssh, session, 'CLONING',
    'git clone https://github.com/qhanm/voxcpm-server-py.git /app'
  );
  
  // Step 2: Setup (longest step)
  await this.execAndLog(ssh, session, 'SETUP',
    'cd /app && chmod +x *.sh && bash setup.sh'
  );
  
  // Step 3: Generate API key
  const apiKey = this.generateApiKey();
  await this.gpuSessionsRepository.update(session.id, { 
    voxcpmApiKey: apiKey 
  });
  
  // Step 4: Start server
  await this.execAndLog(ssh, session, 'STARTING',
    `cd /app && export API_KEY="${apiKey}" && bash start.sh --daemon`
  );
  
  // Step 5: Health check
  await this.execAndLog(ssh, session, 'HEALTH_CHECK',
    'cd /app && bash health-check.sh 180'
  );
  
  ssh.dispose();
}
```

### Time estimates

| Phase | Time | Total |
|---|---|---|
| Rent GPU + boot | 1-2 min | 1-2 min |
| Git clone | 30s | 1.5-2.5 min |
| pip install | 1-2 min | 2.5-4.5 min |
| Model download | 5-10 min | 7.5-14.5 min |
| Start + load model | 30-60s | 8-15.5 min |

→ **Cold start: ~10-15 minutes**.

## Method 3: Cached Deployment (Faster)

Pre-build venv + model archive trên R2/MinIO. Subsequent deploys chỉ cần download cache.

### Build cache (one-time)

Trên 1 server đã setup xong:

```bash
# Tar venv (nếu dùng venv)
cd /opt
tar czf voxcpm-venv-v1.0.tar.gz voxcpm-venv/

# Upload to R2
aws s3 cp voxcpm-venv-v1.0.tar.gz s3://voxcpm-cache/

# Tar model
tar czf voxcpm-model.tar.gz models/VoxCPM2/
aws s3 cp voxcpm-model.tar.gz s3://voxcpm-cache/

# Upload pip wheels
pip wheel -r requirements.txt -w ./wheels/
aws s3 sync ./wheels/ s3://voxcpm-cache/wheels/
```

### Deploy from cache

```bash
# Download model (faster than HuggingFace, especially for VN)
aws s3 cp s3://voxcpm-cache/voxcpm-model.tar.gz /tmp/
tar xzf /tmp/voxcpm-model.tar.gz -C /app/

# Install pip from wheels (offline)
aws s3 sync s3://voxcpm-cache/wheels/ /tmp/wheels/
pip install --no-index --find-links /tmp/wheels/ -r /app/requirements.txt

# Skip setup.sh, go straight to start.sh
cd /app && bash start.sh --daemon
```

→ **Cached deploy: ~3-5 minutes** (vs 10-15 min fresh).

## Common Issues

Xem [troubleshooting.md](troubleshooting.md) cho danh sách lỗi thường gặp.

## Monitoring

### Logs

```bash
# Daemon mode logs
tail -f /var/log/voxcpm-server.log

# Specific stages
grep "ERROR\|WARN" /var/log/voxcpm-server.log | tail -20

# Generation stats
grep "Generated" /var/log/voxcpm-server.log | tail -10
```

### Health monitoring

```bash
# Continuous health check
watch -n 5 'curl -s http://localhost:8000/health | python3 -m json.tool'

# GPU usage
watch -n 1 nvidia-smi

# Disk usage  
df -h
```

### Process info

```bash
# Server PID
cat /tmp/voxcpm-server.pid

# Process status
ps aux | grep uvicorn

# Network listening
ss -tlnp | grep 8000
```

## Updating

Khi có version mới của VoxCPM2 hoặc code:

```bash
# 1. Stop server
bash stop.sh

# 2. Pull updates
cd /app && git pull

# 3. Update deps (if requirements.txt changed)
pip install -r requirements.txt

# 4. (Optional) Re-download model if changed
rm -rf models/VoxCPM2 && bash setup.sh

# 5. Start
bash start.sh --daemon
bash health-check.sh
```

## Cleanup

Khi không dùng nữa:

```bash
# Stop server
bash stop.sh

# Backup voice library (optional)
tar czf voice_library_backup.tar.gz voice_library/

# Cleanup
rm -rf models/ outputs/ cache/

# On ckey: delete GPU session
curl "https://ckey.vn/api/option_gpu3?key=YOUR_KEY&id=GPU_ID&option=delete"
```
