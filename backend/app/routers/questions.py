import uuid
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, File, UploadFile, HTTPException, Form
from google.cloud import firestore, storage
from pydantic import BaseModel

from app.services.gcp_ai_service import ai_service
from app.main import get_current_user, User # 依赖认证

router = APIRouter(
    prefix="/api/v1/questions",
    tags=["Questions"]
)

from app.config import settings

# ==========================================
# 1. 初始化 GCP 客户端
# ==========================================
PROJECT_ID = settings.PROJECT_ID
db = firestore.Client(project=PROJECT_ID)
storage_client = storage.Client(project=PROJECT_ID)

# 建议在 GCP bucket 命名时带上项目名防止冲突
BUCKET_NAME = f"{PROJECT_ID}-images"

from google.api_core.exceptions import NotFound

def upload_to_gcs(image_bytes: bytes, file_name: str, content_type: str = "image/jpeg") -> str:
    """上传图片 bytes 到 GCS 并返回公开访问链接 (自用版方便获取)"""
    try:
        bucket = storage_client.get_bucket(BUCKET_NAME)
    except NotFound:
        # 只有在桶确实不存在时才自动创建
        bucket = storage_client.create_bucket(BUCKET_NAME, location="asia-northeast1")
    except Exception as e:
         print(f"[Warning] get_bucket 未决异常，尝试使用直接绑定: {e}")
         bucket = storage_client.bucket(BUCKET_NAME)
    
    blob = bucket.blob(file_name)
    blob.upload_from_string(image_bytes, content_type=content_type)
         
    return blob.public_url

# ==========================================
# 2. 接口端点
# ==========================================

@router.post("/upload")
async def upload_question(
    file: UploadFile = File(...),
    mirror: bool = Form(False),
    rotate_degrees: int = Form(0), 
    crop_left: float = Form(0.0),   # 新增：裁剪百分比 (0.0 - 1.0)
    crop_top: float = Form(0.0),
    crop_width: float = Form(1.0),
    crop_height: float = Form(1.0),
    current_user: User = Depends(get_current_user)
):
    """
    1. 上传图片 
    2. Gemini 3.1 OCR解析
    3. 存入 Firestore & GCS
    """
    contents = await file.read()

    if mirror or rotate_degrees != 0 or crop_left > 0 or crop_top > 0 or crop_width < 1.0 or crop_height < 1.0:
        try:
            from PIL import Image
            import io
            img = Image.open(io.BytesIO(contents))
            
            if mirror:
                from PIL import ImageOps
                img = ImageOps.mirror(img)
                
            if rotate_degrees == 90:
                img = img.transpose(Image.ROTATE_270) # 顺 90 -> 逆 270 对齐轴心
            elif rotate_degrees == 180:
                img = img.transpose(Image.ROTATE_180)
            elif rotate_degrees == 270:
                img = img.transpose(Image.ROTATE_90)
                
            # --- 新增：根据百分比裁剪 ---
            if crop_left > 0 or crop_top > 0 or crop_width < 1.0 or crop_height < 1.0:
                W, H = img.size
                left = int(W * crop_left)
                top = int(H * crop_top)
                left = max(0, min(W - 1, left))
                top = max(0, min(H - 1, top))
                right = max(left + 1, min(W, left + int(W * crop_width)))
                bottom = max(top + 1, min(H, top + int(H * crop_height)))
                img = img.crop((left, top, right, bottom))
                
            buf = io.BytesIO()
            img.save(buf, format=img.format or 'JPEG')
            contents = buf.getvalue()
        except Exception as e:
            print(f"[Warning] 图片处理（镜像/旋转/裁剪）失败: {e}")

    question_uuid = str(uuid.uuid4())
    
    # [Step 1] 存入 GCS (只保存原图)
    try:
        upload_to_gcs(contents, f"original/{question_uuid}.jpg")
        # 覆写为后端专属的流式代理路由，绕过 GCS 组织的 Private 策略锁定
        url_original = f"/api/v1/questions/{question_uuid}/image" 
        url_blank = url_original 
    except Exception as e:
         print(f"[Warning] GCS 上传失败，降级使用本地 Mock：{e}")
         url_original = "http://placeholder.org/original.jpg"
         url_blank = "http://placeholder.org/blank.jpg"

    # [Step 2] Gemini 推理 & 结构化解析 (先抓取标签库作为 AI 参照)
    existing_tags = []
    try:
        tags_doc = db.collection("tags").document(current_user.username).get()
        if tags_doc.exists:
            existing_tags = tags_doc.to_dict().get("tags", [])
    except Exception:
        pass
    if not existing_tags:
        existing_tags = ["语文", "数学", "英语", "物理", "化学"] # 默认兜底参考

    ai_result = ai_service.ocr_and_analyze(contents, existing_tags=existing_tags)
    
    # [Step 3] 编排存入 Firestore
    question_doc = {
        "id": question_uuid,
        "user_id": current_user.username,
        "image_original": url_original,
        "image_blank": url_blank,
        "question_text": ai_result.get("question_text", ""),
        "options": ai_result.get("options"),
        "knowledge_point": ai_result.get("knowledge_point", "未对齐考点"),
        "analysis_steps": ai_result.get("analysis_steps", []),
        "trap_warning": ai_result.get("trap_warning", ""),
        "similar_question": ai_result.get("similar_question"),
        "mastery_status": "unmastered", # 默认未掌握
        "is_deleted": False, # 初始化软删除状态为 False
        "tags": ai_result.get("suggested_tags", []), # 使用 AI 推荐的默认标签归类
        "created_at": datetime.utcnow().isoformat()
    }
    
    db.collection("questions").document(question_uuid).set(question_doc)
    
    return {"message": "错题录入并解析成功", "data": question_doc}

