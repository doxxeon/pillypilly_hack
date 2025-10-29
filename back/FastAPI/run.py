import uvicorn
from app.main import app


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("run:app", host="0.0.0.0", port=8282, reload=True)

