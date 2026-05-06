"""
VoxCPM2 Server - Test Client
Tests all endpoints to verify server is working correctly.

Usage:
    python3 test-client.py --server http://localhost:8000 --api-key YOUR_KEY
    python3 test-client.py --server http://gpu-ip:8000 --api-key YOUR_KEY --skip-clone
"""
import argparse
import sys
import time
from pathlib import Path

import requests


def print_status(text, status="info"):
    colors = {
        "info": "\033[94m",
        "success": "\033[92m",
        "warning": "\033[93m",
        "error": "\033[91m",
    }
    icons = {"info": "→", "success": "✓", "warning": "⚠", "error": "✗"}
    color = colors.get(status, "")
    icon = icons.get(status, "")
    reset = "\033[0m"
    print(f"{color}{icon} {text}{reset}")


def test_health(server_url):
    """Test /health endpoint - no auth required."""
    print_status("Testing /health endpoint...")
    
    try:
        r = requests.get(f"{server_url}/health", timeout=10)
        r.raise_for_status()
        data = r.json()
        
        print_status(f"Server status: {data.get('status')}", "success")
        print_status(f"Model loaded: {data.get('model_loaded')}", "success" if data.get("model_loaded") else "warning")
        print_status(f"Load duration: {data.get('load_duration', 'N/A')}s", "info")
        return data.get("model_loaded", False)
    except Exception as e:
        print_status(f"Health check failed: {e}", "error")
        return False


def test_voices(server_url, api_key):
    """Test /voices endpoint."""
    print_status("Testing /voices endpoint...")
    
    try:
        r = requests.get(
            f"{server_url}/voices",
            headers={"X-API-Key": api_key},
            timeout=10,
        )
        r.raise_for_status()
        data = r.json()
        
        voices = data.get("voices", [])
        print_status(f"Found {len(voices)} voice(s) in library", "success")
        for v in voices[:5]:
            print_status(f"  - {v['voice_id']}: {v['presets']}", "info")
        return voices
    except Exception as e:
        print_status(f"List voices failed: {e}", "error")
        return []


def test_tts(server_url, api_key, output_dir):
    """Test /tts endpoint - Voice Design (no audio sample)."""
    print_status("Testing /tts endpoint (Voice Design)...")
    
    text = "Xin chào, đây là bài kiểm tra giọng nói tiếng Việt. Hello, this is a voice test in English."
    
    try:
        start = time.time()
        r = requests.post(
            f"{server_url}/tts",
            headers={"X-API-Key": api_key},
            data={
                "text": text,
                "voice_description": "A warm and natural voice",
                "cfg_value": 2.0,
                "inference_timesteps": 10,
            },
            timeout=300,
        )
        r.raise_for_status()
        duration = time.time() - start
        
        output_path = output_dir / "test_tts.wav"
        with open(output_path, "wb") as f:
            f.write(r.content)
        
        gen_time = r.headers.get("X-Generation-Time", "?")
        audio_duration = r.headers.get("X-Audio-Duration", "?")
        rtf = r.headers.get("X-RTF", "?")
        
        print_status(
            f"Generated {audio_duration}s audio in {gen_time}s (RTF: {rtf})",
            "success",
        )
        print_status(f"Saved: {output_path} ({len(r.content)/1024:.1f} KB)", "success")
        return True
    except Exception as e:
        print_status(f"TTS failed: {e}", "error")
        return False


