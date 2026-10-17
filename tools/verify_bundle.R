#!/usr/bin/env Rscript
# Verify the actual ZIP (or an unpacked bundle) in a fresh library.
# Rscript tools/verify_bundle.R <bundle.zip|directory> [--keep] [--browser] [--output <dir>]
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if (!length(args)) stop("Usage: verify_bundle.R <bundle.zip|directory> [--keep] [--browser] [--output <dir>]")
  input <- normalizePath(args[[1L]], mustWork = TRUE)
  keep <- "--keep" %in% args
  work <- tempfile("omicsDesk-verify-", tmpdir = dirname(tempdir()))
  dir.create(work)
  on.exit(if (!keep) unlink(work, recursive = TRUE) else message("Verification files: ", work), add = TRUE)
  output_i <- match("--output", args)
  output <- if (!is.na(output_i) && output_i < length(args)) args[[output_i + 1L]] else file.path(work, "evidence")
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  output <- normalizePath(output, mustWork = TRUE)
  if (dir.exists(input)) {
    bundle <- input
  } else {
    entries <- utils::unzip(input, list = TRUE)$Name
    if (any(grepl("(^/|^[A-Za-z]:|(^|/)\\.\\.(/|$))", entries))) stop("Unsafe ZIP paths")
    unpack <- file.path(work, "unpacked")
    utils::unzip(input, exdir = unpack)
    candidates <- list.files(unpack, pattern = "^BUNDLE$", recursive = TRUE, full.names = TRUE)
    if (length(candidates) != 1L) stop("Expected one BUNDLE record in ZIP")
    bundle <- dirname(candidates)
  }
  lib <- file.path(work, "library")
  home <- file.path(work, "home")
  dir.create(lib)
  dir.create(home)
  dead <- "http://127.0.0.1:9"
  Sys.setenv(http_proxy = dead, https_proxy = dead, HTTP_PROXY = dead, HTTPS_PROXY = dead,
             ALL_PROXY = dead, all_proxy = dead, no_proxy = "127.0.0.1,localhost", NO_PROXY = "127.0.0.1,localhost",
             OMICSDESK_HOME = home, R_LIBS = lib, R_LIBS_USER = lib, OMICSAPP_DEV_ROOT = "",
             OMICSCORE_OFFLINE = "1", OMICSCORE_GENESET_CACHE = file.path(home, "genesets"))
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  message("Installing final artifact into ", lib)
  status <- system2(rscript, c("--vanilla", shQuote(file.path(bundle, "INSTALL.R")), "--lib", shQuote(lib), "--force"),
                    stdout = file.path(output, "install.log"), stderr = file.path(output, "install.log"))
  if (status != 0L) stop("INSTALL.R failed; see ", file.path(output, "install.log"))
  check <- sprintf('
.libPaths(c(%s, .Library))
d <- omicsDesk::doctor(workers = TRUE)
stopifnot(all(d$ok[d$required]))
source(%s)
run_desk_acceptance(%s)
base <- rownames(installed.packages(priority = c("base", "recommended")))
loaded <- setdiff(loadedNamespaces(), base)
from <- vapply(loaded, function(ns) normalizePath(dirname(getNamespaceInfo(ns, "path"))), character(1))
leaked <- loaded[from != normalizePath(%s)]
hard <- unique(unlist(tools::package_dependencies(loaded, db = installed.packages(),
  which = c("Depends", "Imports", "LinkingTo"), recursive = FALSE)))
leaked_hard <- intersect(leaked, hard)
if (length(leaked_hard)) stop("Hard dependencies loaded outside bundle: ", paste(leaked_hard, collapse=", "))
cat("BUNDLE OK\\n")
', deparse(lib), deparse(file.path(bundle, "VERIFY.R")), deparse(output), deparse(lib))
  status <- system2(rscript, c("--vanilla", "-e", shQuote(check)),
                    stdout = file.path(output, "acceptance.log"), stderr = file.path(output, "acceptance.log"))
  if (status != 0L) stop("Installed workflow failed; see ", file.path(output, "acceptance.log"))
  if ("--browser" %in% args) {
    script_arg <- grep("^--file=", commandArgs(), value = TRUE)[[1L]]
    browser_script <- file.path(dirname(sub("^--file=", "", script_arg)), "verify_browser.R")
    status <- system2(rscript, c("--vanilla", shQuote(browser_script), shQuote(lib), shQuote(home), shQuote(output)),
                      stdout = file.path(output, "browser.log"), stderr = file.path(output, "browser.log"))
    if (status != 0L) stop("Browser workflow failed; see ", file.path(output, "browser.log"))
  }
  message("BUNDLE OK: installation, engines, QC, replay, persistence, exports", if ("--browser" %in% args) ", browser" else "",
          "\nEvidence: ", output)
}
main()
