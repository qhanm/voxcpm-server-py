# API Reference

Complete reference for VoxCPM2 Server API.

Base URL: `http://<server-ip>:8000`  
Authentication: `X-API-Key` header (required for all endpoints except `/health`)

---

## GET `/health`

Health check endpoint. **No auth required.**

### Response

```json
{
  "status": "ok",
  "model_loaded": true,
  "model": "VoxCPM2",
  "load_duration": 35.2,
  "uptime": 1234.56
}
```

| Field | Type | Description |
|---|---|---|
| `status` | string | Always "ok" if reachable |
| `model_loaded` | boolean | True when model ready for inference |
| `model` | string | Model name |
| `load_duration` | number | Seconds taken to load model |
| `uptime` | number | Server uptime in seconds |

### Example

```bash
curl http://localhost:8000/health
```

---

## GET `/voices`

List all voices in voice library.

### Headers

| Name | Required | Description |
|---|---|---|
| `X-API-Key` | ✅ | API authentication key |

### Response

```json
{
  "voices": [
    {
      "voice_id": "voice_001_male_warm",
      "presets": ["default", "storytelling", "news"]
    },
    {
      "voice_id": "voice_002_female_young",
      "presets": ["default"]
    }
  ]
}
```

### Example

```bash
curl -H "X-API-Key: YOUR_KEY" http://localhost:8000/voices
```

---

## POST `/tts`

Voice Design - generate audio from text + voice description (no audio sample).

### Headers

| Name | Required | Value |
|---|---|---|
| `X-API-Key` | ✅ | API key |
| `Content-Type` | ✅ | `multipart/form-data` |

### Form Parameters

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `text` | string | ✅ | - | Text to synthesize (max 5000 chars) |
| `voice_description` | string | ❌ | "" | Voice description in English |
| `cfg_value` | float | ❌ | 2.0 | Guidance scale (1.0-3.0) |
| `inference_timesteps` | int | ❌ | 10 | Quality vs speed (5-30) |

### Voice Description Examples

```
"A young Vietnamese male voice, warm and friendly"
"An elderly woman, soft and gentle"
"A confident professional female news anchor"
"A childlike voice, cheerful and bright"
```

### Response

- **Content-Type**: `audio/wav`
- **Body**: Binary WAV audio (48kHz, 16-bit PCM)

### Response Headers

| Name | Description |
|---|---|
| `X-Generation-Time` | Seconds taken to generate |
| `X-Audio-Duration` | Output audio duration (seconds) |
| `X-RTF` | Real-Time Factor (gen_time / audio_duration) |

### Example

```bash
curl -X POST http://localhost:8000/tts \
    -H "X-API-Key: YOUR_KEY" \
    -F "text=Xin chào thế giới" \
    -F "voice_description=A warm Vietnamese voice" \
    -F "cfg_value=2.0" \
    -F "inference_timesteps=15" \
    -o output.wav
```

### Errors

| Status | Detail |
|---|---|
| 400 | "Text cannot be empty" |
| 400 | "Text too long (max 5000 chars)" |
| 401 | "Missing X-API-Key header" or "Invalid API key" |
| 500 | "Generation failed: <error>" |
| 503 | "Model not loaded yet" |

---

## POST `/clone`

Voice Cloning - clone voice from uploaded audio sample.

### Form Parameters

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `text` | string | ✅ | - | Text to synthesize |
| `reference_audio` | file | ✅ | - | Audio sample (WAV, max 50MB) |
| `reference_text` | string | ❌ | "" | Transcript of reference audio |
| `style_instruction` | string | ❌ | "" | Style description |
| `cfg_value` | float | ❌ | 2.5 | Guidance scale |
| `inference_timesteps` | int | ❌ | 20 | Quality vs speed |
| `temperature` | float | ❌ | 0.75 | Variation (0.5-1.0) |

### Cloning Modes (based on parameters)

