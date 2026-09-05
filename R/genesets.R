# The gene-set cache, offline.
#
# omicsCore reads MSigDB tables from a directory of qs2 files when
# OMICSCORE_GENESET_CACHE points at one, and falls back to msigdbr when it
# does not. On current msigdbr the fallback is a download -- 34 MB from
# Zenodo with a five-minute timeout -- so on an offline machine the cache
# is not an optimisation, it is the only source there is. omicsDesk ships
# the tables (inst/genesets, built by tools/prewarm_genesets.R) and copies
# them into the user's folder before the app starts, because an installed
# package directory is not somewhere omicsCore should write: a KEGG
# refresh or an import must land in a folder the user owns.
#
# The copy keeps a MANIFEST.json beside the files recording the md5 of
# each file as it was placed. A file whose md5 no longer matches that
# record was changed by the user -- an import, a live KEGG refresh -- and
# is never overwritten by a newer bundle. A file with no record at all is
# treated the same way; the user put it there.

DESK_GENESET_DATABASES <- c("hallmark", "kegg", "reactome", "wikipathways",
                            "go_bp", "go_mf", "go_cc")
DESK_GENESET_ORGANISMS <- c(Hs = "Homo sapiens", Mm = "Mus musculus")

GENESET_FILE_PATTERN <- "^([a-z_]+)__([A-Za-z_]+)\\.qs2$"

organism_token <- function(organism) gsub("[^A-Za-z0-9]+", "_", organism)

geneset_file_name <- function(database, organism) {
  sprintf("%s__%s.qs2", database, organism_token(organism))
}

expected_geneset_files <- function() {
  as.vector(outer(DESK_GENESET_DATABASES, DESK_GENESET_ORGANISMS,
                  geneset_file_name))
}

# ---- manifest -----------------------------------------------------------

read_manifest <- function(dir) {
  path <- file.path(dir, "MANIFEST.json")
  if (!file.exists(path)) return(NULL)
  tryCatch(jsonlite::fromJSON(path, simplifyVector = TRUE),
           error = function(e) NULL)
}

write_manifest <- function(dir, manifest) {
  path <- file.path(dir, "MANIFEST.json")
  # Stage-and-rename, as omicsCore does for the tables themselves.
  tmp <- tempfile(pattern = "MANIFEST.", tmpdir = dir, fileext = ".tmp")
  jsonlite::write_json(manifest, tmp, auto_unbox = TRUE, pretty = TRUE,
                       dataframe = "rows", null = "null", na = "null")
  file.rename(tmp, path)
  invisible(path)
}

manifest_files <- function(manifest) {
  files <- manifest$files
  if (is.null(files) || length(files) == 0L) {
    return(data.frame(file = character(), md5 = character(),
                      origin = character(), stringsAsFactors = FALSE))
  }
  as.data.frame(files, stringsAsFactors = FALSE)
}

recorded_md5 <- function(manifest) {
  files <- manifest_files(manifest)
  stats::setNames(as.character(files$md5), files$file)
}

md5_of <- function(path) unname(tools::md5sum(path))

# What a table says about itself. `ok` is FALSE for anything omicsCore's
# read_geneset_cache() would reject, using the same rule: a data frame
# with rows, a gs_name column, and a gene column under either name.
geneset_table_info <- function(path) {
  df <- tryCatch(qs2::qs_read(path), error = function(e) NULL)
  ok <- is.data.frame(df) && nrow(df) > 0L &&
    "gs_name" %in% colnames(df) &&
    any(c("gene_symbol", "human_gene_symbol") %in% colnames(df))
  list(
    ok = ok,
    n_sets = if (ok) length(unique(df$gs_name)) else NA_integer_,
    gs_source = if (ok && "gs_source" %in% colnames(df))
      as.character(df$gs_source[[1L]]) else NA_character_
  )
}

is_live_kegg_source <- function(gs_source) {
  !is.na(gs_source) && startsWith(gs_source, "KEGG REST")
}

# ---- sync from the bundled copy -------------------------------------------

