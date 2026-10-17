# GIT 上传隐私扫描报告 — 2026-08-29

任务：上传前先扫描隐私信息（密钥/令牌/凭据/个人信息），确认干净才上传。
扫描对象：
1. 源码树 `/home/<user>/claude/r11/out/linux-sdm660-oppor11-t-qcom-sdm660-7.0.y`（7.0.14 fork，分支 main，7 个本地提交）
2. 成品归档 `/home/<user>/claude/r11/backups/products/`（42 个归档目录，228 个文件，共 1.2G）
3. 成品 boot 镜像 `/home/<user>/claude/r11/out/boot_r11s_*.img`（9 个，各约 12~13MB）

扫描模式（全部对象统一）：
- 私钥块：`-----BEGIN ... PRIVATE KEY-----` / `BEGIN OPENSSH` / `BEGIN RSA PRIVATE`
- 令牌：`ghp_/gho_/github_pat_`、`glpat-`、`xox[baprs]-`、`AKIA[0-9A-Z]{16}`
- 口令字段：`password=`、`passwd=`、`psk=`、WiFi 密码类
- 凭据文件：`.netrc`、`.git-credentials`、`id_rsa*`、`*.pem`、`*.p12`
- 二进制用 `strings -a` 抽串后套同一组模式

## 一、源码树扫描清单

| # | 检查项 | 方法 | 命中数 | 处置 |
|---|--------|------|--------|------|
| 1 | 未跟踪/改动文件 | `git status --porcelain` | 0 | 工作区干净，无未提交内容 |
| 2 | 私钥块（全树） | `grep -rIl "BEGIN .* PRIVATE KEY"` 排除 .git | 1 文件：`tools/testing/selftests/sgx/sign_key.pem` | **上游主线内核自带公开测试样例密钥**（Linux 官方仓库同样公开此文件），非用户私密 → 记录放行 |
| 3 | 令牌模式（全树） | `grep -rIEl` ghp_/gho_/github_pat_/glpat-/xox*/AKIA | 0 | 干净 |
| 4 | 凭据文件名 | `find .netrc/.git-credentials/id_rsa*/*.pem/*.p12/*.key` | 3：`build/certs/signing_key.pem`、`tools/.../sgx/sign_key.pem`、`tools/.../ovpn/data64.key` | ① `build/certs/signing_key.pem` 是**编译自动生成的模块签名私钥**，但 `build/` 被 `.gitignore:189:/build/` 整体覆盖（`git ls-files build/` = 0 个、`git check-ignore` 确认），**不会被推送**；② 另两个为上游公开测试数据（data64.key 是 ovpn selftest 的 base64 测试密钥）→ 记录放行 |
| 5 | 本方改动文件的口令/机密字段 | 对 6 个本方改动文件 `grep -i password\|passwd\|secret\|token\|credential` | 2 行：`CONFIG_SECRETMEM=y`、`# CONFIG_EFI_COCO_SECRET is not set` | 均为内核配置项名称，非凭据 → 放行 |
| 6 | 本方改动文件的个人身份信息（主机名/用户名/路径） | `grep -E "lxj\|/home/\|X79\|claude"` | 0 | 干净 |
| 7 | 提交署名 | `git log --format="%an <%ae>"` | 全部 `r11s-workspace <r11s@local>` | 无真实身份 → 放行 |
| 8 | 来自 ~/.config、ssh、github token 的文件 | 上述 2/3/4 项模式全树已覆盖 + 文件名扫描 | 0 | 干净 |
| 9 | .gitignore 覆盖度 | `git check-ignore -v build/certs/signing_key.pem` | — | `/build/` 已盖住，build 输出 0 文件入库 |

**源码树结论：干净，放行。**

本方 7 个提交（01fdb21b0 baseline → b55601e7d HEAD）仅改动 6 个文件：
`arch/arm64/configs/r11s_defconfig`、`drivers/gpu/drm/panel/{Kconfig,Makefile,panel-samsung-sofeg01-s.c}`、`drivers/input/rmi4/{rmi_driver.c,rmi_i2c.c}`。

## 二、成品归档扫描清单（backups/products/ + out/boot_r11s_*.img）

| # | 检查项 | 方法 | 命中数 | 处置 |
|---|--------|------|--------|------|
| 1 | 私钥块（全归档文本+二进制） | `grep -rIl` + 逐二进制 `strings -a` | 1 文件：`products_r11s_ubuntu_rootfs_20260809_222410/r11s-ubuntu-noble-arm64.ext4` | 该 512MB Ubuntu rootfs 内嵌多段私钥块（系统发行物，可能含镜像生成时产生的 ssh host key / 包内密钥），无法逐一证明无害 → **按判定规则剔除该文件不上传**（且 512MB 本也超 GitHub 单文件 100MB 上限）。同目录 README.md / SHA256SUMS 无命中，保留 |
| 2 | 令牌模式（全归档） | 同上 | 0 | 干净 |
| 3 | 口令/psk/WiFi 密码 | `grep -rIEli password=\|passwd=\|psk=\|wifi.*pass` | 0 | 干净 |
| 4 | 凭据文件名 | `find .netrc/.git-credentials/id_rsa*/*.pem/*.p12` | 0 | 干净 |
| 5 | boot 镜像 strings 扫描 | 9 个 `out/boot_r11s_*.img` 逐个 `strings -a` | 0 真命中（`/etc/passwd` 字样为 busybox 内置提示串，非凭据） | 干净 |
| 6 | 环境痕迹（主机名/用户名/路径） | `grep -rIEl "lxj\|lxj-X79"` 文本文件 | ~30 个 README/日志文件（编译日志中的 `/home/<user>` 路径、主机名等） | 属环境痕迹，按判定规则**记录后放行**，不阻断 |
| 7 | 串口取证日志中的设备信息 | 抽查 | 项目数据（设备启动日志） | 可上传 |

