import sys
import os
sys.path.append(os.getcwd())

# 确保安装了 google-genai 库
import subprocess
subprocess.run([sys.executable, "-m", "pip", "install", "google-genai"])

try:
    from google import genai
    from google.genai import types
    print("\n--- types.EditMode ---")
    print([e for e in types.EditMode])
except Exception as e:
    print(f"Error testing google-genai: {e}")
