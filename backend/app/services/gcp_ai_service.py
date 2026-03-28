import json
import os
from typing import Dict, Any

from google import genai
from google.genai import types

from app.config import settings
from tenacity import retry, stop_after_attempt, wait_exponential

# 初始化 Vertex AI
PROJECT_ID = settings.PROJECT_ID
os.environ["GOOGLE_CLOUD_PROJECT"] = PROJECT_ID

class GCPQuestionsAIService:
    def __init__(self):
        # Gemini 专属：切换至 global endpoint 保证预览模型可用性
        self.client = genai.Client(
            vertexai=True,
            project=PROJECT_ID,
            location="global",
            http_options=types.HttpOptions(timeout=60000) # 60 秒超时
        )
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        reraise=True
    )
    def _do_remove_handwriting(self, image_bytes: bytes) -> bytes:
        """调用 Vertex AI API 智能擦除画面手写筆記（帶重試）"""
        image_part = types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg")
        prompt = "给我把这个题目照片的手写部分和批改部分全部擦除，只保留原题，给题目的角度矫正。"

        response = self.client.models.generate_content(
            model=settings.ERASURE_MODEL,
            contents=[image_part, prompt],
            config=types.GenerateContentConfig(
                response_modalities=["IMAGE"],
                temperature=0.2, 
            )
        )

        candidates = response.candidates
        if candidates and candidates[0].content.parts:
            part = candidates[0].content.parts[0]
            if part.inline_data:
                return part.inline_data.data
            elif hasattr(part, 'as_image') and part.as_image():
                 from io import BytesIO
                 img = part.as_image()
                 img_byte_arr = BytesIO()
                 img.save(img_byte_arr, format='JPEG')
                 return img_byte_arr.getvalue()
        
        raise RuntimeError("gemini-3.1-flash-image-preview 未返回有效的圖片數據內容。")

    def remove_handwriting(self, image_bytes: bytes) -> bytes:
        """公有接口：對外提供安全的降級防護，若 3 次重試後仍失敗則回退原圖。"""
        try:
            return self._do_remove_handwriting(image_bytes)
        except Exception as e:
            print(f"[Warning tenacity] 擦除 3 次熔斷重試後仍宣告宣告失败，降級使用原圖: {e}")
            return image_bytes
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        reraise=True
    )
    def _do_ocr_and_analyze(self, image_bytes: bytes, prompt_content: str) -> Dict[str, Any]:
        """調用 Vertex AI 進行大模型認知解碼（帶重試）"""
        image_part = types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg")

        response = self.client.models.generate_content(
            model=settings.OCR_MODEL,
            contents=[image_part, prompt_content],
            config=types.GenerateContentConfig(
                temperature=0.2, 
                response_mime_type="application/json"
            )
        )
        return json.loads(response.text)

    def ocr_and_analyze(self, image_bytes: bytes, existing_tags: list = []) -> Dict[str, Any]:
        """公有接口：對外提供安全的降級，在 3 次熔斷重試後返回默認解析提示。"""
        prompt = """
        作为一个资深的老师，请你仔细阅读这张错题图片。
        **特别指令**：如果照片中包含多个题目，请辨别并**仅仅分析视觉上最主要（居中、最清晰或体量最大）的那个题目**，忽略边缘干扰，只需提取并解决核心的一道题。
        **儿童友好型解释**：你的解析过程（analysis_steps）、易错点提醒（trap_warning）必须通俗易懂，用生动、亲切的语言，就像在给小学生讲课一样，让孩子也能轻松听懂和理解。

        执行以下任务：

        1. 提取题目的正文、选项（如果有）。
        2. 如果题目包含数学/物理等公式，请务必将其转换为标准的 LaTeX 格式（例如: $E=mc^2$）。
        3. 给出分步解析、考点定位和防错指南。
        4. 提供 1 道相同考点但数值不同的【举一反三】变式题（请务必附带答案与解析步骤）。
        5. 对比现有标签候选列表：[EXISTING_TAGS]。请根据题目解析，从列表中选出 1-2 个最贴合本题的标签；如果列表中没有合适的，可自动建议。
        6. **[图表位置提取]**：仔细观察题目是否包含**任何非纯文本、辅助解题用到的视觉结构**（不论任何科目，包括但不限于：几何图形、物理受力分析图、化学分子机构或实验装置、生物细胞组织结构、地理地图、历史路线图、以及各类数据表格、統計图表等）。如果包含，请输出该视觉结构在整体图片上的**归一化边界框坐标**：`[ymin, xmin, ymax, xmax]`，其中坐标值均为浮点数，且在 `0.0` 到 `1.0` 之间。如果不包含，则输出 `null`。

        请严格以下列 JSON 结构返回结果，且不要包含任何 Markdown 标识符(如 ```json)：
        {
            "question_text": "题干文本 (包含 LaTeX)",
            "diagram_bbox": [ymin, xmin, ymax, xmax] 或 null,
            "options": ["选项A", "选项B"...] 或 null,
            "knowledge_point": "考点名称",
            "analysis_steps": ["步骤1简介...", "步骤2简介..."],
            "trap_warning": "易错点提醒",
            "suggested_tags": ["标签1", "标签2"],
            "similar_question": {
                "question_text": "变式题干 (包含 LaTeX)",
                "options": ["选项A", "选项B"...] 或 null,
                "answer": "参考答案 (例如 A 选项，或者具体的公式数值)",
                "analysis": "针对变式题的详细分步解析或思路"
            }
        }
        """
        try:
            prompt_content = prompt.replace("[EXISTING_TAGS]", str(existing_tags))
            return self._do_ocr_and_analyze(image_bytes, prompt_content)
        except Exception as e:
            import traceback
            print(f"[Error tenacity] Gemini 3 次熔斷重試後依舊宣告失敗，異常拋出如下:")
            traceback.print_exc()
            return {
                "error": "AI 解析失败",
                "question_text": "无法提取题目，请重试。"
            }
# 初始化全局单例
ai_service = GCPQuestionsAIService()
