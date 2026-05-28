FROM node:24-trixie-slim

ARG CLAUDE_CODE_VERSION=latest

# 1. Cài đặt các thư viện hệ thống cần thiết (bao gồm gosu để chạy quyền user chuẩn)
#    + Python 3 và OS deps cho doc-parser MCP (Unstructured: OCR + PDF render)
RUN apt-get update && apt-get install -y --no-install-recommends \
  git \
  jq \
  wget \
  curl \
  gnupg2 \
  ca-certificates \
  gosu \
  rsync \
  inotify-tools \
  python3 \
  python3-venv \
  python3-pip \
  tesseract-ocr \
  tesseract-ocr-eng \
  tesseract-ocr-jpn \
  tesseract-ocr-vie \
  poppler-utils \
  libmagic1 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Thiết lập thư mục cài đặt NPM global để tránh lỗi phân quyền
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share/npm-global

# 3. Tạo sẵn các thư mục làm việc và cấp quyền cho user 'node'
#    /opt/doc-parser-venv: container-owned Python venv cho doc-parser MCP (build runtime).
RUN mkdir -p /workspace/supportFiles /workspace/output /home/node/.claude /opt/doc-parser-venv && \
  chown -R node:node /workspace /home/node/.claude /opt/doc-parser-venv

# 4. Cài đặt môi trường AI (Claude Code) bằng user 'node'
USER node
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Bỏ qua màn hình chào mừng lúc mới khởi động Claude
ENV CLAUDE_CODE_SKIP_ONBOARDING=1

RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Copy các file cấu hình AI cơ bản
COPY --chown=node:node settings.json /home/node/.claude/settings.json
COPY --chown=node:node CLAUDE.md /home/node/CLAUDE.md.default

# 5. Chuyển lại quyền root để cấp quyền thực thi cho Entrypoint
USER root
COPY entrypoint.sh /home/node/entrypoint.sh
RUN chmod +x /home/node/entrypoint.sh

# 6. --- PHẦN THÊM MỚI CHO BACKEND API SERVER ---
# Đặt server NGOÀI /workspace để Claude (chỉ thấy /workspace) không đọc được mã nguồn
RUN mkdir -p /opt/app && chown -R node:node /opt/app
WORKDIR /opt/app

# Copy file cấu hình thư viện của Server (package.json) nếu có
COPY --chown=node:node package*.json ./

# Tự động cài thư viện nếu phát hiện có file package.json
RUN if [ -f "package.json" ]; then npm install; fi

# Copy file mã nguồn Server của bạn vào
COPY --chown=node:node server.js ./

# Đặt lại cwd về /workspace cho Claude
WORKDIR /workspace

# Mở cổng 8080 ra để giao tiếp với mạng bên ngoài
EXPOSE 8080

# Chạy kịch bản khởi động chuẩn
ENTRYPOINT ["/home/node/entrypoint.sh"]

