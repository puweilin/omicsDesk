# omicsDesk offline installer.
#
# Run this from the unzipped bundle, on a machine whose R version matches
# the one named in the BUNDLE file next to this script:
#
#   Rscript INSTALL.R                  # into the user library
#   Rscript INSTALL.R --lib <dir>      # into a library of your choice
#   Rscript INSTALL.R --home <dir>     # put the omicsDesk folder elsewhere
#   Rscript INSTALL.R --force          # reinstall what is already there
#
# From inside R:  source("INSTALL.R"); install_offline_bundle("<bundle dir>")
#
# Base R only, on purpose: this runs before anything else is installed.
# omicsDesk::install_offline() sources this same file, so there is one
# installer, not two that drift.

`%||%` <- function(a, b) if (is.null(a)) b else a

file_url <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  if (.Platform$OS.type == "windows") paste0("file:///", path) else paste0("file://", path)
}

r_minor <- function() {
  paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1L]][[1L]],
        sep = ".")
}

desk_home <- function() {
  dir <- Sys.getenv("OMICSDESK_HOME", "")
  if (!nzchar(dir)) dir <- path.expand("~/omicsDesk")
  dir
}

read_bundle_info <- function(bundle_dir) {
  path <- file.path(bundle_dir, "BUNDLE")
  if (!file.exists(path)) {
    stop("No BUNDLE file in ", bundle_dir,
         "; is this an unzipped omicsDesk bundle?", call. = FALSE)
  }
  as.list(read.dcf(path)[1L, ])
}

# "pkgA (1.0), pkgB, pkgC (2.1.3)" -> data.frame(package, version)
parse_package_field <- function(field) {
  items <- trimws(strsplit(field %||% "", ",")[[1L]])
  items <- items[nzchar(items)]
  pkg <- trimws(sub("\\(.*\\)$", "", items))
  ver <- ifelse(grepl("\\(", items), sub("^.*\\((.*)\\)$", "\\1", items),
                NA_character_)
  data.frame(package = pkg, version = ver, stringsAsFactors = FALSE)
}

