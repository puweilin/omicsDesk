#!/usr/bin/env Rscript
# Reproducible desktop budgets; uses synthetic data and installed packages.
# Rscript tools/benchmark_desktop.R <output directory>
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  output <- if (length(args)) args[[1L]] else tempfile("omicsDesk-benchmark-")
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  results <- data.frame(step = character(), elapsed_seconds = numeric(), budget_seconds = numeric())
  measure <- function(step, budget = Inf, code) {
    start <- proc.time()[["elapsed"]]
    value <- force(code)
    elapsed <- proc.time()[["elapsed"]] - start
    results[nrow(results) + 1L, ] <<- list(step, elapsed, budget)
    message(sprintf("%s: %.3f s (budget %s)", step, elapsed, budget))
    value
  }
  on.exit(utils::write.csv(results, file.path(output, "performance.csv"), row.names = FALSE), add = TRUE)
  home <- tempfile("omicsDesk-benchmark-home-")
  dir.create(home)
  on.exit(unlink(home, recursive = TRUE), add = TRUE)
  Sys.setenv(OMICSDESK_HOME = home, OMICSCORE_OFFLINE = "1", OMICSCORE_GENESET_TTL_DAYS = "0")
  Sys.unsetenv(c("OMICSCORE_GENESET_CACHE", "OMICSAPP_DATA_DIR"))
  measure("prepare_first_launch", 5, omicsDesk:::desk_env())
  measure("prepare_warm_launch", 1, omicsDesk:::desk_env())
  Sys.setenv(OMICSCORE_GENESET_CACHE = file.path(home, "genesets"))
  measure("genesets_cold_process", 20, omicsCore::list_gene_sets("hallmark", "Hs"))
  measure("genesets_memory_hit", 0.25, omicsCore::list_gene_sets("hallmark", "Hs"))
  set.seed(20261016)
  counts <- matrix(stats::rpois(63241L * 258L, 30L), 63241L, 258L,
                    dimnames = list(sprintf("ENSG%011d", 1:63241), sprintf("S%03d", 1:258)))
  counts[seq_len(nrow(counts) %/% 5L), ] <- 0L
  tsv <- tempfile(fileext = ".tsv")
  on.exit(unlink(tsv), add = TRUE)
  utils::write.table(data.frame(gene_id = rownames(counts), counts, check.names = FALSE),
                     tsv, sep = "\t", row.names = FALSE, quote = FALSE)
  imported <- measure("import_63241x258", 60, omicsCore::read_omics(tsv, omics_type = "rnaseq", assay_type = "raw_count"))
  stopifnot(identical(dim(imported$input$expr_mat), dim(counts)))
  rm(imported)
  pca <- measure("pca_63241x258", 20, getFromNamespace("pca_over_samples", "omicsCore")(log2(counts + 1)))
  stopifnot(identical(attr(pca, "n_dropped"), nrow(counts) %/% 5L))
  rm(counts, pca)
  mat <- matrix(stats::rnorm(20000L * 258L, 20, 2), 20000L, 258L,
                 dimnames = list(sprintf("P%05d", 1:20000), sprintf("S%03d", 1:258)))
  meta <- data.frame(group = rep(c("A", "B"), each = 129), age = stats::runif(258, 20, 80), row.names = colnames(mat))
  input <- omicsCore::omics_input(mat, meta, data.frame(feature_id = rownames(mat)),
                                   omics_type = "proteomics", assay_type = "normalized_intensity")
  diff <- measure("limma_20000x258", 30, omicsCore::run_diff(input, method = "limma", group_col = "group",
                            control_group = "A", case_group = "B", covariates = "age"))
  stopifnot(nrow(diff$results$diff_result_df) == 20000L, is.null(diff$results$diff_object))
  table <- diff$results$diff_result_df[rep(seq_len(20000), length.out = 63241L), ]
  measure("remask_63241", 0.25, omicsCore::filter_diff_results(table, p_cutoff = 0.05, effect_cutoff = 0.5))
  capture.output(sessionInfo(), file = file.path(output, "session-info.txt"))
  stopifnot(all(results$elapsed_seconds < results$budget_seconds))
  message("PERFORMANCE OK")
}
main()
