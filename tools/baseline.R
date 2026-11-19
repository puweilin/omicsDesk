# Sourceable checks used by the builder and source-tree tests. No side effects.
check_upstream_baseline <- function(root, upstream, sha, allow_unpinned = FALSE) {
  desk <- read.dcf(file.path(root, "DESCRIPTION"))[1L, ]
  pin <- unname(desk[["Config/omicsDesk/UpstreamRef"]])
  if (!grepl("^[0-9a-f]{40}$", pin)) stop("UpstreamRef must be a full commit SHA.")
  versions <- vapply(c("omicsCore", "omicsApp"), function(pkg) {
    unname(read.dcf(file.path(upstream, "packages", pkg, "DESCRIPTION"))[1L, "Version"])
  }, character(1))
  if (length(unique(c(unname(versions), unname(desk[["Version"]])))) != 1L) {
    stop("Version baseline mismatch: omicsDesk ", desk[["Version"]], "; ",
         paste(names(versions), versions, collapse = ", "))
  }
  if (!identical(sha, pin) && !isTRUE(allow_unpinned)) {
    stop("Upstream source does not match pinned baseline ", pin,
         ". Use that clean checkout, or --allow-unpinned for a development build.")
  }
  if (!identical(sha, pin)) warning("Development build: upstream differs from pinned baseline.")
  invisible(pin)
}
