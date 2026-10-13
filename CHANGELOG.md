# CHANGELOG

本项目是 [dannyge/openvohive](https://github.com/dannyge/openvohive) 的 fork，只记录**我方增量**。

## [0.1.0] - 2026-10-13
### Added
- NAS 自建发行版立项：发行分支 `nas`，基线 `a0e2d642`（= 生产镜像 `ghcr.io/dannyge/openvohive:latest` 的构建源），保证与线上差异最小、可审计。
- 仓库脚手架：`Dockerfile.nas`（自包含多阶段构建）、CI（构建镜像 → 跑测试 → 凭据泄漏检查）、release 工作流、`deploy/`（compose + deploy.sh）、`docs/`（任务书 / 方案 / 交接 / 令牌）。
- 双远端：`origin` = 我方 fork，`upstream` = `dannyge/openvohive`（只拉不推）。

### Notes
- 许可沿用上游 **PolyForm Noncommercial 1.0.0**（个人非商业自用）。
- 时间戳：2026-10-13T22:42:31+08:00
