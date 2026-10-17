#!/usr/bin/env Rscript
# Exercise omicsDesk::launch(), installed packages and actual multisession workers.
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  stopifnot(length(args) == 3L)
  lib <- normalizePath(args[[1L]], mustWork = TRUE)
  home <- normalizePath(args[[2L]], mustWork = TRUE)
  output <- normalizePath(args[[3L]], mustWork = TRUE)
  .libPaths(c(lib, .libPaths()))
  Sys.setenv(NOT_CRAN = "true", SHINYTEST2_APP_DRIVER_TEST_ON_CRAN = "true")
  for (pkg in c("callr", "shinytest2", "chromote")) {
    if (!requireNamespace(pkg, quietly = TRUE)) stop("Browser verification needs ", pkg)
  }
  port <- httpuv::randomPort()
  start_server <- function() {
    callr::r_bg(function(lib, home, port) {
      .libPaths(c(lib, .libPaths()))
      Sys.setenv(OMICSDESK_HOME = home, OMICSAPP_DEV_ROOT = "")
      options(shiny.testmode = TRUE)
      omicsDesk::launch(port = port, browser = FALSE, workers = 2L)
    }, args = list(lib, home, port), supervise = TRUE,
    stdout = file.path(output, "server.log"), stderr = file.path(output, "server.log"))
  }
  server <- start_server()
  on.exit(if (server$is_alive()) server$kill_tree(), add = TRUE)
  url <- sprintf("http://127.0.0.1:%d", port)
  ready <- FALSE
  for (i in seq_len(120L)) {
    if (!server$is_alive()) stop("Desktop server exited: ", paste(readLines(file.path(output, "server.log")), collapse="\n"))
    ready <- tryCatch({
      conn <- url(url, open = "rb")
      close(conn)
      TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (ready) break
    Sys.sleep(0.25)
  }
  stopifnot(ready)
  app <- shinytest2::AppDriver$new(url, name = "omicsDesk-installed", load_timeout = 60000, timeout = 60000)
  on.exit(try(app$stop(), silent = TRUE), add = TRUE)
  expected <- c(nav_project = "Project overview", nav_import = "Import data", nav_qc = "Quality control",
                nav_diff = "Differential", nav_enrich = "Pathway enrichment",
                nav_integration = "Multi-omics integration", nav_report = "Report")
  for (id in names(expected)) {
    app$click(selector = paste0("#", id))
    app$wait_for_idle(timeout = 60000)
    stopifnot(grepl(expected[[id]], app$get_text(".tab-pane.active .page-title"), fixed = TRUE))
  }
  message("PASS seven desktop views")
  app$click(selector = "#nav_import")
  app$upload_file(`import-file` = file.path(output, "raw", "protein.xlsx"))
  app$wait_for_idle(timeout = 30000)
  app$set_inputs(`import-normalize_method` = "vsn", wait_ = FALSE)
  app$click("import-confirm")
  app$wait_for_idle(timeout = 30000)
  app$click(selector = "#nav_qc")
  app$wait_for_idle(timeout = 30000)
  app$set_inputs(`qc-missing_threshold` = 0.5, `qc-impute_method` = "min", wait_ = FALSE)
  app$wait_for_idle(timeout = 30000)
  app$click("qc-apply_to_downstream")
  app$wait_for_idle(timeout = 30000)
  app$click(selector = "#nav_diff")
  app$wait_for_idle(timeout = 60000)
  app$set_inputs(`diff-method` = "limma", `diff-group_col` = "group", `diff-control` = "A", `diff-case` = "B", wait_ = FALSE)
  app$click("diff-rerun")
  app$wait_for_idle(timeout = 60000)
  snapshot <- file.path(home, "projects", "_autosave.omp")
  stopifnot(file.exists(snapshot))
  project <- omicsCore::load_project(snapshot)
  tag <- names(project$experiments)[[1L]]
  stopifnot(!is.null(project$preprocessing[[tag]]))
  effective <- omicsCore::effective_input(project, tag)$input
  stopifnot(!anyNA(effective$expr_mat), nrow(effective$expr_mat) == 299L)
  result <- project$bundles$diff$results$diff_result_df
  stopifnot(nrow(result) == 299L)
  direct <- omicsCore::run_diff(effective, method = "limma", group_col = "group", control_group = "A", case_group = "B")
  reference <- direct$results$diff_result_df
  stopifnot(isTRUE(all.equal(result$effect[match(reference$feature_id, result$feature_id)], reference$effect, tolerance = 1e-8)))
  message("PASS browser upload, VSN, applied QC, real background limma and numeric comparison")
  screenshot <- file.path(output, "desktop-differential.png")
  unlink(screenshot)
  app$get_screenshot(file = screenshot)
  app$click(selector = "#nav_enrich")
  app$wait_for_idle(timeout = 30000)
  app$set_inputs(`enrich-type` = "ora", `enrich-database` = "hallmark", wait_ = FALSE)
  app$click("enrich-rerun")
  app$wait_for_idle(timeout = 60000)
  project <- omicsCore::load_project(snapshot)
  stopifnot(nrow(project$bundles$enrich$results$enrich_result_df) > 0L)
  message("PASS browser offline enrichment")
  app$click(selector = "#nav_report")
  app$wait_for_idle(timeout = 30000)
  for (id in c("report-download_script", "report-download_xlsx", "report-download_html")) {
    download <- app$get_download(id)
    stopifnot(file.exists(download), file.size(download) > 100)
    file.copy(download, file.path(output, paste0("browser-", basename(download))), overwrite = TRUE)
  }
  message("PASS browser script, workbook and HTML downloads")
  app$stop()
  server$kill_tree()
  server <- start_server()
  Sys.sleep(2)
  app <- shinytest2::AppDriver$new(url, name = "omicsDesk-restart", load_timeout = 60000, timeout = 60000)
  app$click(selector = "#nav_diff")
  app$wait_for_idle(timeout = 60000)
  stats <- paste(unlist(app$get_value(output = "diff-stats")), collapse = " ")
  stopifnot(grepl("299", stats, fixed = TRUE))
  stopifnot(identical(app$get_value(input = "diff-method"), "limma"))
  errors <- app$get_js("Array.from(document.querySelectorAll('.shiny-output-error')).map(x=>x.innerText).filter(Boolean)")
  stopifnot(length(errors) == 0L)
  message("PASS desktop restart and project recovery")
  message("BROWSER OK")
}
main()
