# Environment variables, set for a call and restored after it.
#
# Base R only: withr is a test dependency here, not a runtime one, and the
# two functions below are all launch() and the tests need. An `NA` value
# means "unset".

set_envvar <- function(vars) {
  for (nm in names(vars)) {
    val <- vars[[nm]]
    if (is.na(val)) {
      Sys.unsetenv(nm)
    } else {
      do.call(Sys.setenv, stats::setNames(list(as.character(val)), nm))
    }
  }
  invisible(vars)
}

with_envvar <- function(new, code) {
  new <- unlist(new)
  old <- Sys.getenv(names(new), unset = NA, names = TRUE)
  set_envvar(new)
  on.exit(set_envvar(old), add = TRUE)
  force(code)
}

env_or <- function(name, default) {
  val <- Sys.getenv(name, "")
  if (nzchar(val)) val else default
}
