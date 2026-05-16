import { invoke } from "@tauri-apps/api/core";

type Status = "ok" | "failed" | "not_implemented" | "not_checked" | string;

type CommandResult<T> = T & {
  status: Status;
  message: string;
};

type PathState = {
  status: string;
  path: string | null;
};

type LaunchStatus = {
  status: string;
  message: string;
  started_at_ms: number;
  debug_port: number | null;
  helper_port: number | null;
  codex_app: string | null;
};

type OverviewResult = CommandResult<{
  codex_app: PathState;
  silent_shortcut: PathState;
  management_shortcut: PathState;
  latest_launch: LaunchStatus | null;
  current_version: string;
  update_status: string;
  settings_path: string;
  logs_path: string;
}>;

type BackendSettings = {
  providerSyncEnabled: boolean;
  cliWrapperEnabled: boolean;
  cliWrapperBaseUrl: string;
  cliWrapperApiKey: string;
  cliWrapperApiKeyEnv: string;
};

type UserScriptInventory = {
  enabled?: boolean;
  builtin_dir?: string;
  user_dir?: string;
  scripts?: Array<{
    key: string;
    name: string;
    source: string;
    enabled: boolean;
    status: string;
    error: string;
  }>;
  error?: string;
};

type SettingsResult = CommandResult<{
  settings: BackendSettings;
  settings_path: string;
  user_scripts: UserScriptInventory;
}>;

type LogsResult = CommandResult<{
  path: string;
  text: string;
  lines: number;
}>;

type DiagnosticsResult = CommandResult<{
  report: string;
}>;

type InstallResult = CommandResult<{
  silent_shortcut: { installed: boolean; path: string | null };
  management_shortcut: { installed: boolean; path: string | null };
}>;

type UpdateResult = CommandResult<{
  currentVersion: string;
  latestVersion?: string | null;
  releaseSummary?: string;
  progress?: number;
}>;

type Route = "overview" | "launch" | "install" | "update" | "settings" | "logs" | "diagnostics";

const routes: Array<{ id: Route; label: string; symbol: string }> = [
  { id: "overview", label: "概览", symbol: "O" },
  { id: "launch", label: "启动", symbol: "L" },
  { id: "install", label: "安装", symbol: "I" },
  { id: "update", label: "更新", symbol: "U" },
  { id: "settings", label: "设置", symbol: "S" },
  { id: "logs", label: "日志", symbol: "G" },
  { id: "diagnostics", label: "诊断", symbol: "D" },
];

const defaultSettings: BackendSettings = {
  providerSyncEnabled: false,
  cliWrapperEnabled: false,
  cliWrapperBaseUrl: "",
  cliWrapperApiKey: "",
  cliWrapperApiKeyEnv: "CUSTOM_OPENAI_API_KEY",
};

type State = {
  route: Route;
  busy: boolean;
  notice: string;
  overview: OverviewResult | null;
  settings: SettingsResult | null;
  logs: LogsResult | null;
  diagnostics: DiagnosticsResult | null;
  update: UpdateResult | null;
  launchForm: {
    appPath: string;
    debugPort: string;
    helperPort: string;
  };
  settingsForm: BackendSettings;
  removeOwnedData: boolean;
};

