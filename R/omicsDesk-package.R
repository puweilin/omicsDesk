#' omicsDesk: omicsApp on one machine, offline
#'
#' omicsCore and omicsApp are written for a machine that can reach CRAN and
#' Bioconductor: heavy engines are optional packages installed on first
#' use, and the MSigDB gene sets come from `msigdbr`, which on current
#' versions downloads them. omicsDesk is the layer that removes both
#' assumptions. It depends on every engine the app can call, ships the
#' gene-set tables, and starts the app with its files in one folder that
#' persists between sessions.
#'
#' Three functions matter to a user:
#'
#' * [launch()] starts the app.
#' * [doctor()] says what, if anything, is missing on this machine.
#' * [install_offline()] installs the whole stack from a bundle built by
#'   `tools/build_bundle.R` on a networked machine.
#'
#' @keywords internal
"_PACKAGE"

`%||%` <- function(a, b) if (is.null(a)) b else a
