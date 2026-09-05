# Where omicsDesk keeps a user's things.
#
# One visible folder, `~/omicsDesk` by default (`Documents/omicsDesk` on
# Windows, because that is where R's `~` points there). Projects the user
# saves, the gene-set cache the app reads, and the pandoc the bundle
# installed all live under it, so "where are my files" has one answer and
# uninstalling is deleting one folder.
#
# `OMICSDESK_HOME` moves the folder. omicsApp's own knobs
# (`OMICSAPP_DATA_DIR`, `OMICSCORE_GENESET_CACHE`) are derived from these
# paths by launch(), and left alone when the caller set them first.

#' The omicsDesk folder
#'
#' Everything a user accumulates lives under one directory:
#' `projects/` for saved `.omp` files and the autosave, `genesets/` for the
#' MSigDB tables the app reads, `pandoc/` for the report renderer the
#' bundle installed. The default is `~/omicsDesk`; set `OMICSDESK_HOME` to
#' move it.
#'
#' @return `desk_home()` returns the folder path; `desk_paths()` a named
#'   list of the folder and its sub-directories. Neither creates anything.
#' @export
#' @examples
#' desk_home()
#' desk_paths()$projects
desk_home <- function() {
  dir <- Sys.getenv("OMICSDESK_HOME", "")
  if (!nzchar(dir)) dir <- path.expand("~/omicsDesk")
  dir
}

#' @rdname desk_home
#' @export
desk_paths <- function() {
  home <- desk_home()
  list(
    home     = home,
    projects = file.path(home, "projects"),
    genesets = file.path(home, "genesets"),
    pandoc   = file.path(home, "pandoc"),
    bundle   = file.path(home, "BUNDLE")
  )
}

desk_data_dir    <- function() desk_paths()$projects
desk_geneset_dir <- function() desk_paths()$genesets
desk_pandoc_dir  <- function() desk_paths()$pandoc
desk_bundle_file <- function() desk_paths()$bundle

ensure_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  invisible(path)
}

# The tables shipped inside the installed package. Empty string when the
# package was built without them (a source checkout before
# tools/prewarm_genesets.R has run).
bundled_geneset_dir <- function() {
  system.file("genesets", package = "omicsDesk")
}

# A pandoc executable inside `dir`, or "" when there is none.
pandoc_in <- function(dir) {
  if (!nzchar(dir) || !dir.exists(dir)) return("")
  exe <- if (.Platform$OS.type == "windows") "pandoc.exe" else "pandoc"
  path <- file.path(dir, exe)
  if (file.exists(path)) path else ""
}
