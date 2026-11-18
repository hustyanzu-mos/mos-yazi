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
- 配置和数据默认持久化到 `/mnt` 的 pool
- 提供 MOS 插件页面：版本、pool 路径、配置/数据目录、依赖状态、后台安装依赖
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

依赖清单在仓库根目录的 `packages` 文件里。MOS Hub 安装插件时会读取它，
并持久化到：

```text
/boot/optional/plugins/yazi/packages/packages
```

如果安装时网络超时，MOS 启动时会继续安装。插件页面的
**Install basic dependencies** 按钮会在后台执行安装，页面轮询状态，
避免 MOS 插件查询的 60 秒上限。

### 图片预览与终端

Yazi 的图片预览使用终端图形协议，不是靠 `chafa`：

- Kitty graphics：Kitty、WezTerm、Ghostty
- Sixel：foot、WezTerm、部分 xterm 配置
- iTerm2 images：iTerm2、WezTerm

SSH 到普通 xterm/PuTTY 时通常没有图片预览，但文件管理、文本/代码预览、
搜索、压缩包和 PDF 预览仍然可用。

---

## 构建

本地（当前架构）：

```bash
./build.sh 0.1.1
```

输出：

```text
build/yazi-0.1.1-1+mos-plugin_amd64.deb
build/yazi-0.1.1-1+mos-plugin_amd64.deb.md5
```

GitHub Actions 会同时构建：

```text
yazi-0.1.1-1+mos-plugin_amd64.deb
yazi-0.1.1-1+mos-plugin_arm64.deb
```

Hub 会根据机器架构选择对应的 `.deb`。

---

## 发布与安装

```bash
git tag 0.1.1
git push origin 0.1.1
```

在 MOS 添加索引仓库：

```text
https://github.com/hustyanzu-mos/mos-templates
```

Refresh 后到 **Docker → MOS Hub → Plugins** 安装 **Yazi**。

安装后：

- `/usr/lib/yazi/yazi`：Yazi 二进制
- `/usr/lib/yazi/ya`：Yazi 包管理器
- `/usr/bin/yazi`：包装脚本
- `/usr/bin/ya`：包装脚本
- `/usr/bin/fd`：`fd-find` 的别名（如果系统没有 `fd`）
- 配置：`/mnt/cache/appdata/yazi/config`（自动检测）
- 数据：`/mnt/cache/appdata/yazi/data`（自动检测）
- state/cache：`/run/yazi`（RAM）

---

## 持久化

Hub 安装器会把 `.deb` 和 `functions` 放到：

```text
/boot/optional/plugins/yazi/<version>/
```

启动时 `installplugins-mos` 重新安装该 `.deb`，恢复 `/usr/lib/yazi` 和
`/usr/bin/yazi`、`/usr/bin/ya`。

配置和数据默认自动选择：

```text
/mnt/cache/appdata/yazi/config
/mnt/cache/appdata/yazi/data
```

如果没有 `/mnt/cache`，会依次尝试：

```text
/mnt/user/appdata/yazi
/mnt/disk*/appdata/yazi
```

如果都没有检测到可写 pool，才退回 `/run/yazi`（RAM），页面会显示警告。

- 配置持久化在 pool 的 `.../yazi/config`
- 数据（包括回收站）持久化在 pool 的 `.../yazi/data`
- state/cache 在 `/run/yazi`，重启清空
- 依赖清单在 `/boot/optional/plugins/yazi/packages/packages`
- `fd` 别名在启动时由 `functions` 恢复

`config`、`data`、`state`、`cache` 是独立的 XDG 根，不会互相覆盖。
`/boot` 是 vfat/exFAT，不支持 Linux ownership；插件不再往 `/boot` 写配置或数据。

从 0.1.0 升级时，旧的 `/boot/optional/plugins/yazi/config` 会复制到
新的 pool 配置根；旧文件不会删除。

---

## 设置

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `config_dir` | `""` | 留空使用自动检测的 pool 路径；填了用该绝对路径作为 Yazi 配置目录 |
| `data_dir` | `""` | 留空使用自动检测的 pool 路径；填 `/run/yazi/data` 可显式改回 RAM |

页面会显示实际的 `config_root`、`data_root` 和 Persistent/RAM 状态。
路径必须是绝对路径，且不能指向 `/boot`。

---

## Yazi 插件

Yazi 自带 `ya` 包管理器。`ya pkg add` 会把插件安装到持久化的配置目录：

```bash
ya pkg add yazi-rs/plugins:smart-enter
ya pkg add yazi-rs/plugins:full-border
ya pkg add yazi-rs/plugins:git
ya pkg add yazi-rs/plugins:chmod
ya pkg add yazi-rs/plugins:compress
ya pkg add yazi-rs/plugins:max-preview
ya pkg add yazi-rs/plugins:mount
```

然后在 pool 配置根下的 `init.lua` 里按每个插件的 README
启用。`mount` 需要 `udisks2`，`git` 需要 `git`，`compress` 需要 `7z`/`zip`；
这些都已经在基础依赖里。

---

## 使用

```bash
yazi
yazi /mnt/cache
yazi /mnt/user/appdata
ya pkg list
```

`y` 之类的 shell 包装函数是可选的，可以在自己的 shell 配置里添加；
插件本身只保证 `yazi` 和 `ya` 命令可用。

---

## 升级 / 卸载

**升级**：MOS Hub 里刷新并更新 Yazi 插件，或安装新的插件 Release。
Yazi 版本随 `.deb` 更新。

**卸载**：卸载插件会移除 `/usr/lib/yazi`、`/usr/bin/yazi`、`/usr/bin/ya`
和 `fd` 别名；pool 上的配置和数据不会删除；`/boot/optional/plugins/yazi` 里的
`settings.json` 和依赖清单会保留。

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