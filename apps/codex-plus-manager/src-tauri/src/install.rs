use std::path::PathBuf;

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct ShortcutState {
    pub installed: bool,
    pub path: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct EntryPointState {
    pub silent_shortcut: ShortcutState,
    pub management_shortcut: ShortcutState,
}

#[derive(Debug, Clone, Serialize)]
pub struct InstallActionResult {
    pub status: String,
    pub message: String,
    pub silent_shortcut: ShortcutState,
    pub management_shortcut: ShortcutState,
}

#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InstallOptions {
    #[serde(default)]
    pub remove_owned_data: bool,
}

impl ShortcutState {
    fn missing(path: Option<PathBuf>) -> Self {
        Self {
            installed: false,
            path: path.map(|path| path.to_string_lossy().to_string()),
        }
    }
}

pub fn inspect_entrypoints() -> EntryPointState {
    let desktop = desktop_dir();
    EntryPointState {
        silent_shortcut: ShortcutState::missing(
            desktop.as_ref().map(|path| path.join("Codex++.lnk")),
        ),
        management_shortcut: ShortcutState::missing(
            desktop
                .as_ref()
                .map(|path| path.join("Codex++ Manager.lnk")),
        ),
    }
}

pub fn install_entrypoints() -> InstallActionResult {
    skipped("安装入口尚未迁移到 Tauri；Task 8 将接入真实安装器。")
}

pub fn uninstall_entrypoints(options: InstallOptions) -> InstallActionResult {
    let suffix = if options.remove_owned_data {
        "已请求移除托管数据，但当前实现尚未执行。"
    } else {
        "未请求移除托管数据。"
    };
    skipped(&format!(
        "卸载入口尚未迁移到 Tauri；Task 8 将接入真实卸载器。{suffix}"
    ))
}

pub fn repair_shortcuts() -> InstallActionResult {
    skipped("快捷方式修复尚未迁移到 Tauri；Task 8 将接入真实修复逻辑。")
}

fn skipped(message: &str) -> InstallActionResult {
    let state = inspect_entrypoints();
    InstallActionResult {
        status: "not_implemented".to_string(),
        message: message.to_string(),
        silent_shortcut: state.silent_shortcut,
        management_shortcut: state.management_shortcut,
    }
}

fn desktop_dir() -> Option<PathBuf> {
    if cfg!(windows) {
        if let Some(user_profile) = std::env::var_os("USERPROFILE") {
            return Some(PathBuf::from(user_profile).join("Desktop"));
        }
    }
    directories::UserDirs::new().and_then(|dirs| dirs.desktop_dir().map(PathBuf::from))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn install_stub_reports_not_implemented_with_shortcut_state() {
        let result = install_entrypoints();

        assert_eq!(result.status, "not_implemented");
        assert!(!result.silent_shortcut.installed);
        assert!(!result.management_shortcut.installed);
    }

    #[test]
    fn uninstall_message_mentions_owned_data_request() {
        let result = uninstall_entrypoints(InstallOptions {
            remove_owned_data: true,
        });

        assert_eq!(result.status, "not_implemented");
        assert!(result.message.contains("移除托管数据"));
    }
}
