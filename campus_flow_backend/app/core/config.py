from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    # ── AI Provider ───────────────────────────────────────────────
    GEMINI_API_KEY: str = ""
    GEMINI_MODEL: str = "gemini-1.5-flash"
    EMBEDDING_MODEL: str = "all-MiniLM-L6-v2"

    # Thresholds
    AUTO_WRITE_THRESHOLD: float = 0.85
    ACTIVITY_FEED_THRESHOLD: float = 0.50
    OCR_CONFIDENCE_THRESHOLD: int = 70

    # AWS
    AWS_ACCESS_KEY_ID: str = ""
    AWS_SECRET_ACCESS_KEY: str = "" 
    AWS_REGION: str = "us-east-1"
    REKOGNITION_REGION: str = "us-east-1"
    S3_BUCKET_NAME: str = "campusflow-files"
    DYNAMODB_TABLE_PREFIX: str = "campusflow"

    # App
    APP_ENV: str = "production"
    SECRET_KEY: str = ""
    MAX_NOTIFICATION_BATCH: int = 100
    DIGEST_HOUR: int = 8                     # 8 AM daily digest
    SOCIAL_PACKAGES: list[str] = [
        "com.whatsapp",
        "org.telegram.messenger",
        "com.instagram.android",
        "com.snapchat.android",
        "com.twitter.android",
        "com.facebook.katana",
        "com.google.android.youtube",
        "com.zhiliaoapp.musically",
    ]

    # Google Classroom OAuth
    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_SECRET: str = ""
    GOOGLE_REDIRECT_URI: str = "http://3.80.224.136:8001/api/classroom/oauth/callback"

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()