import boto3
import asyncio
from app.core.config import settings

_dynamodb = None

def get_dynamodb():
    global _dynamodb
    if _dynamodb is None:
        _dynamodb = boto3.resource(
            "dynamodb",
            region_name=settings.AWS_REGION,
            aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
            aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
        )
    return _dynamodb

def get_table(table_name: str):
    db = get_dynamodb()
    return db.Table(f"{settings.DYNAMODB_TABLE_PREFIX}_{table_name}")

# ── Table definitions ────────────────────────────────────────────────────────

TABLES = [
    {
        "TableName": f"{settings.DYNAMODB_TABLE_PREFIX}_notifications",
        "KeySchema": [
            {"AttributeName": "user_id",       "KeyType": "HASH"},
            {"AttributeName": "notification_id","KeyType": "RANGE"},
        ],
        "AttributeDefinitions": [
            {"AttributeName": "user_id",        "AttributeType": "S"},
            {"AttributeName": "notification_id","AttributeType": "S"},
        ],
        "BillingMode": "PAY_PER_REQUEST",
    },
    {
        "TableName": f"{settings.DYNAMODB_TABLE_PREFIX}_schedules",
        "KeySchema": [
            {"AttributeName": "user_id", "KeyType": "HASH"},
            {"AttributeName": "item_id", "KeyType": "RANGE"},
        ],
        "AttributeDefinitions": [
            {"AttributeName": "user_id", "AttributeType": "S"},
            {"AttributeName": "item_id", "AttributeType": "S"},
        ],
        "BillingMode": "PAY_PER_REQUEST",
    },
    {
        "TableName": f"{settings.DYNAMODB_TABLE_PREFIX}_tasks",
        "KeySchema": [
            {"AttributeName": "user_id", "KeyType": "HASH"},
            {"AttributeName": "task_id", "KeyType": "RANGE"},
        ],
        "AttributeDefinitions": [
            {"AttributeName": "user_id", "AttributeType": "S"},
            {"AttributeName": "task_id", "AttributeType": "S"},
        ],
        "BillingMode": "PAY_PER_REQUEST",
    },
    {
        "TableName": f"{settings.DYNAMODB_TABLE_PREFIX}_routine_logs",
        "KeySchema": [
            {"AttributeName": "user_id",   "KeyType": "HASH"},
            {"AttributeName": "log_id",    "KeyType": "RANGE"},
        ],
        "AttributeDefinitions": [
            {"AttributeName": "user_id",   "AttributeType": "S"},
            {"AttributeName": "log_id",    "AttributeType": "S"},
        ],
        "BillingMode": "PAY_PER_REQUEST",
    },
    {
        "TableName": f"{settings.DYNAMODB_TABLE_PREFIX}_notes",
        "KeySchema": [
            {"AttributeName": "user_id",  "KeyType": "HASH"},
            {"AttributeName": "note_id",  "KeyType": "RANGE"},
        ],
        "AttributeDefinitions": [
            {"AttributeName": "user_id",  "AttributeType": "S"},
            {"AttributeName": "note_id",  "AttributeType": "S"},
        ],
        "BillingMode": "PAY_PER_REQUEST",
    },
    {
        "TableName": f"{settings.DYNAMODB_TABLE_PREFIX}_wellness",
        "KeySchema": [
            {"AttributeName": "user_id",  "KeyType": "HASH"},
            {"AttributeName": "date",     "KeyType": "RANGE"},
        ],
        "AttributeDefinitions": [
            {"AttributeName": "user_id",  "AttributeType": "S"},
            {"AttributeName": "date",     "AttributeType": "S"},
        ],
        "BillingMode": "PAY_PER_REQUEST",
    },
    {
        "TableName": f"{settings.DYNAMODB_TABLE_PREFIX}_chat_history",
        "KeySchema": [
            {"AttributeName": "user_id",  "KeyType": "HASH"},
            {"AttributeName": "msg_id",   "KeyType": "RANGE"},
        ],
        "AttributeDefinitions": [
            {"AttributeName": "user_id",  "AttributeType": "S"},
            {"AttributeName": "msg_id",   "AttributeType": "S"},
        ],
        "BillingMode": "PAY_PER_REQUEST",
    },
]

async def init_dynamodb():
    """Create all DynamoDB tables if they don't exist."""
    client = boto3.client(
        "dynamodb",
        region_name=settings.AWS_REGION,
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
    )
    existing = [t["TableName"] for t in client.list_tables()["TableNames"]]

    for table_def in TABLES:
        if table_def["TableName"] not in existing:
            client.create_table(**table_def)
            print(f"[DynamoDB] Created table: {table_def['TableName']}")
        else:
            print(f"[DynamoDB] Table already exists: {table_def['TableName']}")