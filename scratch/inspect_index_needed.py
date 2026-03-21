import os
import sys
from google.cloud import firestore

# 假设运行在项目根目录，将 backend 放入 sys.path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), 'backend')))
from app.config import settings

def main():
    db = firestore.Client(project=settings.PROJECT_ID)
    try:
        print(f"Testing questions query on project: {settings.PROJECT_ID}...")
        query = db.collection("questions")\
                  .where("user_id", "==", "admin")\
                  .where("is_deleted", "==", False)\
                  .order_by("created_at", direction=firestore.Query.DESCENDING)\
                  .limit(10)
        
        docs = query.stream()
        for doc in docs:
             pass
        print("Success: Index is already created and fully active!")
    except Exception as e:
        print("\n=== Firestore Index Error Caught ===")
        print(e)

if __name__ == "__main__":
    main()
