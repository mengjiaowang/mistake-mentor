from PIL import Image
import io

img = Image.new('RGB', (10, 5), color='blue')
# Draw a dot at top-left
img.putpixel((0, 0), (255, 0, 0)) # Red at 0,0

# Rotate 90
rotated = img.rotate(90, expand=True)
print(f"Original size: {img.size}")
print(f"Rotated size: {rotated.size}")
# If counter-clockwise, 10x5 becomes 5x10.
# The top-left (0,0) becomes bottom-left (0, 9) or similar.
# Let's check where the red pixel is.
for y in range(rotated.size[1]):
    for x in range(rotated.size[0]):
        if rotated.getpixel((x, y)) == (255, 0, 0):
            print(f"Red pixel at: ({x}, {y})")
