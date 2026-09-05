#!/usr/bin/env Rscript
#
# Build inst/genesets: the MSigDB tables omicsCore reads, in the qs2
# layout its on-disk cache expects.
#
#   Rscript tools/prewarm_genesets.R            # -> inst/genesets
#   Rscript tools/prewarm_genesets.R <out dir>
#
# Needs network the first time msigdbr loads its data (current msigdbr
# downloads it from Zenodo); that is the whole reason this runs on the
# build machine and ships the result. The contract is omicsCore's
# (enrich-genesets.R): one file per database and organism named
# `<database>__<Organism>.qs2`, a data frame with the columns below.
# `gs_source` is what refresh_geneset_cache() would stamp, so a shipped
# table and a refreshed one read the same.
#
# The collection map mirrors omicsCore:::DB_MSIGDBR_MAP; a test in
# tests/testthat/test-bundle-contract.R checks that the two agree.

suppressPackageStartupMessages({
  library(msigdbr)
  library(qs2)
  library(jsonlite)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
repo_root <- if (length(script_path)) normalizePath(file.path(dirname(script_path[[1L]]), "..")) else getwd()
args <- commandArgs(trailingOnly = TRUE)
OUT_DIR <- if (length(args) >= 1L) args[[1L]] else file.path(repo_root, "inst", "genesets")

ORGANISMS <- c("Homo sapiens", "Mus musculus")

COLLECTIONS <- list(
  hallmark     = list(collection = "H",  subcollection = NA_character_),
  kegg         = list(collection = "C2", subcollection = "CP:KEGG_LEGACY"),
  reactome     = list(collection = "C2", subcollection = "CP:REACTOME"),
  wikipathways = list(collection = "C2", subcollection = "CP:WIKIPATHWAYS"),
  go_bp        = list(collection = "C5", subcollection = "GO:BP"),
  go_mf        = list(collection = "C5", subcollection = "GO:MF"),
  go_cc        = list(collection = "C5", subcollection = "GO:CC")
)

KEEP <- c("gs_name", "gene_symbol", "gs_description", "gs_id")

msigdbr_version <- as.character(packageVersion("msigdbr"))

# msigdbr >= 10 is versioned after the MSigDB release it carries
# (25.1.x -> MSigDB 2025.1); older versions were numbered like MSigDB
# itself (7.5.1).
msigdb_release <- function() {
  v <- unclass(packageVersion("msigdbr"))[[1L]]
  if (v[[1L]] >= 10L) sprintf("20%02d.%d", v[[1L]], v[[2L]]) else msigdbr_version
}

fetch <- function(cfg, organism) {
  msig_args <- names(formals(msigdbr::msigdbr))
  if ("collection" %in% msig_args) {
    msigdbr::msigdbr(
      species = organism,
      collection = cfg$collection,
      subcollection = if (is.na(cfg$subcollection)) NULL else cfg$subcollection
    )
  } else {
    # msigdbr < 10 carries MSigDB 7.5, whose KEGG subcategory is
    # "CP:KEGG"; the map above uses the modern name.
    sub <- cfg$subcollection
    if (identical(sub, "CP:KEGG_LEGACY")) sub <- "CP:KEGG"
    raw <- msigdbr::msigdbr(species = organism, category = cfg$collection)
    if (!is.na(sub) && "gs_subcat" %in% colnames(raw)) {
      raw <- raw[raw$gs_subcat == sub, , drop = FALSE]
    }
    raw
  }
}

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
cache_file <- function(database, organism) {
  file.path(OUT_DIR, sprintf("%s__%s.qs2", database,
                             gsub("[^A-Za-z0-9]+", "_", organism)))
}

gs_source <- paste("MSigDB msigdbr", msigdbr_version)
files <- list()
failed <- character()

for (organism in ORGANISMS) {
  for (database in names(COLLECTIONS)) {
    path <- cache_file(database, organism)
    ok <- tryCatch({
      df <- fetch(COLLECTIONS[[database]], organism)
      cols <- intersect(KEEP, colnames(df))
      if (!all(c("gs_name", "gene_symbol") %in% cols)) stop("missing gs_name / gene_symbol")
      df <- as.data.frame(df[, cols, drop = FALSE])
      df$gs_source <- gs_source
      qs2::qs_save(df, path)
      files[[length(files) + 1L]] <- data.frame(
        file = basename(path), database = database, organism = organism,
        n_sets = length(unique(df$gs_name)), n_rows = nrow(df),
        bytes = file.size(path), md5 = unname(tools::md5sum(path)),
        gs_source = gs_source, stringsAsFactors = FALSE)
      TRUE
    }, error = function(e) {
      message(sprintf("  ! %s / %s: %s", database, organism, conditionMessage(e)))
      FALSE
    })
    if (!isTRUE(ok)) { failed <- c(failed, sprintf("%s/%s", database, organism)); next }
    message(sprintf("  %-14s %-14s %6.2f MB", database, organism, file.size(path) / 1024^2))
  }
}

if (length(files) == 0L) stop("No gene-set tables were built; nothing to ship.")
files <- do.call(rbind, files)

manifest <- list(
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  msigdbr_version = msigdbr_version,
  msigdb_release = msigdb_release(),
  organisms = ORGANISMS,
  databases = names(COLLECTIONS),
  columns = c(KEEP, "gs_source"),
  license = paste(
    "MSigDB gene sets, redistributed as msigdbr does, under MSigDB's terms",
    "(https://www.gsea-msigdb.org/gsea/msigdb_license_terms.jsp).",
    "The kegg table is MSigDB's frozen CP:KEGG_LEGACY collection, not the",
    "live KEGG database; tables fetched from the KEGG REST API are for",
    "local use only and are never shipped."),
  files = files
)
jsonlite::write_json(manifest, file.path(OUT_DIR, "MANIFEST.json"),
                     auto_unbox = TRUE, pretty = TRUE, dataframe = "rows")

message(sprintf("\n%d tables, %.1f MB, MSigDB %s (msigdbr %s) -> %s",
                nrow(files), sum(files$bytes) / 1024^2, manifest$msigdb_release,
                msigdbr_version, OUT_DIR))
if (length(failed)) message("Not built: ", paste(failed, collapse = ", "))
