# The packages the app can call at runtime.
#
# omicsCore lists its engines as Suggests so that a networked install can
# stay slim and add DESeq2 or GSVA the day they are first needed. Offline
# there is no "first needed": a package that is not in the bundle is a
# feature that silently is not there -- the app gates each view on
# requireNamespace() and hides what it cannot run. Listing every engine
# here as an Import of omicsDesk is what makes the dependency solver fetch
# all of them, on the build machine and again from the bundle.
#
# The groups are omicsCore's install_optional() groups plus the two
# packages themselves, and doctor() reports one row per group.

DESK_BACKENDS <- list(
  engine        = c("omicsCore", "omicsApp"),
  rnaseq        = c("DESeq2", "edgeR", "limma"),
  proteomics    = c("vsn", "pcaMethods", "impute", "imputeLCMD"),
  enrichment    = c("clusterProfiler", "msigdbr", "fgsea", "GSVA", "enrichplot"),
  integration   = c("ActivePathways"),
  visualization = c("ComplexHeatmap", "circlize", "ggrepel", "plotly"),
  report        = c("rmarkdown", "knitr"),
  export        = c("writexl", "openxlsx", "readxl", "qs2")
)

# One exported function per Import. R CMD check counts a `pkg::fn`
# reference as use of the import, and this body is not evaluated until a
# test asks, so the heavy namespaces are not loaded on library(). The
# test evaluates every entry: an engine that renamed its entry point
# shows up there, not in a user's session.
backend_entrypoints <- function() {
  list(
    omicsCore       = omicsCore::run_diff,
    omicsApp        = omicsApp::launch,
    DESeq2          = DESeq2::DESeq,
    edgeR           = edgeR::glmQLFit,
    limma           = limma::lmFit,
    vsn             = vsn::vsn2,
    pcaMethods      = pcaMethods::pca,
    impute          = impute::impute.knn,
    imputeLCMD      = imputeLCMD::impute.MinProb,
    clusterProfiler = clusterProfiler::enricher,
    msigdbr         = msigdbr::msigdbr,
    fgsea           = fgsea::fgsea,
    GSVA            = GSVA::gsva,
    enrichplot      = enrichplot::gseaplot2,
    ActivePathways  = ActivePathways::ActivePathways,
    ComplexHeatmap  = ComplexHeatmap::Heatmap,
    circlize        = circlize::colorRamp2,
    ggrepel         = ggrepel::geom_text_repel,
    plotly          = plotly::plot_ly,
    rmarkdown       = rmarkdown::render,
    knitr           = knitr::kable,
    writexl         = writexl::write_xlsx,
    openxlsx        = openxlsx::write.xlsx,
    readxl          = readxl::read_excel,
    qs2             = qs2::qs_save,
    jsonlite        = jsonlite::fromJSON,
    future          = future::multisession
  )
}

# One seam for "is this package here?", so a test can answer it.
has_pkg <- function(pkg) {
  requireNamespace(pkg, quietly = TRUE)
}

pkg_version_or_na <- function(pkg) {
  if (!has_pkg(pkg)) return(NA_character_)
  as.character(utils::packageVersion(pkg))
}
