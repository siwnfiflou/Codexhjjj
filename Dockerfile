FROM node:19.1.0-alpine3.16

ARG APP_HOME=/home/node/app



RUN apk add --no-cache gcompat tini git python3 py3-pip bash dos2unix findutils tar curl

RUN pip3 install --no-cache-dir huggingface_hub

ENTRYPOINT [ "tini", "--" ]

WORKDIR ${APP_HOME}

ENV NODE_ENV=production

ENV USERNAME="admin"
ENV PASSWORD="password"

RUN git clone https://github.com/SillyTavern/SillyTavern.git .

RUN echo "*** 安装npm包 ***" && \
    npm install && npm cache clean --force

# 替换原来下载并执行 cocktail-plus-helper.sh 的那段 RUN
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
    echo "*** 使docker-entrypoint.sh可执行 ***" && \
    chmod +x "./docker-entrypoint.sh" && \
    echo "*** 转换行尾为Unix格式 ***" && \
    dos2unix "./docker-entrypoint.sh" || true

RUN sed -i 's/# Start the server/.\/launch.sh/g' docker-entrypoint.sh

RUN mkdir -p /tmp/sillytavern_backup && \
    mkdir -p ${APP_HOME}/data

RUN chmod -R 777 ${APP_HOME} && \
    chmod -R 777 /tmp/sillytavern_backup

EXPOSE 8000

CMD [ "./docker-entrypoint.sh" ] 
