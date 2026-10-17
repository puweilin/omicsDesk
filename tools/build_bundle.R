#!/usr/bin/env Rscript
#
# Build an omicsDesk bundle: a folder (and zip) that installs omicsCore,
# omicsApp, omicsDesk and their entire dependency closure on a machine
# with no network, for the platform and R minor version this script runs
# under. Cross-platform builds are a CI matrix, not a flag: a bundle for
# Windows is built on Windows, because R's binary package layout and the
# repositories' binary availability are both decided by the running R.
#
#   Rscript tools/build_bundle.R [--omicsapp <dir> | --omicsapp-ref <ref>] [--out <dir>]
#                                [--pandoc <exe>] [--reuse-downloads] [--no-zip]
#
# --omicsapp      checkout of the omicsApp monorepo (default ../omicsApp when it exists)
# --omicsapp-ref  fetch the monorepo from GitHub at this branch, tag or commit
#                 instead (default main when there is no local checkout)
# --out        output directory (default dist/)
# --pandoc     pandoc executable to ship; default: the one rmarkdown finds
# --reuse-downloads  skip pak if the download cache for this target exists
#
# Needs: pak (to resolve and download), the R CMD build toolchain, and
# network. inst/genesets must already be populated (tools/prewarm_genesets.R).
#
# Output layout (see inst/bundle/README.bundle.md for the user's view):
#   <out>/omicsDesk-<ver>-R<minor>-<platform>/
#     BUNDLE, MD5SUMS, README.md, INSTALL.R, START.R, launchers
#     repo/src/contrib/               the three packages + source-only deps
#     repo/bin/<platform>/contrib/<minor>/   binaries (Windows, macOS)
#     pandoc/

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}
has_flag <- function(flag) flag %in% args

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
root <- if (length(script_path)) normalizePath(file.path(dirname(script_path[[1L]]), "..")) else normalizePath(".")

out_dir <- get_arg("--out", file.path(root, "dist"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_dir <- normalizePath(out_dir, mustWork = TRUE)
pandoc_arg <- get_arg("--pandoc", NULL)

if (!requireNamespace("pak", quietly = TRUE)) stop("pak is needed: install.packages('pak')")

# ---- where omicsCore and omicsApp come from -----------------------------------
#
# A local checkout when there is one (the developer's, or CI's), otherwise
# GitHub at a ref. Either way the commit is recorded in BUNDLE, because a
# bundle that cannot say which omicsCore it holds cannot be reproduced.

OMICSAPP_REPO <- "https://github.com/puweilin/omicsApp"

fetch_omicsapp <- function(ref, into) {
  unlink(into, recursive = TRUE)
  dir.create(into, recursive = TRUE)
  tarball <- file.path(into, "omicsApp.tar.gz")
  utils::download.file(sprintf("%s/archive/%s.tar.gz", OMICSAPP_REPO, ref), tarball,
                       mode = "wb", quiet = TRUE)
  top <- unique(sub("/.*$", "", utils::untar(tarball, list = TRUE)))
  top <- top[nzchar(top)][[1L]]
  utils::untar(tarball, exdir = into)
  file.path(into, top)
}

github_sha <- function(ref) {
  tryCatch(jsonlite::fromJSON(sprintf("https://api.github.com/repos/puweilin/omicsApp/commits/%s", ref))$sha,
           error = function(e) "")
}

local_sha <- function(dir) {
  sha <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(dir), "rev-parse", "HEAD"),
                                           stdout = TRUE, stderr = FALSE))[[1L]],
                  error = function(e) "")
  if (!grepl("^[0-9a-f]{40}$", sha)) return("")
  dirty <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(dir), "status", "--porcelain", "--", "packages"),
                                             stdout = TRUE, stderr = FALSE)),
                    error = function(e) character())
  if (length(dirty) > 0L) paste(sha, "(with uncommitted changes)") else sha
}

