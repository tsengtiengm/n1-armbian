# N1 Armbian Builder（斐讯 N1 / s905d）

通过 GitHub Actions 云端编译斐讯 N1（Amlogic S905D）的定制 Armbian 固件。
本地**不需要任何编译环境**，点一下按钮即可云端出包。

## 固件特性

- **Armbian stable**（minimal 精简版，无桌面），基于官方 Armbian 源镜像重建
- **ophub 稳定版内核**（默认 6.12.y，可选 5.10/5.15/6.1/6.6）
- 两种配方（workflow 里 `profile` 选择）：
  - **base**：精简底座 —— `python3`(pip/venv) + `rustc/cargo` + `metasploit-framework`（含 PostgreSQL）+ 编译工具链
  - **pentest**（默认）：base 之上再加常见渗透工具与 v2rayA（**不含 msf**，8G eMMC 空间有限；要 msf 请用 base 配方）：
    - 侦察/扫描：`nmap` `masscan` `whatweb` `nikto` `wafw00f` `gobuster` `ffuf` `dirb` `dirsearch` `wfuzz` `fierce` `dnsrecon` `dnsenum` 等
    - 爆破/破解：`hydra` `john` `hashcat`
    - 无线：`aircrack-ng`
    - Web：`sqlmap` `sslscan` `testssl.sh`
    - 网络/中间人：`hping3` `macchanger` `tcpdump` `tshark` `socat` `proxychains4`（已预配置 socks5 → 127.0.0.1:20170）
    - 内网/SMB：`smbclient` `Responder`(`/opt/Responder`) `impacket`(pip) `enum4linux`
    - 字典与漏洞库：`seclists`(`/usr/share/seclists`) `searchsploit`(exploitdb, GitLab 源)
    - 科学上网：**v2rayA** + **Xray-Core**(arm64) + geoip/geosite，开机自启，web 面板 `http://<N1的IP>:2017`
- 已做精简：排除文档/手册/多余语言包，`--no-install-recommends` 安装

## 使用方法

1. 打开本仓库 **Actions → Build N1 Armbian (s905d) → Run workflow**
2. 按需选择参数（默认即可）：

   | 参数 | 说明 | 默认 |
   |---|---|---|
   | `profile` | 配方：`base`（精简）/ `pentest`（渗透全家桶 + v2rayA） | pentest |
   | `kernel` | 内核分支（ophub stable 通道） | 6.12.y |
   | `root_mb` | rootfs 分区大小 MiB（pentest 建议 ≥ 6656） | 6656 |
   | `install_msf` | 是否内置 Metasploit（pentest 配方强制关闭） | true |
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

- **本仓库是私有的**：固件下载需登录 GitHub；编译跑在 x86 云主机 + qemu 模拟上（较慢，计入每月 2000 分钟免费额度）。若转回公开仓库，把 workflow 里 `runs-on: ubuntu-24.04` 改成 `ubuntu-24.04-arm` 即可恢复原生编译（快很多且免费）
- **msf 启动慢**：N1 只有 2G 内存 + eMMC 性能一般，`msfconsole` 首次加载 1~2 分钟属正常
- **想换内核**：直接改 workflow 触发参数里的 `kernel` 即可，无需改代码
- **想加装其他软件**：编辑 `custom/customize-rootfs.sh` 里的 `apt-get install` 列表后重新触发
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
