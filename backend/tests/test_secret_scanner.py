import os
import re
import pytest

def test_no_secrets_in_codebase():
    """扫描项目代码，确保没有硬编码的敏感密钥 (API Key, Secret 等)"""
    PATTERNS = {
        'api_key': re.compile(r'(?i)(api_key|secret|password|token)\s*=\s*[\'"]([^\'"]+)[\'"]'),
        'google_api_key': re.compile(r'AIzaSy[A-Za-z0-9_\-]{35}'),
        'openai_api_key': re.compile(r'sk-[A-Za-z0-9]{32,}'),
        'jwt_secret_hex': re.compile(r'(?i)(secret_key)\s*=\s*[\'"]([a-f0-9]{32,})[\'"]'),
    }
    
    EXCLUDE_DIRS = {'.git', '.venv', 'build', '__pycache__', '.dart_tool', 'node_modules', '.firebase'}
    EXCLUDE_FILES = {'.env', '.env.template'}
    
    results = []
    
    # 动态获取项目根目录 (向前两层: backend/tests/test_secret_scanner.py -> backend -> root)
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
    
    for root, dirs, files in os.walk(base_dir):
        # 排除特定的文件夹
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        
        for file in files:
            if file in EXCLUDE_FILES:
                continue
                
            filepath = os.path.join(root, file)
            
            # 1. 检查 Google Service Account JSON 文件
            if file.endswith('.json'):
                try:
                    with open(filepath, 'r', encoding='utf-8') as f:
                        content = f.read()
                        if '"type": "service_account"' in content:
                            results.append(f"[Service Account] {filepath}")
                except:
                    pass
                    
            # 2. 检查常见文本文件中的密钥模式
            if file.endswith(('.py', '.dart', '.js', '.yaml', '.md', '.sh', '.json')):
                try:
                    with open(filepath, 'r', encoding='utf-8') as f:
                        for i, line in enumerate(f, 1):
                            for name, pattern in PATTERNS.items():
                                match = pattern.search(line)
                                if match:
                                    # 过滤掉 README / 模板中的示例字符
                                    if 'README' in file and ('example' in line or 'admin123' in line):
                                         continue
                                    # 过滤掉 test 文件夹里的 Mock 数据/测试内容 (免得自己扫到自己)
                                    if 'test' in filepath:
                                         continue
                                    results.append(f"[{name}] {filepath}:{i} -> {line.strip()}")
                except:
                    pass

    assert len(results) == 0, f"在项目代码中扫描到以下可能的硬编码密钥（请排查）：\n" + "\n".join(results)
