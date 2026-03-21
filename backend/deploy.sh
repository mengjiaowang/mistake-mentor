#!/bin/bash

# ==========================================
# 智能错题本 - Cloud Run 自动化部署脚本
# ==========================================

# 1. 基础配置
# ==========================================
# 加载配置文件 (.env)
# ==========================================
if [ -f .env ]; then
    echo "📜 加载 backend/.env 配置文件..."
    export $(grep -v '^#' .env | xargs)
elif [ -f ../.env ]; then
    echo "📜 加载根目录 .env 配置文件..."
    export $(grep -v '^#' ../.env | xargs)
else
    echo "ℹ️ 未找到 .env 配置文件，将依赖环境已有的变量。"
fi

# 1. 基础配置
if [ -z "$PROJECT_ID" ]; then
    echo "❌ 错误: 未设置 PROJECT_ID 环境变量！"
    echo "💡 请创建 .env 文件并配置 PROJECT_ID=您的项目ID ，或者直接在此脚本外 export PROJECT_ID=..."
    exit 1
fi

SERVICE_NAME="mistakementor-backend"          # Cloud Run 服务名称
REGION="asia-northeast1"                  # 部署区域：东京
REPO_NAME="mistakementor-docker"         # Artifact Registry 镜像仓库名

echo "----------------------------------------"
echo "🚀 开始部署: $SERVICE_NAME 到项目 $PROJECT_ID"
echo "📍 部署可用区: $REGION"
echo "----------------------------------------"

# 2. 设置当前项目
echo "⚙️ 设置 gcloud 项目..."
gcloud config set project $PROJECT_ID

# 3. 启用必要的 Google Cloud APIs (已交由 setup_gcp.sh 统一管理)
echo "🔌 检查并确认 API 后台配置..."
# gcloud services enable 移向 setup 一次性运行

# 3.5 创建 Artifact Registry 容器仓库 (如果不存在)
echo "📦 正在检查并创建 Artifact Registry 镜像仓库..."
if ! gcloud artifacts repositories describe $REPO_NAME --location=$REGION > /dev/null 2>&1; then
    gcloud artifacts repositories create $REPO_NAME \
        --repository-format=docker \
        --location=$REGION \
        --description="MistakeMentor Backend Docker Repo"
    echo "✅ 镜像仓库 $REPO_NAME 创建成功！"
else
    echo "ℹ️ 镜像仓库 $REPO_NAME 已存在。"
fi

# 4. 使用 Cloud Build 编译镜像
IMAGE_TAG="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$SERVICE_NAME"

echo "🛠️ 正在使用 Cloud Build 提交构建..."
gcloud builds submit --tag $IMAGE_TAG .

# 5. 发布到 Cloud Run
echo "🚢 正在发布到 Cloud Run (仅允许 Firebase Hosting 负载均衡转发调用)..."
gcloud run deploy $SERVICE_NAME \
  --image $IMAGE_TAG \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --cpu 1 \
  --memory 4Gi \
  --port 8080

echo "----------------------------------------"
echo "🎉 部署完成！"
echo "🔗 请查看上方输出的 Service URL 作为您的 API 主地址。"
echo "----------------------------------------"