#' Copy the shipped gene-set tables into the user's folder
#'
#' Called by [launch()] and [doctor()]; there is rarely a reason to call
#' it directly. Copies every table under `inst/genesets` of the installed
#' package into `desk_paths()$genesets`, skipping files that are already
#' identical and never overwriting a file the user has changed since it
#' was placed (an import, a live KEGG refresh).
#'
#' @param target Destination directory. Defaults to the desk folder.
#' @param source Directory of shipped tables. Defaults to the package's.
#' @param quiet If `FALSE`, say what was copied and what was kept.
#'
#' @return Invisibly, a list with `copied`, `kept` (user-changed files the
#'   bundle would have replaced) and `current` (already up to date).
#' @export
sync_geneset_cache <- function(target = desk_geneset_dir(),
                               source = bundled_geneset_dir(),
                               quiet = TRUE) {
  out <- list(copied = character(), kept = character(), current = character())
  if (!nzchar(source) || !dir.exists(source)) return(invisible(out))
  files <- list.files(source, pattern = GENESET_FILE_PATTERN)
  if (length(files) == 0L) return(invisible(out))

  ensure_dir(target)
  src_manifest <- read_manifest(source)
  tgt_manifest <- read_manifest(target)
  recorded <- recorded_md5(tgt_manifest)
  rows <- manifest_files(tgt_manifest)
  src_rows <- manifest_files(src_manifest)

  for (f in files) {
    src <- file.path(source, f)
    dst <- file.path(target, f)
    src_md5 <- md5_of(src)
    if (file.exists(dst)) {
      dst_md5 <- md5_of(dst)
      if (identical(dst_md5, src_md5)) {
        out$current <- c(out$current, f)
        next
      }
      if (is.na(recorded[f]) || !identical(dst_md5, unname(recorded[f]))) {
        out$kept <- c(out$kept, f)
        next
      }
    }
    if (!file.copy(src, dst, overwrite = TRUE)) {
      stop("Could not copy ", f, " into ", target, call. = FALSE)
    }
    out$copied <- c(out$copied, f)
    src_row <- src_rows[src_rows$file == f, , drop = FALSE]
    rows <- rows[rows$file != f, , drop = FALSE]
    rows <- rbind_rows(rows, data.frame(
      file = f, md5 = src_md5, origin = "bundle",
      placed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      n_sets = if (nrow(src_row)) as.integer(src_row$n_sets[[1L]]) else NA_integer_,
      gs_source = if (nrow(src_row) && "gs_source" %in% colnames(src_row))
        as.character(src_row$gs_source[[1L]]) else NA_character_,
      stringsAsFactors = FALSE
    ))
  }

  if (length(out$copied) > 0L) {
    write_manifest(target, list(
      source = src_manifest[setdiff(names(src_manifest), "files")],
      files = rows
    ))
  }
  if (!quiet) {
    if (length(out$copied)) message("Copied ", length(out$copied), " gene-set table(s) into ", target)
    if (length(out$kept)) message("Kept your version of: ", paste(out$kept, collapse = ", "))
  }
  invisible(out)
}

# rbind for data frames that may disagree on columns; missing ones fill NA.
rbind_rows <- function(a, b) {
  if (nrow(a) == 0L) return(b)
  for (col in setdiff(colnames(b), colnames(a))) a[[col]] <- NA
  for (col in setdiff(colnames(a), colnames(b))) b[[col]] <- NA
  rbind(a, b[colnames(a)])
}

# ---- status ---------------------------------------------------------------

#' The gene-set tables the app will read
#'
#' One row per database and organism, as omicsCore sees the desk folder:
#' whether the table is present and readable, how many sets it holds,
#' where it came from, and how old the file is.
#'
#' @return A `data.frame` with columns `organism`, `database`, `cached`,
#'   `n_sets`, `source`, `cached_at`, `age_days`.
#' @export
#' @family genesets
geneset_status <- function() {
  sync_geneset_cache(quiet = TRUE)
  with_envvar(c(OMICSCORE_GENESET_CACHE = desk_geneset_dir()), {
    rows <- lapply(names(DESK_GENESET_ORGANISMS), function(code) {
      st <- omicsCore::geneset_cache_status(DESK_GENESET_DATABASES, organism = code)
      cbind(organism = unname(DESK_GENESET_ORGANISMS[code]), st,
            stringsAsFactors = FALSE)
    })
    do.call(rbind, rows)
  })
}

# The vintage line printed by launch() and doctor().
geneset_vintage <- function(dir = desk_geneset_dir()) {
  m <- read_manifest(dir)
  src <- m$source %||% m
  if (is.null(src$msigdb_release)) return(NA_character_)
  sprintf("MSigDB %s (msigdbr %s, built %s)",
          src$msigdb_release, src$msigdbr_version %||% "?",
          substr(src$built_at %||% "?", 1L, 10L))
}

# ---- import / export ------------------------------------------------------

