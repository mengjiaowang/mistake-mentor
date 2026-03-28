import os
import sys
import io
from google.cloud import firestore, storage
from PIL import Image

# 将 backend 路径注册入解析器
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'backend')))
from app.config import settings

def main():
    # 初始化
    db = firestore.Client(project=settings.PROJECT_ID)
    storage_client = storage.Client(project=settings.PROJECT_ID)
    bucket_name = f"{settings.PROJECT_ID}-images"
    bucket = storage_client.bucket(bucket_name)

    print(f"正在扫描项目: {settings.PROJECT_ID} 下的所有错题...")
    
    docs = db.collection("questions").stream()
    count = 0
    updated_count = 0

    for doc in docs:
        count += 1
        data = doc.to_dict()
        q_id = doc.id
        
        # 1. 检查是否存在缩略图字段
        image_thumbnail = data.get("image_thumbnail")
        if image_thumbnail and not image_thumbnail.endswith("image"): # 如果原本绑定了 original，我们强制重新刷一下
            continue
            
        print(f"发现缺失缩略图的题目ID: {q_id}")
        
        try:
            # 2. 从 GCS 下载原图
            blob_original = bucket.blob(f"original/{q_id}.jpg")
            if not blob_original.exists():
                print(f"  [跳过] GCS 中未找到原图 original/{q_id}.jpg")
                continue
                
            img_bytes = blob_original.download_as_bytes()
            
            # 3. 压缩生成缩略图
            img = Image.open(io.BytesIO(img_bytes))
            img.thumbnail((350, 350)) # 切块大小
            
            buf = io.BytesIO()
            img.save(buf, format='JPEG', quality=80) # 80% 画质高压缩
            thumb_bytes = buf.getvalue()
            
            # 4. 上传至缩略图专属桶文件夹
            blob_thumb = bucket.blob(f"thumbnail/{q_id}.jpg")
            blob_thumb.upload_from_string(thumb_bytes, content_type="image/jpeg")
            
            # 5. 更新库
            db.collection("questions").document(q_id).update({
                "image_thumbnail": f"/api/v1/questions/{q_id}/thumbnail"
            })
            
            updated_count += 1
            print(f"  [成功] 缩略图已生成并同步至 Firestore: {q_id}")
            
        except Exception as e:
            print(f"  [报错] 处理 {q_id} 时发生错误: {e}")

    print(f"\n执行完毕！共扫描 {count} 条数据，更新/修复了 {updated_count} 条。")

if __name__ == "__main__":
    main()
