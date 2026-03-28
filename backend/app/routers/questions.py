import uuid
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, File, UploadFile, HTTPException, Form, BackgroundTasks
from google.cloud import firestore, storage
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import BaseModel

from app.services.gcp_ai_service import ai_service
from app.main import get_current_user, User # 依赖认证

router = APIRouter(
    prefix="/api/v1/questions",
    tags=["Questions"]
)

from app.config import settings

# 初始化 GCP 客户端
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

# 错题管理接口端点

async def _process_question_background(question_uuid: str, contents: bytes, username: str):
    """后台任务：处理 AI 全图擦除、Gemini OCR 解析、图表切片去手写，并更新 Firestore"""
    print(f"[Background] 开始异步处理题目 {question_uuid} ...")
    
    url_original = f"/api/v1/questions/{question_uuid}/image" 
    url_blank = url_original # 兜底

    # [Step 1] 全图擦除手写并存入 GCS
    try:
        print("[Background] 正在执行全图抹除手写...")
        clean_full_bytes = ai_service.remove_handwriting(contents)
        upload_to_gcs(clean_full_bytes, f"blank/{question_uuid}.jpg")
        url_blank = f"/api/v1/questions/{question_uuid}/blank"
    except Exception as e:
         print(f"[Warning Background] 全图去手写失败，降级为原图: {e}")

    # [Step 2] Gemini 推理 & 结构化解析 (抓取标签库作为 AI 参照)
    existing_tags = []
    try:
        tags_doc = db.collection("tags").document(username).get()
        if tags_doc.exists:
            existing_tags = tags_doc.to_dict().get("tags", [])
    except Exception:
        pass
    if not existing_tags:
        existing_tags = ["语文", "数学", "英语", "物理", "化学"]

    try:
        ai_result = ai_service.ocr_and_analyze(contents, existing_tags=existing_tags)
    except Exception as e:
        print(f"[Error Background] Gemini 解析失败: {e}")
        ai_result = {"question_text": "解析失败，请检查图像清晰度或稍后重试。"}

    # --- 智能图表提取 + 局部去手写流水线 ---
    diagram_bbox = ai_result.get("diagram_bbox")
    url_diagram_clean = None
    if diagram_bbox and isinstance(diagram_bbox, list) and len(diagram_bbox) == 4:
         try:
              from PIL import Image
              import io
              orig_img = Image.open(io.BytesIO(contents))
              W, H = orig_img.size
              ymin, xmin, ymax, xmax = diagram_bbox
              left = int(max(0.0, min(1.0, xmin)) * W)
              top = int(max(0.0, min(1.0, ymin)) * H)
              right = int(max(0.0, min(1.0, xmax)) * W)
              bottom = int(max(0.0, min(1.0, ymax)) * H)
              
              if right > left + 5 and bottom > top + 5:
                   cropped_img = orig_img.crop((left, top, right, bottom))
                   crop_buf = io.BytesIO()
                   cropped_img.save(crop_buf, format='JPEG', quality=95, subsampling=0)
                   cropped_bytes = crop_buf.getvalue()
                   
                   clean_bytes = ai_service.remove_handwriting(cropped_bytes)
                   upload_to_gcs(clean_bytes, f"diagram/{question_uuid}.jpg")
                   url_diagram_clean = f"/api/v1/questions/{question_uuid}/diagram"
         except Exception as e:
              print(f"[Warning Background] BBox 图象切片与去手写失败: {e}")

    # [Step 3] 复写更新 Firestore 结果并翻转 status 为 unreviewed
    updated_fields = {
        "image_blank": url_blank,
        "image_diagram_clean": url_diagram_clean,
        "question_text": ai_result.get("question_text", "无法提取题目，请重试。"),
        "options": ai_result.get("options"),
        "knowledge_point": ai_result.get("knowledge_point", "未对齐考点"),
        "analysis_steps": ai_result.get("analysis_steps", []),
        "trap_warning": ai_result.get("trap_warning", ""),
        "similar_question": ai_result.get("similar_question"),
        "status": "unreviewed",
        "tags": ai_result.get("suggested_tags", []),
    }
    
    db.collection("questions").document(question_uuid).update(updated_fields)
    print(f"[Background] 题目 {question_uuid} 异步解析履约完成。")


