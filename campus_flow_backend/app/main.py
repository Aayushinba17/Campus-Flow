from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from app.core.config import settings
from app.core.database import init_dynamodb
from app.api.routes import (
    schedule,
    notifications,
    routine,
    reminders,
    chat,
    notes,
    wellness
)

@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_dynamodb()
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

app.include_router(schedule.router,       prefix="/api/schedule",       tags=["Schedule"])
app.include_router(notifications.router,  prefix="/api/notifications",   tags=["Notifications"])
app.include_router(routine.router,        prefix="/api/routine",         tags=["Routine"])
app.include_router(reminders.router,      prefix="/api/reminders",       tags=["Reminders"])
app.include_router(chat.router,           prefix="/api/chat",            tags=["Chat"])
app.include_router(notes.router,          prefix="/api/notes",           tags=["Notes"])
app.include_router(wellness.router,       prefix="/api/wellness",        tags=["Wellness"])

@app.get("/health")
async def health():
    return {"status": "ok", "service": "CampusFlow API"}