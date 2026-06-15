# app/services/embedding_service.py
from sentence_transformers import SentenceTransformer
import numpy as np
from app.core.config import settings

_model = None

def get_model():
    """Load the model once and reuse it (lazy singleton)."""
    global _model
    if _model is None:
        _model = SentenceTransformer(settings.EMBEDDING_MODEL)
    return _model

def embed(text: str) -> list:
    """Return a 384-dim embedding for the text. Empty text -> empty list."""
    if not text or not text.strip():
        return []
    vec = get_model().encode(text, normalize_embeddings=True)
    return vec.tolist()

def cosine_sim(a: list, b: list) -> float:
    """Cosine similarity between two embedding lists. Safe on empties."""
    if not a or not b or len(a) != len(b):
        return 0.0
    a = np.array(a, dtype=float)
    b = np.array(b, dtype=float)
    denom = np.linalg.norm(a) * np.linalg.norm(b)
    if denom == 0:
        return 0.0
    return float(np.dot(a, b) / denom)