#!/usr/bin/env Rscript
#
# Prove a bundle installs and runs with no network. Installs it into a
# throwaway library with every HTTP route pointed at a dead port, then
# runs omicsDesk::doctor() from that library alone and checks that no
# package was loaded from anywhere else.
#
#   Rscript tools/verify_bundle.R dist/omicsDesk-<...>   [--keep]
#
# Exit status 0 means the bundle is complete for this machine.

args <- commandArgs(trailingOnly = TRUE)
bundle_dir <- args[!startsWith(args, "--")][1L]
if (is.na(bundle_dir) || !dir.exists(bundle_dir)) stop("Usage: verify_bundle.R <bundle dir> [--keep]")
bundle_dir <- normalizePath(bundle_dir, winslash = "/")
keep <- "--keep" %in% args

lib <- tempfile("omicsDesk-verify-lib-")
home <- tempfile("omicsDesk-verify-home-")
dir.create(lib); dir.create(home)
dead <- "http://127.0.0.1:9"
Sys.setenv(http_proxy = dead, https_proxy = dead, HTTP_PROXY = dead, HTTPS_PROXY = dead,
           no_proxy = "", NO_PROXY = "", OMICSDESK_HOME = home, R_LIBS = lib,
           R_LIBS_USER = lib)
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

message("Installing ", basename(bundle_dir), " into ", lib, " with the network blackholed")
status <- system2(rscript, c(shQuote(file.path(bundle_dir, "INSTALL.R")), "--lib", shQuote(lib), "--force"))
if (!identical(status, 0L)) stop("INSTALL.R failed with status ", status)

check <- sprintf('
lib <- %s
stopifnot(normalizePath(.libPaths()[[1L]]) == normalizePath(lib))
d <- omicsDesk::doctor(workers = TRUE)
base <- rownames(installed.packages(priority = "base"))
loaded <- setdiff(loadedNamespaces(), base)
from <- vapply(loaded, function(ns) normalizePath(dirname(getNamespaceInfo(ns, "path"))), character(1))
leaked <- loaded[from != normalizePath(lib)]
if (length(leaked)) cat("LEAKED (loaded from outside the bundle library):", paste(leaked, collapse = ", "), "\n")
ok <- all(d$ok[d$required]) && length(leaked) == 0L
cat(if (ok) "BUNDLE OK\n" else "BUNDLE INCOMPLETE\n")
quit(status = if (ok) 0L else 1L)
', deparse(lib))
status <- system2(rscript, c("-e", shQuote(check)))
if (!keep) unlink(c(lib, home), recursive = TRUE)
quit(status = status)
