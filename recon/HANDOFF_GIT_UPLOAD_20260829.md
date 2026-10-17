# 交接书：R11s 源码与成品镜像 git 上传（2026-08-29 23:00）

给接手上传工作的智能体：本项目的源码树与成品镜像**已经完成首轮上传**，以下是完整现状、约定与剩余事项。用户已在 `/home/<user>/claude/r11/CLAUDE.md` 放入 GitHub key，后续认证可用该 key。

## 1. 已完成（2026-08-29 22:53，执行者 Cindy）

| 对象 | 本地位置 | 远端（均为**独立新仓库**，未动 Z1 仓库 `lxjuyn/z1-mt6572-mainline`） | 状态 |
|---|---|---|---|
| 适配源码树（7.0.14 fork + 面板驱动/rmi4 修复/defconfig） | `/home/<user>/claude/r11/out/linux-sdm660-oppor11-t-qcom-sdm660-7.0.y`（分支 main） | `github.com/lxjuyn/r11s-mainline-kernel`（2026-08-29 23:15 已改名，旧名 `z1-r11s-mainline-kernel`） | 7 提交推送成功，远端 HEAD = `b55601e7d` 与本地一致 |
| 成品镜像与归档（237 文件：各版 boot 镜像、DTB、ramdisk、SHA256SUMS、README、日志） | `/home/<user>/claude/r11/backups/products_git/`（独立仓库目录，实体复制，未动 `backups/products/` 原结构） | `github.com/lxjuyn/r11s-mainline-products`（2026-08-29 23:15 已改名，旧名 `z1-r11s-mainline-products`） | 3 提交推送成功，远端 HEAD = `4ec09ce`。**⚠ 该仓库已按用户要求删除（见 §5），本地 `products_git/` 目录亦已清理** |

注意：两个远端 URL 内嵌了 PAT（`git remote -v` 可见），**任何交接文档/提交里都不得再现该令牌**。

## 2. 隐私扫描结论（前置强制项，已过）

报告：`/home/<user>/claude/r11/recon/GIT_UPLOAD_PRIVACY_SCAN_20260829.md`
- 源码树：干净。唯一私钥命中是上游内核自带公开测试样例；`build/certs/signing_key.pem`（编译产物私钥）被 .gitignore 盖住不入库。
- 成品归档：**剔除 1 文件**——`products_r11s_ubuntu_rootfs_20260809_222410/r11s-ubuntu-noble-arm64.ext4`（512MB，内嵌多段私钥）**永不上传**，本地原位保留。后续增量上传同样要排除它。
- 提交署名一律 `-c user.name=r11s-workspace -c user.email=r11s@local`；**禁止改全局/仓库 git config，禁止把凭据写进任何被提交文件**。

## 3. 接手者的待办（按优先级）

1. ~~**仓库改名（用户明确要求"单独开仓、别沾 z1"）**~~ **✅ 已完成（2026-08-29 23:15，执行者 Jay）**：已用 GitHub API 改名为 `lxjuyn/r11s-mainline-kernel` / `lxjuyn/r11s-mainline-products`（HTTP 200；改名前确认目标名空闲），本地两仓库 `.git/config` 的 remote URL 已同步更新（仅换仓库名，凭据形式不变），直连 `ls-remote` 验证远端 HEAD 与本地一致（`b55601e7d…` / `4ec09ce…`）。
2. **增量同步**：源码树后续每轮驱动修复都会有新提交（署名同上）——按"扫描（参照报告方法，重点扫私钥块/令牌模式）→ 提交 → 推送"流程持续同步。**成品镜像不再建 products 仓**：每步产物（boot 镜像 + SHA256SUMS）直接挂到 `lxjuyn/r11s-mainline-kernel` 的 GitHub Releases（建 release → uploads.github.com 传资产，方法见 §5）。
3. **推送技巧**：经全局代理推送大仓库会 TLS 断连（curl 56），直连可解：`git -c http.proxy= -c https.proxy= push ...`。
4. **体积**：源码树仓库 .git 约 287MB。GitHub 单文件上限 100MB；Releases 资产单文件上限 2GB（当前镜像 ~13MB 无碍），镜像走 Releases 后不再增大仓库 .git。

## 4. 硬约束

- `backups/products/` 原目录结构与内容不许动（原镜像复制方案 `backups/products_git/` 已随 products 仓库删除一并清理，不再需要）。
- 不触碰 `/home/<user>/claude/6572`（Z1 项目）的任何文件与配置。
- 被剔除的 Ubuntu rootfs（含私钥）永不上传。
- 上传前任何新增文件必须先过隐私扫描（方法见报告）。

## 5. 任务 21 更新（2026-08-29 夜）：镜像改走 Releases，products 仓库删除（用户要求）

执行者：任务 21 工程师。用户明确要求"取消掉" products 仓库，镜像发布改走源码树仓库的 GitHub Releases。

1. **README 重写**：`lxjuyn/r11s-mainline-kernel` 新增规范中英双语 `README.md`（项目简介/当前状态/仓库内容/快速上手/Releases 说明/致谢/许可），提交 `35dae918a` 已直连推送，远端 `refs/heads/main` 核验一致。
2. **7 个阶段镜像已建 Release**（仓库 `lxjuyn/r11s-mainline-kernel`，每个含镜像 + `SHA256SUMS` 两个资产，正文双语，含变更/实测/回滚/SHA256）：
   - `stage1-dtbsurg` → `boot_r11s_dtbsurg.img`（94b07f70…，第三方 7.0.9 + 手术 DTB，上板 PASS）
   - `stage2-v2` → `boot_r11s_phase2_v2.img`（7b7dc461…，首个自编 7.0.14 基线，PASS）
   - `stage3-touch-v3` → `boot_r11s_phase3_touch_v3.img`（54a186ff…，RMI4 内建，probe 中止）
   - `stage3-touch-v4` → `boot_r11s_phase3_touch_v4.img`（506494dc…，PDT 容错，绑定成功）
   - `stage5-display-v5` → `boot_r11s_phase5_display_v5.img`（b62d15e4…，DRM_MSM+面板，供电 defer）
   - `stage3-touch-v6` → `boot_r11s_phase3_touch_v6.img`（42f4b8d3…，OLEDB 内建，显示点亮里程碑）
   - `stage3-touch-v7` → `boot_r11s_phase3_touch_v7.img`（0d01c644…，rmi_i2c 重试）
   上传前全部 `sha256sum` 与记录核对一致。发布方法：`POST /repos/{repo}/releases` 建 release，再向返回的 `upload_url`（uploads.github.com）逐资产 `POST ?name=...`（镜像 `application/octet-stream`、校验文件 `text/plain`）；凭据取源码树 `git remote -v` URL 内嵌 PAT，不落任何文件。
3. **products 仓库删除**：`DELETE /repos/lxjuyn/r11s-mainline-products` → HTTP 204；`GET` 复核返回 `Not Found`。本地 `/home/<user>/claude/r11/backups/products_git/`（仅上传用实体复制件，含内嵌令牌的 .git）已整目录删除；删除前核验其内容全部冗余（顶层镜像 = `out/` 现行件，`products_*/` 为指向 `backups/products/` 的符号链接，README/扫描报告原件均在 `r11/recon/`）。**`backups/products/` 原归档零改动**。
4. **后续约定**：不再建任何 products 仓；每轮新镜像按本节第 2 条方法直接挂 Releases（tag 建议延续 `阶段名-用途-版本号` 习惯），同时归档仍写 `backups/products/`。