@router.post("/upload")
async def upload_question(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    mirror: bool = Form(False),
    rotate_degrees: int = Form(0), 
    crop_left: float = Form(0.0),
    crop_top: float = Form(0.0),
    crop_width: float = Form(1.0),
    crop_height: float = Form(1.0),
    current_user: User = Depends(get_current_user)
):
    """
    1. 上传图片 (秒级物理归档)
    2. 下推 BackgroundTasks 异步跑大模型多模态
    3. 快速返还 processing 状态给前端
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
                img = img.transpose(Image.ROTATE_270)
            elif rotate_degrees == 180:
                img = img.transpose(Image.ROTATE_180)
            elif rotate_degrees == 270:
                img = img.transpose(Image.ROTATE_90)
                
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
            img.save(buf, format=img.format or 'JPEG', quality=95, subsampling=0)
            contents = buf.getvalue()
        except Exception as e:
            print(f"[Warning] 图片处理（镜像/旋转/裁剪）失败: {e}")

    question_uuid = str(uuid.uuid4())
    
    # [Step 1] 存入 GCS (秒级保存处理后的原图)
    try:
        upload_to_gcs(contents, f"original/{question_uuid}.jpg")
        url_original = f"/api/v1/questions/{question_uuid}/image" 
    except Exception as e:
         print(f"[Warning] GCS 上传原图失败，降级使用本地 Mock：{e}")
         url_original = "http://placeholder.org/original.jpg"

    # [Step 1.5] 生成并上传缩略图 (同步处理，极快位图)
    url_thumbnail = url_original # 兜底
    try:
        from PIL import Image
        import io
        img = Image.open(io.BytesIO(contents))
        img.thumbnail((350, 350)) # 缩短长边至 350，适配标准移动列表
        buf = io.BytesIO()
        img.save(buf, format='JPEG', quality=80) 
        thumb_bytes = buf.getvalue()
        upload_to_gcs(thumb_bytes, f"thumbnail/{question_uuid}.jpg")
        url_thumbnail = f"/api/v1/questions/{question_uuid}/thumbnail"
    except Exception as e:
         print(f"[Warning] 生成缩略图失败，降级使用原图：{e}")

    # [Step 2] 往 Firestore 插入骨架数据（带友情提示占位，防前端白屏或崩溃）
    init_doc = {
        "id": question_uuid,
        "user_id": current_user.username,
        "image_original": url_original,
        "image_thumbnail": url_thumbnail,
        "image_blank": url_original, # 临时复用原图，等擦除完后覆写
        "image_diagram_clean": None,
        "question_text": "📄 题目正在后台 AI 解析中，请稍候...",
        "options": [],
        "knowledge_point": "自动考点解析中...",
        "analysis_steps": ["系统正在努力为您分步解析题意..."],
        "trap_warning": "⚠️ 易错点提取中...",
        "similar_question": None,
        "status": "processing", # 特殊状态
        "next_review_date": datetime.now(timezone(timedelta(hours=8))).isoformat(),
        "current_interval": 1,
        "review_history": [],
        "is_deleted": False,
        "tags": [],
        "created_at": datetime.now(timezone(timedelta(hours=8))).isoformat()
    }
    
    db.collection("questions").document(question_uuid).set(init_doc)

    # [Step 3] 提交给 FastAPI 异步线程池跑重度 OCR 和毛玻璃
    background_tasks.add_task(_process_question_background, question_uuid, contents, current_user.username)
    
    return {"message": "错题已提交，AI 正在后台解析中，您可以继续其他操作...", "data": init_doc}

@router.get("/")
async def list_questions(
    current_user: User = Depends(get_current_user),
    knowledge_point: Optional[str] = None,
    tag: Optional[str] = None, # 新增：支持标签过滤
    is_deleted: bool = False, # 新增：默认不查询回收站
    limit: int = 24, # 新增：分页大小
    offset: int = 0  # 新增：偏移量
):
    """获取错题列表，支持分页、考点及标签筛选"""
    query = db.collection("questions")\
              .where(filter=FieldFilter("user_id", "==", current_user.username))\
              .where(filter=FieldFilter("is_deleted", "==", is_deleted))
              
    if knowledge_point:
        query = query.where(filter=FieldFilter("knowledge_point", "==", knowledge_point))
    
    if tag:
        # 使用全量查询然后在内存排序和截断，避免强制要求复合索引
        query = query.where(filter=FieldFilter("tags", "array_contains", tag))
        docs = query.stream()
        result = [doc.to_dict() for doc in docs]
        result.sort(key=lambda x: x.get("created_at", ""), reverse=True)
        return {"questions": result[offset:offset+limit]}
    else:
        # 原有逻辑：由 Firestore 排序截断 (已建立了对应索引)
        docs = query.order_by("created_at", direction=firestore.Query.DESCENDING)\
                    .offset(offset)\
                    .limit(limit)\
                    .stream()
        result = [doc.to_dict() for doc in docs]
        return {"questions": result}

@router.get("/tts")
async def get_tts(
    ticket_id: str
):
    """
    根据 Ticket ID 调用 Google Cloud TTS 并流式返回 MP3
    """
    ticket_ref = db.collection("tts_tickets").document(ticket_id).get()
    if not ticket_ref.exists:
        raise HTTPException(status_code=404, detail="该凭证无效或已被消费")
    ticket_data = ticket_ref.to_dict()
    
    import datetime
    try:
        expires_at = datetime.datetime.fromisoformat(ticket_data.get("expires_at"))
        if datetime.datetime.utcnow() > expires_at:
            raise HTTPException(status_code=410, detail="该凭证已过期，请重新播报")
    except ValueError:
        raise HTTPException(status_code=400, detail="凭证格式异常")
        
    question_id = ticket_data.get("question_id")
    doc = db.collection("questions").document(question_id).get()
    if not doc.exists:
         raise HTTPException(status_code=404, detail="错题未找到")
    q = doc.to_dict()
    
    # 拼接文本：解析步骤 + 易错点
    steps = q.get("analysis_steps", [])
    trap = q.get("trap_warning", "")
    
    # 移除 LaTeX 符号 $ 防止 TTS 发出奇怪的声音
    def clean_text(text):
         if not text: return ""
         return text.replace("$", "")
         
    text_to_speak = "下面是这道题的分步解析。"
    if steps:
        for i, step in enumerate(steps, 1):
            text_to_speak += f"第 {i} 步：{clean_text(step)}。"
    else:
        text_to_speak += "暂无分步解析。"
        
    if trap:
        text_to_speak += f"易错警示：{clean_text(trap)}。"
        
    # 调用 Google Cloud TTS API
    from google.cloud import texttospeech
    try:
        client = texttospeech.TextToSpeechClient()
        synthesis_input = texttospeech.SynthesisInput(text=text_to_speak)
        voice = texttospeech.VoiceSelectionParams(
            language_code="cmn-CN",
            name="cmn-CN-Standard-A"  # 标准女声
        )

        audio_config = texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.MP3
        )
        response = client.synthesize_speech(
            input=synthesis_input, voice=voice, audio_config=audio_config
        )
        # 单次消费 ticket
        db.collection("tts_tickets").document(ticket_id).delete()
        return Response(content=response.audio_content, media_type="audio/mpeg")
    except Exception as e:
         # 容错：即使 TTS 失败清理 ticket 防止堆积
         db.collection("tts_tickets").document(ticket_id).delete()
         raise HTTPException(status_code=500, detail=f"TTS 生成异常: {e}")

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

@router.get("/{question_id}/blank")
async def get_question_blank(question_id: str):
    """流式代理拉取 GCS 上的擦除后图片"""
    try:
        bucket = storage_client.bucket(BUCKET_NAME)
        blob = bucket.blob(f"blank/{question_id}.jpg")
        bytes_data = blob.download_as_bytes()
        return Response(content=bytes_data, media_type="image/jpeg")
    except NotFound:
        # 降级：如果 blank 不存在，尝试返回 original
        try:
            bucket = storage_client.bucket(BUCKET_NAME)
            blob = bucket.blob(f"original/{question_id}.jpg")
            bytes_data = blob.download_as_bytes()
            return Response(content=bytes_data, media_type="image/jpeg")
        except:
             raise HTTPException(status_code=404, detail="图片未找到")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"拉取擦除图片失败: {e}")

@router.get("/{question_id}/thumbnail")
async def get_question_thumbnail(question_id: str):
    """流式代理拉取 GCS 上的压缩缩略图并直接回传给前端"""
    try:
        bucket = storage_client.bucket(BUCKET_NAME)
        blob = bucket.blob(f"thumbnail/{question_id}.jpg")
        bytes_data = blob.download_as_bytes()
        return Response(content=bytes_data, media_type="image/jpeg")
    except NotFound:
        # 降级：如果 thumbnail 不存在，尝试返回 original
        try:
            bucket = storage_client.bucket(BUCKET_NAME)
            blob = bucket.blob(f"original/{question_id}.jpg")
            bytes_data = blob.download_as_bytes()
            return Response(content=bytes_data, media_type="image/jpeg")
        except:
             raise HTTPException(status_code=404, detail="图片未找到")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"拉取缩略图失败: {e}")

async def _do_regenerate_erasure(question_id: str):
    """后台执行擦除图重新生成"""
    try:
        doc_ref = db.collection("questions").document(question_id)
        
        # 获取原图
        bucket = storage_client.bucket(BUCKET_NAME)
        blob_original = bucket.blob(f"original/{question_id}.jpg")
        image_bytes = blob_original.download_as_bytes()
        
        # 重新调用擦除服务
        clean_bytes = ai_service.remove_handwriting(image_bytes)
        
        # 保存覆盖 blank
        blob_blank = bucket.blob(f"blank/{question_id}.jpg")
        blob_blank.upload_from_string(clean_bytes, content_type="image/jpeg")
        
        # 更新 Firestore 带上缓存穿透参数
        timestamp = int(datetime.utcnow().timestamp())
        new_url = f"/api/v1/questions/{question_id}/blank?t={timestamp}"
        doc_ref.update({"image_blank": new_url})
        print(f"[Success] Background regeneration complete for {question_id}")
    except Exception as e:
        print(f"[Error] Background regeneration failed for {question_id}: {e}")

@router.post("/{question_id}/regenerate-erasure")
async def regenerate_erasure(
    question_id: str,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user)
):
    """重新生成该题目的擦除图"""
    doc_ref = db.collection("questions").document(question_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="错题未找到")
    
    data = doc.to_dict()
    if data["user_id"] != current_user.username:
        raise HTTPException(status_code=403, detail="无权操作该错题")
    
    # 将任务提交给后台执行
    background_tasks.add_task(_do_regenerate_erasure, question_id)
    
    return {"message": "擦除图重新生成任务已提交，将在后台异步执行。请稍后刷新查看最新结果。"}



@router.get("/{question_id}/diagram")
async def get_question_diagram(question_id: str):
    """流式代理插图拉取去手写干净配图"""
    try:
        bucket = storage_client.bucket(BUCKET_NAME)
        # 从 diagram/ 路径加载
        blob = bucket.blob(f"diagram/{question_id}.jpg")
        bytes_data = blob.download_as_bytes()
        return Response(content=bytes_data, media_type="image/jpeg")
    except NotFound:
        raise HTTPException(status_code=404, detail="插图未找到")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"拉取插图失败: {e}")

# 标签与科目管理

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

# 批量管理

class BatchRequest(BaseModel):
    ids: List[str]

@router.post("/batch/restore")
async def batch_restore_questions(
    request: BatchRequest,
    current_user: User = Depends(get_current_user)
):
    """批量从回收站恢复错题"""
    batch = db.batch()
    # 分片处理，Firestore 'in' 查询限制单次最多 30 个项目
    chunks = [request.ids[i:i + 30] for i in range(0, len(request.ids), 30)]
    count = 0
    for chunk in chunks:
        docs = db.collection("questions").where(filter=FieldFilter("user_id", "==", current_user.username)).where(filter=FieldFilter("id", "in", chunk)).stream()
        for doc in docs:
            batch.update(doc.reference, {"is_deleted": False})
            count += 1
    batch.commit()
    return {"message": f"成功恢复 {count} 道错题 到错题本"}

@router.post("/batch/permanent")
async def batch_permanent_delete_questions(
    request: BatchRequest,
    current_user: User = Depends(get_current_user)
):
    """批量永久删除回收站错题 (不可逆)"""
    batch = db.batch()
    chunks = [request.ids[i:i + 30] for i in range(0, len(request.ids), 30)]
    count = 0
    for chunk in chunks:
        docs = db.collection("questions").where(filter=FieldFilter("user_id", "==", current_user.username)).where(filter=FieldFilter("id", "in", chunk)).stream()
        for doc in docs:
            batch.delete(doc.reference)
            count += 1
    batch.commit()
    return {"message": f"成功永久删除 {count} 道错题"}

# TTS 语音接口

from fastapi.responses import Response

@router.post("/{question_id}/tts/ticket")
async def create_tts_ticket(
    question_id: str,
    current_user: User = Depends(get_current_user)
):
    """
    签发用于播放 TTS 的极短生命期一次性凭证（Ticket ID）。
    """
    import uuid, datetime
    # 验证 question_id 所属权
    doc_ref = db.collection("questions").document(question_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="错题未找到")
    data = doc.to_dict()
    if data["user_id"] != current_user.username:
        raise HTTPException(status_code=403, detail="无权操作该错题")
        
    ticket_id = str(uuid.uuid4())
    ticket_payload = {
        "user_id": current_user.username,
        "question_id": question_id,
        "expires_at": (datetime.datetime.utcnow() + datetime.timedelta(minutes=3)).isoformat()
    }
    db.collection("tts_tickets").document(ticket_id).set(ticket_payload)
    return {"ticket_id": ticket_id}


# 试卷生成与导出接口

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
        # 生成的题目不附带原图照片，保持干净文本版式

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

    final_html = html_content.replace("[QUESTIONS_LIST]", questions_html).replace("[ANSWERS_LIST]", answers_html).replace("[DATE_NOW]", datetime.datetime.now().strftime("%Y-%m-%d %H:%M"))
    
    from fastapi import Response
    return Response(content=final_html, media_type="text/html")
