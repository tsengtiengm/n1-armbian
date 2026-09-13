# N1 Armbian Builder（斐讯 N1 / s905d）

通过 GitHub Actions 云端编译斐讯 N1（Amlogic S905D）的定制 Armbian 固件。
本地**不需要任何编译环境**，点一下按钮即可云端出包。

## 固件特性

- **Armbian stable**（server 精简版，无桌面），基于官方 Armbian 源镜像重建
- **ophub 稳定版内核**（默认 6.12.y，可选 5.10/5.15/6.1/6.6）
- 内置：
  - `python3` + `pip` + `venv`
  - `rustc` + `cargo`（发行版稳定版本）
  - `metasploit-framework`（msfconsole / msfvenom / msfdb 等，含 PostgreSQL）
  - `build-essential` 编译工具链（rust/内核头编译需要）
- 已做精简：排除文档/手册/多余语言包，`--no-install-recommends` 安装

## 使用方法

1. 打开本仓库 **Actions → Build N1 Armbian (s905d) → Run workflow**
2. 按需选择参数（默认即可）：

   | 参数 | 说明 | 默认 |
   |---|---|---|
   | `kernel` | 内核分支（ophub stable 通道） | 6.12.y |
   | `root_mb` | rootfs 分区大小 MiB（装 msf 建议 ≥ 4096） | 4096 |
   | `install_msf` | 是否内置 Metasploit | true |
   | `upload_release` | 是否发布到 Releases | true |

   源镜像自动选择 Armbian 官方仓库里最新的 **minimal 精简版**（无桌面），无需手动指定系统版本。

3. 等待约 40~90 分钟（公有仓库免费 ARM 云主机原生编译）
4. 到 **Releases** 下载 `.img.xz` 固件（同 run 的 Artifacts 里也有备份）

## 刷机（N1）

1. 解压 `Armbian_*.img.xz` 得到 `.img`
2. 用 Rufus / balenaEtcher 写入 U 盘（建议 ≥ 8G 的好一点的 U 盘）
3. N1 插 U 盘、网线，U 盘启动（已刷过中小硅固件的 N1 通常通电即从 U 盘引导）
4. SSH 登录：`root` / `1234`（首次登录会让你改密码）
5. 验证内置工具：
   ```bash
   python3 -V && rustc -V && cargo -V
   msfconsole -v
   ```
6. 写入 eMMC：`armbian-install`（选 mmcblk2，之后可拔 U 盘从 eMMC 启动）
7. msf 数据库（可选）：`msfdb init` 然后 `db_status` 检查

## 常见问题

- **msf 启动慢**：N1 只有 2G 内存 + eMMC 性能一般，`msfconsole` 首次加载 1~2 分钟属正常
- **想换内核**：直接改 workflow 触发参数里的 `kernel` 即可，无需改代码
- **想加装其他软件**：编辑 `custom/customize-rootfs.sh` 里的 `apt-get install` 列表后重新触发
- **仓库转私有后**：免费 ARM 云主机不可用，把 workflow 里 `runs-on: ubuntu-24.04-arm` 改成 `ubuntu-24.04`（会自动退回 qemu 模拟编译，速度明显变慢，且计入 Actions 分钟数）
- **默认 root 密码**：`1234`，首次登录强制修改；暴露公网请务必改强密码/禁用密码登录

## 目录结构

```
.github/workflows/build-n1-armbian.yml   # 云端编译流水线
scripts/customize-image.sh               # 挂载镜像 + chroot（宿主侧）
custom/customize-rootfs.sh               # 固件内预装软件清单（改这里加软件）
```

## 致谢

构建工具来自 [ophub/amlogic-s9xxx-armbian](https://github.com/ophub/amlogic-s9xxx-armbian)，
内核来自 [ophub/kernel](https://github.com/ophub/kernel)。
