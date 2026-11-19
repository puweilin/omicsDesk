#' Check that this machine can run omicsDesk
#'
#' One row per thing the app needs, with what was found and, when it is
#' missing, what to do about it. Meant to be the first thing run after
#' installing from a bundle, and the first thing asked for when something
#' does not work.
#'
#' @param workers Also start one background worker and confirm it sees the
#'   same library. Costs a few seconds; set `FALSE` to skip.
#' @param quiet Return the table without printing it.
#'
#' @return A `data.frame` of class `desk_doctor` with columns `check`,
#'   `ok`, `required`, `detail`, `fix`. Rows with `required = FALSE`
#'   (optional PDF support or unrecorded source provenance) are informational.
#' @export
#' @examples
#' \dontrun{
#' doctor()
#' }
doctor <- function(workers = TRUE, quiet = FALSE) {
  assert_flag(workers, "workers")
  assert_flag(quiet, "quiet")
  rows <- list()
  add <- function(check, ok, detail = "", fix = "", required = TRUE) {
    rows[[length(rows) + 1L]] <<- data.frame(
      check = check, ok = isTRUE(ok), required = required,
      detail = detail, fix = fix, stringsAsFactors = FALSE)
  }

  # ---- R itself ---------------------------------------------------------
  bundle <- read_bundle_record()
  minor <- r_minor_version()
  if (!is.null(bundle) && !is.na(bundle[["RMinor"]]) &&
      !identical(bundle[["RMinor"]], minor)) {
    add("R version", FALSE,
        sprintf("%s, but the installed bundle was built for R %s",
                R.version.string, bundle[["RMinor"]]),
        sprintf("install R %s.x, or a bundle built for R %s", bundle[["RMinor"]], minor))
  } else {
    add("R version", getRversion() >= "4.2", R.version.string,
        "omicsDesk needs R 4.2 or newer")
  }

  # ---- packages ---------------------------------------------------------
  for (group in names(DESK_BACKENDS)) {
    pkgs <- DESK_BACKENDS[[group]]
    present <- vapply(pkgs, has_pkg, logical(1))
    detail <- if (all(present)) {
      paste(sprintf("%s %s", pkgs, vapply(pkgs, pkg_version_or_na, character(1))),
            collapse = ", ")
    } else {
      paste("missing:", paste(pkgs[!present], collapse = ", "))
    }
    add(paste0("packages: ", group), all(present), detail,
        "run the bundle's INSTALL.R again, or omicsDesk::install_offline(<bundle>)")
  }

  versions <- vapply(c("omicsDesk", "omicsCore", "omicsApp"), pkg_version_or_na, character(1))
  add("version baseline", !anyNA(versions) && length(unique(versions)) == 1L,
      paste(names(versions), versions, collapse = "; "),
      "install all three application packages from the same bundle and restart R")
  source <- vapply(c("omicsCore", "omicsApp"), package_source_sha, character(1))
  ref <- utils::packageDescription("omicsDesk", fields = "Config/omicsDesk/UpstreamRef")
  if (!is.null(bundle$OmicsAppSha) && nzchar(bundle$OmicsAppSha)) ref <- bundle$OmicsAppSha
  ref <- gsub("[[:space:]]+", " ", trimws(ref))
  recorded <- all(!is.na(source))
  add("upstream source", recorded && all(source == ref),
      paste(names(source), ifelse(is.na(source), "unrecorded", source), collapse = "; "),
      "reinstall this bundle and restart R to verify the exact shared source revision",
      required = recorded || !is.null(bundle$OmicsAppSha))

  # ---- gene sets --------------------------------------------------------
  sync <- tryCatch(sync_geneset_cache(quiet = TRUE), error = function(e) NULL)
  status <- tryCatch(geneset_status(), error = function(e) NULL)
  if (is.null(status)) {
    add("gene sets", FALSE, "could not read the desk folder's gene-set tables",
        "reinstall omicsDesk, or import_geneset_cache() a copy from another machine")
  } else {
    n_ok <- sum(status$cached)
    detail <- sprintf("%d of %d tables readable in %s", n_ok, nrow(status),
                      desk_geneset_dir())
    vintage <- geneset_vintage()
    if (!is.na(vintage)) detail <- paste0(detail, "; ", vintage)
    if (!is.null(sync) && length(sync$kept)) {
      detail <- paste0(detail, "; your own version kept for: ",
                       paste(sync$kept, collapse = ", "))
    }
    add("gene sets", n_ok == nrow(status), detail,
        "import_geneset_cache() the missing tables, or reinstall omicsDesk")
  }

  # ---- reports ----------------------------------------------------------
  pandoc_env <- desk_pandoc_for_env()
  pandoc <- with_envvar(
    if (nzchar(pandoc_env)) c(RSTUDIO_PANDOC = pandoc_env) else character(),
    {
      refresh_pandoc_lookup()
      if (has_pkg("rmarkdown") && rmarkdown::pandoc_available()) {
        list(ok = TRUE, detail = paste("pandoc",
             as.character(rmarkdown::pandoc_version()), "at",
             rmarkdown::pandoc_exec()))
      } else {
        list(ok = FALSE, detail = "pandoc not found; HTML reports are unavailable")
      }
    })
  refresh_pandoc_lookup()
  add("HTML reports", pandoc$ok, pandoc$detail,
      sprintf("copy the bundle's pandoc/ folder to %s", desk_pandoc_dir()))

  latex <- unname(Sys.which("pdflatex"))
  add("PDF reports", nzchar(latex),
      if (nzchar(latex)) latex else "pdflatex not found; use the HTML report",
      "install LaTeX, or print the HTML report to PDF from the browser",
      required = FALSE)

  # ---- data folder --------------------------------------------------------
  data_dir <- path.expand(env_or("OMICSAPP_DATA_DIR", desk_data_dir()))
  writable <- tryCatch({
    ensure_dir(data_dir)
    probe <- tempfile(pattern = ".doctor-", tmpdir = data_dir)
    writeLines("ok", probe)
    unlink(probe)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE)
  add("projects folder", writable, data_dir,
      "choose a writable folder with OMICSDESK_HOME or launch(data_dir = ...)")

  # ---- background worker ----------------------------------------------
  if (isTRUE(workers)) {
    w <- tryCatch(check_worker(), error = function(e) list(ok = FALSE,
                  detail = conditionMessage(e)))
    add("background worker", w$ok, w$detail,
        "analyses will still run, in the foreground; check that Rscript is on the PATH")
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  class(out) <- c("desk_doctor", class(out))
  if (!quiet) print(out)
  invisible(out)
}

package_source_sha <- function(pkg) {
  desc <- suppressWarnings(utils::packageDescription(pkg))
  if (!is.list(desc)) return(NA_character_)
  value <- desc[["Config/omicsDesk/SourceSHA"]] %||% desc[["RemoteSha"]]
  if (is.null(value) || length(value) != 1L || is.na(value)) return(NA_character_)
  gsub("[[:space:]]+", " ", trimws(value))
}

check_worker <- function() {
  previous <- future::plan(future::multisession, workers = I(1L))
  on.exit(future::plan(previous), add = TRUE)
  parent_pid <- Sys.getpid()
  libs <- .libPaths()
  seen <- future::value(future::future({
    list(pid = Sys.getpid(), lib = .libPaths()[[1L]],
         core = requireNamespace("omicsCore", quietly = TRUE),
         app = requireNamespace("omicsApp", quietly = TRUE))
  }, seed = TRUE))
  separate <- !identical(seen$pid, parent_pid)
  same_lib <- identical(seen$lib, libs[[1L]])
  if (isTRUE(seen$core) && isTRUE(seen$app) && separate && same_lib) {
    list(ok = TRUE, detail = paste("worker", seen$pid, "sees", seen$lib),
         pid = seen$pid, parent_pid = parent_pid)
  } else {
    list(ok = FALSE, detail = paste("worker started but cannot load omicsCore from",
                                    seen$lib))
  }
}

r_minor_version <- function() {
  paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1L]][[1L]],
        sep = ".")
}

# The BUNDLE record the installer left in the desk folder, or NULL.
read_bundle_record <- function(path = desk_bundle_file()) {
  if (!file.exists(path)) return(NULL)
  dcf <- tryCatch(read.dcf(path), error = function(e) NULL)
  if (is.null(dcf) || nrow(dcf) == 0L) return(NULL)
  fields <- as.list(dcf[1L, ])
  for (f in c("RMinor", "Version", "Platform", "Built")) {
    if (is.null(fields[[f]])) fields[[f]] <- NA_character_
  }
  fields
}

#' @export
print.desk_doctor <- function(x, ...) {
  mark <- ifelse(x$ok, "[ok]", ifelse(x$required, "[!!]", "[--]"))
  cat(sprintf("%s %-20s %s", mark, x$check, x$detail), sep = "\n")
  bad <- x[!x$ok & x$required, , drop = FALSE]
  if (nrow(bad) > 0L) {
    cat("\nTo fix:\n")
    cat(sprintf("  * %s: %s", bad$check, bad$fix), sep = "\n")
  } else {
    cat("\nEverything omicsDesk needs is here.\n")
  }
  invisible(x)
}
