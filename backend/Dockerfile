FROM python:3.9-slim

# 设置工作目录
WORKDIR /backend

# 设置环境变量，防止 Python 生成 .pyc 文件或缓冲输出
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# 安装系统级依赖 (如果需要)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# 安装 Python 相关依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 复制代码
COPY . .

# 默认端口 8080
ENV PORT=8080

# 启动命令：Cloud Run 会自动传入 $PORT 环境变量
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