omicsapp_arg <- get_arg("--omicsapp", NULL)
omicsapp_ref <- get_arg("--omicsapp-ref", NULL)
if (!is.null(omicsapp_arg) && !is.null(omicsapp_ref)) stop("Pass --omicsapp or --omicsapp-ref, not both.")
if (is.null(omicsapp_arg) && is.null(omicsapp_ref)) {
  default_dir <- file.path(root, "..", "omicsApp")
  if (dir.exists(default_dir)) omicsapp_arg <- default_dir else {
    omicsapp_ref <- read.dcf(file.path(root, "DESCRIPTION"))[1L, "Config/omicsDesk/UpstreamRef"]
  }
}
if (!is.null(omicsapp_arg)) {
  omicsapp_dir <- normalizePath(omicsapp_arg, mustWork = FALSE)
  omicsapp_source <- paste0("local checkout ", omicsapp_dir)
  omicsapp_sha <- local_sha(omicsapp_dir)
} else {
  message("Fetching omicsApp@", omicsapp_ref, " from GitHub")
  omicsapp_sha <- github_sha(omicsapp_ref)
  if (!nzchar(omicsapp_sha)) stop("Cannot resolve omicsApp ref: ", omicsapp_ref)
  omicsapp_dir <- fetch_omicsapp(omicsapp_sha, file.path(out_dir, "omicsApp-src"))
  omicsapp_source <- paste0(OMICSAPP_REPO, " @ ", omicsapp_ref)
}
message("  omicsApp from ", omicsapp_source, if (nzchar(omicsapp_sha)) paste0(" (", omicsapp_sha, ")") else "")

pkg_dirs <- c(
  omicsCore = file.path(omicsapp_dir, "packages", "omicsCore"),
  omicsApp  = file.path(omicsapp_dir, "packages", "omicsApp"),
  omicsDesk = root
)
for (nm in names(pkg_dirs)) {
  if (!file.exists(file.path(pkg_dirs[[nm]], "DESCRIPTION"))) {
    stop("No package at ", pkg_dirs[[nm]], " (pass --omicsapp <monorepo checkout>)")
  }
}
if (length(list.files(file.path(root, "inst", "genesets"), pattern = "\\.qs2$")) == 0L) {
  stop("inst/genesets is empty; run tools/prewarm_genesets.R first.")
}
geneset_helpers <- new.env(parent = baseenv())
sys.source(file.path(root, "R", "genesets.R"), envir = geneset_helpers)
expected_genesets <- geneset_helpers$expected_geneset_files()
geneset_dir <- file.path(root, "inst", "genesets")
geneset_manifest <- jsonlite::fromJSON(file.path(geneset_dir, "MANIFEST.json"))$files
if (!setequal(geneset_manifest$file, expected_genesets) ||
    any(!file.exists(file.path(geneset_dir, expected_genesets))) ||
    any(unname(tools::md5sum(file.path(geneset_dir, geneset_manifest$file))) != geneset_manifest$md5)) {
  stop("Bundled gene-set tables are incomplete or differ from MANIFEST.json.")
}

# ---- naming -------------------------------------------------------------------

desc <- read.dcf(file.path(root, "DESCRIPTION"))
version <- unname(desc[1L, "Version"])
r_minor <- paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1L]][[1L]], sep = ".")
is_windows <- .Platform$OS.type == "windows"
is_macos <- identical(Sys.info()[["sysname"]], "Darwin")

platform_tag <- if (is_windows) {
  "windows"
} else if (is_macos) {
  paste0("macos-", if (R.version$arch == "aarch64") "arm64" else "x86_64")
} else {
  distro <- tryCatch({
    os <- read.dcf(textConnection(gsub("=", ": ", readLines("/etc/os-release"))))
    paste0(gsub('"', "", os[1L, "ID"]), "-", gsub('"', "", os[1L, "VERSION_ID"]))
  }, error = function(e) "linux")
  paste0("linux-", distro, "-", R.version$arch)
}

name <- sprintf("omicsDesk-%s-R%s-%s", version, r_minor, platform_tag)
bundle_dir <- file.path(out_dir, name)
if (dir.exists(bundle_dir)) unlink(bundle_dir, recursive = TRUE)
repo_dir <- file.path(bundle_dir, "repo")
src_contrib <- file.path(repo_dir, "src", "contrib")
dir.create(src_contrib, recursive = TRUE)
bin_contrib <- NULL
if (is_windows || is_macos) {
  rel <- sub("^file://X/?", "", contrib.url("file://X", "binary"))
  bin_contrib <- file.path(repo_dir, rel)
  dir.create(bin_contrib, recursive = TRUE)
}
message("Building ", name)

# ---- 1. the three packages, as source tarballs ------------------------------

