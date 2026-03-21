import os
import re

# Regex for common secret patterns
PATTERNS = {
    'api_key': re.compile(r'(?i)(api_key|secret|password|token)\s*=\s*[\'"]([^\'"]+)[\'"]'),
    'google_api_key': re.compile(r'AIzaSy[A-Za-z0-9_\-]{35}'),
    'openai_api_key': re.compile(r'sk-[A-Za-z0-9]{32,}'),
    'jwt_secret_hex': re.compile(r'(?i)(secret_key)\s*=\s*[\'"]([a-f0-9]{32,})[\'"]'),
}

EXCLUDE_DIRS = {'.git', '.venv', 'build', '__pycache__', '.dart_tool', 'node_modules'}
EXCLUDE_FILES = {'.env', '.env.template'}

results = []

for root, dirs, files in os.walk('.'):
    # Prune excluded directories
    dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
    
    for file in files:
        if file in EXCLUDE_FILES:
            continue
            
        filepath = os.path.join(root, file)
        
        # Check for service account JSON files
        if file.endswith('.json'):
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    content = f.read()
                    if '"type": "service_account"' in content:
                        results.append(f"[Service Account] {filepath}")
            except:
                pass
                
        # Scan text files for secrets
        if file.endswith(('.py', '.dart', '.js', '.yaml', '.md', '.sh')):
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    for i, line in enumerate(f, 1):
                        for name, pattern in PATTERNS.items():
                            match = pattern.search(line)
                            if match:
                                # Skip example strings in READMEs if they look generic
                                if 'README' in file and ('example' in line or 'admin123' in line):
                                    continue
                                results.append(f"[{name}] {filepath}:{i} -> {line.strip()}")
            except:
                pass

for r in results:
    print(r)
