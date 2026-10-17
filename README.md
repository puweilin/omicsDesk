# omicsDesk

The offline, single-machine edition of [omicsApp](https://github.com/puweilin/omicsApp).

**0.1.0** pins omicsApp/omicsCore to `392c877`, based on the tested
`f3c2ff4` baseline plus the desktop offline, cache, report and recovery fixes.
The analysis engine and all seven views come from those shared packages.
Each offline bundle records its exact source revision and file checksums.

### 本地版快速开始

下载与操作系统、CPU 架构及 R 小版本匹配的 ZIP，解压后执行：

```sh
Rscript INSTALL.R
Rscript START.R
```

也可以在 R 中使用：

```r
omicsDesk::doctor()
omicsDesk::launch()
# 较小内存的电脑可以减少后台进程：
omicsDesk::launch(workers = 1L)
```

升级后重启 R。项目和自行导入的基因集会保留在 `~/omicsDesk`。
默认使用独立 R 后台进程，支持 macOS；`workers = 0L` 沿用当前 future 设置。
离线模式下，缺失或损坏的基因集会给出本地修复提示，不尝试下载。
QC 页面需要点击 **Apply to downstream** 才会把清洗结果用于后续分析。

可以用安装包内的 `Rscript VERIFY.R <测试输出目录>` 运行合成数据验收。
该检查会实际执行分析、导出、项目保存与恢复，并在独立 R 进程重跑分析脚本。

omicsCore and omicsApp assume a machine that can reach CRAN and
Bioconductor: analysis engines are optional packages installed on first
use, and the MSigDB gene sets come from `msigdbr`, which on current
versions downloads them. omicsDesk removes both assumptions. It depends
on every engine the app can call, ships the gene-set tables, starts the
app with its files in one folder that persists between sessions, and
comes with the tooling that builds an installable bundle for a machine
that has never seen the internet.

| Function | What it does |
|---|---|
| `launch()` | starts the app: projects in `~/omicsDesk/projects`, gene sets from `~/omicsDesk/genesets`, no auto-refresh, the bundled pandoc for HTML reports |
| `doctor()` | one row per thing the app needs, with what was found and how to fix what was not |
| `install_offline()` | installs the whole stack from a bundle |
| `geneset_status()`, `import_geneset_cache()`, `export_geneset_cache()` | see, bring in, and pass on gene-set tables |
| `desk_home()`, `desk_paths()` | where the files are |

## For users: install from a bundle

A bundle is a zip named like `omicsDesk-0.1.0-R4.5-windows.zip`, built for
one platform and one R minor version. Unzip it, then follow its
`README.md`: install R of that minor version, run `INSTALL.R`, double-click
the launcher. Nothing in the process uses the network.

```r
omicsDesk::doctor()   # after installing: is everything here?
omicsDesk::launch()   # start the app
```

Your projects, gene-set tables and the report renderer live in
`~/omicsDesk` (`Documents\omicsDesk` on Windows). Set `OMICSDESK_HOME`
to put them elsewhere.

### Refreshing gene sets without a network

The shipped tables are MSigDB's; the `kegg` table is MSigDB's frozen
`KEGG_LEGACY` collection. To use current KEGG pathways, a colleague with
network access runs, in a session with omicsDesk installed:

```r
omicsDesk::launch(online = TRUE)              # or just:
omicsCore::refresh_geneset_cache("kegg")      # with OMICSCORE_GENESET_CACHE = desk_paths()$genesets
omicsDesk::export_geneset_cache("D:/genesets", include_kegg_live = TRUE)
```

and the offline user runs `omicsDesk::import_geneset_cache("D:/genesets")`.
KEGG's licence allows this for your own use only; `export_geneset_cache()`
leaves live-KEGG tables out unless told otherwise.

## For developers

### Layout

```
R/            launch(), doctor(), install_offline(), the gene-set helpers
inst/genesets 14 MSigDB tables (7.5 MB) + MANIFEST.json, built by tools/prewarm_genesets.R
inst/bundle   INSTALL.R, START.R, launchers, README template: copied into every bundle
tools/        prewarm_genesets.R, build_bundle.R, verify_bundle.R
docs/         the plan this repository implements
```

omicsDesk is a distribution layer. Analysis and UI code stay in the
monorepo; this package only depends on them, promotes their optional
engines to hard dependencies, and adds what an offline laptop needs.

### Building a bundle

On a machine with network access, with a checkout of the omicsApp
monorepo beside this one:

```sh
Rscript tools/prewarm_genesets.R                     # once per MSigDB release
Rscript tools/build_bundle.R --omicsapp ../omicsApp  # -> dist/omicsDesk-<ver>-R<minor>-<platform>/ and .zip
Rscript tools/build_bundle.R --omicsapp-ref 392c877eb3dc5b022db005966fa6bd48a6c20dfa     # the same, with omicsApp fetched from GitHub at that ref
Rscript tools/verify_bundle.R dist/omicsDesk-<...>.zip --browser --output dist/verification
```

Every bundle's `BUNDLE` file records the omicsApp commit it was built
from, so a bundle can always say which omicsCore and omicsApp it holds.

A bundle is built for the platform and R minor version the script runs
under; the `bundle` workflow builds Windows, macOS (arm64 and x86_64)
and Linux ones on a version tag. Bioconductor publishes binaries only
for its current and previous release, so keep the artifacts: a bundle
for an old R cannot be rebuilt later.

### Installing from source

omicsCore and omicsApp first, from the monorepo; then this package.

```r
devtools::install_local("../omicsApp/packages/omicsCore")
devtools::install_local("../omicsApp/packages/omicsApp")
devtools::install_local(".")
```

Install the pushed desktop branch with pak; its `Remotes` fields pin both
shared packages to the matching companion commit:

```r
pak::pak("puweilin/omicsDesk@codex/local-edition-refresh")
```

This update is on a separate branch. The remote omicsApp main branch has
additional development beyond this tested baseline and needs a separate
compatibility update before it can replace the pin. CI reads the same pinned
revision from `DESCRIPTION`.

### Tests and CI

```sh
Rscript -e 'devtools::test()'
```

`tools/verify_bundle.R` checks the **final ZIP**, installs every package in a
fresh library, validates checksums and upstream provenance, and runs real
proteomics/RNA-seq, enrichment, integration, persistence and export checks.
`--browser` additionally requires `callr`, `shinytest2`, `chromote` and Chrome;
it launches `omicsDesk::launch()` with real background workers, exercises
upload → VSN → apply QC → differential → enrichment → downloads, then restarts
and checks recovery. Proxy blackholing is used for these checks; this is not an
operating-system network sandbox.

The suite covers the environment `launch()` sets, the copy-and-never-
overwrite rule for gene-set tables, import and export, `doctor()` with
engines mocked away, and `install_offline()` against a real one-package
bundle built during the test. CI checks out the omicsApp monorepo beside
this one; both repositories are public, so no secret is involved.

## Gene sets and licences

`inst/genesets` holds MSigDB collections for human and mouse (Hallmark,
Reactome, WikiPathways, GO BP/MF/CC, and the frozen `KEGG_LEGACY` set),
taken from the `msigdbr` package and redistributed as it does, under
[MSigDB's licence terms](https://www.gsea-msigdb.org/gsea/msigdb_license_terms.jsp).
`inst/genesets/MANIFEST.json` records the MSigDB release and msigdbr
version they came from. Tables fetched live from the KEGG REST API by
`omicsCore::refresh_geneset_cache()` are for local use only under KEGG's
licence: they are never part of this package or a bundle, and
`export_geneset_cache()` leaves them out unless told otherwise.

## 中文快速开始

omicsDesk 是 omicsApp 的单机离线版：把所有分析引擎变成硬依赖、随包附带
MSigDB 基因集、把项目文件放在 `~/omicsDesk`（Windows 为 `文档\omicsDesk`），
并提供把整套依赖打包成离线安装包的工具。

用户：解压对应平台和 R 版本的 `omicsDesk-<版本>-R<x.y>-<平台>.zip`，按其中的
`README.md` 安装 R、运行 `INSTALL.R`、双击启动器。之后在 R 里用
`omicsDesk::doctor()` 自检，`omicsDesk::launch()` 启动。

开发者：先从 monorepo 安装 omicsCore 和 omicsApp，再安装本包；用
`tools/build_bundle.R` 生成离线包，`tools/verify_bundle.R` 在断网条件下验证。

## License

MIT (c) 2026 Weilin Pu.
