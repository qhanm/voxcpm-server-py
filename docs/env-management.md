# Environment Management

Hướng dẫn quản lý environment variables cho VoxCPM2 server trong các môi trường khác nhau.

## Loading Priority

Server đọc env theo thứ tự (sau override trước):

1. **`.env` file** trong project root (loaded by `python-dotenv` trong `server.py`)
2. **OS environment variables** (export trong shell, hoặc từ NestJS deploy script)
3. **Default values** trong code

→ OS environment **luôn override** `.env` file. Cho phép NestJS orchestrator inject API_KEY runtime mà không cần edit file.

## Setup Workflows

### Workflow 1: Manual Development

Khi develop/test thủ công trên máy local hoặc 1 GPU server cố định.

```bash
# Bước 1: Tạo .env tự động (auto-generate API_KEY)
bash init-env.sh

# Bước 2: Setup dependencies + model
bash setup.sh

# Bước 3: Start server
bash start.sh --daemon

# View API key để dùng cho client
grep API_KEY .env
```

### Workflow 2: Auto Deployment (Backend Orchestrator)

Khi NestJS backend tự động deploy lên GPU server.

NestJS không tạo `.env` file, mà **inject env qua SSH command**:

```typescript
// Trong NestJS deploy.service.ts
const apiKey = generateRandomKey();  // Backend tạo

await ssh.execCommand(`
  cd /app
  bash setup.sh
`);

// Inject API_KEY khi start
await ssh.execCommand(`
  cd /app
  export API_KEY="${apiKey}"
  bash start.sh --daemon
`);

// Save apiKey vào DB session để dùng khi gọi VoxCPM
await this.gpuRepo.update(sessionId, { voxcpmApiKey: apiKey });
```

→ **Backend giữ API_KEY**, không cần `.env` trên GPU server.

### Workflow 3: Hybrid (cả 2)

Vừa có `.env` mặc định, vừa cho NestJS override:

```bash
# Setup tạo .env với API_KEY default (random)
bash setup.sh

# NestJS có thể override khi start
export API_KEY="key-from-backend"
bash start.sh --daemon

# Server sẽ dùng key từ NestJS, không phải từ .env
```

→ Linh hoạt, dùng được cả manual và auto.

## Environment Variables Reference

### Required

| Variable | Description | Example |
|---|---|---|
| `API_KEY` | API authentication key (required) | `openssl rand -hex 32` output |

### Server settings

| Variable | Default | Description |
|---|---|---|
| `HOST` | `0.0.0.0` | Bind address |
| `PORT` | `8000` | Server port |
| `LOG_LEVEL` | `INFO` | DEBUG / INFO / WARNING / ERROR |

### Paths

| Variable | Default | Description |
|---|---|---|
| `MODEL_PATH` | `./models/VoxCPM2` | Path to model weights |
| `VOICE_LIBRARY_DIR` | `./voice_library` | Voice library folder |
| `OUTPUTS_DIR` | `./outputs` | Generated audio outputs |
| `CACHE_DIR` | `./cache` | Cache for uploaded refs |

### Optional features

| Variable | Default | Description |
|---|---|---|
| `LOAD_DENOISER` | `false` | Load denoiser (extra ~1GB VRAM) |

### Daemon mode

| Variable | Default | Description |
|---|---|---|
| `LOG_FILE` | `/var/log/voxcpm-server.log` | Daemon log file |
| `PID_FILE` | `/tmp/voxcpm-server.pid` | Daemon PID file |

## API_KEY Best Practices

### Generation

```bash
# Strong key (32 bytes = 64 hex chars)
openssl rand -hex 32

# Or with /dev/urandom
head -c 32 /dev/urandom | xxd -p -c 64

# Avoid weak keys:
# ❌ "password123"
# ❌ "test"
# ❌ "change-me"
```

### Storage

✅ **DO:**
- Store in `.env` file (mode 600)
- Store in backend DB (encrypted column)
- Use environment variables in production

❌ **DON'T:**
- Commit to Git (`.env` is in `.gitignore`)
- Hardcode in source files
- Log to files
- Share via insecure channels (chat, email)

### Rotation

Khi cần thay đổi API_KEY (security, compromised, regular rotation):

```bash
# Bước 1: Generate key mới
NEW_KEY=$(openssl rand -hex 32)

# Bước 2: Update .env
sed -i "s/^API_KEY=.*/API_KEY=$NEW_KEY/" .env

# Bước 3: Restart server
bash stop.sh && bash start.sh --daemon

# Bước 4: Update backend NestJS với key mới
# Update VOXCPM_API_KEY trong backend .env hoặc DB
```

→ Recommend rotation mỗi 3-6 tháng.

## Troubleshooting

### Error: "API_KEY environment variable is required"

```bash
# Check .env file exists
ls -la .env

# Check API_KEY is set
grep API_KEY .env

# If missing, generate
bash init-env.sh
```

### Error: "API_KEY is using default placeholder"

```bash
# Check current value
grep API_KEY .env

# If see "change-me-..." → regenerate
bash init-env.sh --force
```

### Error: ".env not loaded"

```bash
# Verify python-dotenv installed
pip show python-dotenv

# Install if missing
pip install python-dotenv

# Check file exists
ls -la .env
```

### NestJS không gọi được VoxCPM server

Verify API_KEY khớp giữa 2 nơi:

```bash
# Trên GPU server
grep API_KEY /app/.env
# hoặc nếu inject runtime: kiểm tra deployment logs

# Trên backend NestJS
echo $VOXCPM_API_KEY
# Phải giống nhau!
```

## Security Notes

### File permissions

```bash
# .env nên có mode 600 (owner read/write only)
chmod 600 .env
ls -la .env
# -rw------- 1 user user 500 May  6 12:34 .env
```

### Git ignore

`.gitignore` đã có:
```
.env
.env.local
.env.*.local
```

→ Verify trước khi commit:
```bash
git status
# .env should NOT appear

git check-ignore .env
# Output: .env (means it's ignored)
```

### Logging

Server tự động mask API_KEY trong logs:
```
API key: a3f9b2c8...***f9a2 (64 chars)
```

→ Không log full key.

## Multi-Environment Setup

Cho nhiều môi trường (dev/staging/prod):

```bash
# Different env files
.env.development
.env.staging
.env.production

# Symlink active one
ln -sf .env.production .env

# Or specify explicitly
DOTENV_PATH=.env.staging bash start.sh
```

(Cần modify server.py để support DOTENV_PATH).

## Integration với Backend Orchestrator

Khi NestJS deploy VoxCPM server lên GPU mới:

```typescript
// modules/gpu/deploy.service.ts
async deployVoxcpm(session: GpuSession) {
  // 1. Generate API key
  const apiKey = crypto.randomBytes(32).toString('hex');
  
  // 2. SSH deploy
  await ssh.execCommand('git clone https://github.com/qhanm/voxcpm-server-py.git /app');
  await ssh.execCommand('cd /app && bash setup.sh --skip-deps');  // setup tạo .env mặc định
  
  // 3. Override API_KEY với key từ backend
  await ssh.execCommand(`
    cd /app
    sed -i "s/^API_KEY=.*/API_KEY=${apiKey}/" .env
  `);
  
  // 4. Start server
  await ssh.execCommand('cd /app && bash start.sh --daemon');
  
  // 5. Save apiKey vào DB
  await this.gpuRepo.update(session.id, { voxcpmApiKey: apiKey });
  
  // 6. Khi gọi VoxCPM API sau này, dùng key này
}
```

→ Mỗi GPU server có API_KEY riêng, backend track per session.
