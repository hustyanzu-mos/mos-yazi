# Yazi MOS Plugin

在 **MOS NAS**（不可变、运行于 RAM 的 Devuan 系统）上安装并管理
[Yazi](https://yazi-rs.github.io) 终端文件管理器的插件实现仓库。

- Hub 索引条目在：[hustyanzu-mos/mos-templates](https://github.com/hustyanzu-mos/mos-templates)
- 本仓库负责插件实现、依赖清单和架构对应的 release `.deb`

---

## 它做什么

- 构建时把 Yazi 官方 release 的 `yazi` 和 `ya` 打进插件 `.deb`
- `.deb` 安装二进制到 `/usr/lib/yazi`，安装 `/usr/bin/yazi`、`/usr/bin/ya` 包装脚本
- MOS 启动时重新安装 `.deb`，恢复 `/usr/lib/yazi` 和 `/usr/bin`
- `/boot` 只存 `.deb`、`settings.json` 和依赖包清单，不存 Yazi 配置/数据
- **不自动探测任何持久化路径**
- 默认所有状态在 `/run/yazi`（RAM），重启清空
- 只有用户在插件页面指定一个 app 目录后，config/data/state/cache
  才持久化到那个目录
- 依赖清单持久化到 `packages/packages`，MOS 启动时自动恢复

Yazi 本体的更新通过新的插件 Release（和 `mos-vim` 一样），页面不单独下载 Yazi。

---

## 仓库结构

```text
mos-yazi/
├── functions
├── settings.json
├── packages                      # Hub 自动安装的依赖清单
├── yazi-env                      # 共享路径解析
├── yazi-backend                  # /usr/bin/plugins/yazi
├── yazi-wrapper                  # /usr/bin/yazi
├── ya-wrapper                    # /usr/bin/ya
├── debian/
│   ├── postinst
│   └── postrm
├── images/
│   └── yazi.png
├── page/                         # Vue 插件页面
├── build.sh
└── .github/workflows/build-plugin.yml
```

---

## 依赖

Yazi 本体是静态 Rust 二进制，但很多功能依赖外部命令。插件会安装这组基础依赖：

| 包 | 命令 | 用途 |
| --- | --- | --- |
| `file` | `file` | MIME 类型检测（Yazi 必需） |
| `ripgrep` | `rg` | 内容搜索 |
| `fd-find` | `fd` | 文件名搜索（插件创建 `fd` 别名） |
| `fzf` | `fzf` | 快速跳转 |
| `zoxide` | `zoxide` | 目录跳转 |
| `jq` | `jq` | JSON 预览 |
| `ffmpeg` | `ffmpeg` | 视频缩略图 |
| `poppler-utils` | `pdftoppm` | PDF 预览 |
| `p7zip-full` | `7z` | 压缩包预览/解压 |
| `resvg` | `resvg` | SVG 预览 |
| `imagemagick` | `magick` | AVIF/HEIC/JXL 等图片预览 |
| `git` | `git` | Git 状态插件 |
| `udisks2` | `udisksctl` | 挂载插件 |
| `zip` / `unzip` | `zip` / `unzip` | ZIP 压缩/解压 |

依赖安装分两层：

1. 仓库根目录的 `packages` 里**只有 `file`**。这是 Yazi 做 MIME 检测
   必需的包，体积很小。MOS Hub 安装插件时会读取它，并持久化到：

   ```text
   /boot/optional/plugins/yazi/packages/packages
   ```

2. 插件安装完成后，`functions install` 会自动启动
   `yazi-backend install_deps`，只确保 `file` 已安装。

其他依赖都是可选的，默认**不会下载**，在插件页面按组安装：

| 组 | 包 | 用途 |
| --- | --- | --- |
| Search & navigation | `ripgrep`、`fd-find`、`fzf`、`zoxide`、`jq` | 搜索、跳转、JSON 预览 |
| Media previews | `ffmpeg`、`poppler-utils`、`p7zip-full`、`imagemagick` | 视频、PDF、压缩包、AVIF/HEIC/JXL |
| Extras | `resvg`、`git`、`udisks2`、`zip`、`unzip` | SVG、Git 状态、挂载、ZIP |

Media previews 是较大的下载，只有需要对应预览时才点。
`resvg` 在旧版 Devuan（daedalus）里可能不存在，Extras 组会逐个安装，
一个包失败不会影响其他包。

依赖安装在后台执行，页面轮询状态，避免 MOS 插件查询的 60 秒上限。

### 图片预览与终端

Yazi 的图片预览使用终端图形协议，不是靠 `chafa`：

- Kitty graphics：Kitty、WezTerm、Ghostty
- Sixel：foot、WezTerm、部分 xterm 配置
- iTerm2 images：iTerm2、WezTerm

SSH 到普通 xterm/PuTTY 时通常没有图片预览，但文件管理、文本/代码预览、
搜索、压缩包和 PDF 预览仍然可用。

---

## 持久化规则

没有自动检测，没有默认 `/mnt` 路径。

### 未指定 app 目录

```text
/run/yazi/config
/run/yazi/data
/run/yazi/state
/run/yazi/cache
```

全部在 RAM，重启丢失。页面会显示警告。

### 指定 app 目录

在页面填入一个绝对目录，例如：

```text
/mnt/tank/appdata/yazi
```

实际布局：

```text
<app_dir>/config/yazi.toml
<app_dir>/config/plugins/
<app_dir>/data
<app_dir>/state
<app_dir>/cache
```

一个 app 一个目录，`ya pkg add` 也会把插件装到 `<app_dir>/config/plugins`。

---

## 构建

本地（当前架构）：

```bash
./build.sh 0.2.0
```

输出：

```text
build/yazi-0.2.0-1+mos-plugin_amd64.deb
build/yazi-0.2.0-1+mos-plugin_amd64.deb.md5
```

GitHub Actions 会同时构建：

```text
yazi-0.2.0-1+mos-plugin_amd64.deb
yazi-0.2.0-1+mos-plugin_arm64.deb
```

Hub 会根据机器架构选择对应的 `.deb`。

---

## 发布与安装

```bash
git tag 0.2.0
git push origin 0.2.0
```

在 MOS 添加索引仓库：

```text
https://github.com/hustyanzu-mos/mos-templates
```

Refresh 后到 **Docker → MOS Hub → Plugins** 安装 **Yazi**。

安装后默认：

- `/usr/lib/yazi/yazi`：Yazi 二进制
- `/usr/lib/yazi/ya`：Yazi 包管理器
- `/usr/bin/yazi`：包装脚本
- `/usr/bin/ya`：包装脚本
- `/usr/bin/fd`：`fd-find` 的别名（如果系统没有 `fd`）
- 配置/数据：`/run/yazi`（RAM）

要持久化，打开插件页填写 **App directory** 并保存。

---

## 设置

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `data_dir` | `""` | 空 = 全部在 `/run/yazi`（RAM）；填写一个绝对目录 = 该 app 的 config/data/state/cache 都放这里 |

页面会显示实际的 `app_root`、config 路径和 RAM/Configured 状态。
路径必须是绝对路径，且不能指向 `/boot`。

---

## Yazi 插件

Yazi 自带 `ya` 包管理器。`ya pkg add` 会把插件安装到 app 目录：

```bash
ya pkg add yazi-rs/plugins:smart-enter
ya pkg add yazi-rs/plugins:full-border
ya pkg add yazi-rs/plugins:git
ya pkg add yazi-rs/plugins:chmod
ya pkg add yazi-rs/plugins:compress
ya pkg add yazi-rs/plugins:max-preview
ya pkg add yazi-rs/plugins:mount
```

然后在 `<app_dir>/config/init.lua` 里按每个插件的 README 启用。
`mount` 需要 `udisks2`，`git` 需要 `git`，`compress` 需要 `7z`/`zip`；
这些都已经在基础依赖里。

---

## 使用

```bash
yazi
yazi /mnt/cache
ya pkg list
```

`y` 之类的 shell 包装函数是可选的，可以在自己的 shell 配置里添加；
插件本身只保证 `yazi` 和 `ya` 命令可用。

---

## 旧版本数据

0.2.0 不会自动迁移旧路径，也不会读取 `/boot` 或 `/mnt` 里的旧 config/data。
如果需要保留：

```bash
cp -a /boot/optional/plugins/yazi/config/. <app_dir>/config/
```

确认复制完成后，旧的 `/boot/optional/plugins/yazi/config` 和
`/boot/optional/plugins/yazi/data` 可以手动删除。

---

## 升级 / 卸载

**升级**：MOS Hub 里刷新并更新 Yazi 插件，或安装新的插件 Release。
Yazi 版本随 `.deb` 更新。

**卸载**：卸载插件会移除 `/usr/lib/yazi`、`/usr/bin/yazi`、`/usr/bin/ya`
和 `fd` 别名；如果配置过 app 目录，那份数据保留；RAM 数据随重启消失。
`/boot/optional/plugins/yazi` 里的 `settings.json` 和依赖清单会保留。

---

## 排错

```bash
/usr/bin/plugins/yazi status
/usr/bin/plugins/yazi version
ls -la /usr/lib/yazi
cat /boot/optional/plugins/yazi/packages/install.log
```

- `yazi: command not found`：重新安装 Yazi 插件，让 MOS 重新安装 `.deb`。
- 页面显示依赖缺失：点击 **Install basic dependencies**，或重启让 MOS 按
  `packages/packages` 安装。
- 图片预览不显示：先确认终端支持 Kitty/Sixel/iTerm2 图形协议。
- `fd: command not found`：确认 `fd-find` 已安装，或重新安装插件恢复别名。

---

## 许可证

插件代码使用 MIT License。Yazi 由其官方 release 提供，遵循 Yazi 的上游 MIT 许可。