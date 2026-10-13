
# 方案：Bark 验证码自动复制（自建镜像）

- 状态：**待用户批准**（阶段②出口）
- 起草：Hermes，2026-10-13T22:44:02+08:00
- 依据：`docs/任务书.md` T2；上游查证记录见文末

## 1. 目标与非目标

**目标**
1. 建立**可复现构建**的自建镜像：与生产现役镜像同源（基线 `a0e2d642`），只做最小增量。
2. 短信推送带 Bark 的 `copy`（要复制的内容）与 `autoCopy=1`，让验证码**自动进剪贴板**。
3. 发布/部署可回滚：换 `IMAGE_TAG` 一分钟回官方镜像。

**非目标（明确不做）**
- 不改前端 Vue 页面、不加 UI 开关（配置走 `config.yaml` / `PROXY_*`）
- 不迁到上游 `main` 线（那条线更旧：缺 Bark 测试通知、通知重试重写、URC 噪声抑制、"静默丢短信"修复）
- 不做中继/旁路服务（方案 B，已否）
- 不新增通知渠道、不改数据库结构

## 2. 分层步骤（每步可独立回退）

| 步 | 动作 | 回退方式 |
|---|---|---|
| S1 | 立项：脚手架 + CI（**本次已完成**） | `git reset --hard <立项提交>`（未部署，线上零影响） |
| S2 | 打补丁：`internal/notify/bark.go` 恢复 `copy`/`autoCopy` + 验证码提取；`internal/config/config.go` 加 `bark.auto_copy`（默认 false）；补 Go 单测 | 分支未合并即重置；线上仍是官方镜像 |
| S3 | 发版：`VERSION=0.1.0` → tag `v0.1.0` → CI 构建 → 冒烟过 → 推 GHCR | 不部署即可；或删 tag/包 |
| S4 | 部署：部署目录 compose 薄 wrapper（include 仓库内 compose 绝对路径）+ `.env` 换 `IMAGE_TAG` → `deploy.sh` | `.env` 改回官方镜像 + `docker compose up -d`（分钟级） |
| S5 | 验收：独立探针（真实短信 + Bark 服务端日志 + 负例 + 造反例） | 同 S4 |

## 3. 每步验收标准（可证伪）

| 步 | 判据 | 失败长什么样 |
|---|---|---|
| S2 | `go test ./internal/notify/...` 全绿；`grep -c autoCopy internal/notify/bark.go` ≥1 | 测试红 / grep 输出 0 |
| S2 | 「无验证码短信 → 不产生 copy」的用例通过 | 该用例红 |
| S3 | release run conclusion=success；冒烟输出 `✅ 冒烟通过：可登录 + 版本串一致` | run 红 / 版本串不符 |
| S4 | `deploy.sh` 打印容器 ID 变化 + `容器内版本: 0.1.0` + 未挂源码 | 版本串还是旧值（源码遮蔽 / 没换镜像） |
| S5 | Bark 服务端日志出现 `"copy":"123456","autoCopy":"1"`（真实短信） | 只有 title/body/group = 补丁没生效 |

## 4. 风险与缓解

| 风险 | 缓解 |
|---|---|
| **autoCopy 覆盖剪贴板**（很可能是上游删它的原因） | 只在**识别到验证码**时才带 `copy`/`autoCopy`；无验证码短信一律不带（任务书 A3 负例）。开关 `bark.auto_copy` 默认 **false**，我方部署显式置 true |
| 正则误判（把订单号/金额当验证码） | 只认 4–8 位数字且靠近「验证码 / code」语境；宁可漏判不复制。误判代价=剪贴板被覆盖，不会发错短信 |
| 自建镜像落后上游修复 | 基线 commit 写进 CHANGELOG；保留 `upstream` 远端，定期 `git fetch upstream && git log --oneline a0e2d642..upstream/main` 对比 |
| GHCR 拉不动（私有包） | 包保持 public；实在拉不动改用本地 `docker compose build` 兜底 |
| CI 编译失败（Go 1.26 + Bun 前端） | 全部在 CI 构建，不消耗 NAS；失败就地修 CI，不影响线上 |
| 回滚后通知配置不兼容 | 本次不改配置结构，回官方镜像后 `data/config.yaml` 原样可用 |

## 5. 影响面

- 只影响「短信 → Bark 通知」链路；短信收发、设备管理、网页后台、QMI 后端不变。
- 串口互斥关系不变（与 FreePBX 仍二选一）。
- 备份：把 `/vol1/1000/Docker/openvohive/` 纳入每周备份脚本（待办，随 S4 做）。
- 文档：`NAS操作指南.md` 目录地图 + `dev-workspace/README.md` 各加一行（待办）。

## 附：上游查证记录（可复核）

| 事实 | 证据 |
|---|---|
| 现役镜像构建源 = `a0e2d642` | `dannyge/vohive-docker` 的 submodule `openvohive/src` 指向该 commit（分支 `feat/bark-notification`） |
| 该 commit 无 `copy`/`autoCopy` | `git show a0e2d642:internal/notify/bark.go` 的 payload 结构只有 device_key / title / body / group / sound |
| 功能是被主动删除的 | 提交 `d0971537`（2026-07-13）*refactor: remove verification code extraction and auto-copy* |
| 带功能的版本在另一条线 | `main` 线 `00d24b58`（2026-07-11），bark.go 206 行，含 `autoCopy` 与 `extractVerificationCode` |
| 生产实例缺字段（实测） | Bark 服务端日志 `POST /push` 的 JSON 只有 `device_key/title/body/group` |
