import pytest
from PIL import Image

def test_pil_rotate():
    """验证 Pillow 库的旋转逻辑是否正确"""
    img = Image.new('RGB', (10, 5), color='blue')
    img.putpixel((0, 0), (255, 0, 0)) # Red at 0,0
    
    rotated = img.rotate(90, expand=True)
    assert img.size == (10, 5)
    assert rotated.size == (5, 10)
    
    red_found = False
    for y in range(rotated.size[1]):
        for x in range(rotated.size[0]):
             if rotated.getpixel((x, y)) == (255, 0, 0):
                  red_found = True
                  assert (x, y) == (0, 9)
    assert red_found