build_dir <- file.path(out_dir, "build-tmp")
dir.create(build_dir, recursive = TRUE, showWarnings = FALSE)
for (nm in names(pkg_dirs)) {
  message("  R CMD build ", nm)
  r_bin <- file.path(R.home("bin"), if (is_windows) "R.exe" else "R")
  work <- tempfile(paste0(nm, "-"), tmpdir = build_dir)
  dir.create(work)
  input <- pkg_dirs[[nm]]
  if (nm != "omicsDesk") {
    if (!file.copy(input, work, recursive = TRUE)) stop("Could not stage ", nm)
    input <- file.path(work, nm)
    metadata <- read.dcf(file.path(input, "DESCRIPTION"))
    metadata <- cbind(metadata, `Config/omicsDesk/SourceSHA` = omicsapp_sha)
    write.dcf(metadata, file.path(input, "DESCRIPTION"))
  }
  old_wd <- setwd(work)
  status <- system2(r_bin, c("CMD", "build", "--no-build-vignettes", "--no-manual",
                             shQuote(input)),
                    stdout = file.path(build_dir, paste0(nm, ".log")),
                    stderr = file.path(build_dir, paste0(nm, ".log")))
  setwd(old_wd)
  if (!identical(status, 0L)) {
    stop("R CMD build failed for ", nm, "; see ", file.path(build_dir, paste0(nm, ".log")))
  }
  # R CMD build writes into the working directory.
  tarball <- list.files(work, pattern = paste0("^", nm, "_.*\\.tar\\.gz$"), full.names = TRUE)
  if (length(tarball) != 1L) stop("Expected one tarball for ", nm, ", found ", length(tarball))
  if (!file.rename(tarball, file.path(src_contrib, basename(tarball)))) stop("Could not stage ", nm)
  unlink(work, recursive = TRUE)
}

# ---- 2. the dependency closure ----------------------------------------------

# Recommended packages ship with every R installer; a bundle carries them
# only when pak fetched a newer build, and never depends on them being in
# the repository.
base_pkgs <- c("R", rownames(installed.packages(priority = c("base", "recommended"))))
dep_fields <- c("Depends", "Imports", "LinkingTo")
direct <- unlist(lapply(pkg_dirs, function(d) {
  x <- read.dcf(file.path(d, "DESCRIPTION"))
  unlist(lapply(intersect(dep_fields, colnames(x)), function(f) {
    items <- trimws(strsplit(x[1L, f], ",")[[1L]])
    trimws(sub("\\(.*\\)", "", items[nzchar(items)]))
  }))
}), use.names = FALSE)
direct <- setdiff(unique(direct), c(names(pkg_dirs), base_pkgs))
message("  ", length(direct), " direct dependencies; resolving the closure with pak")

downloads <- file.path(out_dir, "downloads", paste0("R", r_minor, "-", platform_tag))
if (has_flag("--reuse-downloads") && dir.exists(downloads) && length(list.files(downloads)) > 0L) {
  message("  reusing ", downloads)
} else {
  unlink(downloads, recursive = TRUE)
  dir.create(downloads, recursive = TRUE)
  res <- pak::pkg_download(direct, dest_dir = downloads, dependencies = NA)
  message("  pak downloaded ", nrow(res), " packages")
}

# pak writes a repository-shaped tree -- bin/<platform>/contrib/<minor>/
# for the running platform's binaries, src/contrib/ for sources -- and
# fetches both for every package. Ship the binary where there is one and
# the source only where there is not: shipping both doubles the bundle.
pkg_of <- function(f) sub("_.*$", "", basename(f))
bin_files <- if (is.null(bin_contrib)) character() else
  list.files(file.path(downloads, "bin"), pattern = "\\.(zip|tgz)$",
             recursive = TRUE, full.names = TRUE)
src_files <- list.files(file.path(downloads, "src", "contrib"),
                        pattern = "\\.tar\\.gz$", full.names = TRUE)
have_bin <- pkg_of(bin_files)
src_only <- src_files[!pkg_of(src_files) %in% have_bin]
for (f in bin_files) file.copy(f, file.path(bin_contrib, basename(f)), overwrite = TRUE)
for (f in src_only) file.copy(f, file.path(src_contrib, basename(f)), overwrite = TRUE)
message("  ", length(bin_files), " binaries, ", length(src_only), " source-only")

# ---- 3. repository indexes ------------------------------------------------

tools::write_PACKAGES(src_contrib, type = "source", verbose = FALSE)
index <- read.dcf(file.path(src_contrib, "PACKAGES"))
src_index <- data.frame(Package = index[, "Package"], Version = index[, "Version"],
                        NeedsCompilation = if ("NeedsCompilation" %in% colnames(index)) index[, "NeedsCompilation"] else NA,
                        stringsAsFactors = FALSE)
