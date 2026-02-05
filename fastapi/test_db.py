import pymysql

DB_CONFIG = {
    "host": "team-db.cdiqqa2um9xa.ap-south-1.rds.amazonaws.com",
    "user": "admin",
    "password": "team1234",
    "database": "team-db",
    "port": 3306,
    "charset": "utf8mb4",
    "cursorclass": pymysql.cursors.DictCursor
}

def test_connection():
    print(f"Connecting to {DB_CONFIG['host']}...")
    try:
        connection = pymysql.connect(
            host=DB_CONFIG['host'],
            user=DB_CONFIG['user'],
            password=DB_CONFIG['password'],
            database=DB_CONFIG['database'],
            port=DB_CONFIG['port'],
            connect_timeout=5
        )
        print("✅ Connection successful!")
        with connection.cursor() as cursor:
            cursor.execute("SELECT VERSION();")
            version = cursor.fetchone()
            print(f"Database version: {version}")
        connection.close()
    except Exception as e:
        print(f"❌ Connection failed: {e}")

if __name__ == "__main__":
    test_connection()
