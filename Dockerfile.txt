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
