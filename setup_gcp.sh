#!/bin/bash

# ==========================================
# MistakeMentor - GCP 一键权限与 API 初始化脚本
# ==========================================

# ==========================================
# 加载配置文件 (.env)
# ==========================================
if [ -f .env ]; then
    echo "📜 加载 .env 配置文件..."
    export $(grep -v '^#' .env | xargs)
else
    echo "ℹ️ 未找到 .env 配置文件，将依赖环境已有的变量。"
fi

if [ -z "$PROJECT_ID" ]; then
    echo "❌ 错误: 未设置 PROJECT_ID 环境变量！"
    echo "💡 请创建 .env 文件并配置 PROJECT_ID=您的项目ID ，或者直接在此脚本外 export PROJECT_ID=..."
    exit 1
fi

echo "----------------------------------------"
echo "🛠️ 开始为项目 [ $PROJECT_ID ] 配置 GCP 服务..."
echo "----------------------------------------"

# 1. 切换并设置当前 gcloud 项目
echo "⚙️ 设置当前 gcloud 处于项目: $PROJECT_ID"
gcloud config set project $PROJECT_ID

# 2. 启用必要的 Google Cloud APIs
echo "🔌 1/3. 正在开启必要的云端 API 接口..."
gcloud services enable \
  aiplatform.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com \
  storage.googleapis.com

# 3. 检查并创建 Cloud Storage 桶 (供后端存放原图和去痕图)
BUCKET_NAME="$PROJECT_ID-images"
echo "🪣 🚀 正在检查并创建存储桶: gs://$BUCKET_NAME ..."
# 获取当前区域，通常为asia-northeast1对应东京节点
if ! gcloud storage buckets describe gs://$BUCKET_NAME > /dev/null 2>&1; then
    gcloud storage buckets create gs://$BUCKET_NAME --location=asia-northeast1
    echo "✅ 存储桶 gs://$BUCKET_NAME 创建成功！"
else
    echo "ℹ️ 存储桶 gs://$BUCKET_NAME 已存在，无需再开启。"
fi

# 4. 自动拉取项目的 Project Number 用于构造默认服务账号
echo "🔍 2/3. 正在自动获取项目编号 (Project Number)..."
PROJECT_NUMBER=$(gcloud projects list --filter="projectId:$PROJECT_ID" --format="value(projectNumber)")

if [ -z "$PROJECT_NUMBER" ]; then
    echo "❌ 错误: 无法获取到项目编号，请确保您已经在终端登录（运行过 gcloud auth login）"
    exit 1
fi

SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
echo "✅ 默认服务账号为: $SERVICE_ACCOUNT"

# 4. 绑定 IAM 权限角色
echo "🔑 3/3. 正在将权限赋予服务账号..."

ROLES=(
  "roles/aiplatform.user"
  "roles/datastore.user"
  "roles/storage.objectAdmin"
  "roles/artifactregistry.writer"
  "roles/logging.logWriter"
)

for ROLE in "${ROLES[@]}"; do
  echo "👉 正在绑定角色: $ROLE"
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="$ROLE" \
    --condition=None > /dev/null
done

echo "----------------------------------------"
echo "🎉 所有 API 及 IAM 权限配置绑定完成！"
echo "💡 现在，您的 Cloud Run 后端在发布后将能正常读写数据库、存储和调用 AI 接口了。"
echo "----------------------------------------"
