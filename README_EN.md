[English](README_EN.md) | [中文](README.md)

# MistakeMentor - Smart Review Notebook

`MistakeMentor` is an AI-powered smart incorrect question management and revision tool designed specifically for home learning environments. It has fully integrated end-to-end support for pixel-level hand-writing erasure, structured extraction, and immersive tablet revision dashboards.

---

## 📖 1. Project Overview & Purpose
The purpose of this project is to reduce the time cost for students to organize mistake collections. By capturing photos with a mobile phone and leveraging Google Cloud's advanced image processing and Large Multimodal Models (Vertex AI):
1.  **Restore Blank Questions**: Use `Imagen 3` Inpaint-Removal to automatically erase handwritten answers and correction marks from images pixel by pixel.
2.  **Formula & Text Digitization**: Use `Gemini 3.1` to extract text and accurately format math formulas into standard `LaTeX` notation.
3.  **Socratic AI Explanations & Variation Generation**: Guide students through reasoning without giving answers directly, and generate "analogous questions" to ensure mastery of the underlying concepts.

---

## 🛠️ 2. Technical Architecture & Core Modules

### 🖥️ 2.1 Backend API Architecture (`/backend`)
A lightweight & serverless monolithic architecture on **Google Cloud Run (FastAPI)**.
*   [**`app/services/gcp_ai_service.py`**](file:///Users/mengjiaowang/vscode/learning_assistant/backend/app/services/gcp_ai_service.py)
    *   Integrates **Vertex AI**. Cleans up strokes with `Imagen`, and formats to JSON (stems, options, analysis, variation) using `Gemini`.
*   [**`app/routers/questions.py`**](file:///Users/mengjiaowang/vscode/learning_assistant/backend/app/routers/questions.py)
    *   Serves the main API endpoints for secure photo uploads linking directly into **Cloud Storage (GCS)** and metadata pipelines into **Firestore**.

### 📱 2.2 Frontend Client Architecture (`/frontend`)
Built using **Flutter**, supports highly adaptive responsive canvas layouts.
*   `lib/services/api_service.dart`: Restful bridge wrapper, auto-validates requests with safe lock using JWT.
*   `lib/screens/dashboard_screen.dart`: Complete Modal workflow for tablet overview sheet lists.
*   `lib/screens/capture_screen.dart`: Trigger standard camera for lightweight pipeline routing to endpoint.

---

## 💻 3. Local Development & Debugging (Using `uv`)

### ⚠️ Prerequisite Before Running AI Services Locally
Vertex AI services maintain credential locking. Before testing the backend, run this command in your Mac terminal for temporary fetch configuration:
```bash
gcloud auth application-default login
```

### 3.1 Step 1: Create and Activate Virtual Environment
```bash
# 1. Ensure uv is installed (e.g., brew install uv)
uv venv

# 2. Activate virtual environment (macOS/Linux)
source .venv/bin/activate
```

### 3.2 Step 2: Install Dependency Packages
```bash
# Install requirements.txt extremely fast with uv
uv pip install -r backend/requirements.txt
```

### 3.3 Step 3: Start Local FastAPI Server
```bash
cd backend
uvicorn app.main:app --reload --port 8000
```
*   **API Documentation**: Visibly test endpoints on `http://127.0.0.1:8000/docs` inside Swagger UI.

### 3.4 Step 4: Local Frontend Debugging (Flutter)
Ensure you have the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed locally.
```bash
# 1. Enter the frontend directory
cd frontend

# 2. Fetch dependencies
flutter pub get

# 3. Run the application on your device/emulator
flutter run
```
> 💡 **Tip**: The default `baseUrl` connects to local `http://127.0.0.1:8000`. To access cloud endpoints, modify the configuration variable in `lib/services/api_service.dart`.

---

## 🚢 4. Cloud Deployment (Google Cloud Run)

### One-Click Deploy Script
If you have the `gcloud` command locally on your machine, just run the following:
```bash
cd backend
./deploy.sh
```
The script will automatically enable APIs, push builds to Cloud Build, and deploy to Tokyo (`asia-northeast1`) supporting direct app integration.

---

## 🔑 5. Built-in Test Account Settings
*   **Username**: `admin`
*   **Password**: `admin123`
