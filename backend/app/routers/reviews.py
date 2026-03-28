import uuid
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import BaseModel

from app.main import get_current_user, User
from app.config import settings

router = APIRouter(
    prefix="/api/v1/reviews",
    tags=["Reviews"]
)

PROJECT_ID = settings.PROJECT_ID
db = firestore.Client(project=PROJECT_ID)

# Interval logic based on SM-2 simplified
INTERVALS = [1, 2, 4, 7, 15, 30, 60]

@router.get("/batch")
async def get_review_batch(
    current_user: User = Depends(get_current_user),
    subjects: Optional[List[str]] = Query(None), # 允许用户多选科目
    limit: int = Query(15, ge=1, le=50)
):
    """
    Fetch a batch of questions for review based on Priority:
    1. Overdue & Not Mastered
    2. Unreviewed (New questions)
    3. Overdue & Mastered (Maintenance)
    If subjects are specified, fetch per subject (at most limit per subject) and combine.
    """
    questions_ref = db.collection("questions")
    now_iso = datetime.now(timezone(timedelta(hours=8))).isoformat()
    
    results_map = {}
    
    targets = subjects if subjects and len(subjects) > 0 else [None]

    for subj in targets:
        # 查新题
        unrev_query = questions_ref.where(filter=FieldFilter("user_id", "==", current_user.username))\
                                   .where(filter=FieldFilter("is_deleted", "==", False))\
                                   .where(filter=FieldFilter("status", "==", "unreviewed"))
        if subj:
            unrev_query = unrev_query.where(filter=FieldFilter("tags", "array_contains", subj))
        unrev_query = unrev_query.limit(limit)

        # 查到期题
        due_query = questions_ref.where(filter=FieldFilter("user_id", "==", current_user.username))\
                                 .where(filter=FieldFilter("is_deleted", "==", False))\
                                 .where(filter=FieldFilter("next_review_date", "<=", now_iso))
        if subj:
            due_query = due_query.where(filter=FieldFilter("tags", "array_contains", subj))
        due_query = due_query.limit(limit)

        unrev_docs = unrev_query.stream()
        due_docs = due_query.stream()

        for doc in due_docs:
            data = doc.to_dict()
            score = 0
            if data.get("status") in ["unmastered", "blurry"]:
                score = 100
            elif data.get("status") == "mastered":
                score = 10
            
            if data["id"] not in results_map or score > results_map[data["id"]]["score"]:
                results_map[data["id"]] = {"data": data, "score": score}

        for doc in unrev_docs:
            data = doc.to_dict()
            if data["id"] not in results_map:
                results_map[data["id"]] = {"data": data, "score": 50}

    # 按权重排序
    sorted_items = sorted(results_map.values(), key=lambda x: x["score"], reverse=True)
    
    # 如果指定了具体科目，返回合集（每门限额由拉取控制）；如果是通用，维持老 limit 全局截断
    actual_limit = limit * len(targets) if subjects else limit
    final_batch = [item["data"] for item in sorted_items[:actual_limit]]
    
    return {"questions": final_batch}

@router.get("/free")
async def get_free_batch(
    current_user: User = Depends(get_current_user),
    subjects: Optional[List[str]] = Query(None),
    limit: int = Query(50, ge=1, le=100) # 限额切片下发以防卡顿
):
    """
    获取自由练习题目：排除掉已完全掌握(mastered)的题目，支持科目多选。
    """
    questions_ref = db.collection("questions")
    
    query = questions_ref.where(filter=FieldFilter("user_id", "==", current_user.username))\
                         .where(filter=FieldFilter("is_deleted", "==", False))
                         
    if subjects and len(subjects) > 0:
        query = query.where(filter=FieldFilter("tags", "array_contains_any", subjects))
        
    query = query.limit(limit * 2) # 多拉一些用于 Python 过滤

    docs = query.stream()
    
    final_batch = []
    for doc in docs:
        data = doc.to_dict()
        if data.get("status") != "mastered":
            final_batch.append(data)
        if len(final_batch) >= limit:
            break
            
    return {"questions": final_batch}

class ReviewFeedback(BaseModel):
    feedback: str # 'mastered', 'blurry', 'unmastered'
    
