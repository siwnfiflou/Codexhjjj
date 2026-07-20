#!/bin/sh

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
}

# ═══════════════════════════════════════════════
# 环境变量
#   HF_TOKEN / DATASET_ID     : HuggingFace 备份【仅上传】（必需，缺失则整体不启用）
#   MS_TOKEN / MS_DATASET_ID  : 魔搭(ModelScope) 备份【上传 + 下载恢复】（可选）
#   SYNC_INTERVAL             : 同步间隔秒数，默认 3600
# ═══════════════════════════════════════════════
if [ -z "$HF_TOKEN" ] || [ -z "$DATASET_ID" ]; then
    log_error "未启用备份功能 - 缺少HF_TOKEN或DATASET_ID环境变量"
    log_info "HF_TOKEN=${HF_TOKEN:0:3}... DATASET_ID=${DATASET_ID}"
    exit 0
fi

# 魔搭是否启用（下载恢复依赖魔搭）
MS_ENABLED=0
if [ -n "$MS_TOKEN" ] && [ -n "$MS_DATASET_ID" ]; then
    MS_ENABLED=1
fi

TEMP_DIR="/tmp/sillytavern_backup"
DATA_DIR="/home/node/app/data"

# 魔搭上传固定文件名（覆盖式，天然只保留最新一份，
# 规避魔搭用token认证无法通过API删除文件的限制）
MS_BACKUP_NAME="sillytavern_backup.tar.gz"

mkdir -p $TEMP_DIR
chmod -R 777 $TEMP_DIR
mkdir -p $DATA_DIR
chmod -R 777 $DATA_DIR

log_info "临时目录: $TEMP_DIR"
log_info "数据目录: $DATA_DIR"
log_info "HF_TOKEN: ${HF_TOKEN:0:5}..."
log_info "DATASET_ID: $DATASET_ID"
if [ "$MS_ENABLED" -eq 1 ]; then
    log_info "魔搭已启用 - MS_DATASET_ID: $MS_DATASET_ID（用于上传+下载恢复）"
else
    log_info "魔搭未启用（缺少MS_TOKEN或MS_DATASET_ID），将无法进行下载恢复"
fi

# ═══════════════════════════════════════════════
# 依赖安装
# ═══════════════════════════════════════════════
if ! command -v python3 > /dev/null 2>&1; then
    log_info "正在安装Python..."
    apk add --no-cache python3 py3-pip
else
    log_info "Python3已安装: $(python3 --version)"
fi

if ! command -v pip3 > /dev/null 2>&1; then
    log_info "正在安装pip..."
    apk add --no-cache py3-pip
else
    log_info "Pip3已安装: $(pip3 --version)"
fi

log_info "正在安装/更新huggingface_hub..."
pip3 install --no-cache-dir --upgrade huggingface_hub
log_info "huggingface_hub安装完成"

if ! python3 -c "import huggingface_hub" > /dev/null 2>&1; then
    log_error "huggingface_hub导入失败，正在重试安装..."
    pip3 install --no-cache-dir huggingface_hub
fi

if [ "$MS_ENABLED" -eq 1 ]; then
    log_info "正在安装/更新modelscope-hub..."
    pip3 install --no-cache-dir --upgrade modelscope-hub
    if ! python3 -c "import modelscope_hub" > /dev/null 2>&1; then
        log_error "modelscope-hub导入失败，正在重试安装..."
        pip3 install --no-cache-dir modelscope-hub
    fi
    log_info "modelscope-hub安装完成"
fi

touch "${TEMP_DIR}/test_file" && rm "${TEMP_DIR}/test_file"
if [ $? -ne 0 ]; then
    log_error "修复权限..."
    chmod -R 777 $TEMP_DIR
fi

# ═══════════════════════════════════════════════
# 连接与权限测试
# ═══════════════════════════════════════════════
log_info "正在测试HuggingFace API的连接..."
python3 -c "
from huggingface_hub import HfApi
try:
    api = HfApi(token='$HF_TOKEN')
    user_info = api.whoami()
    print(f'成功连接到HuggingFace API，用户: {user_info}')
except Exception as e:
    print(f'连接HuggingFace API失败: {str(e)}')
    exit(1)
"
if [ $? -ne 0 ]; then
    log_error "HuggingFace API连接测试失败，检查令牌"
else
    log_info "HuggingFace API连接测试成功"
fi

TEST_FILE_NAME="test_file_$(date +%s)"

log_info "HuggingFace Dataset权限测试..."
python3 -c "
from huggingface_hub import HfApi
try:
    api = HfApi(token='$HF_TOKEN')

    with open('$TEMP_DIR/test_file', 'w') as f:
        f.write('test')

    test_file_name = '$TEST_FILE_NAME'
    print(f'正在上传测试文件: {test_file_name}')

    api.upload_file(
        path_or_fileobj='$TEMP_DIR/test_file',
        path_in_repo=test_file_name,
        repo_id='$DATASET_ID',
        repo_type='dataset'
    )
    print('成功上传测试文件到Dataset')

    print('删除文件...')
    api.delete_file(
        path_in_repo=test_file_name,
        repo_id='$DATASET_ID',
        repo_type='dataset'
    )
    print('成功')