bin_index <- NULL
if (!is.null(bin_contrib) && length(list.files(bin_contrib, pattern = "\\.(zip|tgz)$")) > 0L) {
  tools::write_PACKAGES(bin_contrib, type = if (is_windows) "win.binary" else "mac.binary", verbose = FALSE)
  bi <- read.dcf(file.path(bin_contrib, "PACKAGES"))
  bin_index <- data.frame(Package = bi[, "Package"], Version = bi[, "Version"], stringsAsFactors = FALSE)
}

all_pkgs <- rbind(
  if (!is.null(bin_index)) bin_index[, c("Package", "Version")],
  src_index[, c("Package", "Version")]
)
all_pkgs <- all_pkgs[!duplicated(all_pkgs$Package), , drop = FALSE]
all_pkgs <- all_pkgs[order(all_pkgs$Package), , drop = FALSE]

source_only <- character()
if (!is.null(bin_index)) {
  so <- src_index[!src_index$Package %in% bin_index$Package & !src_index$Package %in% names(pkg_dirs), , drop = FALSE]
  source_only <- so$Package[!is.na(so$NeedsCompilation) & so$NeedsCompilation == "yes"]
}

# Every package the closure needs must be in the repository, or the
# installer fails on the user's machine instead of here.
all_indexes <- list(index, if (!is.null(bin_index)) bi)
all_indexes <- Filter(Negate(is.null), all_indexes)
columns <- unique(unlist(lapply(all_indexes, colnames)))
db <- do.call(rbind, lapply(all_indexes, function(x) {
  out <- matrix(NA_character_, nrow(x), length(columns), dimnames = list(NULL, columns))
  out[, colnames(x)] <- x
  out
}))
rownames(db) <- db[, "Package"]
closure <- unique(unlist(tools::package_dependencies(names(pkg_dirs), db = db,
                                                    which = dep_fields, recursive = TRUE)))
missing <- setdiff(c(direct, closure), c(all_pkgs$Package, base_pkgs))
if (length(missing) > 0L) stop("Not in the repository: ", paste(missing, collapse = ", "))

# Reused downloads can be complete by name while holding binaries too old for
# a newer source package. Check version constraints without a network query.
versions <- stats::setNames(all_pkgs$Version, all_pkgs$Package)
base_db <- installed.packages(priority = c("base", "recommended"))
versions <- c(versions, stats::setNames(base_db[, "Version"], base_db[, "Package"]),
              R = as.character(getRversion()))
versions <- versions[!duplicated(names(versions))]
for (i in seq_len(nrow(db))) {
  for (field in intersect(dep_fields, colnames(db))) {
    if (is.na(db[i, field])) next
    specs <- trimws(strsplit(db[i, field], ",", fixed = TRUE)[[1L]])
    for (spec in specs) {
      parsed <- regmatches(spec, regexec("^([A-Za-z][A-Za-z0-9.]*)\\s*\\((>=|<=|==|!=|>|<)\\s*([^()[:space:]]+)\\)$", spec))[[1L]]
      if (length(parsed) != 4L) next
      available <- unname(versions[parsed[[2L]]])
      if (is.na(available)) stop("Missing dependency ", spec, " for ", db[i, "Package"])
      cmp <- utils::compareVersion(available, parsed[[4L]])
      valid <- switch(parsed[[3L]], `>=` = cmp >= 0, `<=` = cmp <= 0,
                       `==` = cmp == 0, `!=` = cmp != 0, `>` = cmp > 0, `<` = cmp < 0)
      if (!valid) stop("Dependency version mismatch: ", db[i, "Package"], " needs ", spec,
                       "; bundle has ", available)
    }
  }
}

# ---- 4. pandoc ---------------------------------------------------------------

pandoc_exe <- pandoc_arg
if (is.null(pandoc_exe) && requireNamespace("rmarkdown", quietly = TRUE) && rmarkdown::pandoc_available()) {
  pandoc_exe <- rmarkdown::pandoc_exec()
}
if (is.null(pandoc_exe) || !nzchar(pandoc_exe)) pandoc_exe <- unname(Sys.which("pandoc"))
pandoc_version <- ""
if (nzchar(pandoc_exe) && file.exists(pandoc_exe)) {
  if (grepl("^/opt/homebrew|^/usr/local/Cellar", pandoc_exe)) {
    message("  ! ", pandoc_exe, " is a Homebrew build, which links against Homebrew libraries;",
            " pass --pandoc <official release binary> for a bundle that runs elsewhere.")
  }
  dir.create(file.path(bundle_dir, "pandoc"))
  file.copy(pandoc_exe, file.path(bundle_dir, "pandoc", basename(pandoc_exe)))
  Sys.chmod(file.path(bundle_dir, "pandoc", basename(pandoc_exe)), "0755")
  pandoc_version <- tryCatch(sub("^pandoc(\\.exe)?\\s+", "", system2(pandoc_exe, "--version", stdout = TRUE)[[1L]]),
                             error = function(e) "unknown")
  message("  pandoc ", pandoc_version, " from ", pandoc_exe)
} else {
  message("  ! no pandoc found; HTML reports will need one installed separately")
}

