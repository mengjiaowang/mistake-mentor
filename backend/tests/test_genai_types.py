import pytest

def test_genai_types():
    """验证 google-genai 库依赖及其 Types 是否正常"""
    try:
         from google import genai
         from google.genai import types
         
         assert hasattr(types, "EditMode")
         edit_modes = [e for e in types.EditMode]
         assert len(edit_modes) > 0
    except ImportError as e:
         pytest.fail(f"Failed to import google.genai: {e}")
