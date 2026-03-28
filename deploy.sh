#!/bin/bash

# ==========================================
# 智能错题本 - 部署脚本 (Frontend + Backend)
# ==========================================

USAGE="
用法: ./deploy.sh [target]

目标 (target):
  all       部署前后端 (默认)
  backend   仅部署后端到 Cloud Run
  frontend  仅部署前端 Web 到 Firebase Hosting
  help      显示此帮助信息
"

TARGET=${1:-all}

if [ "$TARGET" == "help" ]; then
    echo "$USAGE"
    exit 0
fi

if [[ "$TARGET" != "all" && "$TARGET" != "backend" && "$TARGET" != "frontend" ]]; then
    echo "❌ 错误: 无效的目标参数 '$TARGET'"
    echo "$USAGE"
    exit 1
fi

# ==========================================
# 授权检查 (Pre-flight Auth Checks)
# ==========================================
echo "🔍 检查 Google Cloud 授权状态..."
if ! gcloud auth application-default print-access-token >/dev/null 2>&1 && ! gcloud auth print-access-token >/dev/null 2>&1; then
    echo "❌ 错误: Google Cloud 凭证已过期或未获取。"
    echo "💡 请先执行: gcloud auth application-default login"
    exit 1
fi

if [[ "$TARGET" == "all" || "$TARGET" == "frontend" ]]; then
    echo "🔍 检查 Firebase 授权状态..."
    if ! firebase projects:list >/dev/null 2>&1; then
        echo "❌ 错误: Firebase 凭证已过期或未获取。"
        echo "💡 请先执行: firebase login --reauth"
        exit 1
    fi
fi

# ==========================================
# 加载配置文件 (.env)
# ==========================================
if [ -f .env ]; then
    echo "📜 加载 .env 配置文件..."
    export $(grep -v '^#' .env | xargs)
fi

if [ -z "$PROJECT_ID" ]; then
    echo "❌ 错误: 未设置 PROJECT_ID 环境变量！"
    echo "💡 请创建 .env 文件并配置 PROJECT_ID=您的项目ID ，或者直接在此脚本外 export PROJECT_ID=..."
    exit 1
fi

echo "========================================"
echo "🚀 开始部署 [ $PROJECT_ID ] | 模式: $TARGET"
echo "========================================"

# 1. 设置当前项目
gcloud config set project $PROJECT_ID

# 2. 部署后端 (Cloud Run)
if [[ "$TARGET" == "all" || "$TARGET" == "backend" ]]; then
    echo ""
    echo "----------------------------------------"
    echo "📦 正在部署后端 (Cloud Run)..."
    echo "----------------------------------------"
    if [ -f "backend/deploy.sh" ]; then
        cd backend
        # 赋予执行权限以防万一
        chmod +x deploy.sh
        ./deploy.sh
        cd ..
    else
        echo "❌ 错误: 未找到 backend/deploy.sh 脚本！"
        exit 1
    fi
else
    echo ""
    echo "⏩ 跳过后端部署..."
fi

# 3. 部署前端 (Firebase Hosting)
if [[ "$TARGET" == "all" || "$TARGET" == "frontend" ]]; then
    echo ""
    echo "----------------------------------------"
    echo "🌐 正在部署前端 (Firebase Hosting)..."
    echo "----------------------------------------"
    if [ -d "frontend" ]; then
        cd frontend
        if [ -f "pubspec.yaml" ]; then
            echo "🛠️ 正在清理并打包 Flutter Web (Release 模式)..."
            flutter clean
            flutter pub get
            flutter build web --release
            
            echo "🚀 正在推送到 Firebase Hosting..."
            firebase deploy --only hosting --project $PROJECT_ID
        else
            echo "❌ 错误: 未在 frontend 目录下找到 Flutter 配置 (pubspec.yaml)！"
            cd ..
            exit 1
        fi
        cd ..
    else
        echo "❌ 错误: 未找到 frontend 目录！"
        exit 1
    fi
else
    echo ""
    echo "⏩ 跳过前端部署..."
fi

echo ""
echo "========================================"
if [[ "$TARGET" == "all" || "$TARGET" == "frontend" ]]; then
    echo "🎉 部署完成！"
    echo "🔗 请通过 Firebase Hosting 域名访问您的应用。"
else
    echo "🎉 后端部署完成！"
fi
echo "========================================"
