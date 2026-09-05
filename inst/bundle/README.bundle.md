# omicsDesk {{VERSION}} for {{PLATFORM}}, R {{RMINOR}}

Built {{BUILT}}. Everything the app needs is in this folder; no network
connection is used at any point.

## Install

1. Install R **{{RMINOR}}.x** if it is not already installed. Any patch
   release of {{RMINOR}} works; another minor version does not, because the
   packages in `repo/` are built for {{RMINOR}}.
2. Run the installer:
   * Windows: open `R` or `RStudio`, then `source("INSTALL.R")` and run
     `install_offline_bundle(".")`; or from a command prompt in this
     folder, `Rscript INSTALL.R`.
   * macOS / Linux: in a terminal, `Rscript INSTALL.R` from this folder.
3. Start the app: double-click `omicsDesk.bat` (Windows) or
   `omicsDesk.command` (macOS), or run `Rscript START.R`. In R,
   `omicsDesk::launch()` does the same.

The installer copies {{PACKAGE_COUNT}} packages into your R library and
creates the folder `~/omicsDesk` (`Documents\omicsDesk` on Windows) for
your projects, the gene-set tables and the report renderer.

If something does not work, run `omicsDesk::doctor()` in R; it says what
is missing and what to do.

{{SOURCE_ONLY_NOTE}}

## What is inside

| Path | Purpose |
|---|---|
| `INSTALL.R` | the installer |
| `START.R`, `omicsDesk.bat`, `omicsDesk.command` | launchers |
| `repo/` | a local package repository: omicsCore, omicsApp, omicsDesk and their dependencies |
| `pandoc/` | the HTML report renderer ({{PANDOC}}) |
| `BUNDLE` | what this bundle was built with and for |
| `MD5SUMS` | checksums of every file |

## 中文快速开始

1. 安装 R **{{RMINOR}}.x**（其它小版本不行，`repo/` 里的包是为 {{RMINOR}} 编译的）。
2. 运行安装脚本：Windows 在 R 或 RStudio 里 `source("INSTALL.R")` 后执行
   `install_offline_bundle(".")`；macOS / Linux 在终端里进入本文件夹执行
   `Rscript INSTALL.R`。
3. 启动：双击 `omicsDesk.bat`（Windows）或 `omicsDesk.command`（macOS），
   或在 R 里执行 `omicsDesk::launch()`。

项目文件、基因集和报告渲染器都在 `~/omicsDesk`（Windows 为
`文档\omicsDesk`）。遇到问题先在 R 里运行 `omicsDesk::doctor()`。