# ---- 5. installer, launchers, records -------------------------------------

bundle_src <- file.path(root, "inst", "bundle")
for (f in c("INSTALL.R", "START.R", "VERIFY.R", "omicsDesk.bat", "omicsDesk.command")) {
  file.copy(file.path(bundle_src, f), file.path(bundle_dir, f), overwrite = TRUE)
}
Sys.chmod(file.path(bundle_dir, "omicsDesk.command"), "0755")

git_sha <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(root), "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE))[[1L]],
                    error = function(e) NA_character_)
genesets <- tryCatch(jsonlite::fromJSON(file.path(root, "inst", "genesets", "MANIFEST.json")), error = function(e) NULL)
record <- rbind(c(
  Bundle = "omicsDesk",
  BundleFormat = "2",
  Version = version,
  Built = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
  Platform = R.version$platform,
  OS = platform_tag,
  RVersion = paste(R.version$major, R.version$minor, sep = "."),
  RMinor = r_minor,
  BiocVersion = if (requireNamespace("BiocManager", quietly = TRUE)) as.character(BiocManager::version()) else "",
  GitSha = if (is.na(git_sha) || !grepl("^[0-9a-f]{40}$", git_sha)) "" else git_sha,
  OmicsAppSource = omicsapp_source,
  OmicsAppSha = omicsapp_sha,
  Pandoc = pandoc_version,
  Genesets = if (is.null(genesets)) "" else sprintf("MSigDB %s via msigdbr %s, built %s", genesets$msigdb_release, genesets$msigdbr_version, genesets$built_at),
  Packages = paste(sprintf("%s (%s)", all_pkgs$Package, all_pkgs$Version), collapse = ", "),
  SourceOnly = paste(source_only, collapse = ", ")
))
write.dcf(record, file.path(bundle_dir, "BUNDLE"), width = 80)

readme <- readLines(file.path(bundle_src, "README.bundle.md"))
fill <- c(
  VERSION = version, PLATFORM = platform_tag, RMINOR = r_minor,
  BUILT = unname(record[1L, "Built"]), PACKAGE_COUNT = as.character(nrow(all_pkgs)),
  PANDOC = if (nzchar(pandoc_version)) paste("pandoc", pandoc_version) else "not included",
  SOURCE_ONLY_NOTE = if (length(source_only)) paste0(
    "Note: no binary was available for ", paste(source_only, collapse = ", "),
    "; installing them needs a compiler (Rtools on Windows, Xcode command line tools on macOS).")
    else ""
)
for (k in names(fill)) readme <- gsub(paste0("{{", k, "}}"), fill[[k]], readme, fixed = TRUE)
writeLines(readme, file.path(bundle_dir, "README.md"))

all_files <- list.files(bundle_dir, recursive = TRUE, full.names = TRUE)
sums <- tools::md5sum(all_files)
writeLines(sprintf("%s  %s", sums, substring(names(sums), nchar(bundle_dir) + 2L)),
           file.path(bundle_dir, "MD5SUMS"))

# ---- 6. zip --------------------------------------------------------------------

size_mb <- sum(file.size(all_files)) / 1024^2
message(sprintf("  %d packages, %.0f MB unpacked", nrow(all_pkgs), size_mb))
if (!has_flag("--no-zip")) {
  zip_path <- file.path(out_dir, paste0(name, ".zip"))
  if (file.exists(zip_path)) unlink(zip_path)
  old <- setwd(out_dir)
  if (nzchar(Sys.which("zip"))) {
    utils::zip(basename(zip_path), name, flags = "-r9Xq")
  } else if (requireNamespace("zip", quietly = TRUE)) {
    zip::zip(basename(zip_path), name, mode = "mirror")
  } else {
    stop("No zip tool found. Install zip or pass --no-zip.")
  }
  setwd(old)
  if (!file.exists(zip_path)) stop("ZIP creation failed: ", zip_path)
  message(sprintf("  %s (%.0f MB)", zip_path, file.size(zip_path) / 1024^2))
}
message("Done: ", bundle_dir)