#### A. Controllable Cloning (default)
- Có `reference_audio`
- Không có `reference_text`
- Quality: ⭐⭐⭐⭐ (8/10)

#### B. Ultimate Cloning (best quality)
- Có cả `reference_audio` + `reference_text`
- Quality: ⭐⭐⭐⭐⭐ (9/10)
- Recommend: `cfg_value=2.8`, `inference_timesteps=25`

### Style Instruction Examples

| Style | Instruction |
|---|---|
| Storytelling | `"warm, intimate, emotional, slow pace, breath pauses"` |
| News | `"formal, clear articulation, neutral tone, steady pace"` |
| Advertising | `"energetic, enthusiastic, upbeat, faster pace"` |
| Audiobook | `"narrative, expressive, varied pace, immersive"` |
| Tutorial | `"friendly, clear, patient, moderate pace"` |
| Podcast | `"casual, conversational, natural pauses, relaxed"` |

### Reference Audio Requirements

- Format: WAV (mono preferred)
- Sample rate: ≥16kHz (24-48kHz recommended)
- Duration: 5-60 seconds (sweet spot: 30s)
- Quality: clean, no noise, single speaker
- Content: clear speech with natural intonation

### Example: Controllable Cloning

```bash
curl -X POST http://localhost:8000/clone \
    -H "X-API-Key: YOUR_KEY" \
    -F "text=Câu mới cần generate" \
    -F "reference_audio=@my_voice.wav" \
    -F "style_instruction=warm, slow" \
    -F "cfg_value=2.5" \
    -F "inference_timesteps=20" \
    -o cloned.wav
```

### Example: Ultimate Cloning

```bash
curl -X POST http://localhost:8000/clone \
    -H "X-API-Key: YOUR_KEY" \
    -F "text=Câu mới cần generate" \
    -F "reference_audio=@my_voice.wav" \
    -F "reference_text=Transcript chính xác từng từ của my_voice.wav" \
    -F "style_instruction=warm, storytelling" \
    -F "cfg_value=2.8" \
    -F "inference_timesteps=25" \
    -o cloned_ultimate.wav
```

### Errors

| Status | Detail |
|---|---|
| 400 | "Text cannot be empty" |
| 400 | "Reference audio is empty" |
| 400 | "Reference audio too large (max 50MB)" |
| 401 | Auth errors |
| 500 | Generation errors |

---

## POST `/clone-with-preset`

Generate audio using voice + preset from voice library.

### Form Parameters

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `text` | string | ✅ | - | Text to synthesize |
| `voice_id` | string | ✅ | - | Voice ID from library |
| `preset` | string | ❌ | "default" | Preset name |

### Workflow

1. Server loads `voice_library/<voice_id>/presets.json`
2. Looks up specified preset config
3. Uses preset's `reference_audio`, `reference_text`, `style_instruction`, `params`
4. Generates audio

### Voice Library Structure

```
voice_library/voice_001_male_warm/
├── reference.wav              # Master 60s reference
├── reference.txt              # Master transcript
├── presets.json               # Preset configurations
└── presets/
    ├── storytelling.wav       # 30s storytelling sample
    ├── storytelling.txt
    ├── news.wav
    └── news.txt
```

### presets.json Format

```json
{
  "default": {
    "name": "Default voice",
    "reference_audio": "reference.wav",
    "reference_text_file": "reference.txt",
    "style_instruction": "natural, clear",
    "params": {
      "cfg_value": 2.5,
      "inference_timesteps": 20,
      "temperature": 0.75
    }
  },
  "storytelling": {
    "name": "Storytelling mode",
    "reference_audio": "presets/storytelling.wav",
    "reference_text_file": "presets/storytelling.txt",
    "style_instruction": "warm, intimate, emotional, slow pace",
    "params": {
      "cfg_value": 2.5,
      "inference_timesteps": 25,
      "temperature": 0.75
    }
  }
}
```

### Example

