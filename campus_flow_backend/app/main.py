from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import json
import botocore.exceptions
from contextlib import asynccontextmanager
import app.core.decimal_patch  # Patch FastAPI jsonable_encoder for Decimal
from app.core.config import settings
from app.core.database import init_dynamodb
from app.api.routes import classroom
from app.services.embedding_service import get_model as load_embedding_model
from app.api.routes import (
    schedule,
    notifications,
    routine,
    reminders,
    chat,
    notes,
    wellness,
    email_summarization,
    location,
    proactive_alerts,
)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 0. Validate essential credentials
    if not settings.GEMINI_API_KEY:
        raise RuntimeError("Startup Failed: GEMINI_API_KEY is missing")
    if not settings.AWS_ACCESS_KEY_ID or not settings.AWS_SECRET_ACCESS_KEY:
        raise RuntimeError("Startup Failed: AWS credentials are missing")

    # 1. Initialize database
    await init_dynamodb()
    
    # 2. Warm up the embedding model so the first request isn't slow
    try:
        load_embedding_model()
        print("[Embeddings] Model loaded and ready")
    except Exception as e:
        print(f"[Embeddings] Warm-up skipped: {e}")
        
    yield
    
app = FastAPI(
    title="CampusFlow API",
    version="1.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Mount all routers ────────────────────────────────────────────────────────
app.include_router(schedule.router,            prefix="/api/schedule",        tags=["Schedule"])
app.include_router(notifications.router,       prefix="/api/notifications",   tags=["Notifications"])
app.include_router(routine.router,             prefix="/api/routine",         tags=["Routine"])
app.include_router(reminders.router,           prefix="/api/reminders",       tags=["Reminders"])
app.include_router(chat.router,                prefix="/api/chat",            tags=["Chat"])
app.include_router(notes.router,               prefix="/api/notes",           tags=["Notes"])
app.include_router(wellness.router,            prefix="/api/wellness",        tags=["Wellness"])
app.include_router(email_summarization.router,  prefix="/api/emails",          tags=["Email Summarization"])
app.include_router(location.router,            prefix="/api/location",        tags=["Location Context"])
app.include_router(proactive_alerts.router,    prefix="/api/alerts",          tags=["Proactive Alerts"])
app.include_router(classroom.router, prefix="/api/classroom", tags=["Classroom"])

@app.exception_handler(botocore.exceptions.ClientError)
async def botocore_exception_handler(request: Request, exc: botocore.exceptions.ClientError):
    return JSONResponse(
        status_code=502,
        content={"detail": "AWS Service Error", "message": str(exc)},
    )

@app.exception_handler(json.JSONDecodeError)
async def json_decode_exception_handler(request: Request, exc: json.JSONDecodeError):
    return JSONResponse(
        status_code=422,
        content={"detail": "JSON Parsing Error", "message": str(exc)},
    )

@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal Server Error", "message": str(exc)},
    )

@app.get("/health")
async def health():
    try:
        from app.core.database import get_dynamodb
        db = get_dynamodb()
        # A lightweight operation to verify DB connectivity
        list(db.tables.limit(1))
        db_status = "ok"
    except Exception as e:
        db_status = f"error: {str(e)}"

    return {
        "status": "ok" if db_status == "ok" else "degraded",
        "service": "CampusFlow API",
        "database": db_status
    }

@app.get("/")
def root():
    return {"status": "Campus Flow API running"}