#!/usr/bin/env python3
"""
Test Script: Deterministic MusicGen Generation

This script demonstrates seed-based deterministic generation across different MusicGen models.
Perfect for comparing quality and characteristics between small/medium/large models.
"""

import requests
import json
import time
import sys
from pathlib import Path

# Configuration
BASE_URL = "http://localhost:8000"
TEST_PROMPT = "electronic music, with energetic mood, at medium tempo, in the style of Daft Punk"
TEST_DURATION = 30.0  # Short duration for quick testing
TEST_SEED = 3  # Fixed seed for deterministic results

def test_generation_with_seed(prompt: str, duration: float, seed: int):
    """Test music generation with a specific seed."""
    
    print(f"🎵 Testing generation with seed {seed}")
    print(f"📝 Prompt: '{prompt}'")
    print(f"⏱️ Duration: {duration}s")
    print("-" * 50)
    
    # Start generation
    generation_data = {
        "prompt": prompt,
        "duration": duration,
        "seed": seed,
        "temperature": 1.0,
        "top_k": 250,
        "top_p": 0.0,
        "cfg_coef": 3.0
    }
    
    try:
        # Submit generation request
        response = requests.post(f"{BASE_URL}/api/v1/generate", json=generation_data)
        
        if response.status_code != 200:
            print(f"❌ Failed to start generation: {response.status_code}")
            print(f"Response: {response.text}")
            return None
            
        result = response.json()
        job_id = result["job_id"]
        print(f"✅ Generation started: {job_id}")
        
        # Poll for completion
        while True:
            status_response = requests.get(f"{BASE_URL}/api/v1/status/{job_id}")
            
            if status_response.status_code != 200:
                print(f"❌ Failed to get status: {status_response.status_code}")
                return None
                
            status_data = status_response.json()
            status = status_data["status"]
            progress = status_data.get("progress", 0.0)
            
            print(f"📊 Status: {status} ({progress:.1%})")
            
            if status == "completed":
                print(f"✅ Generation completed!")
                print(f"📁 Audio URL: {status_data.get('audio_url')}")
                print(f"📏 File size: {status_data.get('file_size')} bytes")
                print(f"⏱️ Actual duration: {status_data.get('actual_duration'):.2f}s")
                return job_id
                
            elif status == "failed":
                print(f"❌ Generation failed: {status_data.get('error_message')}")
                return None
                
            elif status in ["cancelled"]:
                print(f"🚫 Generation {status}")
                return None
                
            # Wait before next poll
            time.sleep(2)
            
    except requests.exceptions.ConnectionError:
        print("❌ Cannot connect to MusicGen service")
        print("💡 Make sure the service is running: python -m app.main")
        return None
    except Exception as e:
        print(f"❌ Error: {e}")
        return None

def compare_models_with_seed():
    """Compare different model sizes with the same seed."""
    
    print("🎯 DETERMINISTIC MUSICGEN COMPARISON")
    print("=" * 60)
    print()
    print("This script will help you compare MusicGen model quality")
    print("by generating the same prompt with the same seed across")
    print("different model sizes (small/medium/large).")
    print()
    print("🔧 To test different models:")
    print("1. Edit musicgen-service/app/main.py")
    print("2. Change: musicgen_engine = MusicGenEngine(model_size='small')")
    print("3. Restart the service")
    print("4. Run this script")
    print("5. Repeat for 'medium' and 'large'")
    print()
    
    # Test current model
    job_id = test_generation_with_seed(TEST_PROMPT, TEST_DURATION, TEST_SEED)
    
    if job_id:
        print()
        print("🎉 SUCCESS!")
        print(f"Generated file: generated_audio/{job_id}.wav")
        print()
        print("💡 Tips for model comparison:")
        print("- Use the SAME seed (42) for all models")
        print("- Use the SAME prompt for fair comparison")
        print("- Listen for differences in:")
        print("  • Audio quality and clarity")
        print("  • Musical complexity and arrangement")
        print("  • Instrument separation and realism")
        print("  • Adherence to prompt description")
        print()
        print("🎵 Expected differences:")
        print("- Small (300M): Fast, basic quality")
        print("- Medium (1.5B): Better quality, more complex")
        print("- Large (3.3B): Best quality, most sophisticated")
        
    return job_id

def test_seed_consistency():
    """Test that the same seed produces identical results."""
    
    print("🔄 TESTING SEED CONSISTENCY")
    print("=" * 40)
    print("Generating the same prompt twice with seed 42...")
    print()
    
    prompt = "simple piano melody"
    duration = 5.0
    seed = 42
    # First generation
    print("🎵 Generation 1:")
    job1 = test_generation_with_seed(prompt, duration, seed)
    
    if not job1:
        return False
        
    print()
    print("🎵 Generation 2:")
    job2 = test_generation_with_seed(prompt, duration, seed)
    
    if not job2:
        return False
        
    print()
    print("✅ Both generations completed!")
    print(f"File 1: generated_audio/{job1}.wav")
    print(f"File 2: generated_audio/{job2}.wav")
    print()
    print("💡 These files should be IDENTICAL if deterministic generation works!")
    print("You can compare them with audio software or file checksums.")
    
    return True

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--consistency":
        test_seed_consistency()
    else:
        compare_models_with_seed()
