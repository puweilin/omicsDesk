bundle_file <- function(name) system.file("bundle", name, package = "omicsDesk")

test_that("the installer script parses, defines the installer, and does not run on source()", {
  env <- new.env(parent = globalenv())
  expect_silent(sys.source(bundle_file("INSTALL.R"), envir = env))
  expect_true(is.function(env$install_offline_bundle))
  parsed <- env$parse_package_field("a (1.0), b, c (2.1.3)")
  expect_identical(parsed$package, c("a", "b", "c"))
  expect_identical(parsed$version, c("1.0", NA, "2.1.3"))
  expect_identical(env$r_minor(), omicsDesk:::r_minor_version())
})

test_that("the launchers start START.R, and START.R starts omicsDesk", {
  bat <- readLines(bundle_file("omicsDesk.bat"))
  cmd <- readLines(bundle_file("omicsDesk.command"))
  expect_true(any(grepl("START.R", bat, fixed = TRUE)))
  expect_true(any(grepl("START.R", cmd, fixed = TRUE)))
  expect_true(grepl("^#!/bin/bash", cmd[[1L]]))
  start <- readLines(bundle_file("START.R"))
  expect_true(any(grepl("omicsDesk::launch(browser = TRUE)", start, fixed = TRUE)))
  expect_true(any(grepl("BUNDLE", start, fixed = TRUE)))
})

test_that("the README template has every placeholder the builder fills", {
  readme <- readLines(bundle_file("README.bundle.md"))
  for (k in c("VERSION", "PLATFORM", "RMINOR", "BUILT", "PACKAGE_COUNT", "PANDOC", "SOURCE_ONLY_NOTE")) {
    expect_true(any(grepl(paste0("{{", k, "}}"), readme, fixed = TRUE)), info = k)
  }
})

test_that("the prewarm script's collection map agrees with omicsCore's", {
  script <- readLines(source_tree_file("tools", "prewarm_genesets.R"))
  block <- script[seq(grep("^COLLECTIONS <- list\\(", script), length(script))]
  block <- block[seq_len(grep("^\\)", block)[[1L]])]
  keys <- sub("^\\s*([a-z_]+)\\s*=.*$", "\\1", grep("collection = ", block, value = TRUE))
  expect_setequal(keys, getFromNamespace("SUPPORTED_ENRICH_DATABASES", "omicsCore"))
  map <- getFromNamespace("DB_MSIGDBR_MAP", "omicsCore")
  for (k in keys) {
    line <- grep(paste0("^\\s*", k, "\\s*="), block, value = TRUE)
    expect_true(grepl(paste0('collection = "', map[[k]]$collection, '"'), line), info = k)
    sub <- map[[k]]$subcollection
    expected <- if (is.na(sub)) "NA_character_" else paste0('"', sub, '"')
    expect_true(grepl(paste0("subcollection = ", expected), line, fixed = TRUE), info = k)
  }
})

test_that("the builder ships the files the installer and launchers expect", {
  builder <- readLines(source_tree_file("tools", "build_bundle.R"))
  for (f in c("INSTALL.R", "START.R", "omicsDesk.bat", "omicsDesk.command", "README.bundle.md")) {
    expect_true(any(grepl(f, builder, fixed = TRUE)), info = f)
    expect_true(nzchar(bundle_file(f)), info = f)
  }
  for (field in c("RMinor", "Packages", "SourceOnly", "Pandoc", "Genesets")) {
    expect_true(any(grepl(paste0(field, " = "), builder, fixed = TRUE)), info = field)
  }
})