except Exception as e:
    print(f'Dataset权限测试失败: {str(e)}')
    exit(1)
"
if [ $? -ne 0 ]; then
    log_error "HuggingFace Dataset权限测试失败，请检查DATASET_ID是否正确且有写入权限"
else
    log_info "HuggingFace Dataset权限测试成功，测试文件已清理"
fi

rm -f "$TEMP_DIR/test_file"

# 魔搭连接测试（仅测试连接，不测试删除，因为token无法删除）
if [ "$MS_ENABLED" -eq 1 ]; then
    log_info "正在测试魔搭API的连接..."
    python3 -c "
from modelscope_hub import HubApi
try:
    api = HubApi(token='$MS_TOKEN')
    user = api.whoami()
    print(f'成功连接到魔搭API，用户: {user}')
except Exception as e:
    print(f'连接魔搭API失败: {str(e)}')
    exit(1)
"
    if [ $? -ne 0 ]; then
        log_error "魔搭API连接测试失败，检查MS_TOKEN"
    else
        log_info "魔搭API连接测试成功"
    fi
fi

# ═══════════════════════════════════════════════
# 上传：HuggingFace（保留最近N个 + 自动删旧）
# ═══════════════════════════════════════════════
upload_backup_hf() {
    file_path="$1"
    file_name="$2"

    if [ ! -f "$file_path" ]; then
        log_error "备份文件不存在: $file_path"
        return 1
    fi

    log_info "开始上传备份到HuggingFace: $file_name ($(du -h $file_path | cut -f1))"

    python3 -c "
from huggingface_hub import HfApi
import sys
import os
import time
def manage_backups(api, repo_id, max_files=10):
    try:
        files = api.list_repo_files(repo_id=repo_id, repo_type='dataset')
        backup_files = [f for f in files if f.startswith('sillytavern_backup_') and f.endswith('.tar.gz')]
        backup_files.sort()

        if len(backup_files) >= max_files:
            files_to_delete = backup_files[:(len(backup_files) - max_files + 1)]
            for file_to_delete in files_to_delete:
                try:
                    api.delete_file(path_in_repo=file_to_delete, repo_id=repo_id, repo_type='dataset')
                    print(f'已删除旧备份: {file_to_delete}')
                except Exception as e:
                    print(f'删除 {file_to_delete} 时出错: {str(e)}')
    except Exception as e:
        print(f'管理备份文件时出错: {str(e)}')
token='$HF_TOKEN'
repo_id='$DATASET_ID'
try:
    api = HfApi(token=token)

    file_size = os.path.getsize('$file_path')
    print(f'备份文件大小: {file_size / (1024*1024):.2f} MB')
    try:
        dataset_info = api.dataset_info(repo_id=repo_id)
        print(f'Dataset信息: {dataset_info.id}')
    except Exception as e:
        print(f'获取Dataset信息失败: {str(e)}')

    start_time = time.time()
    print(f'开始上传: {start_time}')

    api.upload_file(
        path_or_fileobj='$file_path',
        path_in_repo='$file_name',
        repo_id=repo_id,
        repo_type='dataset'
    )

    end_time = time.time()
    print(f'上传完成，耗时: {end_time - start_time:.2f} 秒')
    print(f'成功上传 $file_name')

    manage_backups(api, repo_id)
except Exception as e:
    print(f'上传文件时出错: {str(e)}')
    sys.exit(1)
"
    if [ $? -ne 0 ]; then
        log_error "HuggingFace备份上传失败"
        return 1
    else
        log_info "HuggingFace备份上传成功"
        return 0
    fi
}

# ═══════════════════════════════════════════════
# 上传：魔搭（固定文件名覆盖，只保留最新一份）
# ═══════════════════════════════════════════════
upload_backup_ms() {
    file_path="$1"

    if [ "$MS_ENABLED" -ne 1 ]; then
        return 0
    fi
    if [ ! -f "$file_path" ]; then
        log_error "备份文件不存在: $file_path"
        return 1
    fi

    log_info "开始上传备份到魔搭: $MS_BACKUP_NAME ($(du -h $file_path | cut -f1))"

    python3 -c "
from modelscope_hub import HubApi
import sys, os, time
try:
    api = HubApi(token='$MS_TOKEN')
    file_size = os.path.getsize('$file_path')
    print(f'备份文件大小: {file_size / (1024*1024):.2f} MB')

    start_time = time.time()
    print(f'开始上传: {start_time}')

    # 固定远程文件名，覆盖式上传，天然只保留最新一份
    api.upload_file(
        '$MS_DATASET_ID',    # repo_id
        'dataset',           # repo_type
        '$file_path',        # 本地文件
        '$MS_BACKUP_NAME',   # 仓库内路径（固定名）
    )

    end_time = time.time()
    print(f'上传完成，耗时: {end_time - start_time:.2f} 秒')
    print(f'成功上传 $MS_BACKUP_NAME 到魔搭')
except Exception as e:
    print(f'上传到魔搭时出错: {str(e)}')
    sys.exit(1)
"
    if [ $? -ne 0 ]; then
        log_error "魔搭备份上传失败"
        return 1
    else
        log_info "魔搭备份上传成功"
        return 0
    fi
}