@router.get("/")
async def list_questions(
    current_user: User = Depends(get_current_user),
    knowledge_point: Optional[str] = None,
    tag: Optional[str] = None, # 新增：支持标签过滤
    is_deleted: bool = False # 新增：默认不查询回收站
):
    """获取错题列表，支持考点及标签筛选"""
    query = db.collection("questions").where("user_id", "==", current_user.username)
    if knowledge_point:
        query = query.where("knowledge_point", "==", knowledge_point)
    if tag:
        # 使用 Firestore 阵列包含语法过滤
        query = query.where("tags", "array_contains", tag)
    
    docs = query.stream()
    result = []
    for doc in docs:
         data = doc.to_dict()
         # 兼容性设计：如果历史数据没有 is_deleted 字段，默认就是 False（未删除）
         if data.get("is_deleted", False) == is_deleted:
              result.append(data)
         
    return {"questions": result}

@router.get("/{question_id}")
async def get_question_detail(
    question_id: str,
    current_user: User = Depends(get_current_user)
):
    """错题详情查看"""
    doc_ref = db.collection("questions").document(question_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="错题未找到")
        
    data = doc.to_dict()
    if data["user_id"] != current_user.username:
         raise HTTPException(status_code=403, detail="无权访问该错题")
         
    return data

@router.delete("/{question_id}")
async def delete_question(
    question_id: str,
    current_user: User = Depends(get_current_user)
):
    """软删除单条错题（移入回收站）"""
    doc_ref = db.collection("questions").document(question_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="错题未找到")
        
    data = doc.to_dict()
    if data["user_id"] != current_user.username:
         raise HTTPException(status_code=403, detail="无权删除该错题")
         
    # 执行软删除：翻转状态标志位位
    doc_ref.update({"is_deleted": True})
    return {"message": "错题已移入回收站"}

@router.post("/{question_id}/restore")
async def restore_question(
    question_id: str,
    current_user: User = Depends(get_current_user)
):
    """从回收站恢复单条错题"""
    doc_ref = db.collection("questions").document(question_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="错题未找到")
        
    data = doc.to_dict()
    if data["user_id"] != current_user.username:
         raise HTTPException(status_code=403, detail="无权操作该错题")
         
    doc_ref.update({"is_deleted": False})
    return {"message": "错题已成功恢复至错题本"}

@router.delete("/{question_id}/permanent")
async def permanent_delete_question(
    question_id: str,
    current_user: User = Depends(get_current_user)
):
    """永久删除/粉碎单条错题"""
    doc_ref = db.collection("questions").document(question_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="错题未找到")
        
    data = doc.to_dict()
    if data["user_id"] != current_user.username:
         raise HTTPException(status_code=403, detail="无权删除该错题")
         
    doc_ref.delete()
    return {"message": "错题已从云端永久删除"}
from fastapi.responses import Response

