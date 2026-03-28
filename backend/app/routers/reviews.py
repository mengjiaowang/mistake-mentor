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
    limit: int = Query(15, ge=1, le=50)
):
    """
    Fetch a batch of questions for review based on Priority:
    1. Overdue & Not Mastered
    2. Unreviewed (New questions)
    3. Overdue & Mastered (Maintenance)
    """
    questions_ref = db.collection("questions")
    now_iso = datetime.now(timezone(timedelta(hours=8))).isoformat()
    
    # Query 1: Unreviewed
    unrev_query = questions_ref.where(filter=FieldFilter("user_id", "==", current_user.username))\
                               .where(filter=FieldFilter("is_deleted", "==", False))\
                               .where(filter=FieldFilter("status", "==", "unreviewed"))\
                               .limit(limit)
    
    # Query 2: Due for review (next_review_date <= now)
    due_query = questions_ref.where(filter=FieldFilter("user_id", "==", current_user.username))\
                             .where(filter=FieldFilter("is_deleted", "==", False))\
                             .where(filter=FieldFilter("next_review_date", "<=", now_iso))\
                             .limit(limit)
                             
    unrev_docs = unrev_query.stream()
    due_docs = due_query.stream()
    
    results_map = {}
    
    for doc in due_docs:
        # Prioritize unmastered/blurry overdue over mastered
        data = doc.to_dict()
        score = 0
        if data.get("status") in ["unmastered", "blurry"]:
            score = 100 # Highest priority
        elif data.get("status") == "mastered":
            score = 10 # Lower priority maintenance
        results_map[data["id"]] = {"data": data, "score": score}
        
    for doc in unrev_docs:
        data = doc.to_dict()
        if data["id"] not in results_map:
            results_map[data["id"]] = {"data": data, "score": 50} # Medium priority
            
    # Sort by score descending
    sorted_items = sorted(results_map.values(), key=lambda x: x["score"], reverse=True)
    
    # Extract data and limit
    final_batch = [item["data"] for item in sorted_items[:limit]]
    
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
async def get_statistics(current_user: User = Depends(get_current_user)):
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
    # Format: {"SubjectName": {"mastered": X, "blurry": y, "unmastered": z}}
    subjects = {}
    
    # 3. Time Trends (activity by day for last 7 days)
    # Format: {"YYYY-MM-DD": count}
    activity = {}
    
    for doc in docs:
        data = doc.to_dict()
        status = data.get("status", "unreviewed")
        tags = data.get("tags", [])
        history = data.get("review_history", [])
        
        # Overview
        if status in overview:
            overview[status] += 1
        overview["total"] += 1
        
        # Breakdown by tags (assume primary subject is first tag or we count for all tags)
        # We will count primary tag (subject)
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
                
    # Format trends for the frontend explicitly
    # Only keep last 7 or 14 days of activity to keep payload small
    now = datetime.now(timezone(timedelta(hours=8)))
    recent_activity = []
    for i in range(7):
        d = (now - timedelta(days=6-i)).strftime("%Y-%m-%d")
        recent_activity.append({
            "date": d,
            "count": activity.get(d, 0)
        })

    return {
        "overview": overview,
        "subjects": subjects,
        "trends": recent_activity[::-1] # return chronological order
    }
