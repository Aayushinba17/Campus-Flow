from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    # ── AI Provider ───────────────────────────────────────────────
    GEMINI_API_KEY: str = ""

    # AWS
    AWS_ACCESS_KEY_ID: str = ""
    AWS_SECRET_ACCESS_KEY: str = "" 
    AWS_REGION: str = "us-east-1"
    S3_BUCKET_NAME: str = "campusflow-files"
    DYNAMODB_TABLE_PREFIX: str = "campusflow"

    # App
    APP_ENV: str = "production"
    SECRET_KEY: str = ""
    MAX_NOTIFICATION_BATCH: int = 100
    DIGEST_HOUR: int = 8                     # 8 AM daily digest

    # Google Classroom OAuth
    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_SECRET: str = ""
    GOOGLE_REDIRECT_URI: str = "http://3.80.224.136:8001/api/classroom/oauth/callback"

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()