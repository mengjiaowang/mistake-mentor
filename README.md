[English](README_EN.md) | [中文](README.md)

# 智能错题笔记本 (MistakeMentor)

`MistakeMentor` 是一款专为家庭场景设计的智能错题管理与复习工具，主打“轻量录入、大屏复习、高能 AI 辅助”。目前项目已经打通了从图片擦除、结构化提取到平板端沉浸看板的端到端全链路。

---

## 📖 1. 项目简介与核心特性

本项目的目的是为降低学生整理错题集的时间成本。通过手机端拍照快速采集，利用谷歌云先进的图像处理及大模型（Vertex AI）能力：

1. **还原空白题目**：通过谷歌云多模态视觉大模型像素级擦除手写批改和答案痕迹。
2. **公式及文字精准数字化**：利用 `Gemini 3.1` 提取文本、对齐 `LaTeX` 公式符号。
3. **启发式 AI 解析及一键“举一反三”**：不直接给答案，而是给出分步推理和相似的变式训练题，做一题学一类。**新增相似题折叠功能**，界面更清爽。
4. **沉浸式语音播报 (TTS)**：集成 Google Cloud TTS (Neural2/Studio语音)，支持高质量的题目解析朗读。
5. **多主题支持 (含护眼模式)**：支持浅色、深色，以及专为长时间学习设计的**蓝光过滤护眼模式**。
6. **回收站批量管理**：支持一键批量删除或恢复回收站中的错题记录。
7. **智能复习系统 (艾宾浩斯/SM-2)**：根据错题掌握程度（已掌握、模糊、未掌握）智能安排下次复习时间，巩固薄弱知识点。
8. **数据看板与统计图表**：全方位展示错题分布、按科目分类统计，以及最近7天的复习活跃趋势图谱。

---

## 🛠️ 2. 技术架构与核心代码模块

### 🖥️ 2.1 后端 API架构 (`/backend`)

基于 **FastAPI (Python)** 部署于 **Google Cloud Run**。

- [**`app/services/gcp_ai_service.py`**](backend/app/services/gcp_ai_service.py)
  - 集成 **Vertex AI**。结合多模态大语言模型进行图像智能去字擦除，同时输出符合接口规范的结构化 `JSON`（题干、考点、步骤、变式题）。集成 Cloud TTS 提供语音合成。
- [**`app/routers/questions.py`**](backend/app/routers/questions.py)
  - 管理业务入口。包含图片直接安全上载至 **Cloud Storage (GCS)** 以及将错题元数据流水写入 **Firestore**。支持基于内存排序的高效标签检索。

### 📱 2.2 前端客户端架构 (`/frontend`)

使用 **Flutter** 构建，支持移动/平板大屏以及 Web 发布。

- `lib/services/api_service.dart`：绑定 Dio 模块，无缝附加 JWT 安全锁进行上载流控。
- `lib/screens/dashboard_screen.dart`：错题详情面板卡片，支持主题切换与语音播报控制。
- `lib/screens/capture_screen.dart`：支持一键调用相机触发 `/questions/upload`。
- `lib/theme.dart`：全局主题管理器，支持浅色/深色/护眼模式无缝切换。

---

## 💻 3. 本地开发与调试 (使用 `uv`)

### ⚠️ 本地环境调用 AI 接口前必读

调用 Vertex AI 预置了权限校验。开始测试后端前，请打开您的 Mac 终端一键拉取本地凭证：

```bash
gcloud auth application-default login
```

### 3.1 步骤一：创建并激活虚拟环境

```bash
# 1. 确保已安装 uv (如未安装：brew install uv)
uv venv

# 2. 激活虚拟环境 (macOS/Linux)
source .venv/bin/activate
```

### 3.2 步骤二：安装依赖包

```bash
# 使用 uv 极速安装 requirements.txt 依赖
export UV_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
uv pip install -r backend/requirements.txt
```

### 3.3 步骤三：启动本地 FastAPI 服务

```bash
cd backend
uvicorn app.main:app --reload --port 8000
```

- **接口测试 (Swagger UI)**：服务启动后浏览器访问 `http://127.0.0.1:8000/docs` 可直接预览。

### 3.4 步骤四：前端本地开发调试 (Flutter)

确保您本地已安装 [Flutter SDK](https://docs.flutter.dev/get-started/install)。

```bash
# 1. 进入前端目录
`cd frontend`

# 2. 获取依赖包
flutter pub get

# 3. 启动应用在 Chrome 浏览器进行本地调试
flutter run -d chrome
```

> 💡 **小贴士**：默认 `baseUrl` 为本地 `http://127.0.0.1:8000`。若需接入云端，请修改 `lib/services/api_service.dart` 中的变量。

---

## 🚢 4. 云端全栈一键部署

项目提供了一键编译发布脚本，将后端部署至 **Google Cloud Run**，前端 Web 部署至 **Firebase Hosting**。

### 一键部署命令

请确保本地已配置 `gcloud` 和 `firebase-tools`：

```bash
# 在项目根目录下运行 (默认部署前后端)
./deploy.sh

# 可选独立部署:
./deploy.sh backend   # 仅部署后端
./deploy.sh frontend  # 仅部署前端
```

脚本会自动启用依赖的 GCP API，后端推送构建镜像至东京区域 (`asia-northeast1`)，前端编译 Flutter Web Release 包并同步至 Firebase。

---

## 🔑 5. 内置超级测试账号

- **用户名**：`admin`
- **密码**：`admin123`