export function mountApp(root: HTMLElement) {
  const state: State = {
    route: "overview",
    busy: false,
    notice: "",
    overview: null,
    settings: null,
    logs: null,
    diagnostics: null,
    update: null,
    launchForm: {
      appPath: "",
      debugPort: "9229",
      helperPort: "57321",
    },
    settingsForm: { ...defaultSettings },
    removeOwnedData: false,
  };

  const run = async <T>(task: () => Promise<T>): Promise<T | null> => {
    state.busy = true;
    render();
    try {
      return await task();
    } catch (error) {
      state.notice = `调用失败：${stringifyError(error)}`;
      return null;
    } finally {
      state.busy = false;
      render();
    }
  };

  const call = <T>(command: string, args?: Record<string, unknown>) => invoke<T>(command, args);

  const refreshOverview = async () => {
    const result = await run(() => call<OverviewResult>("load_overview"));
    if (result) {
      state.overview = result;
      state.notice = result.message;
    }
  };

  const refreshSettings = async () => {
    const result = await run(() => call<SettingsResult>("load_settings"));
    if (result) {
      state.settings = result;
      state.settingsForm = { ...result.settings };
      state.notice = result.message;
    }
  };

  const refreshLogs = async () => {
    const result = await run(() => call<LogsResult>("read_latest_logs", { request: { lines: 240 } }));
    if (result) {
      state.logs = result;
      state.notice = result.message;
    }
  };

  const refreshDiagnostics = async () => {
    const result = await run(() => call<DiagnosticsResult>("copy_diagnostics"));
    if (result) {
      state.diagnostics = result;
      state.notice = result.message;
    }
  };

  const navigate = async (route: Route) => {
    state.route = route;
    render();
    if (route === "overview") await refreshOverview();
    if (route === "settings") await refreshSettings();
    if (route === "logs") await refreshLogs();
    if (route === "diagnostics") await refreshDiagnostics();
  };

  const launch = async () => {
    const result = await run(() =>
      call<CommandResult<Record<string, unknown>>>("launch_codex_plus", {
        request: {
          appPath: state.launchForm.appPath,
          debugPort: numberOrDefault(state.launchForm.debugPort, 9229),
          helperPort: numberOrDefault(state.launchForm.helperPort, 57321),
        },
      }),
    );
    if (result) {
      state.notice = result.message;
      await refreshOverview();
      state.route = "launch";
    }
  };

  const repairBackend = async () => {
    const result = await run(() => call<InstallResult>("repair_shortcuts"));
    if (result) state.notice = `后端修复入口：${result.message}`;
  };

  const installEntrypoints = async () => {
    const result = await run(() => call<InstallResult>("install_entrypoints"));
    if (result) {
      state.notice = result.message;
      await refreshOverview();
      state.route = "install";
    }
  };

  const uninstallEntrypoints = async () => {
    const result = await run(() =>
      call<InstallResult>("uninstall_entrypoints", {
        options: { removeOwnedData: state.removeOwnedData },
      }),
    );
    if (result) {
      state.notice = result.message;
      await refreshOverview();
      state.route = "install";
    }
  };

  const repairShortcuts = async () => {
    const result = await run(() => call<InstallResult>("repair_shortcuts"));
    if (result) {
      state.notice = result.message;
      await refreshOverview();
      state.route = "install";
    }
  };

  const checkUpdate = async () => {
    const result = await run(() => call<UpdateResult>("check_update"));
    if (result) {
      state.update = result;
      state.notice = result.message;
    }
  };

  const performUpdate = async () => {
    const result = await run(() => call<UpdateResult>("perform_update"));
    if (result) {
      state.update = result;
      state.notice = result.message;
    }
  };

  const saveSettings = async () => {
    const result = await run(() => call<SettingsResult>("save_settings", { settings: state.settingsForm }));
    if (result) {
      state.settings = result;
      state.settingsForm = { ...result.settings };
      state.notice = result.message;
    }
  };

  const resetSettings = async () => {
    const result = await run(() => call<SettingsResult>("reset_settings"));
    if (result) {
      state.settings = result;
      state.settingsForm = { ...result.settings };
      state.notice = result.message;
    }
  };

  const copyText = async (text: string, message: string) => {
    try {
      await navigator.clipboard.writeText(text);
      state.notice = message;
    } catch (error) {
      state.notice = `复制失败：${stringifyError(error)}`;
    }
    render();
  };

  const render = () => {
    root.innerHTML = `
      <div class="shell">
        <aside class="sidebar">
          <div class="brand">
            <div class="brand-mark">C++</div>
            <div>
              <div class="brand-title">Codex++</div>
              <div class="brand-subtitle">管理控制台</div>
            </div>
          </div>
          <nav class="nav">
            ${routes
              .map(
                (item) => `
                  <button class="nav-item ${state.route === item.id ? "active" : ""}" data-route="${item.id}" title="${item.label}">
                    <span>${item.symbol}</span>
                    ${item.label}
                  </button>
                `,
              )
              .join("")}
          </nav>
        </aside>
        <main class="workspace">
          <header class="topbar">
            <div>
              <h1>${routeTitle(state.route)}</h1>
              <p>${routeSubtitle(state.route)}</p>
            </div>
            <div class="topbar-actions">
              <button class="icon-button" data-action="refresh-current" title="刷新当前页面">R</button>
            </div>
          </header>
          ${state.notice ? `<div class="notice">${escapeHtml(state.notice)}</div>` : ""}
          ${state.busy ? `<div class="busy">正在处理...</div>` : ""}
          <section class="screen">${renderScreen()}</section>
        </main>
      </div>
    `;
  };

  const renderScreen = () => {
    if (state.route === "overview") return renderOverview();
    if (state.route === "launch") return renderLaunch();
    if (state.route === "install") return renderInstall();
    if (state.route === "update") return renderUpdate();
    if (state.route === "settings") return renderSettings();
    if (state.route === "logs") return renderLogs();
    return renderDiagnostics();
  };

  const renderOverview = () => {
    const overview = state.overview;
    return `
      <div class="grid two">
        ${statusPanel("Codex 应用", overview?.codex_app.status, overview?.codex_app.path)}
        ${statusPanel("静默快捷方式", overview?.silent_shortcut.status, overview?.silent_shortcut.path)}
        ${statusPanel("管理快捷方式", overview?.management_shortcut.status, overview?.management_shortcut.path)}
        ${statusPanel("更新状态", overview?.update_status ?? "not_checked", `当前版本 ${overview?.current_version ?? "-"}`)}
      </div>
      <div class="panel">
        <div class="panel-head">
          <h2>最近启动</h2>
          <span class="muted">${overview?.logs_path ? escapeHtml(overview.logs_path) : "暂无状态文件"}</span>
        </div>
        ${renderLatestLaunch(overview?.latest_launch ?? null)}
      </div>
      <div class="toolbar">
        <button data-action="launch">启动 Codex++</button>
        <button data-action="repair-shortcuts">修复快捷方式</button>
        <button data-action="go-logs">打开日志</button>
      </div>
    `;
  };

  const renderLaunch = () => `
    <div class="panel">
      <div class="panel-head">
        <h2>手动启动</h2>
        <span class="muted">留空应用路径时使用自动探测</span>
      </div>
      <label class="field">
        <span>应用路径覆盖</span>
        <input data-field="launch.appPath" value="${escapeAttr(state.launchForm.appPath)}" placeholder="例如 C:\\Program Files\\WindowsApps\\OpenAI.Codex...\\app" />
      </label>
      <div class="form-row">
        <label class="field">
          <span>Debug 端口</span>
          <input data-field="launch.debugPort" inputmode="numeric" value="${escapeAttr(state.launchForm.debugPort)}" />
        </label>
        <label class="field">
          <span>Helper 端口</span>
          <input data-field="launch.helperPort" inputmode="numeric" value="${escapeAttr(state.launchForm.helperPort)}" />
        </label>
      </div>
      <div class="toolbar">
        <button data-action="launch">启动</button>
        <button data-action="repair-backend">修复后端</button>
      </div>
    </div>
  `;

  const renderInstall = () => `
    <div class="panel">
      <div class="panel-head">
        <h2>入口管理</h2>
        <span class="muted">安装器迁移前返回真实 stub 状态</span>
      </div>
      <div class="grid two">
        ${statusPanel("静默启动入口", state.overview?.silent_shortcut.status, state.overview?.silent_shortcut.path)}
        ${statusPanel("管理控制台入口", state.overview?.management_shortcut.status, state.overview?.management_shortcut.path)}
      </div>
      <label class="check-row">
        <input data-field="removeOwnedData" type="checkbox" ${state.removeOwnedData ? "checked" : ""} />
        <span>卸载时移除 Codex++ 托管数据</span>
      </label>
      <div class="toolbar">
        <button data-action="install-entrypoints">安装入口</button>
        <button data-action="uninstall-entrypoints">卸载入口</button>
        <button data-action="repair-shortcuts">修复快捷方式</button>
      </div>
    </div>
  `;

  const renderUpdate = () => {
    const update = state.update;
    return `
      <div class="panel">
        <div class="panel-head">
          <h2>更新</h2>
          <span class="muted">当前版本 ${escapeHtml(state.overview?.current_version ?? update?.currentVersion ?? "-")}</span>
        </div>
        <div class="metric-list">
          <div><span>状态</span><strong>${escapeHtml(update?.status ?? "not_checked")}</strong></div>
          <div><span>最新版本</span><strong>${escapeHtml(update?.latestVersion ?? "未检查")}</strong></div>
          <div><span>进度</span><strong>${escapeHtml(String(update?.progress ?? 0))}%</strong></div>
        </div>
        <textarea readonly class="log-view">${escapeHtml(update?.releaseSummary || update?.message || "尚未检查更新。")}</textarea>
        <div class="toolbar">
          <button data-action="check-update">检查更新</button>
          <button data-action="perform-update">安装更新</button>
        </div>
      </div>
    `;
  };

  const renderSettings = () => {
    const scripts = state.settings?.user_scripts.scripts ?? [];
    return `
      <div class="panel">
        <div class="panel-head">
          <h2>后端设置</h2>
          <span class="muted">${escapeHtml(state.settings?.settings_path ?? "")}</span>
        </div>
        <label class="check-row">
          <input data-field="settings.providerSyncEnabled" type="checkbox" ${state.settingsForm.providerSyncEnabled ? "checked" : ""} />
          <span>启用 Provider 同步</span>
        </label>
        <label class="check-row">
          <input data-field="settings.cliWrapperEnabled" type="checkbox" ${state.settingsForm.cliWrapperEnabled ? "checked" : ""} />
          <span>启用 Codex 命令包装器</span>
        </label>
        <div class="form-row">
          <label class="field">
            <span>包装器 Base URL</span>
            <input data-field="settings.cliWrapperBaseUrl" value="${escapeAttr(state.settingsForm.cliWrapperBaseUrl)}" />
          </label>
          <label class="field">
            <span>API Key 环境变量</span>
            <input data-field="settings.cliWrapperApiKeyEnv" value="${escapeAttr(state.settingsForm.cliWrapperApiKeyEnv)}" />
          </label>
        </div>
        <label class="field">
          <span>API Key</span>
          <input data-field="settings.cliWrapperApiKey" type="password" value="${escapeAttr(state.settingsForm.cliWrapperApiKey)}" />
        </label>
        <div class="toolbar">
          <button data-action="save-settings">保存设置</button>
          <button data-action="reset-settings">重置设置</button>
        </div>
      </div>
      <div class="panel">
        <div class="panel-head">
          <h2>用户脚本</h2>
          <span class="muted">${scripts.length} 个脚本，整体 ${state.settings?.user_scripts.enabled === false ? "关闭" : "开启"}</span>
        </div>
        <div class="table">
          ${scripts.length ? scripts.map(renderScriptRow).join("") : `<div class="empty">未发现用户脚本。</div>`}
        </div>
      </div>
    `;
  };

  const renderLogs = () => `
    <div class="panel fill">
      <div class="panel-head">
        <h2>最近日志</h2>
        <span class="muted">${escapeHtml(state.logs?.path ?? "")}</span>
      </div>
      <textarea readonly class="log-view tall">${escapeHtml(state.logs?.text ?? "暂无日志。")}</textarea>
      <div class="toolbar">
        <button data-action="refresh-logs">刷新</button>
        <button data-action="copy-logs">复制</button>
      </div>
    </div>
  `;

  const renderDiagnostics = () => `
    <div class="panel fill">
      <div class="panel-head">
        <h2>诊断报告</h2>
        <span class="muted">包含版本、路径、设置和平台信息</span>
      </div>
      <textarea readonly class="log-view tall">${escapeHtml(state.diagnostics?.report ?? "尚未生成诊断报告。")}</textarea>
      <div class="toolbar">
        <button data-action="refresh-diagnostics">重新生成</button>
        <button data-action="copy-diagnostics">复制报告</button>
      </div>
    </div>
  `;

  root.addEventListener("click", (event) => {
    const target = event.target as HTMLElement;
    const routeButton = target.closest<HTMLElement>("[data-route]");
    if (routeButton) {
      void navigate(routeButton.dataset.route as Route);
      return;
    }
    const action = target.closest<HTMLElement>("[data-action]")?.dataset.action;
    if (!action) return;
    const handlers: Record<string, () => void | Promise<void>> = {
      "refresh-current": () => navigate(state.route),
      launch,
      "repair-backend": repairBackend,
      "go-logs": () => navigate("logs"),
      "install-entrypoints": installEntrypoints,
      "uninstall-entrypoints": uninstallEntrypoints,
      "repair-shortcuts": repairShortcuts,
      "check-update": checkUpdate,
      "perform-update": performUpdate,
      "save-settings": saveSettings,
      "reset-settings": resetSettings,
      "refresh-logs": refreshLogs,
      "copy-logs": () => copyText(state.logs?.text ?? "", "日志已复制。"),
      "refresh-diagnostics": refreshDiagnostics,
      "copy-diagnostics": () => copyText(state.diagnostics?.report ?? "", "诊断报告已复制。"),
    };
    void handlers[action]?.();
  });

  root.addEventListener("input", (event) => {
    const target = event.target as HTMLInputElement;
    const field = target.dataset.field;
    if (!field) return;
    updateField(field, target);
  });

  const updateField = (field: string, target: HTMLInputElement) => {
    if (field === "launch.appPath") state.launchForm.appPath = target.value;
    if (field === "launch.debugPort") state.launchForm.debugPort = target.value;
    if (field === "launch.helperPort") state.launchForm.helperPort = target.value;
    if (field === "removeOwnedData") state.removeOwnedData = target.checked;
    if (field === "settings.providerSyncEnabled") state.settingsForm.providerSyncEnabled = target.checked;
    if (field === "settings.cliWrapperEnabled") state.settingsForm.cliWrapperEnabled = target.checked;
    if (field === "settings.cliWrapperBaseUrl") state.settingsForm.cliWrapperBaseUrl = target.value;
    if (field === "settings.cliWrapperApiKey") state.settingsForm.cliWrapperApiKey = target.value;
    if (field === "settings.cliWrapperApiKeyEnv") state.settingsForm.cliWrapperApiKeyEnv = target.value;
  };

  render();
  void refreshOverview();
}

