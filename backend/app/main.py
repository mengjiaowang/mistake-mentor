from datetime import datetime, timedelta
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel

from app.config import settings

# ==========================================
# 1. 基础配置 (自用版可写在代码中，生产建议点.env)
# ==========================================
SECRET_KEY = settings.SECRET_KEY
ALGORITHM = settings.ALGORITHM
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES

# ==========================================
# 2. 安全与密码哈希模块
# ==========================================
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    return pwd_context.hash(password)

# ==========================================
# 3. 极简本地 mock 数据库 (初始化一个 admin 账号)
# ==========================================
# 这里的 "admin" 账号对应的密码是从 settings 获取的
DEFAULT_HASHED_PASS = get_password_hash(settings.ADMIN_PASSWORD)

fake_users_db = {
    "admin": {
        "username": "admin",
        "full_name": "管理员",
        "hashed_password": DEFAULT_HASHED_PASS,
        "disabled": False,
    }
}

# ==========================================
# 4. Pydantic 模型
# ==========================================
class User(BaseModel):
    username: str
    full_name: Optional[str] = None
    disabled: Optional[bool] = None

class Token(BaseModel):
    access_token: str
    token_type: str

# ==========================================
# 5. JWT 生成与验证工具
# ==========================================
def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
    user = fake_users_db.get(username)
    if user is None:
        raise credentials_exception
    return User(**user)

# ==========================================
# 6. FastAPI 主实例与接口
# ==========================================
app = FastAPI(
    title="智能错题本 (MistakeMentor) Backend",
    description="家庭/自用版极简后端架构 (基于 FastAPI)",
    version="1.0"
)

# ---- 添加 CORS 跨域支持 ----
from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # 允许所有来源（自用/测试环境）
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

from app.routers import questions
app.include_router(questions.router)

@app.get("/health", tags=["System"])
async def health_check():
    """Cloud Run 健康检查端点"""
    return {"status": "ok", "message": "Backend is running"}

@app.post("/api/v1/auth/login", response_model=Token, tags=["Auth"])
async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends()):
    """标准 OAuth2 兼容登录接口，验证账密并签发 JWT"""
    user = fake_users_db.get(form_data.username)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="用户名或密码不正确",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not verify_password(form_data.password, user["hashed_password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="用户名或密码不正确",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user["username"]}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}

@app.get("/api/v1/users/me", response_model=User, tags=["Users"])
async def read_users_me(current_user: User = Depends(get_current_user)):
    """测试接口：获取当前登录用户信息 (需要带上 Auth Token)"""
    return current_user
