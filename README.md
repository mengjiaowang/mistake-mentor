[English](README_EN.md) | [中文](README.md)

# 智能错题笔记本 (MistakeMentor)

`MistakeMentor` 是一款专为家庭场景设计的智能错题管理与复习工具，主打“轻量录入、大屏复习、高能 AI 辅助”。目前项目已经打通了从图片擦除、结构化提取到平板端沉浸看板的端到端全链路。

---

## 📖 1. 项目简介与目的

本项目的目的是为降低学生整理错题集的时间成本。通过手机端拍照快速采集，利用谷歌云先进的图像处理及大模型（Vertex AI）能力：

1.  **还原空白题目**：利用 `Imagen 3` 像素级擦除手写批改和答案痕迹。
2.  **公式及文字精准数字化**：利用 `Gemini 3.1` 提取文本、对齐 `LaTeX` 公式符号。
3.  **启发式 AI 解析及一键“举一反三”**：不直接给答案，而是给出分步推理和相似的变式训练题，做一题学一类。

---

## 🛠️ 2. 技术架构与核心代码模块

### 🖥️ 2.1 后端 API架构 (`/backend`)

基于 **FastAPI (Python)** 部署于 **Google Cloud Run**。

- [**`app/services/gcp_ai_service.py`**](file:///Users/mengjiaowang/vscode/learning_assistant/backend/app/services/gcp_ai_service.py)
  - 集成 **Vertex AI**。使用 `Imagen` 擦除字迹，使用 `Gemini` 输出符合接口规范的结构化 `JSON`（题干、考点、步骤、变式题）。
- [**`app/routers/questions.py`**](file:///Users/mengjiaowang/vscode/learning_assistant/backend/app/routers/questions.py)
  - 管理业务入口。包含图片直接安全上载至 **Cloud Storage (GCS)** 以及将错题元数据流水写入 **Firestore**。

### 📱 2.2 前端客户端架构 (`/frontend`)

使用 **Flutter** 构建，支持移动/平板大屏。

- `lib/services/api_service.dart`：绑定 Dio 模块，无缝附加 JWT 安全锁进行上载流控。
- `lib/screens/dashboard_screen.dart`：错题详情面板卡片。
- `lib/screens/capture_screen.dart`：支持一键调用相机触发 `/questions/upload`。

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
cd frontend

# 2. 获取依赖包
flutter pub get

# 3. 启动应用并选择运行设备 (平板/手机模拟器或真机)
flutter run
```

> 💡 **小贴士**：默认 `baseUrl` 为本地 `http://127.0.0.1:8000`。若需接入云端，请修改 `lib/services/api_service.dart` 中的变量。

---

## 🚢 4. 云端一键部署 (Google Cloud Run)

### 一键脚本自动化

如果您本地已经配置了 `gcloud`：

```bash
cd backend
./deploy.sh
```

脚本会自动启用依赖 APIs，将代码托管给 Cloud Build 打包，最终一站式发布至 **东京地区 (`asia-northeast1`)**。

---

## 🔑 5. 内置超级测试账号

- **用户名**：`admin`
- **密码**：`admin123`