#' Bring gene-set tables into the desk folder
#'
#' The way a refreshed table reaches an offline machine: a colleague with
#' network access runs `omicsCore::refresh_geneset_cache("kegg")` and
#' [export_geneset_cache()], and the files travel on a USB stick. Accepts
#' one `.qs2` file or a directory of them. File names must follow
#' omicsCore's `<database>__<Organism>.qs2` convention, and each table
#' must have the columns omicsCore reads; anything else is refused before
#' any file is copied.
#'
#' Tables sourced from the live KEGG REST API are for local use only,
#' under KEGG's licence; the function says so when it imports one.
#'
#' @param path A `.qs2` file or a directory containing them.
#' @param quiet If `FALSE`, report each table imported.
#'
#' @return A `data.frame` with one row per imported file: `file`,
#'   `database`, `organism`, `n_sets`, `gs_source`. Restart the app (or
#'   the R session) afterwards: omicsCore memoises tables it has already
#'   read.
#' @export
#' @family genesets
import_geneset_cache <- function(path, quiet = FALSE) {
  if (!is.character(path) || length(path) != 1L || !file.exists(path)) {
    stop("`path` must be an existing .qs2 file or directory.", call. = FALSE)
  }
  files <- if (dir.exists(path)) {
    list.files(path, pattern = "\\.qs2$", full.names = TRUE)
  } else {
    path
  }
  if (length(files) == 0L) stop("No .qs2 files found in ", path, call. = FALSE)

  # Validate everything first, so a bad file in a directory does not leave
  # the folder half-updated.
  checked <- lapply(files, function(f) {
    name <- basename(f)
    m <- regmatches(name, regexec(GENESET_FILE_PATTERN, name))[[1L]]
    if (length(m) != 3L) {
      stop("Not a gene-set cache file name: ", name,
           " (expected <database>__<Organism>.qs2)", call. = FALSE)
    }
    database <- m[[2L]]
    organism <- names(which(organism_token(DESK_GENESET_ORGANISMS) == m[[3L]]))
    if (!database %in% DESK_GENESET_DATABASES || length(organism) != 1L) {
      stop("Unsupported database or organism in file name: ", name,
           call. = FALSE)
    }
    info <- geneset_table_info(f)
    if (!info$ok) {
      stop("Not a readable gene-set table: ", name,
           " (needs a gs_name column and a gene_symbol column)", call. = FALSE)
    }
    data.frame(file = name, database = database,
               organism = unname(DESK_GENESET_ORGANISMS[organism]),
               n_sets = info$n_sets, gs_source = info$gs_source,
               stringsAsFactors = FALSE)
  })
  imported <- do.call(rbind, checked)

  target <- ensure_dir(desk_geneset_dir())
  manifest <- read_manifest(target) %||% list()
  rows <- manifest_files(manifest)
  for (i in seq_along(files)) {
    dst <- file.path(target, imported$file[[i]])
    tmp <- tempfile(pattern = paste0(imported$file[[i]], "."), tmpdir = target,
                    fileext = ".tmp")
    file.copy(files[[i]], tmp, overwrite = TRUE)
    file.rename(tmp, dst)
    rows <- rows[rows$file != imported$file[[i]], , drop = FALSE]
    rows <- rbind_rows(rows, data.frame(
      file = imported$file[[i]], md5 = md5_of(dst), origin = "import",
      placed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      n_sets = imported$n_sets[[i]], gs_source = imported$gs_source[[i]],
      stringsAsFactors = FALSE
    ))
  }
  manifest$files <- rows
  write_manifest(target, manifest)

  if (!quiet) {
    for (i in seq_len(nrow(imported))) {
      message("Imported ", imported$file[[i]], ": ", imported$n_sets[[i]],
              " gene sets (", imported$gs_source[[i]] %||% "no provenance", ")")
    }
    if (any(vapply(imported$gs_source, is_live_kegg_source, logical(1)))) {
      message("Note: tables from the KEGG REST API are for local use only ",
              "and must not be redistributed.")
    }
  }
  invisible(imported)
}

#' Copy the desk folder's gene-set tables somewhere
#'
#' The other half of [import_geneset_cache()]. Copies every table (and
#' the manifest) into `dest`, which is created if needed. Tables fetched
#' live from KEGG are skipped unless `include_kegg_live = TRUE`, because
#' KEGG's licence forbids passing them on; the flag is for moving your own
#' cache between your own machines.
#'
#' @param dest Destination directory.
#' @param include_kegg_live Copy live-KEGG tables too. Default `FALSE`.
#'
#' @return Invisibly, the paths written.
#' @export
#' @family genesets
export_geneset_cache <- function(dest, include_kegg_live = FALSE) {
  src <- desk_geneset_dir()
  files <- list.files(src, pattern = GENESET_FILE_PATTERN, full.names = TRUE)
  if (length(files) == 0L) {
    stop("No gene-set tables in ", src, "; run sync_geneset_cache() first.",
         call. = FALSE)
  }
  ensure_dir(dest)
  written <- character()
  skipped <- character()
  for (f in files) {
    info <- geneset_table_info(f)
    if (is_live_kegg_source(info$gs_source) && !isTRUE(include_kegg_live)) {
      skipped <- c(skipped, basename(f))
      next
    }
    out <- file.path(dest, basename(f))
    file.copy(f, out, overwrite = TRUE)
    written <- c(written, out)
  }
  if (file.exists(file.path(src, "MANIFEST.json"))) {
    file.copy(file.path(src, "MANIFEST.json"), file.path(dest, "MANIFEST.json"),
              overwrite = TRUE)
  }
  if (length(skipped)) {
    message("Skipped live-KEGG table(s), which KEGG's licence does not allow ",
            "to be redistributed: ", paste(skipped, collapse = ", "),
            " (include_kegg_live = TRUE to copy them between your own machines).")
  }
  invisible(written)
}
