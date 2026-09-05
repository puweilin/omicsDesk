#' Launch omicsApp on this machine
#'
#' Starts the omicsApp interface with the environment an offline laptop
#' needs, and puts everything back when the app stops:
#'
#' * projects and the autosave go to `desk_paths()$projects` instead of a
#'   temporary directory, so they are still there tomorrow;
#' * enrichment reads the shipped MSigDB tables from `desk_paths()$genesets`
#'   (copied there on first launch), so nothing is downloaded;
#' * the 30-day KEGG auto-refresh is off, and omicsCore's offline flag is
#'   on, unless `online = TRUE`;
#' * a pandoc placed in `desk_paths()$pandoc` by the bundle installer is
#'   used for HTML reports when none is on the PATH.
#'
#' Variables the caller set beforehand (`OMICSAPP_DATA_DIR`,
#' `OMICSCORE_GENESET_CACHE`, `RSTUDIO_PANDOC`) are respected.
#'
#' @param project Optional `.omp` file to open on start.
#' @param data_dir Where projects are stored. Defaults to
#'   `desk_paths()$projects`.
#' @param port Port for the local server; `NULL` lets Shiny pick one.
#' @param browser Open the default browser. Default `interactive()`;
#'   the bundle's launchers pass `TRUE`.
#' @param workers Background R processes for long analyses, as in
#'   [omicsApp::launch()].
#' @param online Set `TRUE` on a networked machine to allow the KEGG
#'   auto-refresh and live `refresh_geneset_cache()` calls.
#' @param quiet Skip the one-line banner.
#' @param ... Passed on to [omicsApp::launch()].
#'
#' @return Invisible `NULL`, once the app has stopped.
#' @export
#' @examples
#' \dontrun{
#' launch()
#' launch(project = "~/omicsDesk/projects/cheek.omp")
#' }
launch <- function(project = NULL,
                   data_dir = NULL,
                   port = NULL,
                   browser = interactive(),
                   workers = 2L,
                   online = FALSE,
                   quiet = FALSE,
                   ...) {
  env <- desk_env(data_dir = data_dir, online = online)
  ensure_dir(env[["OMICSAPP_DATA_DIR"]])
  with_envvar(env, {
    refresh_pandoc_lookup()
    if (!quiet) launch_banner(env)
    run_app(project = project, port = port, launch.browser = browser,
            workers = workers, ...)
  })
  invisible(NULL)
}

# The environment launch() runs the app under. Separated from launch() so
# a test can check it without starting a server.
desk_env <- function(data_dir = NULL, online = FALSE) {
  sync_geneset_cache(quiet = TRUE)
  env <- c(
    OMICSAPP_DATA_DIR = data_dir %||% env_or("OMICSAPP_DATA_DIR", desk_data_dir()),
    OMICSCORE_GENESET_CACHE = env_or("OMICSCORE_GENESET_CACHE", desk_geneset_dir())
  )
  if (!isTRUE(online)) {
    env <- c(env, OMICSCORE_GENESET_TTL_DAYS = "0", OMICSCORE_OFFLINE = "1")
  }
  pandoc <- desk_pandoc_for_env()
  if (nzchar(pandoc)) env <- c(env, RSTUDIO_PANDOC = pandoc)
  env
}

# The bundle's pandoc wins over none; a caller's RSTUDIO_PANDOC wins over
# the bundle's. A pandoc already on the PATH is left for rmarkdown to
# find when the desk folder has none.
desk_pandoc_for_env <- function() {
  if (nzchar(Sys.getenv("RSTUDIO_PANDOC", ""))) return("")
  if (nzchar(pandoc_in(desk_pandoc_dir()))) return(desk_pandoc_dir())
  ""
}

# rmarkdown remembers where it found pandoc; after changing RSTUDIO_PANDOC
# it has to look again.
refresh_pandoc_lookup <- function() {
  if (has_pkg("rmarkdown")) {
    tryCatch(rmarkdown::find_pandoc(cache = FALSE), error = function(e) NULL)
  }
  invisible(NULL)
}

launch_banner <- function(env) {
  pandoc <- if (has_pkg("rmarkdown") && rmarkdown::pandoc_available()) {
    paste("pandoc", as.character(rmarkdown::pandoc_version()))
  } else {
    "no pandoc, HTML reports unavailable"
  }
  message(
    "omicsDesk ", utils::packageVersion("omicsDesk"),
    "\n  projects:  ", env[["OMICSAPP_DATA_DIR"]],
    "\n  gene sets: ", geneset_vintage(env[["OMICSCORE_GENESET_CACHE"]]) %||% "none",
    "\n  reports:   ", pandoc,
    if (!is.na(env["OMICSCORE_OFFLINE"])) "\n  mode:      offline" else "\n  mode:      online"
  )
}

# The one call that starts a server, so tests can replace it.
run_app <- function(...) {
  omicsApp::launch(...)
}
