use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use codex_plus_core::settings::{BackendSettings, SettingsStore};
use codex_plus_core::status::{LaunchStatus, StatusStore};
use codex_plus_core::user_scripts::UserScriptManager;
use serde::Serialize;
use serde_json::{Value, json};

use crate::install::{self, InstallActionResult, InstallOptions};

#[derive(Debug, Clone, Serialize)]
pub struct CommandResult<T>
where
    T: Serialize,
{
    pub status: String,
    pub message: String,
    #[serde(flatten)]
    pub payload: T,
}

#[derive(Debug, Clone, Serialize)]
pub struct VersionPayload {
    pub version: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct PathState {
    pub status: String,
    pub path: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct OverviewPayload {
    pub codex_app: PathState,
    pub silent_shortcut: PathState,
    pub management_shortcut: PathState,
    pub latest_launch: Option<LaunchStatus>,
    pub current_version: String,
    pub update_status: String,
    pub settings_path: String,
    pub logs_path: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct SettingsPayload {
    pub settings: BackendSettings,
    pub settings_path: String,
    pub user_scripts: Value,
}

#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LaunchRequest {
    #[serde(default)]
    pub app_path: String,
    #[serde(default = "default_debug_port")]
    pub debug_port: u16,
    #[serde(default = "default_helper_port")]
    pub helper_port: u16,
}

#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogRequest {
    #[serde(default = "default_log_lines")]
    pub lines: usize,
}

#[derive(Debug, Clone, Serialize)]
pub struct LogsPayload {
    pub path: String,
    pub text: String,
    pub lines: usize,
}

#[derive(Debug, Clone, Serialize)]
pub struct DiagnosticsPayload {
    pub report: String,
}

#[tauri::command]
pub fn backend_version() -> CommandResult<VersionPayload> {
    ok(
        "后端版本已读取。",
        VersionPayload {
            version: codex_plus_core::version::VERSION.to_string(),
        },
    )
}

#[tauri::command]
pub fn load_overview() -> CommandResult<OverviewPayload> {
    let codex_app_path = codex_plus_core::app_paths::resolve_codex_app_dir(None);
    let entrypoints = install::inspect_entrypoints();
    let latest_launch = StatusStore::default().load_latest().unwrap_or(None);
    ok(
        "概览已加载。",
        OverviewPayload {
            codex_app: path_state(codex_app_path),
            silent_shortcut: shortcut_state(entrypoints.silent_shortcut),
            management_shortcut: shortcut_state(entrypoints.management_shortcut),
            latest_launch,
            current_version: codex_plus_core::version::VERSION.to_string(),
            update_status: "not_checked".to_string(),
            settings_path: codex_plus_core::paths::default_settings_path()
                .to_string_lossy()
                .to_string(),
            logs_path: codex_plus_core::paths::default_latest_status_path()
                .to_string_lossy()
                .to_string(),
        },
    )
}

#[tauri::command]
pub fn launch_codex_plus(request: LaunchRequest) -> CommandResult<Value> {
    let app_dir = if request.app_path.trim().is_empty() {
        None
    } else {
        Some(PathBuf::from(request.app_path.trim()))
    };
    let options = codex_plus_core::launcher::LaunchOptions {
        app_dir,
        debug_port: request.debug_port,
        helper_port: request.helper_port,
        status_store: StatusStore::default(),
    };

    let launch_result =
        tauri::async_runtime::block_on(codex_plus_core::launcher::launch_and_inject(options));
    match launch_result {
        Ok(handle) => {
            let payload = json!({
                "appPath": handle.app_dir.to_string_lossy(),
                "debugPort": handle.debug_port,
                "helperPort": handle.helper_port,
                "launchKind": launch_kind(&handle.launch)
            });
            let _ = std::thread::Builder::new()
                .name("codex-plus-manager-launch-wait".to_string())
                .spawn(move || {
                    let _ = tauri::async_runtime::block_on(handle.wait_for_codex_exit());
                });
            ok("Codex++ 已启动，后端注入已完成。", payload)
        }
        Err(error) => failed(
            &format!("启动失败：{error}"),
            json!({
                "debugPort": request.debug_port,
                "helperPort": request.helper_port
            }),
        ),
    }
}

#[tauri::command]
pub fn load_settings() -> CommandResult<SettingsPayload> {
    settings_payload("设置已加载。")
}

#[tauri::command]
pub fn save_settings(settings: BackendSettings) -> CommandResult<SettingsPayload> {
    match SettingsStore::default().save(&settings) {
        Ok(()) => settings_payload("设置已保存。"),
        Err(error) => failed(
            &format!("保存设置失败：{error}"),
            SettingsPayload {
                settings,
                settings_path: codex_plus_core::paths::default_settings_path()
                    .to_string_lossy()
                    .to_string(),
                user_scripts: user_script_inventory(),
            },
        ),
    }
}

#[tauri::command]
pub fn install_entrypoints() -> InstallActionResult {
    install::install_entrypoints()
}

#[tauri::command]
pub fn uninstall_entrypoints(options: InstallOptions) -> InstallActionResult {
    install::uninstall_entrypoints(options)
}

#[tauri::command]
pub fn repair_shortcuts() -> InstallActionResult {
    install::repair_shortcuts()
}

#[tauri::command]
pub fn check_update() -> CommandResult<Value> {
    skipped(
        "更新检查尚未接入发布源；Task 8 将实现真实更新检查。",
        json!({
            "currentVersion": codex_plus_core::version::VERSION,
            "latestVersion": Value::Null,
            "releaseSummary": "",
            "progress": 0
        }),
    )
}

#[tauri::command]
pub fn perform_update() -> CommandResult<Value> {
    skipped(
        "更新安装尚未实现；Task 8 将接入下载与安装流程。",
        json!({
            "currentVersion": codex_plus_core::version::VERSION,
            "progress": 0
        }),
    )
}

#[tauri::command]
pub fn read_latest_logs(request: LogRequest) -> CommandResult<LogsPayload> {
    let path = codex_plus_core::paths::default_latest_status_path();
    let text =
        read_tail(&path, request.lines).unwrap_or_else(|error| format!("无法读取日志：{error}"));
    ok(
        "日志已读取。",
        LogsPayload {
            path: path.to_string_lossy().to_string(),
            text,
            lines: request.lines,
        },
    )
}

#[tauri::command]
pub fn copy_diagnostics() -> CommandResult<DiagnosticsPayload> {
    ok(
        "诊断报告已生成。",
        DiagnosticsPayload {
            report: diagnostics_report(),
        },
    )
}

#[tauri::command]
pub fn reset_settings() -> CommandResult<SettingsPayload> {
    let settings = BackendSettings::default();
    match SettingsStore::default().save(&settings) {
        Ok(()) => settings_payload("设置已重置为默认值。"),
        Err(error) => failed(
            &format!("重置设置失败：{error}"),
            SettingsPayload {
                settings,
                settings_path: codex_plus_core::paths::default_settings_path()
                    .to_string_lossy()
                    .to_string(),
                user_scripts: user_script_inventory(),
            },
        ),
    }
}

fn settings_payload(message: &str) -> CommandResult<SettingsPayload> {
    let store = SettingsStore::default();
    let settings = store.load().unwrap_or_default();
    ok(
        message,
        SettingsPayload {
            settings,
            settings_path: codex_plus_core::paths::default_settings_path()
                .to_string_lossy()
                .to_string(),
            user_scripts: user_script_inventory(),
        },
    )
}

fn user_script_inventory() -> Value {
    default_user_script_manager()
        .inventory()
        .unwrap_or_else(|error| {
            json!({
                "enabled": true,
                "scripts": [],
                "error": error.to_string()
            })
        })
}

fn default_user_script_manager() -> UserScriptManager {
    let config_dir = user_scripts_config_dir();
    UserScriptManager::new(
        builtin_user_scripts_dir(),
        config_dir.join("user_scripts"),
        config_dir.join("user_scripts.json"),
    )
}

fn user_scripts_config_dir() -> PathBuf {
    if cfg!(windows) {
        if let Some(roaming) = std::env::var_os("APPDATA") {
            return PathBuf::from(roaming).join("Codex++");
        }
    }
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| directories::BaseDirs::new().map(|dirs| dirs.home_dir().join(".config")))
        .unwrap_or_else(|| PathBuf::from(".config"))
        .join("Codex++")
}

