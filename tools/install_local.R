#!/usr/bin/env Rscript
# Install the three matching source packages without a remote dependency solver.
# Dependencies must already be installed (otherwise use the offline bundle).
# Rscript tools/install_local.R [--omicsapp <checkout>] [--lib <library>]
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  i <- match(flag, args)
  if (is.na(i)) return(default)
  if (i == length(args) || startsWith(args[[i + 1L]], "--")) stop("Missing value for ", flag)
  args[[i + 1L]]
}
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), mustWork = TRUE)
upstream <- normalizePath(get_arg("--omicsapp", file.path(root, "..", "omicsApp")), mustWork = TRUE)
lib <- get_arg("--lib", .libPaths()[[1L]])
sha <- system2("git", c("-C", shQuote(upstream), "rev-parse", "HEAD"), stdout = TRUE)
if (length(sha) != 1L || !is.null(attr(sha, "status"))) stop("Cannot read upstream revision")
dirty <- system2("git", c("-C", shQuote(upstream), "status", "--porcelain", "--", "packages"), stdout = TRUE)
if (length(dirty)) stop("Upstream packages have uncommitted changes; commit the shared baseline first.")
source(file.path(root, "tools", "baseline.R"))
check_upstream_baseline(root, upstream, sha)
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
lib <- normalizePath(lib, mustWork = TRUE)
work <- tempfile("omicsDesk-install-")
dir.create(work)
install <- function() {
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  r <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R")
  for (pkg in c("omicsCore", "omicsApp", "omicsDesk")) {
    input <- if (pkg == "omicsDesk") root else file.path(upstream, "packages", pkg)
    if (pkg != "omicsDesk") {
      if (!file.copy(input, work, recursive = TRUE)) stop("Could not stage ", pkg)
      input <- file.path(work, pkg)
      desc <- read.dcf(file.path(input, "DESCRIPTION"))
      desc <- cbind(desc, `Config/omicsDesk/SourceSHA` = sha)
      write.dcf(desc, file.path(input, "DESCRIPTION"))
    }
    status <- system2(r, c("CMD", "INSTALL", "-l", shQuote(lib), shQuote(input)))
    if (status != 0L) stop("Installation failed for ", pkg)
  }
}
install()
message("Installed omicsDesk, omicsApp and omicsCore at ", sha,
        "\nLibrary: ", lib, "\nRestart R, then run omicsDesk::doctor() and omicsDesk::launch().")
