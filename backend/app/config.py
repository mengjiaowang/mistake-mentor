from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional

class Settings(BaseSettings):
    # GCP Configuration
    PROJECT_ID: str = "learning-assistant-490905"
    
    # Model Names
    ERASURE_MODEL: str = "gemini-3.1-flash-image-preview"
    OCR_MODEL: str = "gemini-3.1-pro-preview"
    
    # Backend Security
    SECRET_KEY: str = "SUPER_SECRET_KEY_FOR_DEMO_PURPOSES"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440  # 24 hours
    ADMIN_PASSWORD: str = "admin123" # 默认初始密码

    # 允许从环境变量加载，默认优先读取 .env 文件
    model_config = SettingsConfigDict(
        env_file=(".env", "../.env"), 
        env_file_encoding="utf-8",
        extra="ignore" # 忽略额外的环境变量
    )

settings = Settings()
