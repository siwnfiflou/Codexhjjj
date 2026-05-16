pub mod commands;
pub mod install;

pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            commands::backend_version,
            commands::load_overview,
            commands::launch_codex_plus,
            commands::load_settings,
            commands::save_settings,
            commands::install_entrypoints,
            commands::uninstall_entrypoints,
            commands::repair_shortcuts,
            commands::check_update,
            commands::perform_update,
            commands::read_latest_logs,
            commands::copy_diagnostics,
            commands::reset_settings
        ])
        .run(tauri::generate_context!())
        .expect("failed to run Codex++ manager");
}