fn builtin_user_scripts_dir() -> PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|path| path.parent().map(Path::to_path_buf))
        .map(|path| path.join("user_scripts"))
        .unwrap_or_else(|| PathBuf::from("user_scripts"))
}

fn diagnostics_report() -> String {
    let overview = load_overview();
    let settings = SettingsStore::default().load().unwrap_or_default();
    let generated_at_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    serde_json::to_string_pretty(&json!({
        "generatedAtMs": generated_at_ms,
        "version": codex_plus_core::version::VERSION,
        "overview": overview.payload,
        "settings": settings,
        "platform": {
            "os": std::env::consts::OS,
            "arch": std::env::consts::ARCH
        }
    }))
    .unwrap_or_else(|error| format!("诊断报告序列化失败：{error}"))
}

fn read_tail(path: &Path, max_lines: usize) -> std::io::Result<String> {
    let contents = fs::read_to_string(path)?;
    let mut lines = contents.lines().rev().take(max_lines).collect::<Vec<_>>();
    lines.reverse();
    Ok(lines.join("\n"))
}

fn path_state(path: Option<PathBuf>) -> PathState {
    match path {
        Some(path) => PathState {
            status: "found".to_string(),
            path: Some(path.to_string_lossy().to_string()),
        },
        None => PathState {
            status: "missing".to_string(),
            path: None,
        },
    }
}

