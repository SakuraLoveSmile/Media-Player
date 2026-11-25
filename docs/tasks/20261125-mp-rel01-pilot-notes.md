# MP-REL01：测试版更新说明显示反馈人与解决的问题

- 项目：personal-mediaplayer；创建日期：2026-11-25（Asia/Taipei）
- 状态：待体验（已合入 main；下一次 KaneoPilot 预发布读回正文后确认）
- 基线：main `4e7bbd8`；分支：`fix/20261125-mp-rel01-pilot-notes`；合入目标：main。
- 工作树：`/Users/sakurasep/Documents/Code/Project/Project Worktree/personal-mediaplayer/20261125-fix-mp-rel01-pilot-notes`。
- 现象：`v0.4.16-pilot.1795577309` 的更新说明只有「KaneoPilot 预发布构建 0.4.16 (build 1795577309)，批次 …」，用户看不到是谁反馈的需求、解决了什么问题。

## 根因

- KaneoPilot 已在冻结的任务 manifest 根成员写入 `reporter`（Kaneo 任务可见用户名）与 `summary`（冻结计划「目标」首句），契约见 `KaneoPilot/docs/release-contract.md`；本仓库发布工作流只把它当 provenance 资产，没有用它渲染 Release 正文，因此预发布落到写死的一行批次号文案。
- 已核对批次 `bed49d48-ae0e-4694-ac5f-76d7aed63066`：manifest 根成员确实带 `reporter=上杉九月`、`summary=用户在“一起看”页…请稍后重试”；缺陷在本仓库的渲染缺失，不在 KaneoPilot 冻结数据。

## 改动

- 新增 `.github/scripts/pilot_notes.py`：从 `TASK_MANIFEST_JSON` 根成员渲染 `【本次更新】\n\n@反馈人：一句话`；`reporter` 缺失回退 `@用户`，`summary` 缺失保留旧的一行预发布说明；单行化、按契约上限截断，并去掉句尾悬挂的「：」等标点（问题批次冻结的 summary 正是冒号结尾）。
- 新增 `.github/scripts/test_pilot_notes.py`：7 个用例（正常渲染、冒号结尾、缺 reporter、缺 summary、超长单行化、CLI 写入、CLI 拒绝坏 JSON）。
- `.github/workflows/release.yml` 发布 job：预发布且无 `release/notes/<tag>.md` 时，先按 `github.workflow_sha` 稀疏检出 `.github/scripts` 到 `pilot-tools/`（目标树早于脚本也能用），再渲染 `pilot-notes.md`，并用 `--notes-file` 创建 Release；渲染缺失直接 fail-closed，不再回退批次号文案。正式 tag 流程不变。
- `docs/release.md` §4.1 正文规则与静态说明同步。

## 验证

- `cd .github/scripts && python3 -m unittest test_pilot_notes`：7 项通过。
- 用批次 `bed49d48` 的真实冻结 manifest 渲染，得到：`【本次更新】` + `@上杉九月：用户在“一起看”页填写自建服务地址后，不再出现无信息量的“一起看操作失败，请稍后重试”`（冻结 summary 的结尾冒号被去掉）。
- `.github/workflows/release.yml` 经 PyYAML 解析通过；本机无 actionlint，未跑 ShellCheck/actionlint。
- 未验证：下一次真实预发布 Release 正文、更新弹窗读回；Actions 上的实际执行。

## 交付（2026-11-25）

- 功能 PR [#17](https://github.com/SakuraLoveSmile/Media-Player/pull/17) 合入 main（merge `7ef4085`）；随附清理 PR [#18](https://github.com/SakuraLoveSmile/Media-Player/pull/18)（merge `d7ede5f`）删掉误提交的 `.github/scripts/__pycache__`，并把 `__pycache__/`、`*.pyc` 加进 `.gitignore`。
- 本次未发布本仓库版本：正文渲染在下一次 KaneoPilot 预发布生效；届时核对 Release 正文与客户端更新弹窗。
- 已发布的 `v0.4.16-pilot.1795577309` 说明未修补（用户本轮只要求新测试版不再出现该问题）；如需修补须单独授权 `repair-release-notes`。