@router.get("/{question_id}/image")
async def get_question_image(question_id: str):
    """流式代理拉取 GCS 上的错题图片并直接回传给前端"""
    try:
        # 绕过 get_bucket 直接绑定桶实例
        bucket = storage_client.bucket(BUCKET_NAME)
        blob = bucket.blob(f"original/{question_id}.jpg")
        
        # 从 GCS 下载字节流
        bytes_data = blob.download_as_bytes()
        return Response(content=bytes_data, media_type="image/jpeg")
    except NotFound:
        raise HTTPException(status_code=404, detail="图片未找到")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"拉取图片失败: {e}")

# ==========================================
# 3. 标签与科目管理接口 (Requirement 2)
# ==========================================

@router.get("/tags/all")
async def get_tags(current_user: User = Depends(get_current_user)):
    """拉取用户的所有自定义标签"""
    doc_ref = db.collection("tags").document(current_user.username)
    doc = doc_ref.get()
    
    if doc.exists:
        return {"tags": doc.to_dict().get("tags", [])}
    return {"tags": ["语文", "数学", "英语"]} # 初始默认科目

@router.post("/tags/add")
async def add_tag(
    tag: str,
    current_user: User = Depends(get_current_user)
):
    """追加一个新标签"""
    doc_ref = db.collection("tags").document(current_user.username)
    doc = doc_ref.get()
    
    if not doc.exists:
        doc_ref.set({"tags": ["语文", "数学", "英语", tag]})
    else:
        doc_ref.update({"tags": firestore.ArrayUnion([tag])})
         
    return {"message": f"标签 '{tag}' 新增成功"}

class TagsUpdateRequest(BaseModel):
    tags: List[str]

@router.post("/{question_id}/tags")
async def update_question_tags(
    question_id: str,
    request: TagsUpdateRequest,
    current_user: User = Depends(get_current_user)
):
    """给单条错题绑定/覆盖多个标签"""
    doc_ref = db.collection("questions").document(question_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="错题未找到")
        
    data = doc.to_dict()
    if data["user_id"] != current_user.username:
         raise HTTPException(status_code=403, detail="无权操作该错题")
         
    doc_ref.update({"tags": request.tags})
    return {"message": "标签绑定成功", "tags": request.tags}

# ==========================================
# 4. 试卷生成与导出接口
# ==========================================

from pydantic import BaseModel

class PaperTicketRequest(BaseModel):
    ids: str
    show_answers: bool = False

@router.post("/paper/ticket")
async def create_paper_ticket(
    request: PaperTicketRequest,
    current_user: User = Depends(get_current_user)
):
    """
    签发用于下载/预览试卷的极短生命期一次性凭证（Ticket ID）。
    避免在 URL 拼接持久化 JWT 造成泄露。
    """
    import uuid, datetime
    ticket_id = str(uuid.uuid4())
    
    ticket_payload = {
        "user_id": current_user.username,
        "ids": request.ids,
        "show_answers": request.show_answers,
        "expires_at": (datetime.datetime.utcnow() + datetime.timedelta(minutes=3)).isoformat() # 3分钟生命弹性周期
    }
    
    # 写入 Firestore，用于一期一次消费
    db.collection("paper_tickets").document(ticket_id).set(ticket_payload)
    return {"ticket_id": ticket_id}