install_offline_bundle <- function(bundle_dir = ".", lib = NULL,
                                   force = FALSE, quiet = FALSE) {
  bundle_dir <- normalizePath(bundle_dir, winslash = "/", mustWork = TRUE)
  info <- read_bundle_info(bundle_dir)

  if (!identical(info$RMinor, r_minor()) && !isTRUE(force)) {
    stop(sprintf(paste0(
      "This bundle was built for R %s; this is %s.\n",
      "Install R %s.x, use a bundle built for R %s, or pass force = TRUE ",
      "(Rscript INSTALL.R --force) to try anyway."),
      info$RMinor, R.version.string, info$RMinor, r_minor()), call. = FALSE)
  }

  repo_dir <- file.path(bundle_dir, "repo")
  if (!dir.exists(repo_dir)) stop("No repo/ directory in ", bundle_dir, call. = FALSE)
  repos <- c(CRAN = file_url(repo_dir))
  pkgs <- parse_package_field(info$Packages)
  if (nrow(pkgs) == 0L) stop("The BUNDLE file lists no packages.", call. = FALSE)

  lib <- lib %||% .libPaths()[[1L]]
  if (!dir.exists(lib)) dir.create(lib, recursive = TRUE)
  lib <- normalizePath(lib, winslash = "/")
  .libPaths(c(lib, .libPaths()))

  have <- utils::installed.packages(lib.loc = .libPaths())[, c("Package", "Version"), drop = FALSE]
  have <- have[!duplicated(have[, "Package"]), , drop = FALSE]
  have_ver <- stats::setNames(have[, "Version"], have[, "Package"])
  up_to_date <- vapply(seq_len(nrow(pkgs)), function(i) {
    p <- pkgs$package[[i]]
    v <- pkgs$version[[i]]
    if (is.na(have_ver[p])) return(FALSE)
    is.na(v) || package_version(have_ver[[p]]) >= package_version(v)
  }, logical(1))
  todo <- if (isTRUE(force)) pkgs$package else pkgs$package[!up_to_date]

  # Two passes, not type = "both": with "both", R treats the source index
  # as the master list and calls every binary-only package "not available".
  # Binaries first, then the sources (the three packages, and data
  # packages Bioconductor never builds binaries for), which R CMD INSTALL
  # checks against the now-installed binaries. Dependency order within
  # each pass is install.packages()'s own.
  bin_rel <- tryCatch(sub("^file://X/?", "", contrib.url("file://X", "binary")),
                      error = function(e) "")
  has_binaries <- nzchar(bin_rel) && bin_rel != "src/contrib" &&
    file.exists(file.path(repo_dir, bin_rel, "PACKAGES"))
  old <- options(repos = repos, timeout = 600)
  on.exit(options(old), add = TRUE)

  in_binary_index <- if (has_binaries) {
    rownames(utils::available.packages(contriburl = contrib.url(repos, "binary")))
  } else character()
  bin_todo <- intersect(todo, in_binary_index)
  src_todo <- setdiff(todo, in_binary_index)
  ncpus <- max(1L, parallel::detectCores() - 1L)

  if (length(todo) == 0L) {
    message("All ", nrow(pkgs), " packages are already installed at the bundled ",
            "version (force = TRUE to reinstall).")
  } else {
    message("Installing ", length(todo), " of ", nrow(pkgs), " packages\n  from ",
            repo_dir, "\n  into ", lib)
    if (length(bin_todo) > 0L) {
      message("  ", length(bin_todo), " binary packages")
      utils::install.packages(bin_todo, lib = lib, repos = repos, type = "binary",
                              dependencies = FALSE, quiet = quiet)
    }
    if (length(src_todo) > 0L) {
      message("  ", length(src_todo), " source packages")
      utils::install.packages(src_todo, lib = lib, repos = repos, type = "source",
                              dependencies = FALSE, quiet = quiet, Ncpus = ncpus)
    }
  }

  # Check the target library itself: another library on the path may hold
  # an older copy of a package that failed here, and would hide the failure.
  in_lib <- rownames(utils::installed.packages(lib.loc = lib))
  anywhere <- rownames(utils::installed.packages(lib.loc = .libPaths()))
  failed <- setdiff(todo, in_lib)
  missing <- setdiff(pkgs$package, anywhere)
  if (length(failed) > 0L || length(missing) > 0L) {
    stop("These packages did not install: ",
         paste(unique(c(failed, missing)), collapse = ", "),
         ".\nOn Windows and macOS this usually means a source-only package ",
         "needed a compiler; the bundle's README lists them.", call. = FALSE)
  }

  home <- desk_home()
  dir.create(home, recursive = TRUE, showWarnings = FALSE)
  pandoc_src <- file.path(bundle_dir, "pandoc")
  pandoc_dst <- file.path(home, "pandoc")
  if (dir.exists(pandoc_src) && length(list.files(pandoc_src)) > 0L) {
    dir.create(pandoc_dst, showWarnings = FALSE)
    file.copy(list.files(pandoc_src, full.names = TRUE), pandoc_dst,
              overwrite = TRUE, recursive = TRUE)
    Sys.chmod(list.files(pandoc_dst, full.names = TRUE), "0755")
  }
  record <- read.dcf(file.path(bundle_dir, "BUNDLE"))
  record <- cbind(record, Library = lib, Installed = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  write.dcf(record, file.path(home, "BUNDLE"))

  message("\nomicsDesk ", info$Version %||% "", " is installed.",
          "\n  library: ", lib,
          "\n  folder:  ", home,
          "\n\nNext, in R:  omicsDesk::doctor()  then  omicsDesk::launch()",
          "\n(or double-click the launcher next to this script).")
  invisible(list(lib = lib, installed = pkgs$package, home = home))
}

# ---- command line ---------------------------------------------------------

.script_path <- function() {
  arg <- grep("^--file=", commandArgs(), value = TRUE)
  if (length(arg)) sub("^--file=", "", arg[[1L]]) else ""
}

if (nzchar(.script_path()) && basename(.script_path()) == "INSTALL.R") {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag) {
    i <- match(flag, args)
    if (is.na(i) || i == length(args)) NULL else args[[i + 1L]]
  }
  if (!is.null(get_arg("--home"))) Sys.setenv(OMICSDESK_HOME = get_arg("--home"))
  install_offline_bundle(bundle_dir = dirname(.script_path()),
                         lib = get_arg("--lib"),
                         force = "--force" %in% args,
                         quiet = "--quiet" %in% args)
} else if (interactive()) {
  message("Installer loaded. Now run:  install_offline_bundle(\"<path to the bundle folder>\")")
}
