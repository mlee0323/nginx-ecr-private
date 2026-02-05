import pymysql
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# AWS RDS 연결 정보 (하드코딩)
DB_CONFIG = {
    "host": "lee-db.cdiqqa2um9xa.ap-south-1.rds.amazonaws.com",
    "user": "admin",
    "password": "test1234",
    "database": "lee",
    "port": 3306,
    "charset": "utf8mb4",
    "cursorclass": pymysql.cursors.DictCursor
}

@app.get("/")
def check_connection():
    try:
        # pymysql을 이용한 직접 연결
        connection = pymysql.connect(**DB_CONFIG)
        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                result = cursor.fetchone()
            return {"status": "성공", "message": "DB에 연결되었습니다!", "data": result}
        finally:
            connection.close()
    except Exception as e:
        return {"status": "실패", "message": str(e)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
