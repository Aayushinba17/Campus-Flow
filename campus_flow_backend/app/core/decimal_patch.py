import decimal
import fastapi.encoders

# Monkeypatch FastAPI's global ENCODERS_BY_TYPE to support Decimal from boto3
fastapi.encoders.ENCODERS_BY_TYPE[decimal.Decimal] = lambda obj: int(obj) if obj % 1 == 0 else float(obj)
