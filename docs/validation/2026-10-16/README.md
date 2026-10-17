# omicsDesk 0.1.0 同步与验收记录

日期：2026-10-16。结论：**当前本地 omicsApp 已同步到可安装的桌面分发包；最终 ZIP 在 macOS arm64 / R 4.4.3 上通过全新库安装、真实分析与浏览器验收。**

本次采用共享的 omicsApp/omicsCore 实现，不在 omicsDesk 复制一套分析或界面代码。基线为 omicsApp `f3c2ff412d72ce59dc07e6e812f97625d1fc27cd`，并附带本次共享引擎和恢复流程修补。omicsDesk 版本升至 `0.1.0`，基础提交为 `b2df25e2a22f34357a6d9df5ebfaac6e59506fe7`。

## 可以交付的文件

- [离线安装 ZIP](../../../dist/omicsDesk-0.1.0-R4.4-macos-arm64.zip)：约 518 MiB，271 个包，适用于 **Apple Silicon / R 4.4.x**。
- [R 源码包](../../../dist/omicsDesk-0.1.0-R4.4-macos-arm64/repo/src/contrib/omicsDesk_0.1.0.tar.gz)：配套的 omicsCore、omicsApp 源码包位于同一目录；安装三个包时依次为 Core、App、Desk。
- [构建记录](BUNDLE)、[文件 SHA-256 与源码版本](artifacts.json)、[共享仓库补丁](companion-omicsApp.patch)。

ZIP SHA-256：`3f6fddc2914804a1e72a90a2af02a5dc7c172482903846ca89e63d0599b6820d`。

解压 ZIP 后执行 `Rscript INSTALL.R`，再运行 `Rscript START.R`。在已安装的 R 中可执行 `omicsDesk::doctor()` 和 `omicsDesk::launch()`。升级后重启 R，使已加载的包切换到新代码。旧的 `0.0.0.9000` ZIP 没有被替换，也不属于这次验收的交付物。

## 修改与问题闭环

| 问题 | 本次处理 | 验证 |
|---|---|---|
| 桌面分发仍携带旧 UI、QC 数据流与导出逻辑 | 从当前相邻仓库构建共享 Core/App 包，保留逐层 QC、结果归属、轻量后台载荷和可重放处理记录 | 共享引擎及界面全量测试；安装后实际流程 |
| 导入的基因集被下一次同步覆盖 | 只有来源明确为 bundle 且未被修改的文件允许自动升级；import 和未知来源保留；写入采用暂存后替换并检查返回值 | 导入 → 状态查看 → doctor → 启动准备连续回归；内置表升级回归 |
| 自定义缓存目录没有得到初始化 | 初始化、状态、导入和导出使用一致的有效缓存路径 | 指定临时缓存目录，14 张表齐全且可读 |
| macOS fork 后台存在 Objective-C 崩溃风险 | 桌面入口使用 multisession；单 worker 也启动真实进程；0 保留用户计划；错误退出恢复原计划 | 比较父子 PID；真实浏览器后台 limma 与直接计算一致 |
| 离线标志没有被当前共享引擎执行 | 缓存缺失、KEGG 网络调用和主动刷新均遵守离线模式并给出本地修复提示 | 缺失缓存、离线主动刷新、过期实时 KEGG 缓存测试 |
| 替换磁盘表或切换目录后仍读取旧内存缓存 | 缓存身份包含目录、文件 MD5 和离线状态 | 同进程切目录、替换文件、删除文件连续测试 |
| 自检只验证同进程执行，PDF 能力判断不完整 | 真实子进程检查 Core/App 可用性；PDF 检查与共享引擎的 XeLaTeX/CJK 字体条件一致 | 安装包 doctor 必需项全通过 |
| 开发版本号未变导致旧 Core/App 被跳过 | 安装器每次替换三个应用包，校验目标库版本；源码来源随包记录 | 同版本重复安装回归；实际全新库安装 |
| 仅验证解压目录，ZIP 可能仍旧 | 校验最终 ZIP 中的 MD5SUMS、平台、来源；从 ZIP 解压后进行全部验收 | [最终 ZIP 验收日志](verify-release.log) |
| 安装库路径含空格或中文时 BUNDLE 折行导致启动器找不到库 | Library 字段禁止折行；校验和相对路径不使用正则剥离目录 | `离线安装 bundle with spaces #1 (test)` 路径实际构建与安装测试 |
| HTML 报告引用远程 MathJax | 默认自包含报告关闭远程 MathJax，检查脚本/样式/图片/iframe 无远程资源引用 | 安装包真实 HTML 生成与浏览器下载 |
| 重启后保存结果未出现在页面，模型选项又回到默认 | 修复首次 observer flush 恢复时机；区分图层控件初始化与用户切换；保留保存时模型和协变量选择 | 新增启动/图层回归；浏览器重启后恢复 299 行差异结果且方法为 limma |
| 构建与依赖缓存容易漂移 | 私有目录构建 tarball；校验全部基因集；验证依赖闭包及版本；最终 ZIP 验证；保存 CI 证据 | 本机构建、校验及离线安装通过 |