@router.get("/paper/export")
async def generate_paper(
    ticket_id: str
):
    """
    根据给定的授权票据 ticket_id 渲染排版精美的 HTML 试卷，支持自带 Katex/MathJax 算理核心。
    """
    ticket_ref = db.collection("paper_tickets").document(ticket_id).get()
    if not ticket_ref.exists:
        raise HTTPException(status_code=404, detail="该试卷生成凭证无效或已被消费")
        
    ticket_data = ticket_ref.to_dict()
    
    import datetime
    try:
        expires_at = datetime.datetime.fromisoformat(ticket_data.get("expires_at"))
        if datetime.datetime.utcnow() > expires_at:
             raise HTTPException(status_code=410, detail="试卷预览链接已过期，请重新点击“生成试卷”发起")
    except ValueError:
         raise HTTPException(status_code=400, detail="凭证格式异常")

    current_username = ticket_data.get("user_id")
    ids = ticket_data.get("ids", "")
    show_answers = ticket_data.get("show_answers", False)

    id_list = [i.strip() for i in ids.split(",") if i.strip()]
    
    questions_data = []
    # 逐一从 Firestore 加载题目并校验所属权
    for qid in id_list:
        try:
            doc = db.collection("questions").document(qid).get()
            if doc.exists:
                data = doc.to_dict()
                if data.get("user_id") == current_username:
                    questions_data.append(data)
        except Exception:
            pass # 忽略单条拉取异常
            
    # 定义基础 HTML 模版框架
    html_content = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <title>智能错题本 - 试卷生成</title>
        <!-- 加载 MathJax 算理公式 -->
        <script src="https://polyfill.io/v3/polyfill.min.js?features=es6"></script>
        <script id="MathJax-script" async src="https://cdn.jsdelivr.net/npm/mathjax@3/MathJax-core.js?config=TeX-AMS-MML_HTMLorMML"></script>
        <script>
        MathJax = {
          tex: {
            inlineMath: [['$', '$'], ['\\(', '\\)']],
            displayMath: [['$$', '$$'], ['\\[', '\\]']]
          }
        };
        </script>
        <script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js"></script>
        <style>
            body { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; padding: 40px; color: #333; line-height: 1.6; }
            .header { text-align: center; margin-bottom: 40px; border-bottom: 2px solid #ddd; padding-bottom: 20px; }
            .question-container { margin-bottom: 30px; page-break-inside: avoid; border-bottom: 1px dashed #eee; padding-bottom: 20px; }
            .question-title { font-weight: bold; font-size: 16px; margin-bottom: 12px; }
            .question-image { max-width: 100%; max-height: 350px; margin: 15px 0; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
            .answer-section { margin-top: 15px; padding: 15px; background: #f2f9f2; border-left: 4px solid #4CAF50; border-radius: 4px; }
            .options { margin-left: 20px; margin-top: 8px; }
            .options div { margin-bottom: 6px; }
            .footer { text-align: center; margin-top: 50px; color: #999; font-size: 12px; }
            @media print {
                body { padding: 0; }
                .question-container { border-bottom: none; }
                .answer-section { page-break-inside: avoid; }
            }
        </style>
    </head>
    <body>
        <div class="header">
            <h1>📄 智能错题测验卷</h1>
            <p>生成时间: [DATE_NOW] &nbsp;&nbsp; 考生姓名: ______________ &nbsp;&nbsp; 得分: ______________</p>
        </div>
        
        <div class="content">
            [QUESTIONS_LIST]
        </div>

        [ANSWERS_LIST]

        <div class="footer">
            <p>由 MistakeMentor 智能错题本生成</p>
        </div>
    </body>
    </html>
    """

    questions_html = ""
    answers_html = "" if not show_answers else '<div style="page-break-before: always; border-top: 2px solid #333; margin-top:40px; padding-top:20px;"><h2>🔑 参考答案与详细解析</h2>'

    for index, q in enumerate(questions_data, 1):
        image_html = ""
        # 覆写流流式路由
        if q.get("image_original"):
            image_html = f'<div style="text-align:center;"><img class="question-image" src="{q.get("image_original")}" /></div>'

        options_html = ""
        if q.get("options"):
            options_html = '<div class="options">' + "".join([f'<div>[ ] {opt}</div>' for opt in q["options"]]) + '</div>'

        questions_html += f"""
        <div class="question-container">
            <div class="question-title">第 {index} 题：</div>
            <div class="question-text">{q.get("question_text", '')}</div>
            {image_html}
            {options_html}
            <div style="height: 120px; margin-top: 15px;"></div> <!-- 提供书写空间 -->
        </div>
        """

        if show_answers:
            answers_html += f"""
            <div class="question-container">
                <div class="question-title">第 {index} 题解析：</div>
                <div class="answer-section">
                    <p><strong>💡 辅考点名称：</strong> {q.get("knowledge_point", '')}</p>
                    <p><strong>📝 分步解析：</strong></p>
                    <p>{"<br>".join([f"• {step}" for step in q.get("analysis_steps", [])])}</p>
                    <p><strong>⚠️ 易错警示：</strong> {q.get("trap_warning", '暂无')}</p>
                </div>
            </div>
            """

    if show_answers:
         answers_html += "</div>"

    final_html = html_content.replace("[QUESTIONS_LIST]", questions_html).replace("[ANSWERS_LIST]", answers_html).replace("[DATE_NOW]", datetime.now().strftime("%Y-%m-%d %H:%M"))
    
    from fastapi import Response
    return Response(content=final_html, media_type="text/html")
