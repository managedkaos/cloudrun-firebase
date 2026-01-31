from fastapi import FastAPI
from fastapi.responses import JSONResponse

app = FastAPI(title="CloudRun Firebase Application")


@app.get("/")
async def root():
    """Root endpoint returning a welcome message."""
    return {"message": "Welcome to CloudRun Firebase Application"}


@app.get("/health")
async def health():
    """Health check endpoint."""
    return JSONResponse(
        content={"status": "healthy", "service": "cloudrun-firebase"},
        status_code=200
    )


@app.get("/api/info")
async def info():
    """API information endpoint."""
    return {
        "name": "CloudRun Firebase API",
        "version": "1.0.0",
        "description": "FastAPI Monolith for CloudRun and Firebase"
    }
