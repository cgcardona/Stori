#!/usr/bin/env python3
"""
MusicGen Model Comparison Test Suite

This script provides 5 carefully designed prompts to test the capabilities
of small/medium/large MusicGen models across different musical dimensions.
"""

import requests
import json
import time
from pathlib import Path

BASE_URL = "http://localhost:8000"

# 🎯 Carefully designed test prompts to showcase model differences
TEST_PROMPTS = [
    {
        "id": "complex_jazz",
        "prompt": "sophisticated jazz quartet with intricate piano improvisation, walking bass line, subtle brush drums, and muted trumpet melody in the style of Miles Davis, medium swing tempo",
        "description": "Tests: Complex harmony, multiple instruments, improvisation, style understanding",
        "expected_differences": "Small: Basic jazz, Medium: Better harmony, Large: Sophisticated improvisation"
    },
    {
        "id": "orchestral_epic", 
        "prompt": "epic cinematic orchestral piece with soaring strings, powerful brass fanfares, dramatic timpani, and heroic French horn melody, building to a triumphant climax",
        "description": "Tests: Orchestral arrangement, dynamic build-up, multiple sections",
        "expected_differences": "Small: Simple orchestration, Medium: Better sections, Large: Complex arrangements"
    },
    {
        "id": "electronic_ambient",
        "prompt": "ethereal ambient electronic music with evolving synthesizer pads, subtle arpeggiated sequences, distant reverb-drenched textures, and organic field recording elements",
        "description": "Tests: Texture creation, electronic synthesis, atmospheric depth",
        "expected_differences": "Small: Basic synths, Medium: Better textures, Large: Rich atmospheric layers"
    },
    {
        "id": "acoustic_folk",
        "prompt": "intimate acoustic folk song with fingerpicked steel-string guitar, gentle harmonica, soft brushed percussion, and warm vocal harmonies in a campfire setting",
        "description": "Tests: Acoustic realism, intimate dynamics, organic feel",
        "expected_differences": "Small: Basic acoustic, Medium: Better realism, Large: Nuanced performance"
    },
    {
        "id": "fusion_complexity",
        "prompt": "progressive jazz fusion with complex polyrhythmic drums, fretless bass grooves, distorted guitar solos, analog synthesizer leads, and odd time signatures",
        "description": "Tests: Rhythmic complexity, fusion elements, technical performance",
        "expected_differences": "Small: Simple fusion, Medium: Better complexity, Large: Advanced polyrhythms"
    }
]

def generate_with_prompt(prompt_data, seed=42, duration=30.0):
    """Generate music with a specific prompt and return job info."""
    
    print(f"🎵 Testing: {prompt_data['id'].upper()}")
    print(f"📝 Prompt: {prompt_data['prompt']}")
    print(f"🎯 Tests: {prompt_data['description']}")
    print(f"📊 Expected: {prompt_data['expected_differences']}")
    print("-" * 80)
    
    generation_data = {
        "prompt": prompt_data['prompt'],
        "duration": duration,
        "seed": seed,
        "temperature": 1.0,
        "top_k": 250,
        "top_p": 0.0,
        "cfg_coef": 3.0
    }
    
    try:
        # Start generation
        response = requests.post(f"{BASE_URL}/api/v1/generate", json=generation_data)
        
        if response.status_code != 200:
            print(f"❌ Failed to start generation: {response.status_code}")
            print(f"Response: {response.text}")
            return None
            
        result = response.json()
        job_id = result["job_id"]
        print(f"✅ Generation started: {job_id}")
        
        # Poll for completion
        start_time = time.time()
        while True:
            status_response = requests.get(f"{BASE_URL}/api/v1/status/{job_id}")
            
            if status_response.status_code != 200:
                print(f"❌ Failed to get status: {status_response.status_code}")
                return None
                
            status_data = status_response.json()
            status = status_data["status"]
            progress = status_data.get("progress", 0.0)
            elapsed = time.time() - start_time
            
            print(f"📊 Status: {status} ({progress:.1%}) - {elapsed:.1f}s elapsed")
            
            if status == "completed":
                total_time = time.time() - start_time
                print(f"✅ Generation completed in {total_time:.1f}s!")
                print(f"📁 File: generated_audio/{job_id}.wav")
                print()
                
                return {
                    "job_id": job_id,
                    "prompt_id": prompt_data['id'],
                    "generation_time": total_time,
                    "file_path": f"generated_audio/{job_id}.wav"
                }
                
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

def run_model_comparison():
    """Run the complete model comparison test suite."""
    
    print("🎯 MUSICGEN MODEL COMPARISON TEST SUITE")
    print("=" * 80)
    print()
    print("This test suite will generate 5 different musical styles to showcase")
    print("the differences between MusicGen small/medium/large models.")
    print()
    print("🔧 Instructions:")
    print("1. Run each prompt with the current model")
    print("2. Change model_size in musicgen-service/app/main.py")
    print("3. Restart the service")
    print("4. Repeat for all models")
    print("5. Compare the results!")
    print()
    
    # Check which model is currently loaded
    try:
        health_response = requests.get(f"{BASE_URL}/health/ready")
        if health_response.status_code == 200:
            print("✅ MusicGen service is ready")
        else:
            print("❌ MusicGen service not ready")
            return
    except:
        print("❌ Cannot connect to MusicGen service")
        return
    
    print()
    print("🎵 STARTING GENERATION TESTS...")
    print("=" * 80)
    
    results = []
    
    for i, prompt_data in enumerate(TEST_PROMPTS, 1):
        print(f"\n🎼 TEST {i}/5: {prompt_data['id'].upper()}")
        print("=" * 40)
        
        result = generate_with_prompt(prompt_data, seed=42, duration=30.0)
        
        if result:
            results.append(result)
            print(f"✅ Test {i} completed successfully!")
        else:
            print(f"❌ Test {i} failed!")
            
        # Brief pause between tests
        if i < len(TEST_PROMPTS):
            print("⏳ Waiting 3 seconds before next test...")
            time.sleep(3)
    
    # Summary
    print("\n" + "=" * 80)
    print("🎉 MODEL COMPARISON TEST COMPLETE!")
    print("=" * 80)
    
    if results:
        print(f"✅ Successfully generated {len(results)}/5 test files")
        print("\n📁 Generated Files:")
        
        total_time = 0
        for result in results:
            print(f"   {result['prompt_id']}: {result['file_path']} ({result['generation_time']:.1f}s)")
            total_time += result['generation_time']
            
        print(f"\n⏱️ Total generation time: {total_time:.1f}s")
        print(f"📊 Average per track: {total_time/len(results):.1f}s")
        
        print("\n🎧 LISTENING GUIDE:")
        print("Listen for these differences between models:")
        print("• Small: Faster generation, simpler arrangements")
        print("• Medium: Better instrument separation, more complex harmony")
        print("• Large: Sophisticated arrangements, realistic performance nuances")
        
        print("\n🔄 NEXT STEPS:")
        print("1. Listen to all generated files")
        print("2. Change model in main.py (small → medium → large)")
        print("3. Restart service and run again")
        print("4. Compare the same prompts across models!")
        
    else:
        print("❌ No files were generated successfully")
        print("💡 Check the MusicGen service logs for errors")

if __name__ == "__main__":
    run_model_comparison()
