from fastapi import FastAPI
from datetime import datetime
import os

app = FastAPI()


@app.get("/health")
async def health_check():
    return {
        "status": "up",
        "environment": os.getenv("ENVIRONMENT", "development"),
        "timestamp": datetime.now().isoformat(),
    }
