# Installed-package acceptance checks. Run after INSTALL.R:
# Rscript VERIFY.R <output directory>
run_desk_acceptance <- function(output_dir) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  output_dir <- normalizePath(output_dir, mustWork = TRUE)
  timings <- data.frame(step = character(), elapsed_seconds = numeric())
  timed <- function(step, code) {
    start <- proc.time()[["elapsed"]]
    value <- force(code)
    timings[nrow(timings) + 1L, ] <<- list(step, proc.time()[["elapsed"]] - start)
    message("PASS ", step)
    value
  }
  on.exit(utils::write.csv(timings, file.path(output_dir, "timings.csv"), row.names = FALSE), add = TRUE)
  omicsDesk::sync_geneset_cache()
  Sys.setenv(OMICSCORE_OFFLINE = "1", OMICSCORE_GENESET_TTL_DAYS = "0",
             OMICSCORE_GENESET_CACHE = omicsDesk::desk_paths()$genesets)
  stopifnot(all(omicsDesk::geneset_status()$cached))
  table <- qs2::qs_read(file.path(omicsDesk::desk_paths()$genesets, "hallmark__Homo_sapiens.qs2"))
  pathway <- unique(table$gs_name)[[1L]]
  signal <- head(unique(table$gene_symbol[table$gs_name == pathway]), 60L)
  genes <- unique(c(signal, head(setdiff(table$gene_symbol, signal), 300L - length(signal))))
  n <- length(genes)
  samples <- sprintf("S%02d", 1:12)
  set.seed(20261016)
  mat <- matrix(stats::rnorm(n * 12, 18, 0.6), n, 12,
                dimnames = list(genes, samples))
  mat[seq_along(signal), 7:12] <- mat[seq_along(signal), 7:12] + 3
  mat[1, 1:9] <- NA_real_
  mat[2, 1] <- NA_real_
  metadata <- data.frame(sample_id = samples, group = rep(c("A", "B"), each = 6L))
  features <- data.frame(feature_id = genes, feature_symbol = genes)
  raw <- file.path(output_dir, "raw")
  dir.create(raw, showWarnings = FALSE)
  workbook <- file.path(raw, "protein.xlsx")
  openxlsx::write.xlsx(list(expression = data.frame(feature_id = genes, 2^mat, check.names = FALSE),
                             metadata = metadata, feature_annot = features), workbook)
  input <- timed("import", omicsCore::read_omics(workbook, omics_type = "proteomics",
                                                  assay_type = "raw_intensity")$input)
  normalized <- timed("vsn_normalization", omicsCore::normalize_omics(input, method = "vsn"))
  params <- list(missing_threshold = 0.5, impute_method = "min")
  qc <- timed("qc", do.call(omicsCore::run_qc, c(list(input = normalized), params)))
  cleaned <- qc$results$cleaned_input
  stopifnot(nrow(cleaned$expr_mat) == n - 1L, !anyNA(cleaned$expr_mat),
            !genes[[1L]] %in% rownames(cleaned$expr_mat))
  project <- omicsCore::omics_project("omicsDesk acceptance", list(protein = normalized))
  project <- omicsCore::set_preprocessing(project, "protein", cleaned, params)
  effective <- omicsCore::effective_input(project, "protein")$input
  stopifnot(identical(effective$expr_mat, cleaned$expr_mat))
  diff <- timed("limma", omicsCore::run_diff(effective, method = "limma", analysis_type = "group",
                    group_col = "group", control_group = "A", case_group = "B"))
  stopifnot(nrow(diff$results$diff_result_df) == n - 1L)
  project$bundles <- list(qc = qc, diff = diff)

  # A separate R process executes the exported source and serialises its answer.
  script <- file.path(output_dir, "replay.R")
  omicsCore::export_script(project, script)
  cat('\nsaveRDS(get(grep("^diff", ls(), value = TRUE)[[1L]]), "replayed.rds")\n',
      file = script, append = TRUE)
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  old_wd <- setwd(output_dir)
  on.exit(setwd(old_wd), add = TRUE)
  status <- timed("script_replay_fresh_process", system2(rscript, c("--vanilla", shQuote(script)),
                                      stdout = "replay.log", stderr = "replay.log"))
  stopifnot(identical(status, 0L))
  replayed <- readRDS("replayed.rds")$results$diff_result_df
  expected <- diff$results$diff_result_df
  idx <- match(expected$feature_id, replayed$feature_id)
  stopifnot(!anyNA(idx), nrow(replayed) == nrow(expected))
  for (column in c("effect", "statistic", "p_value", "adj_p_value")) {
    stopifnot(isTRUE(all.equal(replayed[[column]][idx], expected[[column]], tolerance = 1e-8)))
  }

  ora <- timed("ora", omicsCore::run_enrichment(diff, type = "ora", database = "hallmark",
                                                 output_p_cutoff = 1))
  gsea <- timed("gsea", omicsCore::run_enrichment(diff, type = "gsea", database = "hallmark",
                                                    output_p_cutoff = 1))
  gsva <- timed("gsva", omicsCore::run_gsva(effective, database = "hallmark"))
  stopifnot(nrow(ora$results$enrich_result_df) > 0L, nrow(gsea$results$enrich_result_df) > 0L,
            nrow(gsva$results$gsva_matrix) > 0L, ncol(gsva$results$gsva_matrix) == 12L)
  project$bundles$enrich <- ora
  project$bundles$gsva <- gsva
  counts <- matrix(stats::rnbinom(n * 12L, mu = 100, size = 10), n, 12,
                    dimnames = list(genes, samples))
  counts[seq_along(signal), 7:12] <- counts[seq_along(signal), 7:12] * 4L
  meta <- data.frame(group = metadata$group, row.names = samples)
  rownames(features) <- genes
  rna <- omicsCore::omics_input(counts, meta, features, omics_type = "rnaseq", assay_type = "raw_count")
  edge <- timed("edger", omicsCore::run_diff(rna, method = "edger", group_col = "group",
                                control_group = "A", case_group = "B"))
  deseq <- timed("deseq2", omicsCore::run_diff(rna, method = "deseq2", group_col = "group",
                                  control_group = "A", case_group = "B"))
  stopifnot(nrow(edge$results$diff_result_df) == n, nrow(deseq$results$diff_result_df) == n)
  logcpm <- edgeR::cpm(counts, log = TRUE, prior.count = 1)
  project$experiments$rna <- omicsCore::omics_input(logcpm, meta, features,
                                    omics_type = "rnaseq", assay_type = "logcpm")
  integration <- timed("integration", omicsCore::run_integration(project, method = "correlation"))
  stopifnot(nrow(integration$results$integration_df) > 0L)
  project$bundles$integration <- integration
  omp <- file.path(output_dir, "acceptance.omp")
  timed("project_save", omicsCore::save_project(project, omp, overwrite = TRUE))
  restored <- timed("project_restore", omicsCore::load_project(omp))
  stopifnot(identical(restored$experiments$protein$expr_mat, project$experiments$protein$expr_mat))
  timed("workbook_export", omicsCore::export_workbook(project, file.path(output_dir, "results.xlsx"), overwrite = TRUE))
  html <- file.path(output_dir, "report.html")
  timed("html_report", omicsCore::export_report(project, html, overwrite = TRUE))
  text <- paste(readLines(html, warn = FALSE), collapse = "\n")
  stopifnot(file.size(html) > 1000L, !grepl("src=[\"']https?://[^\"']*[Mm]ath[Jj]ax", text))
  stopifnot(!grepl("<(script|link|img|iframe)\\b[^>]*(src|href)=[\"'](https?:)?//", text,
                    perl = TRUE, ignore.case = TRUE))
  utils::write.csv(expected, file.path(output_dir, "differential.csv"), row.names = FALSE)
  message("ACCEPTANCE OK: ", output_dir)
  invisible(timings)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  run_desk_acceptance(if (length(args)) args[[1L]] else tempfile("omicsDesk-acceptance-"))
}
