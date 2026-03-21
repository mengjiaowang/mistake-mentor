import pytest

def test_import_image_generation_model():
    """验证 vertexai.vision_models 导入是否正常"""
    try:
         from vertexai.vision_models import ImageGenerationModel
         assert True
    except ImportError as e:
         pytest.fail(f"Failed to import ImageGenerationModel: {e}")

def test_import_preview_model():
    """验证 vertexai.preview.vision_models 导入是否正常"""
    try:
         from vertexai.preview.vision_models import ImageGenerationModel as PreviewModel
         assert True
    except ImportError as e:
         pytest.fail(f"Failed to import PreviewModel: {e}")
