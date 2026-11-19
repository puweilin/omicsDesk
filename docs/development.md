# omicsDesk 开发与维护

[返回安装与使用说明](../README.md)

omicsDesk 负责单机运行、离线依赖和基因集缓存。分析引擎与界面继续由 [omicsApp 仓库](https://github.com/puweilin/omicsApp) 中的 omicsCore、omicsApp 提供。

## 版本基线

[DESCRIPTION](../DESCRIPTION) 的 `Remotes` 和 `Config/omicsDesk/UpstreamRef` 固定共享源码提交。0.2.0 对应 `30b310282e9e5ee07b8647dd8155234dafdeaabf`，已发布到 omicsApp 仓库；GitHub 安装、CI 和离线包构建均可使用该提交。

本地安装和打包脚本检查共享源码是否与固定提交一致、包目录是否干净，以及三个包的版本号是否一致。离线包的 `BUNDLE` 记录共享源码提交，`MD5SUMS` 记录文件校验值。安装后可用 `omicsDesk::doctor()` 检查版本和已记录的源码来源。

## 目录

| 路径 | 用途 |
| --- | --- |
| `R/` | 启动、自检、离线安装和基因集管理 |
| `inst/genesets/` | 人和小鼠的 14 个 MSigDB 缓存表及来源清单 |
| `inst/bundle/` | 离线安装脚本、启动器和说明模板 |
| `tools/` | 本地安装、打包和验收工具 |
| `tests/` | 自动化测试 |
| `docs/validation/` | 验收记录 |

以下终端命令均从 omicsDesk 仓库根目录执行。

## 从本地源码安装

适用于已具备分析依赖的开发环境。将匹配的 omicsApp 检出目录放在相邻位置，然后执行：

```sh
Rscript tools/install_local.R --omicsapp ../omicsApp
```

脚本按 omicsCore → omicsApp → omicsDesk 的顺序安装，并在共享包中记录源码提交。可用 `--lib <目录>` 指定 R 包安装目录。安装后重启 R。

新环境可先按 [联网安装说明](../README.md#1-联网安装) 安装依赖，或使用完整离线包。

## 构建离线包

构建电脑需要联网，并安装 `pak`、`jsonlite`、`rmarkdown` 及 R 包构建工具。准备适合目标平台的 [Pandoc 官方独立二进制文件](https://pandoc.org/installing.html)。

使用相邻的 omicsApp 检出目录：

```sh
Rscript tools/build_bundle.R --omicsapp ../omicsApp --pandoc /path/to/pandoc
```

也可以让脚本自动下载 `DESCRIPTION` 中固定的共享提交：

```sh
Rscript tools/build_bundle.R --pandoc /path/to/pandoc
```

将 `/path/to/pandoc` 替换为实际可执行文件路径。macOS 打包会拒绝依赖 Homebrew 动态库的 Pandoc，以便安装包能在其他电脑上运行。`--allow-unpinned` 仅用于明确需要其他共享版本的开发构建。

输出位于 `dist/`，包含安装目录和 ZIP。安装包对应构建时的操作系统、CPU 架构及 R 小版本；不同平台需要分别构建。[bundle 工作流](../.github/workflows/bundle.yaml) 支持 Windows、macOS arm64 / x86_64 和 Linux，可手动触发，或随版本标签触发。发布后应保留生成的安装包。

更新随包提供的 MSigDB 缓存时运行；日常打包可直接使用仓库已有缓存：

```sh
Rscript tools/prewarm_genesets.R
```

## 测试与离线验收

运行单元测试：

```sh
Rscript -e 'devtools::test()'
```

验证最终 ZIP（将文件名替换为实际路径）：

```sh
Rscript tools/verify_bundle.R dist/omicsDesk-<版本>-R<小版本>-<平台>.zip --output dist/verification
```

验收会在独立 R 库中安装包，检查校验值、版本来源，执行分析、QC、富集、整合、导出、项目恢复，并在新进程中重跑导出的分析脚本。

追加 `--browser` 可验证浏览器中的上传、分析、下载和重启恢复；需要 `callr`、`shinytest2`、`chromote` 和 Chrome。验证通过无效代理阻断外网请求，不等同于操作系统级网络隔离。

在已安装的离线包目录中，也可以运行合成数据验收：

```sh
Rscript VERIFY.R <测试输出目录>
```

## 基因集和本地目录

`launch()` 默认离线运行，使用本地缓存并关闭 KEGG 自动刷新。离线模式下，缺失或损坏的缓存会提示本地修复，不尝试下载。

随包提供人和小鼠的 Hallmark、Reactome、WikiPathways、GO BP / MF / CC 和 KEGG_LEGACY 表。其他物种可按相同命名格式导入本地缓存；函数说明可通过 `?omicsDesk::import_geneset_cache` 查看。

查看和转移缓存，在已安装 omicsDesk 的 R 会话中运行：

```r
omicsDesk::geneset_status()
omicsDesk::export_geneset_cache("/path/to/transfer")
```

将导出的目录复制到目标电脑，再在目标电脑的 R 中运行：

```r
omicsDesk::import_geneset_cache("/path/to/transfer")
```

默认导出不包含在线获取的 KEGG 数据。需要联网更新 KEGG 时，可在联网电脑上以 `omicsDesk::launch(online = TRUE)` 启动；转移这类数据前应查阅相应许可，只有显式指定 `include_kegg_live = TRUE` 才会将其导出。

设置 `OMICSDESK_HOME` 可以更改默认工作目录；已设置的 `OMICSAPP_DATA_DIR`、`OMICSCORE_GENESET_CACHE` 和 `RSTUDIO_PANDOC` 会被保留。`launch(workers = 0L)` 可沿用调用方已有的 future 后台任务设置。