CI 的 Intel macOS runner 由已停用的 macos-13 更新为 macos-15-intel；可用标签见 [GitHub 官方 runner 文档](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。本次没有触发远程 CI 或发布。

## 自动测试结果

| 测试 | 通过断言 | 失败 / 错误 | 跳过 | 说明 |
|---|---:|---:|---:|---|
| omicsCore 全量 | 2,797 | 0 | 0 | 开启性能预算及重型 API 参数扫描；1 条小样本 DESeq2 方差估计警告 |
| omicsApp 全量 | 1,756 | 0 | 0 | 包含浏览器、真实原始文件 golden、QC 衔接与异步回调；5 条既有 locale/统计拟合警告 |
| 最新恢复与控件专项 | 295 | 0 | 0 | 覆盖最终恢复、图层、差异、富集、整合及顶层连接改动；0 警告 |
| omicsDesk 全量 | 233 | 0 | 0 | 包含真实子进程、特殊路径安装、缓存及来源保护；0 警告 |
| 最终源码包 R CMD check | 203 | 0 | 2 | 0 ERROR、0 WARNING、3 NOTE；两项仅适用于源码目录的 tools 测试跳过，已在源码全量测试运行 |

检查的三个 NOTE 分别为离线发行有意保留较多硬依赖、内置基因集带来的约 7.8 MB 安装体积，以及无法联网验证当前时间。[完整检查日志](00check.log)。CSV 明细分别为 [Core](core-final.csv)、[App](app-final.csv)、[恢复专项](restore-final.csv)、[Desk](desk-final.csv)。

## 最终 ZIP 的实际验收

[安装日志](install.log)记录全新临时库的强制安装，测试未依赖机器上原先安装的应用包。检查实际加载的硬依赖没有来自目标库外的副本；base/recommended 包可使用 R 自带版本。

[分析日志](acceptance.log)覆盖 300 个真实基因符号、12 个样本的合成数据：Excel 导入 → VSN → 特征过滤和缺失填补 → limma → ORA/GSEA/GSVA → RNA-seq edgeR/DESeq2 → 跨组学关联 → 项目保存和重开 → workbook/HTML 导出。清洗后 299 行、无缺失。导出脚本在独立 R 进程重放，effect、statistic、p_value、adj_p_value 按 feature ID 对齐，容差 `1e-8`。这组结果只用于软件验证。

[浏览器日志](browser.log)从真实 `omicsDesk::launch(workers = 2)` 启动，检查七个视图、上传、VSN、应用 QC、后台 limma 数值、离线富集、三类下载和进程重启。重启后保留已保存的 299 行差异结果及 limma 选项。测试未以源码开发模式替代已安装版本。界面截图见 [desktop-differential.png](desktop-differential.png)。

网络验证采用无效 HTTP/HTTPS 代理并放行本地回环，证明所测流程不需要外部网络；未配置操作系统级防火墙。GSEA 对强信号合成数据的极小 p 值有两条估计警告，未用作生物学结论。

## 性能

硬件为 Apple M4 Max / 128 GiB，R 4.4.3；以下是本机单次可重现测量，不代表其他电脑的固定耗时。[原始 CSV](performance.csv)、[运行环境](session-info.txt)。

| 操作 | 耗时 | 预算 |
|---|---:|---:|
| 第一次准备桌面目录及基因集 | 0.031 s | 5 s |
| 再次准备 | 0.027 s | 1 s |
| 冷进程读取 Hallmark，含 Core 初次载入 | 1.925 s | 20 s |
| 内存命中读取 Hallmark | 0.003 s | 0.25 s |
| 63,241 × 258 TSV 导入 | 2.034 s | 60 s |
| 63,241 × 258 PCA，含 log2 转换 | 6.509 s | 20 s |
| 20,000 × 258 limma，含年龄协变量 | 0.238 s | 30 s |
| 63,241 行结果重新筛选 | 0.001 s | 0.25 s |

所有预算通过。大数据分析使用共享引擎现有的向量化计算和精简 worker 载荷；桌面入口没有新增一套重复计算。性能脚本为 `tools/benchmark_desktop.R`。

## 复验与边界

```sh
NOT_CRAN=true Rscript -e 'devtools::test()'
NOT_CRAN=true OMICSCORE_PERF_TESTS=1 OMICSCORE_FUZZ_TESTS=1 Rscript -e 'devtools::test("../omicsApp/packages/omicsCore")'
NOT_CRAN=true Rscript -e 'devtools::test("../omicsApp/packages/omicsApp")'
Rscript tools/verify_bundle.R dist/omicsDesk-0.1.0-R4.4-macos-arm64.zip --browser --output dist/verification
Rscript tools/benchmark_desktop.R dist/performance
```

- 本次实机范围为 macOS arm64 / R 4.4.3。Windows、Intel macOS、Linux 的构建矩阵已维护，但尚未在本次本机验证。
- PDF 工具链由 doctor 检查；此次安装包的主报告验收为 HTML。没有 LaTeX/CJK 字体的电脑需使用 HTML。
- MSigDB 内置版本仍为 2025.1；KEGG 为随 MSigDB 提供的 KEGG_LEGACY，并非本次联网更新的实时 KEGG。
- 历史项目的兼容与迁移由共享测试覆盖；缺少处理 provenance 的旧项目不会被编造参数来导出“可复现”脚本，需要重新导入以记录步骤。
- 原始验收时，两个仓库的代码尚未提交。2026-10-17 推送时将配套修改提交为 omicsApp `392c877eb3dc5b022db005966fa6bd48a6c20dfa`，并将 omicsDesk 的 Remotes、构建默认值及 CI 固定到该提交。原始 BUNDLE、ZIP 和校验值保持为 2026-10-16 实际验收记录，未将历史证据改写为提交后构建。
- 用户真实项目、原始数据与基因集缓存未被本次测试改写；已有 docs/reviews 审查资料保留。

验收结束后，本次创建的临时完整安装库已清理；上述日志、校验值、截图、补丁及分发包均已保留。已核对三个包内全部 R 源文件与当前源码逐字节一致。

## 2026-10-17 推送说明

源码分支为 [omicsDesk/codex/local-edition-refresh](https://github.com/puweilin/omicsDesk/tree/codex/local-edition-refresh) 和 [omicsApp/codex/desktop-offline-compatibility](https://github.com/puweilin/omicsApp/tree/codex/desktop-offline-compatibility)。共享实现的提交为 `392c877eb3dc5b022db005966fa6bd48a6c20dfa`。

推送前发现远程 omicsApp main 已与本次验收的本地基线分叉，因此本次推送独立分支，没有合入 main。源码安装使用 `pak::pak("puweilin/omicsDesk@codex/local-edition-refresh")`；普通 Git 推送不包含 dist 下的大型离线 ZIP。
