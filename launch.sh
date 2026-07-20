#!/bin/sh

BASE=/home/node/app
USERNAME=$(printenv USERNAME)
PASSWORD=$(printenv PASSWORD)
HF_TOKEN=$(printenv HF_TOKEN)
DATASET_ID=$(printenv DATASET_ID)
MS_TOKEN=$(printenv MS_TOKEN)
MS_DATASET_ID=$(printenv MS_DATASET_ID)
SYNC_INTERVAL=$(printenv SYNC_INTERVAL)

if [ -z "${USERNAME}" ]; then
  USERNAME="adminn"
fi

if [ -z "${PASSWORD}" ]; then
  PASSWORD="passwordd"
fi

mkdir -p "${BASE}/config"

if [ ! -e "${BASE}/config/config.yaml" ]; then
  echo "配置文件不存在，从默认目录复制: config.yaml"
  cp -r "${BASE}/default/config.yaml" "${BASE}/config/config.yaml"
fi

sed -i "s/username: .*/username: \"${USERNAME}\"/" ${BASE}/config/config.yaml
sed -i "s/password: .*/password: \"${PASSWORD}\"/" ${BASE}/config/config.yaml

sed -i "s/whitelistMode: true/whitelistMode: false/" ${BASE}/config/config.yaml
sed -i "s/basicAuthMode: false/basicAuthMode: true/" ${BASE}/config/config.yaml

echo "配置文件内容:"
cat ${BASE}/config/config.yaml

if [ ! -z "${HF_TOKEN}" ] && [ ! -z "${DATASET_ID}" ]; then
  echo "===== 启动前：先从魔搭同步恢复数据（前台阻塞，日志直接输出）====="
  RESTORE_ONLY=1 ${BASE}/syd.sh
  echo "===== 恢复流程结束，启动后台循环备份 ====="
  nohup ${BASE}/syd.sh > ${BASE}/sync_data.log 2>&1 &
  echo "数据同步服务已在后台启动"
else
  echo "未提供备份配置，跳过同步"
fi

exec node server.js --listen "$@"
