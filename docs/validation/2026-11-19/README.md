# omicsDesk 0.2.0 版本基线同步与验收

日期：2026-11-19。omicsDesk、omicsApp、omicsCore 已统一为 **0.2.0**，本机用户 R 库也已升级。最终离线 ZIP 已通过全新库安装、真实分析和浏览器验收。

## 共同基线

- omicsApp 上游主分支：`07f523b196e67a98969096097ce9a8bee87f01fb`。同步前已执行 `git fetch origin` 确认。
- 共享兼容提交：`30b310282e9e5ee07b8647dd8155234dafdeaabf`，直接基于上述主分支，保留其所有导入、统计、图形和界面更新。
- omicsDesk 构建提交：`284c55edb19c6d6c2e911a890cb6cfacd9fddfd6`。
- 两个仓库的工作分支均为 `codex/unified-desktop-baseline`。上述提交目前只在本地，尚未推送或发布；旧分支保留。

omicsDesk 继续作为分发和启动层，共用 omicsApp/omicsCore，不复制分析或界面代码。Remotes、构建检查和 CI 固定到同一个共享提交。三个版本号必须一致，普通构建拒绝不同提交或未提交的共享源码；开发者可显式使用 `--allow-unpinned`。本地源码安装器按 Core → App → Desk 顺序安装，并记录来源 SHA。`doctor()` 检查版本和来源。

## 交付物与使用

[离线 ZIP](../../../dist/omicsDesk-0.2.0-R4.4-macos-arm64.zip) 约 **522 MiB**，包含 274 个 R 包，适用于 **Apple Silicon / R 4.4.x**。完整 SHA-256 和源码包校验值见 [artifacts.json](artifacts.json)，构建明细见 [BUNDLE](BUNDLE)。

ZIP SHA-256：`a1f15bd5e452b025222053359eac752170c5701b434ed9f86bbd0b0add3e7485`。

本机已经安装匹配的三个包；重启 R 后执行：

```r
omicsDesk::doctor()
omicsDesk::launch()
```

另一台匹配平台的电脑解压 ZIP 后执行 `Rscript INSTALL.R` 和 `Rscript START.R`。源码开发环境使用 `Rscript tools/install_local.R --omicsapp ../omicsApp`，已有依赖时无需下载或重新解析远程依赖。共享提交尚未推送，因此当前应使用本地源码或 ZIP；推送时先推共享分支，再推桌面分支。

## 主要修改

- 同步 0.2.0 的多图层、多组比较、方向性富集、扩展导入格式、项目签名和逐图 PNG/PDF/SVG 下载。
- 更新离线硬依赖，加入 BiocParallel、SummarizedExperiment、babelgene、data.table、openssl、ragg 和 svglite；移除已不再使用的直接依赖。
- 保留显式 **Apply to downstream**：过滤和填补后的层供差异及整合分析读取，原始层保留供调整阈值。脚本导出重放同样的清洗步骤。
- 0.1 桌面项目的 preprocessing 只有在原始层版本仍匹配时才迁移；过期清洗不会被应用到替换后的数据。迁移保留原始层及已有结果。
- 断网时缺失缓存、主动刷新和 KEGG 请求立即给出本地修复提示；磁盘内容、目录及离线状态变化都会使原始表和派生表缓存失效。
- 人与小鼠的 14 张基因集继续内置；支持导入上游菜单中其他物种的缓存，状态页也能检查这些已导入表。
- 项目恢复时还原差异方法和设计控件；修复 `launch(project = ...)` 未打开指定项目及遗留启动选项的问题。
- 更新验收程序以使用新版 QC、表格导出和每会话自动保存。浏览器验收要求空白测试项目目录，避免旧结果让新流程假通过。
- 打包改用官方独立 pandoc 3.14，验证其下载 SHA-256，并检查其 macOS 动态依赖仅指向系统库。构建器拒绝 Homebrew 路径及依赖本地 Homebrew 库的 pandoc。

Excel 结果从 Differential 页面下载；Report 页面按共享 0.2.0 的接口提供 HTML、R 脚本及脚本与数据压缩包。

## 自动测试