function statusPanel(title: string, status = "unknown", path?: string | null) {
  return `
    <div class="panel compact">
      <div class="status-line">
        <span>${escapeHtml(title)}</span>
        <strong class="${statusClass(status)}">${statusLabel(status)}</strong>
      </div>
      <div class="path-line">${escapeHtml(path || "未记录路径")}</div>
    </div>
  `;
}

function renderLatestLaunch(status: LaunchStatus | null) {
  if (!status) return `<div class="empty">暂无启动状态。</div>`;
  return `
    <div class="metric-list">
      <div><span>状态</span><strong>${escapeHtml(status.status)}</strong></div>
      <div><span>消息</span><strong>${escapeHtml(status.message)}</strong></div>
      <div><span>Debug</span><strong>${escapeHtml(String(status.debug_port ?? "-"))}</strong></div>
      <div><span>Helper</span><strong>${escapeHtml(String(status.helper_port ?? "-"))}</strong></div>
      <div><span>时间</span><strong>${escapeHtml(formatTime(status.started_at_ms))}</strong></div>
    </div>
  `;
}

function renderScriptRow(script: NonNullable<UserScriptInventory["scripts"]>[number]) {
  return `
    <div class="table-row">
      <span>${escapeHtml(script.name)}</span>
      <span>${escapeHtml(script.source)}</span>
      <span>${script.enabled ? "启用" : "关闭"}</span>
      <span>${escapeHtml(script.status)}</span>
    </div>
  `;
}