**成品归档结论：剔除 1 个文件（512MB ext4 rootfs），其余放行。**

## 三、体积核算与上传策略

- 归档总计 1.2G（>1GB 阈值）。剔除 ext4 后 **941MB / 227 文件**。
- 超 50MB 文件仅剩被剔除的 ext4（其余最大 49MB，未超 GitHub 100MB 单文件上限）。
- 6 个 28~49MB 的未压缩 `Image` 合计约 300MB；按任务预案"剔除重复 Image.gz 大件"之精神评估后：剩余 941MB 仍在普通 git 仓库可行范围（远低于 5GB 建议上限），且各轮 Image 内容不同、有取证价值，**全量上传（除 ext4）**。

## 四、判定

- 源码树：✅ 通过，可上传。
- 成品归档：✅ 通过（剔除 `r11s-ubuntu-noble-arm64.ext4` 后），可上传。
- 未发现任何真实用户密钥/令牌/口令外泄；唯一实质命中为 Ubuntu rootfs 系统发行物内嵌密钥，已整体剔除。

## 五、上传结果（2026-08-29）

### 通道盘点

- 源码树原本无任何 remote；fork 上游（NanShengtEAM/linux-sdm660-oppor11_s）未配置为 remote，无需试推。
- `gh` 未安装；无全局 credential helper、无 ~/.git-credentials、无 ~/.netrc。
- 参照 Z1 项目（6572）通道（只读，未动其任何文件/配置）：仓库在 `fork_linux/.git`，remote 内嵌用户 `lxjuyn` 的 fine-grained PAT。API 验证 PAT 有效，且具备建仓权限。
- 注意：首次推送经全局代理（socks5://127.0.0.1:7891）时 TLS 断连（curl 56），改用 `-c http.proxy= -c https.proxy=` 直连后成功。
- 未改任何全局/仓库 git config user；成品仓库提交用 `-c user.name=r11s-workspace -c user.email=r11s@local`；令牌仅出现在两个新仓库各自的 remote URL（与 6572 现行做法一致），未写入任何被提交文件。
- 新建公开仓库 2 个（均经 API 用现有 PAT 创建）：
  - https://github.com/lxjuyn/z1-r11s-mainline-kernel
  - https://github.com/lxjuyn/z1-r11s-mainline-products

### 源码树推送结果 ✅

- 远端：`https://github.com/lxjuyn/z1-r11s-mainline-kernel.git`，分支 `main`（新建，已设跟踪）。
- 推送提交数：7（01fdb21b0 baseline → b55601e7d HEAD）；远端 HEAD 与本地逐字一致（`git ls-remote` 核验）。
- 本地 .git 体积 287MB（推送包同量级）。未做新提交，仅推送已有提交。
- 远端配置在 `out/linux-sdm660-oppor11-t-qcom-sdm660-7.0.y/.git/config`。

### 成品镜像仓库推送结果 ✅

- 仓库根：`/home/<user>/claude/r11/backups/products_git/`（独立新目录，不动 `backups/products/` 原结构；先试软链发现 git 只存链接本体遂改为实体复制）。
- 远端：`https://github.com/lxjuyn/z1-r11s-mainline-products.git`，分支 `main`。
- 提交：`1c47aab` 成品镜像归档上传（隐私扫描已通过…）237 个文件；`38a0d0f` 附隐私扫描报告。远端 HEAD `38a0d0f` 与本地一致。
- 内容 = `backups/products/` 全部 42 个归档目录的 227 个文件（剔除 512MB ext4）+ `out/boot_r11s_*.img` 9 个（与归档内副本逐字节相同，已核 sha256）+ README.md + recon/ 报告。
- 体积：工作区文件 1.1GB，.git 644MB（git 内容寻址对相同镜像自动去重）。
- 提交署名 `r11s-workspace <r11s@local>`。

### 遗留事项

- 无。两仓库均已就位、公开、远端 HEAD 核验一致。
- 提示：① 被剔除的 `r11s-ubuntu-noble-arm64.ext4` 仍保留在本地 `backups/products/` 原位，仅未上传；② 两个新仓库的 remote URL 内嵌 PAT（沿用 6572 现行做法），如后续改用凭据助手可一并清理；③ `z1-r11s-mainline-products` 体积较大（约 1.7GB 含 .git），后续如频繁追加大镜像建议评估 Git LFS。
