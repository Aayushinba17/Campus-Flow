import boto3
import uuid
from app.core.config import settings

def get_rekognition_client():
    # Rekognition is NOT available in ap-east-1 (Hong Kong).
    # Using ap-southeast-1 (Singapore) — the closest supported region.
    return boto3.client(
        "rekognition",
        region_name="ap-southeast-1",
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
    )

def get_s3_client():
    return boto3.client(
        "s3",
        region_name=settings.AWS_REGION,
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
    )


def upload_to_s3(file_bytes: bytes, filename: str, content_type: str = "image/jpeg") -> str:
    """
    Uploads file to S3, returns the S3 key.
    """
    s3 = get_s3_client()
    key = f"uploads/{uuid.uuid4()}/{filename}"
    s3.put_object(
        Bucket=settings.S3_BUCKET_NAME,
        Key=key,
        Body=file_bytes,
        ContentType=content_type,
    )
    return key


def extract_text_from_image(image_bytes: bytes) -> str:
    """
    Runs AWS Rekognition DetectText on image bytes.
    Returns all detected text joined as a single string.
    Free tier: 1,000 images/month.
    """
    rekognition = get_rekognition_client()
    response = rekognition.detect_text(
        Image={"Bytes": image_bytes}
    )
    # Filter to LINE detections only (cleaner than WORD-level)
    lines = [
        detection["DetectedText"]
        for detection in response["TextDetections"]
        if detection["Type"] == "LINE" and detection["Confidence"] > 70
    ]
    return "\n".join(lines)


def detect_text_in_image(image_bytes: bytes) -> str:
    """Alias for extract_text_from_image used by the notes router."""
    return extract_text_from_image(image_bytes)


def extract_text_from_s3_image(s3_key: str) -> str:
    """
    Runs Rekognition on an image already stored in S3.
    """
    rekognition = get_rekognition_client()
    response = rekognition.detect_text(
        Image={
            "S3Object": {
                "Bucket": settings.S3_BUCKET_NAME,
                "Name": s3_key,
            }
        }
    )
    lines = [
        d["DetectedText"]
        for d in response["TextDetections"]
        if d["Type"] == "LINE" and d["Confidence"] > 70
    ]
    return "\n".join(lines)