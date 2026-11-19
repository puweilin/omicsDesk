# omicsDesk

[omicsApp](https://github.com/puweilin/omicsApp) 的本地单机版，用于蛋白组、RNA-seq 等组学数据分析。在自己的电脑上运行，通过浏览器操作，项目保存在本地。

**可以直接通过 `remotes::install_github()` 或 `devtools::install_github()` 安装。安装完成后，默认离线运行。** 完全无法联网的电脑可以使用完整离线安装包。

当前版本为 **0.2.0**，与 omicsApp、omicsCore 共用分析引擎和界面；匹配的源码版本已记录在 [DESCRIPTION](DESCRIPTION) 中。

## 1. 联网安装

需要 R 4.2 或更新版本。在 **R 或 RStudio 控制台**中运行：

```r
options(repos = c(CRAN = "https://cloud.r-project.org"))
install.packages(c("remotes", "BiocManager"))

remotes::install_github(
  "puweilin/omicsDesk",
  ref = "main",
  repos = BiocManager::repositories(),
  upgrade = "always"
)
```

这会安装 omicsDesk、匹配的 omicsApp / omicsCore，以及所需分析依赖。首次安装下载量较大，请保持联网。

- 已有 `devtools`：可将上面的 `remotes::install_github()` 换成 [`devtools::install_github()`](https://devtools.r-lib.org/reference/remote-reexports.html)，参数相同。
- 保留 `repos = BiocManager::repositories()`：DESeq2、GSVA 等依赖来自 Bioconductor，需要同时配置 [Bioconductor 和 CRAN 软件源](https://bioconductor.github.io/BiocManager/reference/repositories.html)。
- `upgrade = "always"` 会更新过旧的依赖，包括旧版 omicsApp / omicsCore，避免混用版本。详见 [remotes 安装参数](https://remotes.r-lib.org/reference/install_github.html)。

## 2. 启动和使用

安装或升级后，**先重启 R**，再运行：

```r
omicsDesk::doctor()  # 检查依赖、基因集和报告工具
omicsDesk::launch()  # 启动界面
```

界面会在浏览器中打开，使用期间保持 R 会话运行。以后启动只需执行 `omicsDesk::launch()`。

基本流程：

1. 导入数据并设置分组。
2. 在 QC 页面检查、过滤数据；点击 **Apply to downstream**，将清洗结果应用到后续分析。
3. 进行差异分析、富集分析或多组学整合。
4. 下载结果：各图支持 PNG / PDF / SVG，Differential 页面可下载 Excel，Report 页面可下载 HTML 报告、R 脚本及脚本与数据压缩包。

项目默认保存在 `~/omicsDesk/projects`，基因集保存在 `~/omicsDesk/genesets`。查看本机的实际目录：

```r
omicsDesk::desk_paths()
```

升级软件会保留该目录中的项目和自行导入的基因集。内置基因集覆盖人和小鼠，可在离线状态下使用。

## 3. 完全离线的电脑如何安装

准备与目标电脑的 **操作系统、CPU 架构和 R 小版本**匹配的完整离线 ZIP。安装包包含 R 包及其依赖、安装脚本和启动器；目标电脑需要先安装对应版本的 R。

例如，文件名中的 `R4.4-macos-arm64` 表示适用于 R 4.4.x 和 Apple Silicon Mac。

解压 ZIP，在**终端或命令提示符**中进入解压目录，执行：

```sh
Rscript INSTALL.R
Rscript START.R
```

也可以按安装包内的 `README.md` 操作。安装完成后，在 R 中同样可以用 `omicsDesk::launch()` 启动。

## 4. 常见问题

### 安装时出现 `401 Bad credentials`

通常是 R 读取到了失效的 GitHub 凭据。可以在 R 控制台运行下面的命令，按提示更新自己的 GitHub token：

```r
install.packages("gitcreds")
gitcreds::gitcreds_set()
```

如果 `.Renviron` 中还设置了旧的 `GITHUB_PAT` 或 `GITHUB_TOKEN`，也需要更新或移除旧值，重启 R 后重新安装。参见 [gitcreds 凭据设置说明](https://gitcreds.r-lib.org/reference/gitcreds_get.html)。

### 提示找不到 DESeq2、GSVA 等依赖

先确认使用了上面的完整安装命令，尤其是 `repos = BiocManager::repositories()`。如果日志提示依赖不支持当前 R 版本，需要使用兼容的 R / Bioconductor 版本。

### 能分析，但不能导出 HTML 报告

先运行 `omicsDesk::doctor()`。如果提示找不到 Pandoc，请按 [Pandoc 官方安装说明](https://pandoc.org/installing.html) 安装后重启 R。GitHub 安装主要安装 R 包，Pandoc 需要本机另行提供。

### 电脑内存较小

减少后台 R 进程数量：

```r
omicsDesk::launch(workers = 1L)
```

### 如何升级

重新执行“联网安装”中的命令，重启 R，再运行 `omicsDesk::doctor()`。如果提示版本不一致，但安装器跳过了安装，可在 `install_github()` 中加上 `force = TRUE` 重装。离线电脑使用匹配的新版本完整安装包升级。

## 更多说明

- [开发与维护](docs/development.md)：本地源码安装、离线包构建与验证、基因集导入导出。
- [0.2.0 验证记录](docs/validation/2026-11-19/README.md)：测试范围和结果。
- [更新记录](NEWS.md) · [问题反馈](https://github.com/puweilin/omicsDesk/issues)

代码采用 [MIT 许可](LICENSE.md)，© 2026 Weilin Pu。内置基因集遵循 [MSigDB 许可](https://www.gsea-msigdb.org/gsea/msigdb_license_terms.jsp)，来源版本记录在 [MANIFEST.json](inst/genesets/MANIFEST.json) 中。内置 KEGG 表为 `KEGG_LEGACY` 集合；在线获取的 KEGG 数据不随本包分发。
