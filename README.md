# DeepSeek Balance Monitor · DeepSeek 余额监控

> A lightweight macOS menu-bar app that monitors the balance of **multiple DeepSeek API keys** in real time, tracks usage, and alerts you on abnormal spending.
>
> 一款轻量 macOS 菜单栏应用：**实时监控多个 DeepSeek API Key 的余额**，统计用量，并在异常消耗时第一时间告警。

![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-blue) ![Language](https://img.shields.io/badge/language-Swift%205-orange) ![License](https://img.shields.io/badge/license-MIT-green)

---

## ✨ Features · 功能

| Feature · 功能 | Description · 说明 |
|---|---|
| 🖥️ Menu-bar resident · 菜单栏常驻 | Sits in the top-right menu bar like WeChat, no Dock icon · 像微信一样挂在右上角，无 Dock 图标 |
| 🔑 Multiple keys · 多 Key 支持 | Manage any number of DeepSeek API keys, each shown separately · 管理任意数量的 Key，每个单独显示 |
| ⚡ Real-time balance · 实时余额 | Polls `GET /user/balance` every 30s–10min (configurable), menu bar shows the total · 定时轮询官方余额接口，菜单栏显示总额 |
| 📊 Usage tracking · 用量统计 | Local daily snapshots compute today / 7-day spend · 本地快照计算今日、近 7 天消耗 |
| 🚨 Spike alert · 突发消耗告警 | Alerts when a single poll consumes more than a threshold · 单次轮询消耗超过阈值即告警 |
| 📈 Rate alert · 消耗速率告警 | Alerts when spend rate exceeds X yuan/minute · 每分钟消耗速率超过阈值即告警 |
| 🔔 Low-balance alert · 余额不足告警 | Notifies when balance drops below a threshold · 余额低于阈值发系统通知 |
| 📤 Export · 导出 | Export all or selected keys to CSV · 导出全部或选中 Key 到 CSV |
| 🖥️ Server monitor · 服务器监控 | Save multiple servers (IP/user/password, exportable), hourly check memory / CPU / disk / top processes / **login audit** · 保存多台服务器（可导出），每小时检查内存/CPU/磁盘/进程/**登录审计** |
| 🤖 Server AI assistant · 服务器 AI 助手 | Chat with DeepSeek: describe what to do in natural language, it generates shell commands, you execute with one click, multi-turn · 自然语言描述 → DeepSeek 生成命令 → 一键执行 → 多轮对话 |
| 📈 Trend charts · 资源趋势图 | Real-time line charts of memory / disk / swap from hourly snapshots · 内存/磁盘/Swap 实时折线趋势图 |
| 🕘 History · 历史记录 | Alerts / balance / server status / **AI operation logs** all persisted and viewable · 告警/余额/服务器状态/**AI 操作日志**全部留痕可追溯 |
| 🔒 Local-only · 数据本地 | All data stays in `~/Library/Application Support/DeepSeekBalance/` · 所有数据仅存本机，不上传 |

---

## 🖼️ Screenshot · 截图

_(Coming soon · 待补充)_

The menu-bar shows the total balance; the drop-down lists each key with balance, granted/topped-up amounts and today's spend.

菜单栏显示余额合计；下拉菜单列出每个 Key 的余额、充值/赠送金额与今日消耗。

---

## 📦 Install · 安装

### Option A · 方式一：直接下载 App（macOS 12+）

Download `DeepSeekBalance.app` from [Releases](../../releases), unzip and drag to `Applications`.

从 [Releases](../../releases) 下载 `DeepSeekBalance.app`，解压后拖入「应用程序」。

> If Gatekeeper blocks it (unsigned ad-hoc build): right-click → Open → Open. · 若被 Gatekeeper 拦截（本地 ad-hoc 签名）：右键 → 打开 → 打开。

### Option B · 方式二：源码编译

```bash
# 需要 Xcode Command Line Tools
git clone https://github.com/tajleonbennis-maker/deepseek-balance.git
cd deepseek-balance
./build.sh
open DeepSeekBalance.app
```

The app can also be copied to `~/Applications/` for convenience.

也可以复制到 `~/Applications/` 使用。

---

## 🚀 Usage · 使用

1. **Click the menu-bar icon** (`$`) → **Settings…**
2. Click **＋ Add Key**, paste your DeepSeek API key (`sk-…`). Names are auto-generated (`账号 1`, `账号 2` …). Repeat for all keys.
3. Close the window — polling starts. The menu bar shows the total balance; the drop-down shows each account's balance, granted/topped-up split and today's spend.

1. **点击菜单栏图标**（$）→ **设置…**
2. 点 **＋ 添加 Key**，粘贴 DeepSeek API Key（`sk-…`）。名称自动生成（账号 1、账号 2……），可添加任意多个。
3. 关闭窗口即开始轮询。菜单栏显示余额合计，下拉菜单显示每个账号的余额、充值/赠送、今日消耗。

### Alerts · 告警设置

In Settings → 告警与刷新:

- **单次轮询消耗超过 ¥X**：a single poll spending more than X triggers an alert (default 1.0)
- **消耗速率超过 ¥Y/分钟**：spend rate above Y yuan/minute triggers an alert (default 0.5)
- **余额低于阈值时提醒**：low-balance notification (default 10)

In Settings → Alerts & Refresh:

- **Single-poll spend > ¥X**: triggers an alert (default 1.0)
- **Spend rate > ¥Y/min**: triggers an alert (default 0.5)
- **Low balance alert**: notifies when balance is below the threshold (default 10)

All thresholds are editable — click the field, type a number, press Enter.

所有金额阈值均可随时修改：点击输入框直接输入数字，回车生效。

### Export · 导出

In Settings: **导出全部 Key** (all) or **导出选中** (multi-select rows with ⌘/Shift first). Output is a CSV:

设置中可「导出全部 Key」或先 ⌘/Shift 多选再「导出选中」，导出为 CSV：

```csv
名称,API Key
账号 1,"sk-xxxxxxxxxxxxxxxx"
账号 2,"sk-yyyyyyyyyyyyyyyy"
```

> ⚠️ The exported CSV contains **plaintext keys** — keep it safe, never commit it to a repo or upload it anywhere.
> ⚠️ 导出的 CSV 包含**明文密钥**，请妥善保管，切勿提交到仓库或上传到任何地方。

### Server monitor · 服务器监控

Menu bar → **服务器管理…** to add servers (name, IP[:port], username, password). The app collects every hour (or on demand via 立即检查全部):

- **内存 / CPU**：usage %, available MB, load average
- **磁盘**：usage % and used/total GB
- **Top 进程**：top memory consumers
- **登录审计**：who logged in, from which IP, at what time (`last`)

Alerts (system notification) when memory > 90% or disk > 85%. Server configs can be exported to CSV (contains plaintext passwords — keep it safe).

菜单栏 → 「服务器管理…」添加服务器（名称、IP[:端口]、用户名、密码）。每小时自动采集（或点「立即检查全部」）：

- **内存 / CPU**：使用率%、可用 MB、负载
- **磁盘**：使用率% 与已用/总量 GB
- **Top 进程**：内存占用最高的进程
- **登录审计**：谁、从哪个 IP、什么时间登录过（`last`）

内存 > 90% 或磁盘 > 85% 时发系统通知。服务器配置可导出 CSV（含明文密码，请妥善保管）。

---

## ⚙️ How it works · 工作原理

- Uses DeepSeek's official API `GET https://api.deepseek.com/user/balance` (Bearer auth).
- Since DeepSeek exposes **no usage API**, spend is derived from local balance snapshots (`delta` between polls), stored in `records.json`.
- Alerts: spike (single delta > threshold) and rate (delta/dt per minute > threshold), with smart de-duplication to avoid notification spam.
- Notifications use the macOS UserNotifications framework — grant permission when prompted, or enable it in System Settings → Notifications.

- 调用 DeepSeek 官方接口 `GET https://api.deepseek.com/user/balance`（Bearer 认证）。
- DeepSeek **没有开放用量 API**，故用量通过本地余额快照差值（轮询间 delta）估算，记录在 `records.json`。
- 告警：单次尖刺（delta > 阈值）与速率（每分钟 delta/dt > 阈值），带智能去重，避免通知轰炸。
- 通知走 macOS 系统通知：首次弹窗请点"允许"，或到 系统设置 → 通知 中开启。

### ⚠️ Note on billing delay · 关于扣款延迟

DeepSeek balance updates are **not real-time** — spending may take minutes to reflect. The app only detects a decrease once the platform settles it. This is normal.

DeepSeek 余额是**延迟结算**的，消费后通常要几分钟才会扣款。应用只在平台扣款后才检测到下降并告警，这是正常现象。

---

## 📁 Data & Privacy · 数据与隐私

| File · 文件 | Purpose · 用途 |
|---|---|
| `config.json` | Keys (plaintext, local only), thresholds, alert states · Key（明文，仅本地）、阈值、告警状态 |
| `records.json` | Daily balance snapshots, last 60 days · 每日余额快照，保留 60 天 |

Location: `~/Library/Application Support/DeepSeekBalance/`

**Nothing is uploaded. Keys never leave your machine.**

**不向任何地方上传数据，密钥绝不离开你的电脑。**

---

## 🛠️ Development · 开发

```bash
# Build · 编译
./build.sh

# Regenerate icon (optional) · 重新生成图标（可选）
python3 make_icon.py   # requires: pip install pillow
```

Key files · 核心文件：

| Path · 路径 | Role · 职责 |
|---|---|
| `Sources/StatusMenuController.swift` | Menu bar, polling loop, alerts · 菜单栏、轮询、告警 |
| `Sources/SettingsWindowController.swift` | Settings window, key management, export · 设置窗口、Key 管理、导出 |
| `Sources/Store.swift` | Local persistence, snapshots, usage calc · 本地存储、快照、用量计算 |
| `Sources/BalanceFetcher.swift` | DeepSeek balance API client · 余额接口客户端 |
| `Sources/Models.swift` | Data models · 数据模型 |

---

## 🧩 Known limitations · 已知限制

- Balance/usage only reflects what the app has observed while running — if the Mac is off, there are no records for that period.
- 应用只在运行时记录观测数据，Mac 关机期间无记录。

---

## 📄 License · 许可

MIT

---

## 🙏 Disclaimer · 免责声明

This project is an independent local tool and is not affiliated with DeepSeek. Use at your own risk.

本项目为独立本地工具，与 DeepSeek 无任何关联，使用风险自负。
