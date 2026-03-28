[English](README_EN.md) | [中文](README.md)

# MistakeMentor - Smart Review Notebook

`MistakeMentor` is an AI-powered smart incorrect question management and revision tool designed specifically for home learning environments. It has fully integrated end-to-end support for pixel-level hand-writing erasure, structured extraction, and immersive tablet revision dashboards.

---

## 📖 1. Project Overview & Core Features

The purpose of this project is to reduce the time cost for students to organize mistake collections. By capturing photos with a mobile phone and leveraging Google Cloud's advanced image processing and Large Multimodal Models (Vertex AI):

1. **Restore Blank Questions**: Use advanced multi-modal visual models to automatically erase handwritten answers and correction marks from images pixel by pixel.
2. **Formula & Text Digitization**: Use `Gemini 3.1` to extract text and accurately format math formulas into standard `LaTeX` notation.
3. **Socratic AI Explanations & Variation Generation**: Guide students through reasoning without giving answers directly, and generate "analogous questions". **Similar questions are now collapsible** for a cleaner interface.
4. **Immersive TTS (Text-to-Speech)**: Integrated Google Cloud TTS (Neural2/Studio) for high-quality audio playback of problem explanations.
5. **Multi-Theme Support (Eye-Care Mode)**: Offers light, dark, and a specially designed **blue-light filtering eye-care theme** for prolonged study sessions.
6. **Batch Management**: Supports batch deletion and restoration of questions directly from the Recycle Bin.
7. **Smart Review System (Ebbinghaus/SM-2 algorithm)**: Dynamically calculates the next review date based on the level of mastery (mastered, blurry, not mastered) to reinforce knowledge points.
8. **Dashboard Statistics & Rich Charting Analytics**: Comprehensive view of incorrect question distribution, categorized by subject and active review trend analysis (for the last 7 days).

---

## 🛠️ 2. Technical Architecture & Core Modules

### 🖥️ 2.1 Backend API Architecture (`/backend`)

A lightweight & serverless monolithic architecture on **Google Cloud Run (FastAPI)**.

- [**`app/services/gcp_ai_service.py`**](backend/app/services/gcp_ai_service.py)
  - Integrates **Vertex AI**. Leverages multi-modal models to clean up strokes, formats to JSON using `Gemini`, and handles high-fidelity voice synthesis using Cloud TTS.
- [**`app/routers/questions.py`**](backend/app/routers/questions.py)
  - Serves the main API endpoints for secure photo uploads linking directly into **Cloud Storage (GCS)** and metadata pipelines into **Firestore**. Uses efficient memory-based sorting for complex tag filtering.

### 📱 2.2 Frontend Client Architecture (`/frontend`)

Built using **Flutter**, supports highly adaptive responsive layouts for Mobile, Tablet, and Web.

- `lib/services/api_service.dart`: Restful bridge wrapper, auto-validates requests with safe lock using JWT.
- `lib/screens/dashboard_screen.dart`: Complete Modal workflow for tablet overview sheet lists, featuring built-in TTS controls and dynamic themes.
- `lib/screens/capture_screen.dart`: Trigger standard camera for lightweight pipeline routing to endpoint.
- `lib/theme.dart`: Global theme engine managing dynamic color palettes securely across environments.

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

- **API Documentation**: Visibly test endpoints on `http://127.0.0.1:8000/docs` inside Swagger UI.

### 3.4 Step 4: Local Frontend Debugging (Flutter)

Ensure you have the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed locally.

```bash
# 1. Enter the frontend directory
cd frontend

# 2. Fetch dependencies
flutter pub get

# 3. Run the application locally in Chrome for debugging
flutter run -d chrome
```

> 💡 **Tip**: The default `baseUrl` connects to local `http://127.0.0.1:8000`. To access cloud endpoints, modify the configuration variable in `lib/services/api_service.dart`.

---

## 🚢 4. Full-Stack Cloud Deployment

The project provides an automated build and deploy script to push the backend to **Google Cloud Run** and the frontend to **Firebase Hosting**.

### One-Click Deploy Command

Ensure you have both `gcloud` and `firebase-tools` configured locally:

```bash
# Run from the project root directory (deploys both by default)
./deploy.sh

# Optional standalone deployment:
./deploy.sh backend   # Deploy only backend
./deploy.sh frontend  # Deploy only frontend
```

The script will automatically enable necessary APIs, push backend images to Tokyo (`asia-northeast1`), compile the Flutter Web Release, and synchronize files with Firebase.

---

## 🔑 5. Built-in Test Account Settings

- **Username**: `admin`
- **Password**: `admin123`
