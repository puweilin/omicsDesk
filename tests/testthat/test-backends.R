desc_imports <- function() {
  d <- read.dcf(system.file("DESCRIPTION", package = "omicsDesk"))
  items <- trimws(strsplit(d[1L, "Imports"], ",")[[1L]])
  trimws(sub("\\(.*\\)", "", items[nzchar(items)]))
}

test_that("every backend doctor() checks is a declared Import", {
  pkgs <- unique(unlist(omicsDesk:::DESK_BACKENDS, use.names = FALSE))
  expect_true(all(pkgs %in% desc_imports()),
              info = paste("not in Imports:", paste(setdiff(pkgs, desc_imports()), collapse = ", ")))
})

test_that("every Import has an entry point, and every entry point exists", {
  # The entry points are what keeps R CMD check from calling an Import
  # unused; an Import without one would be a NOTE, and an entry point that
  # an upstream package renamed would be an error in a user's session.
  eps <- omicsDesk:::backend_entrypoints()
  expect_true(all(vapply(eps, is.function, logical(1))))
  expect_setequal(setdiff(desc_imports(), names(eps)), character())
})

test_that("the shipped database and organism lists match omicsCore's", {
  expect_setequal(omicsDesk:::DESK_GENESET_DATABASES,
                  getFromNamespace("SUPPORTED_ENRICH_DATABASES", "omicsCore"))
  aliases <- getFromNamespace("ORGANISM_ALIASES", "omicsCore")
  expect_setequal(unname(omicsDesk:::DESK_GENESET_ORGANISMS), unique(unname(aliases)))
  expect_true(all(names(omicsDesk:::DESK_GENESET_ORGANISMS) %in% names(aliases)))
})

test_that("the expected file names are the ones omicsCore would look for", {
  cache_file <- getFromNamespace("geneset_cache_file", "omicsCore")
  expected <- omicsDesk:::expected_geneset_files()
  for (db in omicsDesk:::DESK_GENESET_DATABASES) {
    for (org in omicsDesk:::DESK_GENESET_ORGANISMS) {
      expect_true(basename(cache_file("x", db, org)) %in% expected)
    }
  }
  expect_length(expected, 14L)
})
