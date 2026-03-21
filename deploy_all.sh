#!/bin/bash

# ==========================================
# 智能错题本 - 一键全栈部署脚本 (Frontend + Backend)
# ==========================================

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
echo "🚀 开始一键全栈部署 [ $PROJECT_ID ]"
echo "========================================"

# 1. 设置当前项目
gcloud config set project $PROJECT_ID

# 2. 部署后端 (Cloud Run)
echo ""
echo "----------------------------------------"
echo "📦 1/2. 正在部署后端 (Cloud Run)..."
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

# 3. 部署前端 (Firebase Hosting)
echo ""
echo "----------------------------------------"
echo "🌐 2/2. 正在部署前端 (Firebase Hosting)..."
echo "----------------------------------------"
if [ -d "frontend" ]; then
    cd frontend
    if [ -f "pubspec.yaml" ]; then
        echo "🛠️ 正在打包 Flutter Web (Release 模式)..."
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

echo ""
echo "========================================"
echo "🎉 所有组件部署完成！"
echo "🔗 请通过 Firebase Hosting 域名访问您的应用。"
echo "========================================"