function routeTitle(route: Route) {
  return routes.find((item) => item.id === route)?.label ?? "概览";
}

function routeSubtitle(route: Route) {
  const subtitles: Record<Route, string> = {
    overview: "关键状态与快速操作",
    launch: "手动启动与端口参数",
    install: "入口安装、卸载与修复",
    update: "版本检查与更新流程",
    settings: "Provider 同步、命令包装器与脚本摘要",
    logs: "最近状态文件内容",
    diagnostics: "可复制的运行诊断报告",
  };
  return subtitles[route];
}

function statusLabel(status: string) {
  const labels: Record<string, string> = {
    found: "已找到",
    missing: "缺失",
    installed: "已安装",
    ok: "正常",
    running: "运行中",
    failed: "失败",
    not_checked: "未检查",
    not_implemented: "未实现",
    unknown: "未知",
  };
  return labels[status] ?? status;
}

function statusClass(status: string) {
  if (["found", "installed", "ok", "running"].includes(status)) return "good";
  if (["failed", "missing"].includes(status)) return "bad";
  return "warn";
}

function numberOrDefault(value: string, fallback: number) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function formatTime(value: number) {
  if (!value) return "-";
  return new Date(value).toLocaleString("zh-CN");
}

function stringifyError(error: unknown) {
  if (error instanceof Error) return error.message;
  return String(error);
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function escapeAttr(value: string) {
  return escapeHtml(value);
}
