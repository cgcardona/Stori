#!/usr/bin/env python3
"""
Debug Deterministic Generation

This script helps identify why identical seeds produce different file checksums.
"""

import requests
import json
import time
import hashlib
from pathlib import Path

BASE_URL = "http://localhost:8000"

def get_file_checksum(filepath):
    """Calculate SHA256 checksum of a file."""
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def test_immediate_regeneration():
    """Test generating the same prompt twice in quick succession."""
    
    print("🔬 DEBUGGING DETERMINISTIC GENERATION")
    print("=" * 50)
    
    # Test parameters
    test_data = {
        "prompt": "simple test tone",
        "duration": 5.0,  # Minimum duration for API
        "seed": 12345,    # Fixed seed
        "temperature": 1.0,
        "top_k": 250,
        "top_p": 0.0,
        "cfg_coef": 3.0
    }
    
    print(f"🎯 Test Parameters:")
    print(f"   Prompt: '{test_data['prompt']}'")
    print(f"   Seed: {test_data['seed']}")
    print(f"   Duration: {test_data['duration']}s")
    print()
    
    jobs = []
    
    # Generate twice with same parameters
    for i in range(2):
        print(f"🎵 Generation {i+1}:")
        
        try:
            # Start generation
            response = requests.post(f"{BASE_URL}/api/v1/generate", json=test_data)
            
            if response.status_code != 200:
                print(f"❌ Failed: {response.status_code} - {response.text}")
                return
                
            result = response.json()
            job_id = result["job_id"]
            print(f"   Job ID: {job_id}")
            
            # Wait for completion
            while True:
                status_response = requests.get(f"{BASE_URL}/api/v1/status/{job_id}")
                status_data = status_response.json()
                status = status_data["status"]
                
                if status == "completed":
                    print(f"   ✅ Completed")
                    jobs.append(job_id)
                    break
                elif status == "failed":
                    print(f"   ❌ Failed: {status_data.get('error_message')}")
                    return
                    
                time.sleep(1)
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return
    
    # Analyze the generated files
    print()
    print("🔍 FILE ANALYSIS:")
    print("-" * 30)
    
    files = []
    for job_id in jobs:
        filepath = Path(f"musicgen-service/generated_audio/{job_id}.wav")
        if filepath.exists():
            files.append(filepath)
            size = filepath.stat().st_size
            checksum = get_file_checksum(filepath)
            print(f"File: {filepath.name}")
            print(f"   Size: {size:,} bytes")
            print(f"   SHA256: {checksum}")
            print()
        else:
            print(f"❌ File not found: {filepath}")
    
    # Compare results
    if len(files) == 2:
        checksum1 = get_file_checksum(files[0])
        checksum2 = get_file_checksum(files[1])
        
        print("🎯 DETERMINISTIC TEST RESULT:")
        if checksum1 == checksum2:
            print("✅ SUCCESS: Files are IDENTICAL (deterministic generation working!)")
        else:
            print("❌ FAILURE: Files are DIFFERENT (non-deterministic generation)")
            print()
            print("🔍 Possible causes:")
            print("1. AudioCraft audio_write() adds timestamps or metadata")
            print("2. PyTorch/CUDA non-deterministic operations")
            print("3. Random number generator not properly seeded")
            print("4. File I/O adding system metadata")
            
            # Detailed binary comparison
            print()
            print("🔬 BINARY ANALYSIS:")
            with open(files[0], 'rb') as f1, open(files[1], 'rb') as f2:
                data1 = f1.read()
                data2 = f2.read()
                
                if len(data1) != len(data2):
                    print(f"❌ Different file sizes: {len(data1)} vs {len(data2)}")
                else:
                    # Find first difference
                    for i, (b1, b2) in enumerate(zip(data1, data2)):
                        if b1 != b2:
                            print(f"❌ First difference at byte {i}: 0x{b1:02x} vs 0x{b2:02x}")
                            
                            # Show context around difference
                            start = max(0, i - 16)
                            end = min(len(data1), i + 16)
                            print(f"   Context (bytes {start}-{end}):")
                            print(f"   File 1: {data1[start:end].hex()}")
                            print(f"   File 2: {data2[start:end].hex()}")
                            break
                    else:
                        print("🤔 Files are identical in content but different checksums?")

if __name__ == "__main__":
    test_immediate_regeneration()
