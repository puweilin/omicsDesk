# Every test that touches the desk folder gets a throwaway one, with the
# variables launch() derives from it unset so a developer's own
# OMICSAPP_DATA_DIR cannot leak into an expectation.
local_desk_home <- function(env = parent.frame()) {
  home <- withr::local_tempdir(.local_envir = env)
  withr::local_envvar(
    c(OMICSDESK_HOME = home,
      OMICSAPP_DATA_DIR = NA, OMICSCORE_GENESET_CACHE = NA,
      OMICSCORE_GENESET_TTL_DAYS = NA, OMICSCORE_OFFLINE = NA,
      RSTUDIO_PANDOC = NA),
    .local_envir = env)
  home
}

skip_if_no_bundled_genesets <- function() {
  dir <- omicsDesk:::bundled_geneset_dir()
  testthat::skip_if(!nzchar(dir) || length(list.files(dir, pattern = "\\.qs2$")) == 0L,
                    "package built without inst/genesets")
}

# A small but valid gene-set table, in the layout omicsCore reads.
write_geneset_table <- function(path, gs_source = "test fixture", n_sets = 3L) {
  df <- data.frame(
    gs_name = rep(paste0("SET_", seq_len(n_sets)), each = 4L),
    gene_symbol = paste0("GENE", seq_len(4L * n_sets)),
    gs_description = rep(paste("Set", seq_len(n_sets)), each = 4L),
    gs_id = rep(paste0("M", seq_len(n_sets)), each = 4L),
    gs_source = gs_source,
    stringsAsFactors = FALSE
  )
  qs2::qs_save(df, path)
  invisible(path)
}

source_tree_file <- function(...) {
  # tools/ is Rbuildignored, so it only exists when tests run from source.
  path <- testthat::test_path("..", "..", ...)
  if (!file.exists(path)) testthat::skip("not running from the source tree")
  path
}
