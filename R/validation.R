assert_flag <- function(x, name) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    stop("`", name, "` must be TRUE or FALSE.", call. = FALSE)
  }
  invisible(x)
}

assert_path <- function(x, name, allow_null = FALSE) {
  if (is.null(x) && allow_null) return(invisible(x))
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    stop("`", name, "` must be a non-empty path.", call. = FALSE)
  }
  invisible(x)
}

assert_workers <- function(workers) {
  if (!is.numeric(workers) || length(workers) != 1L || is.na(workers) ||
      !is.finite(workers) || workers < 0 || workers != floor(workers) ||
      workers > .Machine$integer.max) {
    stop("`workers` must be a non-negative whole number.", call. = FALSE)
  }
  invisible(workers)
}