def test_clone(server_url, api_key, output_dir, reference_audio_path):
    """Test /clone endpoint - Voice Cloning."""
    print_status("Testing /clone endpoint (Voice Cloning)...")
    
    if not reference_audio_path or not Path(reference_audio_path).exists():
        print_status("No reference audio provided, skipping clone test", "warning")
        return None
    
    text = "Đây là giọng được nhân bản từ file mẫu của bạn."
    
    try:
        start = time.time()
        with open(reference_audio_path, "rb") as audio_file:
            r = requests.post(
                f"{server_url}/clone",
                headers={"X-API-Key": api_key},
                data={
                    "text": text,
                    "reference_text": "",  # Empty for Controllable Cloning
                    "style_instruction": "natural, clear",
                    "cfg_value": 2.5,
                    "inference_timesteps": 20,
                    "temperature": 0.75,
                },
                files={"reference_audio": audio_file},
                timeout=300,
            )
        r.raise_for_status()
        duration = time.time() - start
        
        output_path = output_dir / "test_clone.wav"
        with open(output_path, "wb") as f:
            f.write(r.content)
        
        gen_time = r.headers.get("X-Generation-Time", "?")
        audio_duration = r.headers.get("X-Audio-Duration", "?")
        rtf = r.headers.get("X-RTF", "?")
        
        print_status(
            f"Cloned {audio_duration}s audio in {gen_time}s (RTF: {rtf})",
            "success",
        )
        print_status(f"Saved: {output_path}", "success")
        return True
    except Exception as e:
        print_status(f"Clone failed: {e}", "error")
        return False


def test_clone_preset(server_url, api_key, output_dir, voice_id, preset):
    """Test /clone-with-preset endpoint."""
    print_status(f"Testing /clone-with-preset (voice={voice_id}, preset={preset})...")
    
    text = "Đây là test với giọng có sẵn trong voice library."
    
    try:
        start = time.time()
        r = requests.post(
            f"{server_url}/clone-with-preset",
            headers={"X-API-Key": api_key},
            data={
                "text": text,
                "voice_id": voice_id,
                "preset": preset,
            },
            timeout=300,
        )
        r.raise_for_status()
        
        output_path = output_dir / f"test_preset_{voice_id}_{preset}.wav"
        with open(output_path, "wb") as f:
            f.write(r.content)
        
        gen_time = r.headers.get("X-Generation-Time", "?")
        audio_duration = r.headers.get("X-Audio-Duration", "?")
        
        print_status(
            f"Generated {audio_duration}s in {gen_time}s",
            "success",
        )
        print_status(f"Saved: {output_path}", "success")
        return True
    except Exception as e:
        print_status(f"Clone with preset failed: {e}", "error")
        return False


def main():
    parser = argparse.ArgumentParser(description="Test VoxCPM2 server")
    parser.add_argument("--server", default="http://localhost:8000", help="Server URL")
    parser.add_argument("--api-key", required=True, help="API key")
    parser.add_argument("--output-dir", default="./test_outputs", help="Output directory")
    parser.add_argument("--reference-audio", help="Path to reference audio for /clone test")
    parser.add_argument("--skip-tts", action="store_true", help="Skip /tts test")
    parser.add_argument("--skip-clone", action="store_true", help="Skip /clone test")
    parser.add_argument("--test-preset", help="Test preset: voice_id:preset_name")
    args = parser.parse_args()

    # Setup output dir
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n{'='*60}")
    print(f"  VoxCPM2 Server Test Client")
    print(f"{'='*60}")
    print(f"Server: {args.server}")
    print(f"Output: {output_dir.absolute()}")
    print()

    # Test 1: Health check
    if not test_health(args.server):
        print_status("Server not ready, aborting tests", "error")
        sys.exit(1)
    print()

    # Test 2: List voices
    voices = test_voices(args.server, args.api_key)
    print()

    # Test 3: TTS Voice Design
    if not args.skip_tts:
        test_tts(args.server, args.api_key, output_dir)
        print()

    # Test 4: Voice Cloning
    if not args.skip_clone and args.reference_audio:
        test_clone(args.server, args.api_key, output_dir, args.reference_audio)
        print()

    # Test 5: Clone with preset
    if args.test_preset and ":" in args.test_preset:
        voice_id, preset = args.test_preset.split(":", 1)
        test_clone_preset(args.server, args.api_key, output_dir, voice_id, preset)
        print()

    print(f"{'='*60}")
    print_status("Tests completed", "success")
    print(f"Outputs saved to: {output_dir.absolute()}")
    print()


if __name__ == "__main__":
    main()