# ═══════════════════════════════════════════════
# 下载恢复：从魔搭下载固定文件名的备份并解压
# ═══════════════════════════════════════════════
download_latest_backup() {
    if [ "$MS_ENABLED" -ne 1 ]; then
        log_error "魔搭未启用，跳过下载恢复"
        return 1
    fi

    log_info "开始从魔搭下载最新备份..."

    python3 -c "
from modelscope_hub import HubApi
import sys, os, tarfile, tempfile, time
try:
    api = HubApi(token='$MS_TOKEN')
    print('已创建魔搭API实例')

    with tempfile.TemporaryDirectory() as temp_dir:
        print(f'创建临时目录: {temp_dir}')

        start_time = time.time()
        print(f'开始下载: {start_time}')

        try:
            # 下载魔搭数据集中固定文件名的备份
            filepath = api.download_file(
                '$MS_DATASET_ID',        # repo_id
                'dataset',               # repo_type
                '$MS_BACKUP_NAME',       # 仓库内文件名
                local_dir=temp_dir,
            )
            print(f'文件下载到: {filepath}')
        except Exception as e:
            print(f'下载文件失败（可能是首次运行、魔搭尚无备份）: {str(e)}')
            sys.exit(0)

        end_time = time.time()
        print(f'下载完成，耗时: {end_time - start_time:.2f} 秒')

        if filepath and os.path.exists(filepath):
            os.makedirs('$DATA_DIR', exist_ok=True)
            print(f'文件权限: {oct(os.stat(filepath).st_mode)[-3:]}')
            try:
                with tarfile.open(filepath, 'r:gz') as tar:
                    print('开始解压文件...')
                    tar.extractall('$DATA_DIR')
                    print('文件解压完成')
            except Exception as e:
                print(f'解压文件失败: {str(e)}')
                sys.exit(1)
            print(f'成功从魔搭 $MS_BACKUP_NAME 恢复备份')
        else:
            print('下载的文件路径无效')
            sys.exit(1)
except Exception as e:
    print(f'下载备份过程中出错: {str(e)}')
    sys.exit(1)
"
    if [ $? -ne 0 ]; then
        log_error "备份下载失败"
        return 1
    else
        log_info "备份下载成功"
        return 0
    fi
}

# ═══════════════════════════════════════════════
# 启动时：从魔搭下载恢复
# ═══════════════════════════════════════════════
log_info "正在从魔搭下载最新备份..."
download_latest_backup

# ═══════════════════════════════════════════════
# 同步主循环：上传到 HF + 魔搭
# ═══════════════════════════════════════════════
syn() {
    log_info "数据同步服务已启动"

    while true; do
        log_info "开始同步进程，时间: $(date)"

        if [ -d "$DATA_DIR" ]; then
            timestamp=$(date +%Y%m%d_%H%M%S)
            backup_file="sillytavern_backup_${timestamp}.tar.gz"
            backup_path="${TEMP_DIR}/${backup_file}"

            log_info "创建备份文件: $backup_path"

            file_count=$(find "$DATA_DIR" -type f | wc -l)
            log_info "数据目录文件数量: $file_count"

            if [ "$file_count" -eq 0 ]; then
                log_info "数据目录为空，跳过备份"
            else
                tar -czf "$backup_path" -C "$DATA_DIR" .
                if [ $? -ne 0 ]; then
                    log_error "创建压缩文件失败"
                else
                    log_info "压缩文件创建成功: $(du -h $backup_path | cut -f1)"

                    # 1) 上传到 HuggingFace（带时间戳，保留最近10个，自动删旧）
                    log_info "正在上传备份到HuggingFace..."
                    upload_backup_hf "$backup_path" "$backup_file"

                    # 2) 上传到魔搭（固定文件名覆盖，只保留最新一份）
                    upload_backup_ms "$backup_path"

                    # 删除本地临时备份文件
                    rm -f "$backup_path"
                    log_info "已删除临时备份文件"
                fi
            fi
        else
            log_error "数据目录不存在: $DATA_DIR"
            mkdir -p "$DATA_DIR"
            chmod -R 777 "$DATA_DIR"
        fi

        SYNC_INTERVAL=${SYNC_INTERVAL:-3600}
        log_info "下次同步将在 ${SYNC_INTERVAL} 秒后进行..."
        sleep $SYNC_INTERVAL
    done
}

# 启动同步进程
# 启动同步进程
if [ "${RESTORE_ONLY:-0}" = "1" ]; then
    log_info "RESTORE_ONLY 模式：恢复已完成，退出，不进入备份循环。"
    exit 0
fi

syn

