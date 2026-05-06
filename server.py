"""
VoxCPM2 TTS Server
FastAPI server for voice cloning and TTS using VoxCPM2 model.
"""
import os
import io
import json
import time
import asyncio
from pathlib import Path
from contextlib import asynccontextmanager
from typing import Optional

import functools
import uuid
import torch
import soundfile as sf
import numpy as np
from fastapi import FastAPI, File, UploadFile, Form, HTTPException, Header, Depends
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from loguru import logger

from voxcpm import VoxCPM


# ============================================================
# Configuration
# ============================================================
API_KEY = os.environ.get("API_KEY", "change-me-in-production")
MODEL_PATH = os.environ.get("MODEL_PATH", "./models/VoxCPM2")
VOICE_LIBRARY_DIR = Path(os.environ.get("VOICE_LIBRARY_DIR", "./voice_library"))
OUTPUTS_DIR = Path(os.environ.get("OUTPUTS_DIR", "./outputs"))
CACHE_DIR = Path(os.environ.get("CACHE_DIR", "./cache"))
LOAD_DENOISER = os.environ.get("LOAD_DENOISER", "false").lower() == "true"

# Create directories
VOICE_LIBRARY_DIR.mkdir(parents=True, exist_ok=True)
OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
CACHE_DIR.mkdir(parents=True, exist_ok=True)


# ============================================================
# Logger setup
# ============================================================
logger.remove()
logger.add(
    lambda msg: print(msg, end=""),
    format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level: <8}</level> | {message}",
    level=os.environ.get("LOG_LEVEL", "INFO"),
    colorize=True,
)


