try:
    from vertexai.vision_models import ImageGenerationModel
    print("Success: vertexai.vision_models loaded, ImageGenerationModel is available!")
except ImportError as e:
    print(f"Failed vertexai.vision_models: {e}")

try:
    from vertexai.preview.vision_models import ImageGenerationModel as PreviewModel
    print("Success: vertexai.preview.vision_models loaded.")
except ImportError as e:
    print(f"Failed vertexai.preview.vision_models: {e}")
