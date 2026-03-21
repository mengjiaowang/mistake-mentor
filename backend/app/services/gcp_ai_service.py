import json
import os
from typing import Dict, Any

import vertexai
from vertexai.generative_models import GenerativeModel, Part, Image
from vertexai.preview.vision_models import ImageGenerationModel, Image as VisionImage

from app.config import settings

# ==========================================
# 1. 初始化 Vertex AI
# ==========================================
PROJECT_ID = settings.PROJECT_ID
# 确保在环境中有 PROJECT_ID 主动传入，否则降级使用常量
os.environ["GOOGLE_CLOUD_PROJECT"] = PROJECT_ID
vertexai.init(project=PROJECT_ID, location="us-central1") # 切换至 us-central1 节点，避免 global 节点的 mTLS 依赖报错

class GCPQuestionsAIService:
    def __init__(self):
        # 路线 B: Imagen 模型 (用于擦除字迹)
        # 为 Imagen 4 强制绑定 us-central1 基础区位
        vertexai.init(project=PROJECT_ID, location="us-central1")
        try:
            # 升级为最新的 4.0 旗舰版
            self.imagen_model = ImageGenerationModel.from_pretrained("imagen-4.0-generate-001")
        except Exception:
            # 降级或备用模型
            self.imagen_model = ImageGenerationModel.from_pretrained("image-generation-001")

        # 路线 A/B 核心: Gemini 3.1 模型加载将在运行时动态指向 global 节点，由 ocr_and_analyze 代管

    def remove_handwriting(self, image_bytes: bytes) -> bytes:
        """
        调用 Imagen 3/4 API，利用 Inpaint-Removal 智能擦除画面中的手写笔迹和红笔痕迹
        """
        try:
            # 显式重申该方法只在 us-central1 上下文发送
            vertexai.init(project=PROJECT_ID, location="us-central1")
            
            base_image = VisionImage(image_bytes)
            # 使用 Imagen 3 的编辑模式
            result = self.imagen_model.edit_image(
                base_image=base_image,
                prompt="remove all handwriting, handwritten answers, and red pen marks completely, leave only the printed background question text and diagram",
                edit_mode="inpainting-remove", # 像素级移除痕迹
                number_of_images=1,
            )
            # 返回第一张生成的空白图 bytes
            return result.images[0]._image_bytes
        except Exception as e:
            # 如果 Imagen 失败，为了保证链路通畅，降级为直接返回原图（即走路线 A 依靠 Gemini 过滤）
            print(f"[Warning] Imagen 3 擦除失败，降级使用原图进行解析: {e}")
            return image_bytes

    def ocr_and_analyze(self, image_bytes: bytes, existing_tags: list = []) -> Dict[str, Any]:
        """
        调用 Gemini 1.5/3.1，利用多模态能力提取题目文本、公式(LaTeX) 及生成解析。
        """
        prompt = """
        作为一个资深的老师，请你仔细阅读这张错题图片。
        **特别指令**：如果照片中包含多个题目，请辨别并**仅仅分析视觉上最主要（居中、最清晰或体量最大）的那个题目**，忽略边缘干扰，只需提取并解决核心的一道题。

        执行以下任务：
        1. 提取题目的正文、选项（如果有）。
        2. 如果题目包含数学/物理等公式，请务必将其转换为标准的 LaTeX 格式（例如: $E=mc^2$）。
        3. 给出分步解析、考点定位和防错指南。
        4. 提供 1 道相同考点但数值不同的【举一反三】变式题（请务必附带答案与解析步骤）。
        5. 对比现有标签候选列表：[EXISTING_TAGS]。请根据题目解析，从列表中选出 1-2 个最贴合本题的标签；如果列表中没有合适的，可自动建议。

        请严格以下列 JSON 结构返回结果，且不要包含任何 Markdown 标识符(如 ```json)：
        {
            "question_text": "题干文本 (包含 LaTeX)",
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
            # 构造多模态输入
            image_part = Part.from_data(data=image_bytes, mime_type="image/jpeg")
            
            # 强制切换为 global 用于 Gemini 3.1 预览版
            vertexai.init(project=PROJECT_ID, location="global")
            gemini_model = GenerativeModel("gemini-3.1-pro-preview")

            # 注入现有标签列表
            prompt_content = prompt.replace("[EXISTING_TAGS]", str(existing_tags))

            # 使用 structured output 引导，或者在 prompt 强调。
            response = gemini_model.generate_content(
                [image_part, prompt_content],
                generation_config={
                    "temperature": 0.2, # 降低温度，防止幻觉
                    "response_mime_type": "application/json" # 强制返回 JSON 格式
                }
            )
            
            # 解析返回的 JSON 文本
            return json.loads(response.text)
        except Exception as e:
            import traceback
            print(f"[Error] Gemini 解析失败，异常堆栈如下:")
            traceback.print_exc()
            return {
                "error": "AI 解析失败",
                "question_text": "无法提取题目，请重试。"
            }

# 初始化全局单例
ai_service = GCPQuestionsAIService()
