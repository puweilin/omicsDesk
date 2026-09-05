# Started by omicsDesk.bat / omicsDesk.command. Keep that window open
# while you work; closing it stops the app.

record <- file.path(Sys.getenv("OMICSDESK_HOME", path.expand("~/omicsDesk")), "BUNDLE")
if (file.exists(record)) {
  # INSTALL.R may have put the packages in a library of its own.
  fields <- tryCatch(read.dcf(record), error = function(e) NULL)
  if (!is.null(fields) && "Library" %in% colnames(fields)) {
    lib <- fields[1L, "Library"]
    if (!is.na(lib) && dir.exists(lib)) .libPaths(c(lib, .libPaths()))
  }
}

if (!requireNamespace("omicsDesk", quietly = TRUE)) {
  stop("omicsDesk is not installed yet. Run INSTALL.R first (see README.md).",
       call. = FALSE)
}

omicsDesk::launch(browser = TRUE)
