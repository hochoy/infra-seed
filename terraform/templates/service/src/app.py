from fastapi import FastAPI
import os

app = FastAPI(title="SERVICE_NAME")

@app.get("/")
async def root():
    return {
        "service": "SERVICE_NAME",
        "status": "running",
        "environment": os.getenv("ENVIRONMENT", "production")
    }

@app.get("/health")
async def health():
    return {"status": "healthy"}
