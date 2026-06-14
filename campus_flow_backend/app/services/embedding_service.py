# app/services/embedding_service.py
from sentence_transformers import SentenceTransformer
import numpy as np

_model = None

def get_model():
    global _model
    if _model is None:
        _model = SentenceTransformer('all-MiniLM-L6-v2')
    return _model

def embed(text: str) -> list[float]:
    return get_model().encode(text, normalize_embeddings=True).tolist()

def cosine_sim(vec_a: list[float], vec_b: list[float]) -> float:
    a, b = np.array(vec_a), np.array(vec_b)
    return float(np.dot(a, b))   # already normalized, so dot product = cosine

# Optional helper to add at the bottom of embedding_service.py
def relevance(query: str, text: str) -> float:
    """Cosine similarity between two raw strings (0..1)."""
    if not query or not text:
        return 0.0
    return cosine_sim(embed(query), embed(text))