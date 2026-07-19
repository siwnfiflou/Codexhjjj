FROM node:19.1.0-alpine3.16

ARG APP_HOME=/home/node/app

RUN apk add --no-cache gcompat tini git python3 py3-pip bash dos2unix findutils tar curl

# 同时预装 HuggingFace 与 魔搭(ModelScope) 客户端
RUN pip3 install --no-cache-dir huggingface_hub modelscope-hub

# ===== 安装 cloudflared =====
RUN set -eux; \
    ARCH="$(uname -m)"; \
    case "$ARCH" in \
      x86_64)  CF_ARCH="amd64" ;; \
      aarch64) CF_ARCH="arm64" ;; \
      armv7l)  CF_ARCH="arm" ;; \
      *) echo "不支持的架构: $ARCH" && exit 1 ;; \
    esac; \
    curl -L -o /usr/local/bin/cloudflared \
      "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"; \
    chmod +x /usr/local/bin/cloudflared
# =============================

ENTRYPOINT [ "tini", "--" ]

WORKDIR ${APP_HOME}

ENV NODE_ENV=production

ENV USERNAME="admin"
ENV PASSWORD="password"

# ===== Cloudflare Tunnel Token =====
ENV TUNNEL_TOKEN=""
# ===================================

# ===== 备份相关环境变量（可在部署平台覆盖）=====
# HuggingFace：仅上传
ENV HF_TOKEN=""
ENV DATASET_ID=""
# 魔搭(ModelScope)：上传 + 下载恢复
ENV MS_TOKEN=""
ENV MS_DATASET_ID=""
# 同步间隔（秒），默认 3600
ENV SYNC_INTERVAL="3600"
# =============================================

RUN git clone https://github.com/SillyTavern/SillyTavern.git .

RUN echo "*** 安装npm包 ***" && \
    npm install && npm cache clean --force

RUN bash -c '\
  PLUGIN_ID="cocktail-plus"; \
  APP_HOME=/home/node/app; \
  repos=("https://github.com/Lianues/cocktail-plus.git" "https://gitee.com/lianues/cocktail-plus.git"); \
  tmp="${TMPDIR:-/tmp}/cocktail-plus-repo"; \
  src=""; \
  for repo in "${repos[@]}"; do \
    rm -rf "$tmp"; \
    echo "尝试克隆: $repo"; \
    if git clone --depth 1 "$repo" "$tmp" 2>&1; then \
      if [ -f "$tmp/server-plugins/$PLUGIN_ID/index.mjs" ]; then \
        src="$tmp/server-plugins/$PLUGIN_ID"; \
        break; \
      fi; \
    fi; \
  done; \
  [ -n "$src" ] || { echo "克隆失败或内容不完整"; exit 1; }; \
  mkdir -p "$APP_HOME/plugins"; \
  cp -R "$src" "$APP_HOME/plugins/$PLUGIN_ID"; \
  rm -rf "$tmp"; \
  cfg="$APP_HOME/config/config.yaml"; \
  mkdir -p "$(dirname "$cfg")"; \
  if [ -f "$cfg" ]; then \
    if grep -q "enableServerPlugins" "$cfg"; then \
      sed -i "s/^enableServerPlugins:.*/enableServerPlugins: true/" "$cfg"; \
    else \
      echo "enableServerPlugins: true" >> "$cfg"; \
    fi; \
  else \
    echo "enableServerPlugins: true" > "$cfg"; \
  fi; \
  echo "cocktail-plus 后端插件安装完成"'

COPY launch.sh syd.sh ./
RUN chmod +x launch.sh syd.sh && \
    dos2unix launch.sh syd.sh

RUN echo "*** 安装生产npm包 ***" && \
    npm i --no-audit --no-fund --loglevel=error --no-progress --omit=dev && npm cache clean --force

RUN mkdir -p "config" || true && \
    rm -f "config.yaml" || true && \
    ln -s "./config/config.yaml" "config.yaml" || true

RUN echo "*** 清理 ***" && \
    mv "./docker/docker-entrypoint.sh" "./" && \
    rm -rf "./docker" && \
    chmod +x "./docker-entrypoint.sh" && \
    dos2unix "./docker-entrypoint.sh" || true

RUN sed -i 's/# Start the server/.\/launch.sh/g' docker-entrypoint.sh

RUN mkdir -p /tmp/sillytavern_backup && \
    mkdir -p ${APP_HOME}/data

RUN chmod -R 777 ${APP_HOME} && \
    chmod -R 777 /tmp/sillytavern_backup

# ===== 启动脚本：用 Token 方式跑 cloudflared =====
RUN printf '#!/bin/bash\n\
if [ -z "$TUNNEL_TOKEN" ]; then\n\
  echo "错误: 未设置 TUNNEL_TOKEN 环境变量"; exit 1;\n\
fi\n\
cloudflared tunnel --no-autoupdate run --token "$TUNNEL_TOKEN" &\n\
exec ./docker-entrypoint.sh\n' > /home/node/app/start-with-cloudflared.sh && \
    chmod +x /home/node/app/start-with-cloudflared.sh
# =====================================================

EXPOSE 8000

CMD [ "./start-with-cloudflared.sh" ]
