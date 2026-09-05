#' Install omicsDesk and everything it needs from a bundle
#'
#' A bundle is the directory (or unzipped archive) that
#' `tools/build_bundle.R` produces on a networked machine: a local
#' CRAN-style repository holding omicsCore, omicsApp, omicsDesk and their
#' whole dependency closure as packages built for one platform and one R
#' minor version, plus pandoc and a `BUNDLE` record. This function is the
#' same code as the bundle's own `INSTALL.R`; it exists so that a machine
#' that already has omicsDesk can upgrade from a newer bundle without
#' leaving R.
#'
#' @param bundle_dir Path to the unzipped bundle.
#' @param lib Library to install into. Defaults to the first entry of
#'   `.libPaths()`, normally the user library.
#' @param force Reinstall packages that are already present at the
#'   bundled version.
#' @param quiet Pass `quiet = TRUE` to `install.packages()`.
#'
#' @return Invisibly, a list with `lib`, `installed` (package names) and
#'   `home` (the desk folder pandoc and the BUNDLE record went to).
#' @export
#' @examples
#' \dontrun{
#' install_offline("~/Downloads/omicsDesk-0.1.0-R4.5-windows")
#' }
install_offline <- function(bundle_dir, lib = NULL, force = FALSE, quiet = FALSE) {
  script <- system.file("bundle", "INSTALL.R", package = "omicsDesk")
  if (!nzchar(script)) stop("The installer script is missing from this omicsDesk.")
  env <- new.env(parent = globalenv())
  sys.source(script, envir = env)
  env$install_offline_bundle(bundle_dir = bundle_dir, lib = lib,
                             force = force, quiet = quiet)
}