@router.post("/{question_id}")
async def submit_review(
    question_id: str,
    payload: ReviewFeedback,
    current_user: User = Depends(get_current_user)
):
    """
    Submit a review result and calculate the next review interval.
    """
    doc_ref = db.collection("questions").document(question_id)
    doc = doc_ref.get()
    
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Question not found")
        
    data = doc.to_dict()
    if data.get("user_id") != current_user.username:
        raise HTTPException(status_code=403, detail="Forbidden")
        
    current_interval_index = data.get("current_interval", 1) - 1 # 0-indexed internally
    if current_interval_index < 0:
        current_interval_index = 0
        
    feedback = payload.feedback
    if feedback not in ["mastered", "blurry", "unmastered"]:
        raise HTTPException(status_code=400, detail="Invalid feedback type")
        
    next_interval_days = 1
    
    if feedback == "mastered":
        # Move up in the interval sequence
        current_interval_index += 1
        if current_interval_index >= len(INTERVALS):
            current_interval_index = len(INTERVALS) - 1
        next_interval_days = INTERVALS[current_interval_index]
    elif feedback == "blurry":
        # Keep current interval or slightly step down
        next_interval_days = INTERVALS[current_interval_index]
    elif feedback == "unmastered":
        # Reset back to start
        current_interval_index = 0
        next_interval_days = INTERVALS[0]
        
    now = datetime.now(timezone(timedelta(hours=8)))
    next_review_date = (now + timedelta(days=next_interval_days)).isoformat()
    now_iso = now.isoformat()
    
    history_entry = {
        "timestamp": now_iso,
        "feedback": feedback
    }
    
    update_data = {
        "status": feedback,
        "current_interval": current_interval_index + 1, # Store 1-indexed to match logic conceptually
        "next_review_date": next_review_date,
        "review_history": firestore.ArrayUnion([history_entry])
    }
    
    doc_ref.update(update_data)
    
    return {
        "message": "Review recorded successfully",
        "next_review_date": next_review_date,
        "new_status": feedback
    }

@router.get("/statistics")
async def get_statistics(
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    current_user: User = Depends(get_current_user)
):
    """
    Get aggregation statistics for dashboard
    """
    questions_ref = db.collection("questions")
    docs = questions_ref.where(filter=FieldFilter("user_id", "==", current_user.username))\
                        .where(filter=FieldFilter("is_deleted", "==", False))\
                        .stream()
                        
    # 1. Overview stats
    overview = {
        "unreviewed": 0,
        "mastered": 0,
        "blurry": 0,
        "unmastered": 0,
        "total": 0
    }
    
    # 2. Subject Breakdown
    subjects = {}
    
    # 3. Time Trends (activity by day)
    activity = {}
    
    for doc in docs:
        data = doc.to_dict()
        created_at = data.get("created_at", "")
        
        # Filter by creation date if requested
        if start_date and created_at < start_date:
            continue
        if end_date and created_at > end_date:
            continue
            
        status = data.get("status", "unreviewed")
        tags = data.get("tags", [])
        history = data.get("review_history", [])
        
        # Overview
        if status in overview:
            overview[status] += 1
        overview["total"] += 1
        
        # Breakdown by tags
        primary_tag = tags[0] if tags else "未分类"
        if primary_tag not in subjects:
            subjects[primary_tag] = {"mastered": 0, "blurry": 0, "unmastered": 0}
        
        if status in subjects[primary_tag]:
            subjects[primary_tag][status] += 1
            
        # Activity trend
        for entry in history:
            timestamp = entry.get("timestamp")
            if timestamp:
                day_str = timestamp[:10] # YYYY-MM-DD
                activity[day_str] = activity.get(day_str, 0) + 1
                
    # Format trends for the frontend dynamically
    now = datetime.now(timezone(timedelta(hours=8)))
    
    delta = 7
    base_date = now
    
    if start_date and end_date:
        try:
            # Parse dates to calculate delta
            # Assuming 'Z' or standard ISO format from frontend
            s_dt = datetime.fromisoformat(start_date.split('T')[0])
            e_dt = datetime.fromisoformat(end_date.split('T')[0])
            delta = (e_dt - s_dt).days + 1
            if delta <= 0:
                delta = 1
            if delta > 90: # Cap at 90 days for performance
                delta = 90
            base_date = e_dt
        except Exception as e:
            # Fallback to 7 days
            delta = 7
            base_date = now

    # If base_date is in the future relative to now, we might want to cap it.
    if base_date > now:
        base_date = now

    recent_activity = []
    for i in range(delta):
        d = (base_date - timedelta(days=delta-1-i)).strftime("%Y-%m-%d")
        recent_activity.append({
            "date": d,
            "count": activity.get(d, 0)
        })

    return {
        "overview": overview,
        "subjects": subjects,
        "trends": recent_activity[::-1] # return chronological order
    }