```bash
curl -X POST http://localhost:8000/clone-with-preset \
    -H "X-API-Key: YOUR_KEY" \
    -F "text=Đây là test với voice library" \
    -F "voice_id=voice_001_male_warm" \
    -F "preset=storytelling" \
    -o output.wav
```

### Errors

| Status | Detail |
|---|---|
| 404 | "Voice 'xxx' not found in library" |
| 404 | "No presets.json found for voice 'xxx'" |
| 404 | "Preset 'yyy' not found. Available: ['default', 'news']" |
| 500 | "Reference audio file not found" |

---

## Inference Parameters Guide

### `cfg_value` (Classifier-Free Guidance Scale)

Controls how closely output adheres to reference/description.

| Value | Effect |
|---|---|
| 1.0-1.5 | Free, creative, may diverge from reference |
| 2.0 | Balanced (default for /tts) |
| 2.5 | Closely follows reference (default for /clone) |
| 2.8-3.0 | Very tight to reference, less variation |

### `inference_timesteps` (Quality vs Speed)

Number of diffusion steps.

| Value | Quality | Speed | Use case |
|---|---|---|---|
| 5-10 | Medium | Fast | Quick preview |
| 15-20 | Good | Balanced | Default |
| 25-30 | Excellent | Slow (3x) | Final production |

### `temperature` (Randomness)

Controls output diversity.

| Value | Effect |
|---|---|
| 0.5-0.7 | Stable, consistent runs |
| 0.75 | Default (balanced) |
| 0.8-1.0 | More varied, creative, may have artifacts |

---

## Performance

Tested on RTX 5060 Ti 16GB:

| Operation | Time | RTF |
|---|---|---|
| 5s audio | ~3s | 0.6 |
| 30s audio | ~12s | 0.4 |
| 60s audio | ~20s | 0.33 |
| Cold start (first request) | +5-10s | - |

RTF (Real-Time Factor) < 1.0 means faster than realtime.

---

## Best Practices

### 1. Voice Cloning Quality

**For best results:**
- Use 30-60 seconds of clean reference audio
- Provide accurate transcript (Ultimate Cloning mode)
- Match language between reference and target text
- Use studio-quality recording

### 2. Long-form Generation

For text >500 chars:
- Split into chunks at sentence boundaries
- Generate each chunk separately
- Concat with crossfade (50ms)
- Use same `cfg_value` and reference for consistency

### 3. Production Performance

- Pre-warm server with dummy request after start
- Use `inference_timesteps=20` for production (good quality, reasonable speed)
- Cache generated audio when possible
- Monitor VRAM usage with `nvidia-smi`

### 4. Multi-language

VoxCPM2 supports 30 languages including:
- Vietnamese ⭐ (excellent quality)
- English, Chinese, Japanese, Korean
- French, German, Spanish, Italian
- Hindi, Arabic, Thai, Indonesian
- And more...

Reference audio language should match target text for best quality.

---

## Client Libraries

### Python

```python
import requests

def tts(server, api_key, text, **kwargs):
    r = requests.post(
        f"{server}/tts",
        headers={"X-API-Key": api_key},
        data={"text": text, **kwargs},
        timeout=300,
    )
    r.raise_for_status()
    return r.content

# Usage
audio = tts("http://gpu:8000", "your-key", "Hello world")
with open("out.wav", "wb") as f:
    f.write(audio)
```

### TypeScript / Node.js

```typescript
import axios from 'axios';
import FormData from 'form-data';

async function tts(server: string, apiKey: string, text: string) {
  const form = new FormData();
  form.append('text', text);
  
  const res = await axios.post(`${server}/tts`, form, {
    headers: {
      ...form.getHeaders(),
      'X-API-Key': apiKey,
    },
    responseType: 'arraybuffer',
    timeout: 300_000,
  });
  
  return Buffer.from(res.data);
}
```

---

## Rate Limits

Server không có rate limit built-in. Implement ở backend orchestrator (NestJS) nếu cần.

Recommend: max 10 concurrent requests per server (1 GPU = sequential 1 request).
