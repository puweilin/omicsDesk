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
  # utils handles a local file repository as a literal filesystem path.
  # Percent-encoding it makes available.packages() look for literal %20.
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
  d <- read.dcf(path)
  required <- c("Bundle", "Version", "RMinor", "Platform", "Packages")
  if (nrow(d) != 1L || !all(required %in% colnames(d)) ||
      anyNA(d[1L, required]) || !identical(unname(d[1L, "Bundle"]), "omicsDesk")) {
    stop("Invalid BUNDLE record in ", bundle_dir, call. = FALSE)
  }
  as.list(d[1L, ])
}

verify_bundle_integrity <- function(bundle_dir, required = FALSE) {
  manifest <- file.path(bundle_dir, "MD5SUMS")
  if (!file.exists(manifest)) {
    if (required) stop("Missing MD5SUMS in bundle.", call. = FALSE)
    return(invisible(TRUE))
  }
  lines <- readLines(manifest, warn = FALSE)
  if (!length(lines) || any(!grepl("^[0-9a-fA-F]{32}  .+$", lines))) {
    stop("Invalid MD5SUMS in bundle.", call. = FALSE)
  }
  expected <- tolower(substr(lines, 1L, 32L))
  paths <- substring(lines, 35L)
  if (anyDuplicated(paths) || any(grepl("(^[/\\\\]|^[A-Za-z]:|(^|[/\\\\])\\.\\.([/\\\\]|$))", paths))) {
    stop("Unsafe or duplicate paths in MD5SUMS.", call. = FALSE)
  }
  files <- file.path(bundle_dir, paths)
  resolved <- normalizePath(files, winslash = "/", mustWork = FALSE)
  prefix <- paste0(normalizePath(bundle_dir, winslash = "/"), "/")
  if (any(!startsWith(resolved, prefix)) || any(!file.exists(files)) || any(dir.exists(files))) {
    stop("Missing or unsafe files in bundle MD5SUMS.", call. = FALSE)
  }
  actual <- unname(tools::md5sum(files))
  bad <- paths[is.na(actual) | actual != expected]
  if (length(bad)) stop("Bundle checksum mismatch: ", paste(bad, collapse = ", "), call. = FALSE)
  invisible(TRUE)
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
  for (name in c("force", "quiet")) {
    value <- get(name)
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      stop("`", name, "` must be TRUE or FALSE.", call. = FALSE)
    }
  }
  bundle_dir <- normalizePath(bundle_dir, winslash = "/", mustWork = TRUE)
  info <- read_bundle_info(bundle_dir)
  verify_bundle_integrity(bundle_dir, required = identical(info$BundleFormat, "2"))

  if (!identical(info$Platform, R.version$platform)) {
    stop("This bundle is for ", info$Platform, "; this R uses ", R.version$platform,
         ". Use a bundle for this platform.", call. = FALSE)
  }

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
  if (!is.character(lib) || length(lib) != 1L || is.na(lib) || !nzchar(lib)) {
    stop("`lib` must be a non-empty path.", call. = FALSE)
  }
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
  # Development releases can share a version number while carrying different
  # code. Always replace the three application packages when upgrading.
  todo <- unique(c(todo, intersect(pkgs$package, c("omicsCore", "omicsApp", "omicsDesk"))))

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
  cores <- parallel::detectCores()
  ncpus <- if (is.na(cores)) 1L else max(1L, min(2L, cores - 1L))

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
  target <- utils::installed.packages(lib.loc = lib)
  anywhere <- rownames(utils::installed.packages(lib.loc = .libPaths()))
  failed <- todo[vapply(todo, function(p) {
    if (!p %in% rownames(target)) return(TRUE)
    version <- pkgs$version[match(p, pkgs$package)]
    !is.na(version) && package_version(target[p, "Version"]) < package_version(version)
  }, logical(1))]
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
  # Folding a long path at a space writes a newline into the value read
  # by START.R, so a valid custom library would disappear on restart.
  write.dcf(record, file.path(home, "BUNDLE"), keep.white = "Library")

  message("\nomicsDesk ", info$Version %||% "", " is installed.",
          "\n  library: ", lib,
          "\n  folder:  ", home,
          "\n\nRestart R after an upgrade. Then run omicsDesk::doctor() and omicsDesk::launch().",
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