fn shortcut_state(shortcut: install::ShortcutState) -> PathState {
    PathState {
        status: if shortcut.installed {
            "installed".to_string()
        } else {
            "missing".to_string()
        },
        path: shortcut.path,
    }
}

fn launch_kind(launch: &codex_plus_core::launcher::CodexLaunch) -> &'static str {
    match launch {
        codex_plus_core::launcher::CodexLaunch::Process { .. } => "process",
        codex_plus_core::launcher::CodexLaunch::PackagedActivation { .. } => "packaged_activation",
    }
}

fn ok<T: Serialize>(message: &str, payload: T) -> CommandResult<T> {
    CommandResult {
        status: "ok".to_string(),
        message: message.to_string(),
        payload,
    }
}

fn skipped<T: Serialize>(message: &str, payload: T) -> CommandResult<T> {
    CommandResult {
        status: "not_implemented".to_string(),
        message: message.to_string(),
        payload,
    }
}

fn failed<T: Serialize>(message: &str, payload: T) -> CommandResult<T> {
    CommandResult {
        status: "failed".to_string(),
        message: message.to_string(),
        payload,
    }
}

fn default_debug_port() -> u16 {
    9229
}

fn default_helper_port() -> u16 {
    57321
}

fn default_log_lines() -> usize {
    200
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backend_version_returns_structured_payload() {
        let result = backend_version();

        assert_eq!(result.status, "ok");
        assert!(!result.payload.version.is_empty());
    }

    #[test]
    fn overview_contains_expected_operational_fields() {
        let result = load_overview();

        assert_eq!(result.status, "ok");
        assert!(!result.payload.current_version.is_empty());
        assert!(matches!(
            result.payload.codex_app.status.as_str(),
            "found" | "missing"
        ));
        assert!(matches!(
            result.payload.silent_shortcut.status.as_str(),
            "installed" | "missing"
        ));
    }

    #[test]
    fn update_commands_are_honest_stubs() {
        assert_eq!(check_update().status, "not_implemented");
        assert_eq!(perform_update().status, "not_implemented");
    }
}