- **omicsCore：4,264 项断言通过，0 失败 / 错误，3 警告，2 跳过。** 已开启性能预算和重型 API 参数扫描。[日志](core-final.log)。跳过项分别为上游测试环境没有 KEGG 数据、历史 QC fixture 本来不含差异结果；最终离线包另行检查全部 14 张缓存可读。警告来自特意设置的统计边界数据。
- **omicsApp：3,029 项断言通过，0 失败 / 错误，5 警告，2 跳过。** 包含真实原始数据 golden、浏览器、双会话、下载与恢复。[日志](app-final.log)。macOS 缺少 flock 的服务端备份测试和仅适用于已安装包的测试分支跳过。警告为 C locale 中文路径及上游服务端 Keycloak 标签未固定摘要，不影响桌面流程。
- **omicsDesk：242 项断言通过，0 失败 / 错误 / 警告 / 跳过。** [日志](desk-final.log)。
- **源码包 R CMD check：0 ERROR、0 WARNING、1 NOTE。** 唯一 NOTE 是内置基因集使安装体积为 7.8 MB。[检查日志](00check.log)。

三个源码套件合计 **7,535 项通过断言**。检查并非只有版本字段比较，还实际运行了新旧接口衔接和应用流程。

## 最终 ZIP 实际验收

[安装日志](install.log)来自最终 ZIP 解压后创建的全新 R 库，强制安装全部应用包。验证实际加载的硬依赖均来自该库，基础及推荐包允许使用 R 自带版本；核对三个版本和共享源码 SHA。

[分析日志](acceptance.log)覆盖 300 个真实基因符号、12 个样本的合成测试数据：Excel 导入、VSN、缺失过滤和填补、应用 QC、limma、ORA/GSEA/GSVA、edgeR/DESeq2、跨组学关联、保存重开、Excel/TSV 和自包含 HTML。过滤后为 299 行且无缺失。导出脚本在独立 R 进程执行，按 feature ID 对齐 effect、statistic、p_value、adj_p_value，容差 `1e-8`。GSEA 对强信号合成数据的两条极小 p 值估计警告保留在日志中。

[浏览器日志](browser.log)通过已安装的 `omicsDesk::launch()` 与真实 multisession worker 检查七个视图、上传、VSN、应用 QC、后台 limma 数值、离线富集、Excel、PNG/PDF/SVG、脚本、数据压缩包和 HTML 下载。进程重启后恢复 299 行结果，方法仍为 limma，页面无 Shiny 输出错误。[界面截图](desktop-differential.png)。

[最终验证日志](verify-final.log)确认上述检查全部通过。网络测试使用无效 HTTP/HTTPS 代理并放行本地回环，不是操作系统防火墙隔离。

[本机升级日志](local-upgrade.log)和 [本机自检](local-doctor.log)确认用户 R 库中的三个包均为 0.2.0，共享来源为 `30b3102`，所有必需自检项通过。用户项目和自有基因集未用于测试或被覆盖；原有 `docs/reviews/` 保留。

## 复验与边界

```sh
NOT_CRAN=true Rscript --vanilla -e 'testthat::test_local(".")'
NOT_CRAN=true OMICSCORE_PERF_TESTS=1 OMICSCORE_FUZZ_TESTS=1 Rscript --vanilla -e 'testthat::test_local("../omicsApp/packages/omicsCore")'
NOT_CRAN=true Rscript --vanilla -e 'pkgload::load_all("../omicsApp/packages/omicsCore"); testthat::test_local("../omicsApp/packages/omicsApp")'
Rscript --vanilla tools/verify_bundle.R dist/omicsDesk-0.2.0-R4.4-macos-arm64.zip --browser --output dist/reverification
```

本次实机验收范围为 macOS arm64 / R 4.4.3。Windows、Intel macOS 和 Linux 保留构建矩阵，未在本次执行远程 CI。内置 MSigDB 仍为 2025.1；其他物种需要自行导入缓存。最终 ZIP 的报告验收为 HTML，PDF 图形下载已测试，整份 PDF 报告仍需要额外 LaTeX 工具链。源码升级不会把本机原有 pandoc 替换掉；独立 pandoc 随离线 ZIP 分发。
