from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    # Anthropic
    ANTHROPIC_API_KEY: str = ""
    CLAUDE_MODEL: str = "claude-sonnet-4-6"

    # AWS
    AWS_ACCESS_KEY_ID: str = ""
    AWS_SECRET_ACCESS_KEY: str = ""
    AWS_REGION: str = "ap-south-1"          # Mumbai — closest to India
    S3_BUCKET_NAME: str = "campusflow-files"
    DYNAMODB_TABLE_PREFIX: str = "campusflow"

    # App
    APP_ENV: str = "production"
    SECRET_KEY: str = "change-this-in-production"
    MAX_NOTIFICATION_BATCH: int = 100
    DIGEST_HOUR: int = 8                     # 8 AM daily digest

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()