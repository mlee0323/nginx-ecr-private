#!/bin/bash

# ==============================================================================
# EC2 User Data Script (Ubuntu)
# 목적: 인스턴스 초기화, 도커 설치, S3 설정 파일 연동 및 컨테이너 실행
# 구성: nginx (메인, 80) + nginx (서브, 81) + fastapi (8000)
# 통신: Docker Network 사용
# ==============================================================================

set -e  # 에러 발생 시 스크립트 중단

# 1. 변수 설정
REGION="ap-south-1"
S3_BUCKET="lee-s3-bucket-cicd"
DOCKER_NETWORK="app-network"      # Docker 네트워크 이름

# 컨테이너 이름 (3명의 팀원)
NGINX_MOON_CONTAINER="nginx-moon"    # 문이정 (포트 80)
NGINX_LEE_CONTAINER="nginx-lee"      # 이민석 (포트 81)
NGINX_PARK_CONTAINER="nginx-park"    # 박선우 (포트 82)
FASTAPI_CONTAINER="fastapi-app"

# 팀원 이름
NAME_MOON="문이정"
NAME_LEE="이민석"
NAME_PARK="박선우"

# 로그 파일 설정
LOG_FILE="/var/log/userdata.log"
exec > >(tee -a ${LOG_FILE}) 2>&1
echo "========== User Data Script Started: $(date) =========="

# 2. 필수 서비스 설치 전 업데이트
apt-get update -y
apt-get install -y curl unzip net-tools apt-transport-https ca-certificates gnupg lsb-release

# 3. SSM 에이전트 설치 (snap 버전)
if ! snap list amazon-ssm-agent &>/dev/null; then
    snap install amazon-ssm-agent --classic
fi
snap start amazon-ssm-agent || true

# 4. Docker 설치
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
usermod -aG docker ubuntu

# 5. AWS CLI v2 설치
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf awscliv2.zip aws/
fi

# 6. 앱 디렉토리 준비 및 S3 파일 동기화
APP_DIR="/home/ubuntu/app"
mkdir -p ${APP_DIR}/nginx
mkdir -p ${APP_DIR}/fastapi

# S3에서 nginx 폴더 동기화 (Dockerfile, default.conf, html 포함)
aws s3 sync s3://${S3_BUCKET}/nginx/ ${APP_DIR}/nginx/ --delete

# S3에서 fastapi 폴더 동기화 (Dockerfile, requirements.txt, app 포함)
aws s3 sync s3://${S3_BUCKET}/fastapi/ ${APP_DIR}/fastapi/ --delete

# 권한 설정
chown -R ubuntu:ubuntu ${APP_DIR}
chmod -R 755 ${APP_DIR}

echo "========== S3 Sync Completed =========="

# 7. Docker 네트워크 생성
if ! docker network inspect ${DOCKER_NETWORK} > /dev/null 2>&1; then
    docker network create ${DOCKER_NETWORK}
    echo "Docker network '${DOCKER_NETWORK}' created."
else
    echo "Docker network '${DOCKER_NETWORK}' already exists."
fi

# 8. Docker 이미지 빌드
echo "========== Building Docker Images =========="

# Nginx 이미지 빌드
cd ${APP_DIR}/nginx
docker build -t nginx-local:latest .

# FastAPI 이미지 빌드
cd ${APP_DIR}/fastapi
docker build -t fastapi-local:latest .

echo "========== Docker Images Built =========="

# 9. 기존 컨테이너 정리
docker rm -f ${NGINX_MOON_CONTAINER} ${NGINX_LEE_CONTAINER} ${NGINX_PARK_CONTAINER} ${FASTAPI_CONTAINER} 2>/dev/null || true

# 10. 각 팀원별 HTML 디렉토리 생성
echo "========== Creating Team Member HTML =========="

# HTML 템플릿 함수
create_html() {
    local name=$1
    local dir=$2
    mkdir -p ${dir}
    cat > ${dir}/index.html <<EOF
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${name}</title>
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            text-align: center;
            font-family: 'Segoe UI', Arial, sans-serif;
            margin: 0;
            height: 100vh;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
        }
        h1 {
            font-size: 4rem;
            margin-bottom: 20px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .container {
            background: rgba(255,255,255,0.1);
            padding: 40px 80px;
            border-radius: 20px;
            backdrop-filter: blur(10px);
        }
        .success {
            font-size: 1.5rem;
            color: #90EE90;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>${name}</h1>
        <p class="success">✅ Nginx 서버 정상 작동 중</p>
    </div>
</body>
</html>
EOF
}

# 각 팀원별 HTML 생성
create_html "${NAME_MOON}" "${APP_DIR}/html-moon"
create_html "${NAME_LEE}" "${APP_DIR}/html-lee"
create_html "${NAME_PARK}" "${APP_DIR}/html-park"

echo "HTML files created for all team members."

# 11. 컨테이너 실행 (Docker Network 연결)
echo "========== Starting Containers =========="

# FastAPI 컨테이너 실행 (내부 통신만)
docker run -d \
  --name ${FASTAPI_CONTAINER} \
  --network ${DOCKER_NETWORK} \
  --restart unless-stopped \
  fastapi-local:latest

echo "FastAPI container started: ${FASTAPI_CONTAINER}"

# 문이정 Nginx 컨테이너 실행 (내부 통신만)
docker run -d \
  --name ${NGINX_MOON_CONTAINER} \
  --network ${DOCKER_NETWORK} \
  --restart unless-stopped \
  -v ${APP_DIR}/html-moon:/usr/share/nginx/html:ro \
  nginx-local:latest

echo "Nginx container started: ${NGINX_MOON_CONTAINER} (${NAME_MOON})"

# 이민석 Nginx 컨테이너 실행 (내부 통신만)
docker run -d \
  --name ${NGINX_LEE_CONTAINER} \
  --network ${DOCKER_NETWORK} \
  --restart unless-stopped \
  -v ${APP_DIR}/html-lee:/usr/share/nginx/html:ro \
  nginx-local:latest

echo "Nginx container started: ${NGINX_LEE_CONTAINER} (${NAME_LEE})"

# 박선우 Nginx 컨테이너 실행 (내부 통신만)
docker run -d \
  --name ${NGINX_PARK_CONTAINER} \
  --network ${DOCKER_NETWORK} \
  --restart unless-stopped \
  -v ${APP_DIR}/html-park:/usr/share/nginx/html:ro \
  nginx-local:latest

echo "Nginx container started: ${NGINX_PARK_CONTAINER} (${NAME_PARK})"

# 메인 Nginx 컨테이너 실행 (외부 노출 - 포트 80)
docker run -d \
  --name nginx-main \
  --network ${DOCKER_NETWORK} \
  --restart unless-stopped \
  -p 80:80 \
  -v ${APP_DIR}/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro \
  nginx:alpine

echo "Main Nginx container started: nginx-main (Port 80)"

# 12. 컨테이너 상태 확인
echo "========== Container Status =========="
docker ps -a

echo "========== User Data Script Completed: $(date) =========="
echo ""
echo "Docker Network 내부 통신:"
echo "  - ${NGINX_MOON_CONTAINER}:80 -> ${NAME_MOON}"
echo "  - ${NGINX_LEE_CONTAINER}:80 -> ${NAME_LEE}"
echo "  - ${NGINX_PARK_CONTAINER}:80 -> ${NAME_PARK}"
echo "  - ${FASTAPI_CONTAINER}:8000 -> FastAPI"
echo ""
echo "외부 접속: http://<EC2-IP>:80 (메인 nginx가 라우팅)"