# ============================================================
# Model state
# ============================================================
model_state = {
    "model": None,
    "loaded_at": None,
    "load_duration": None,
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load VoxCPM2 model on startup."""
    logger.info(f"Loading VoxCPM2 model from {MODEL_PATH}...")
    start = time.time()
    
    try:
        # Try local path first, fallback to HuggingFace download
        if Path(MODEL_PATH).exists():
            logger.info(f"Loading from local path: {MODEL_PATH}")
            model = VoxCPM.from_pretrained(MODEL_PATH, load_denoiser=LOAD_DENOISER)
        else:
            logger.info(f"Local path not found, downloading from HuggingFace: openbmb/VoxCPM2")
            model = VoxCPM.from_pretrained("openbmb/VoxCPM2", load_denoiser=LOAD_DENOISER)
        
        duration = time.time() - start
        model_state["model"] = model
        model_state["loaded_at"] = time.time()
        model_state["load_duration"] = duration
        
        logger.success(f"✓ Model loaded in {duration:.1f}s")
        logger.info(f"  Sample rate: {model.tts_model.sample_rate} Hz")
        logger.info(f"  Device: {next(model.tts_model.parameters()).device}")
        
        if torch.cuda.is_available():
            mem = torch.cuda.memory_allocated() / 1e9
            logger.info(f"  VRAM used: {mem:.2f} GB")
        
    except Exception as e:
        logger.error(f"✗ Failed to load model: {e}")
        raise
    
    yield
    
    # Cleanup on shutdown
    logger.info("Shutting down...")
    model_state["model"] = None
    if torch.cuda.is_available():
        torch.cuda.empty_cache()


# ============================================================
# FastAPI app
# ============================================================
app = FastAPI(
    title="VoxCPM2 TTS Server",
    description="Voice cloning and TTS API using VoxCPM2",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================
# Auth dependency
# ============================================================
def verify_api_key(x_api_key: Optional[str] = Header(None)):
    """Verify API key from X-API-Key header."""
    if not x_api_key:
        raise HTTPException(status_code=401, detail="Missing X-API-Key header")
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return x_api_key


def get_model():
    """Get loaded model instance."""
    if model_state["model"] is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")
    return model_state["model"]


# ============================================================
# Helper functions
# ============================================================
def audio_to_wav_bytes(wav: np.ndarray, sample_rate: int) -> bytes:
    """Convert numpy audio array to WAV bytes."""
    buffer = io.BytesIO()
    sf.write(buffer, wav, sample_rate, format="WAV", subtype="PCM_16")
    buffer.seek(0)
    return buffer.read()


def load_voice_preset(voice_id: str, preset: str = "default") -> dict:
    """Load voice preset config from voice_library."""
    voice_dir = VOICE_LIBRARY_DIR / voice_id
    
    if not voice_dir.exists():
        raise HTTPException(
            status_code=404,
            detail=f"Voice '{voice_id}' not found in library"
        )
    
    presets_file = voice_dir / "presets.json"
    if not presets_file.exists():
        raise HTTPException(
            status_code=404,
            detail=f"No presets.json found for voice '{voice_id}'"
        )
    
    with open(presets_file, "r", encoding="utf-8") as f:
        presets = json.load(f)
    
    if preset not in presets:
        available = list(presets.keys())
        raise HTTPException(
            status_code=404,
            detail=f"Preset '{preset}' not found. Available: {available}"
        )
    
    config = presets[preset]
    
    # Resolve file paths
    ref_audio_path = voice_dir / config["reference_audio"]
    if not ref_audio_path.exists():
        raise HTTPException(
            status_code=500,
            detail=f"Reference audio file not found: {ref_audio_path}"
        )
    
    ref_text = ""
    if "reference_text_file" in config:
        ref_text_path = voice_dir / config["reference_text_file"]
        if ref_text_path.exists():
            with open(ref_text_path, "r", encoding="utf-8") as f:
                ref_text = f.read().strip()
    elif "reference_text" in config:
        ref_text = config["reference_text"]
    
    return {
        "reference_audio_path": str(ref_audio_path),
        "reference_text": ref_text,
        "style_instruction": config.get("style_instruction", ""),
        "params": config.get("params", {}),
    }


# ============================================================
# Endpoints
# ============================================================

@app.get("/health")
async def health():
    """Health check - no auth required."""
    return {
        "status": "ok",
        "model_loaded": model_state["model"] is not None,
        "model": "VoxCPM2",
        "load_duration": model_state.get("load_duration"),
        "uptime": time.time() - model_state["loaded_at"] if model_state["loaded_at"] else 0,
    }


@app.get("/voices")
async def list_voices(api_key: str = Depends(verify_api_key)):
    """List all voices in voice_library."""
    voices = []
    
    if not VOICE_LIBRARY_DIR.exists():
        return {"voices": voices}
    
    for voice_dir in VOICE_LIBRARY_DIR.iterdir():
        if not voice_dir.is_dir():
            continue
        
        presets_file = voice_dir / "presets.json"
        if not presets_file.exists():
            continue
        
        try:
            with open(presets_file, "r", encoding="utf-8") as f:
                presets_data = json.load(f)
            
            voices.append({
                "voice_id": voice_dir.name,
                "presets": list(presets_data.keys()),
            })
        except Exception as e:
            logger.warning(f"Failed to load voice {voice_dir.name}: {e}")
            continue
    
    return {"voices": voices}


@app.post("/tts")
async def tts(
    text: str = Form(...),
    voice_description: str = Form(""),
    cfg_value: float = Form(2.0),
    inference_timesteps: int = Form(10),
    api_key: str = Depends(verify_api_key),
):
    """Voice Design - generate audio from text + voice description (no audio sample)."""
    if not text.strip():
        raise HTTPException(status_code=400, detail="Text cannot be empty")
    
    if len(text) > 5000:
        raise HTTPException(status_code=400, detail="Text too long (max 5000 chars)")
    
    model = get_model()
    
    logger.info(f"TTS request: text_len={len(text)}, cfg={cfg_value}, timesteps={inference_timesteps}")
    start = time.time()
    
    try:
        loop = asyncio.get_event_loop()
        wav = await loop.run_in_executor(
            None,
            functools.partial(
                model.generate,
                text=text,
                cfg_value=cfg_value,
                inference_timesteps=inference_timesteps,
            ),
        )

        duration = time.time() - start
        audio_duration = len(wav) / model.tts_model.sample_rate
        rtf = duration / audio_duration if audio_duration > 0 else 0

        logger.success(f"✓ Generated {audio_duration:.1f}s audio in {duration:.1f}s (RTF: {rtf:.2f})")

        wav_bytes = audio_to_wav_bytes(wav, model.tts_model.sample_rate)

        return StreamingResponse(
            io.BytesIO(wav_bytes),
            media_type="audio/wav",
            headers={
                "Content-Disposition": "attachment; filename=tts_output.wav",
                "X-Generation-Time": f"{duration:.2f}",
                "X-Audio-Duration": f"{audio_duration:.2f}",
                "X-RTF": f"{rtf:.2f}",
            },
        )
    except Exception as e:
        logger.error(f"TTS generation failed: {e}")
        raise HTTPException(status_code=500, detail=f"Generation failed: {str(e)}")


@app.post("/clone")
async def clone_voice(
    text: str = Form(...),
    reference_audio: UploadFile = File(...),
    reference_text: str = Form(""),
    style_instruction: str = Form(""),
    cfg_value: float = Form(2.5),
    inference_timesteps: int = Form(20),
    temperature: float = Form(0.75),
    api_key: str = Depends(verify_api_key),
):
    """Voice Cloning - clone voice from uploaded audio sample."""
    if not text.strip():
        raise HTTPException(status_code=400, detail="Text cannot be empty")
    
    if len(text) > 5000:
        raise HTTPException(status_code=400, detail="Text too long (max 5000 chars)")
    
    # Save uploaded audio temporarily
    audio_bytes = await reference_audio.read()
    if len(audio_bytes) == 0:
        raise HTTPException(status_code=400, detail="Reference audio is empty")
    
    if len(audio_bytes) > 50 * 1024 * 1024:  # 50MB limit
        raise HTTPException(status_code=400, detail="Reference audio too large (max 50MB)")
    
    temp_audio_path = CACHE_DIR / f"ref_{uuid.uuid4().hex}.wav"
    
    try:
        # Save temp file
        with open(temp_audio_path, "wb") as f:
            f.write(audio_bytes)
        
        model = get_model()
        
        logger.info(
            f"Clone request: text_len={len(text)}, ref_size={len(audio_bytes)/1024:.1f}KB, "
            f"has_transcript={bool(reference_text)}, cfg={cfg_value}, timesteps={inference_timesteps}"
        )
        start = time.time()
        
        # Generate with reference audio
        generate_kwargs = {
            "text": text,
            "prompt_wav_path": str(temp_audio_path),
            "cfg_value": cfg_value,
            "inference_timesteps": inference_timesteps,
        }
        
        if reference_text.strip():
            generate_kwargs["prompt_text"] = reference_text
        
        if style_instruction.strip():
            generate_kwargs["style_instruction"] = style_instruction

        generate_kwargs["temperature"] = temperature

        loop = asyncio.get_event_loop()
        wav = await loop.run_in_executor(None, functools.partial(model.generate, **generate_kwargs))

        duration = time.time() - start
        audio_duration = len(wav) / model.tts_model.sample_rate
        rtf = duration / audio_duration if audio_duration > 0 else 0

        logger.success(f"✓ Cloned {audio_duration:.1f}s audio in {duration:.1f}s (RTF: {rtf:.2f})")
        
        wav_bytes = audio_to_wav_bytes(wav, model.tts_model.sample_rate)
        
        return StreamingResponse(
            io.BytesIO(wav_bytes),
            media_type="audio/wav",
            headers={
                "Content-Disposition": "attachment; filename=cloned_output.wav",
                "X-Generation-Time": f"{duration:.2f}",
                "X-Audio-Duration": f"{audio_duration:.2f}",
                "X-RTF": f"{rtf:.2f}",
            },
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Clone generation failed: {e}")
        raise HTTPException(status_code=500, detail=f"Clone failed: {str(e)}")
    finally:
        # Cleanup temp file
        if temp_audio_path.exists():
            try:
                temp_audio_path.unlink()
            except Exception:
                pass


@app.post("/clone-with-preset")
async def clone_with_preset(
    text: str = Form(...),
    voice_id: str = Form(...),
    preset: str = Form("default"),
    api_key: str = Depends(verify_api_key),
):
    """Generate audio using voice + preset from voice_library."""
    if not text.strip():
        raise HTTPException(status_code=400, detail="Text cannot be empty")
    
    if len(text) > 5000:
        raise HTTPException(status_code=400, detail="Text too long (max 5000 chars)")
    
    # Load preset config
    preset_config = load_voice_preset(voice_id, preset)
    
    model = get_model()
    
    logger.info(
        f"Preset request: voice={voice_id}, preset={preset}, text_len={len(text)}"
    )
    start = time.time()
    
    try:
        params = preset_config.get("params", {})
        
        generate_kwargs = {
            "text": text,
            "prompt_wav_path": preset_config["reference_audio_path"],
            "cfg_value": params.get("cfg_value", 2.5),
            "inference_timesteps": params.get("inference_timesteps", 20),
        }
        
        if preset_config["reference_text"]:
            generate_kwargs["prompt_text"] = preset_config["reference_text"]
        
        if preset_config["style_instruction"]:
            generate_kwargs["style_instruction"] = preset_config["style_instruction"]
        
        loop = asyncio.get_event_loop()
        wav = await loop.run_in_executor(None, functools.partial(model.generate, **generate_kwargs))

        duration = time.time() - start
        audio_duration = len(wav) / model.tts_model.sample_rate
        rtf = duration / audio_duration if audio_duration > 0 else 0

        logger.success(
            f"✓ Generated {audio_duration:.1f}s with {voice_id}/{preset} "
            f"in {duration:.1f}s (RTF: {rtf:.2f})"
        )
        
        wav_bytes = audio_to_wav_bytes(wav, model.tts_model.sample_rate)
        
        return StreamingResponse(
            io.BytesIO(wav_bytes),
            media_type="audio/wav",
            headers={
                "Content-Disposition": f"attachment; filename={voice_id}_{preset}.wav",
                "X-Generation-Time": f"{duration:.2f}",
                "X-Audio-Duration": f"{audio_duration:.2f}",
                "X-RTF": f"{rtf:.2f}",
                "X-Voice-Id": voice_id,
                "X-Preset": preset,
            },
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Preset generation failed: {e}")
        raise HTTPException(status_code=500, detail=f"Generation failed: {str(e)}")


# ============================================================
# Main
# ============================================================
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "server:app",
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 8000)),
        log_level=os.environ.get("LOG_LEVEL", "info").lower(),
    )
