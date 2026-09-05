test_that("the package ships all 14 tables and a manifest that matches them", {
  skip_if_no_bundled_genesets()
  dir <- omicsDesk:::bundled_geneset_dir()
  expect_setequal(list.files(dir, pattern = "\\.qs2$"), omicsDesk:::expected_geneset_files())
  m <- omicsDesk:::read_manifest(dir)
  expect_false(is.null(m))
  files <- omicsDesk:::manifest_files(m)
  expect_setequal(files$file, omicsDesk:::expected_geneset_files())
  for (i in seq_len(nrow(files))) {
    expect_identical(omicsDesk:::md5_of(file.path(dir, files$file[[i]])), files$md5[[i]],
                     info = files$file[[i]])
  }
  expect_match(m$msigdb_release, "^[0-9]{4}\\.[0-9]+$|^[0-9]+\\.[0-9]+")
})

test_that("sync copies the shipped tables once, then leaves them alone", {
  skip_if_no_bundled_genesets()
  home <- local_desk_home()
  first <- sync_geneset_cache(quiet = TRUE)
  expect_length(first$copied, 14L)
  expect_length(first$kept, 0L)
  target <- desk_paths()$genesets
  expect_setequal(list.files(target, pattern = "\\.qs2$"), omicsDesk:::expected_geneset_files())
  expect_true(file.exists(file.path(target, "MANIFEST.json")))

  second <- sync_geneset_cache(quiet = TRUE)
  expect_length(second$copied, 0L)
  expect_length(second$current, 14L)
})

test_that("sync never overwrites a table the user changed", {
  skip_if_no_bundled_genesets()
  home <- local_desk_home()
  sync_geneset_cache(quiet = TRUE)
  mine <- file.path(desk_paths()$genesets, "kegg__Homo_sapiens.qs2")
  write_geneset_table(mine, gs_source = "KEGG REST 2026-01-01")
  my_md5 <- omicsDesk:::md5_of(mine)

  again <- sync_geneset_cache(quiet = TRUE)
  expect_identical(again$kept, "kegg__Homo_sapiens.qs2")
  expect_identical(omicsDesk:::md5_of(mine), my_md5)
})

test_that("a file the user dropped in without a record is treated as theirs", {
  skip_if_no_bundled_genesets()
  home <- local_desk_home()
  target <- omicsDesk:::ensure_dir(desk_paths()$genesets)
  mine <- file.path(target, "hallmark__Homo_sapiens.qs2")
  write_geneset_table(mine)
  my_md5 <- omicsDesk:::md5_of(mine)
  res <- sync_geneset_cache(quiet = TRUE)
  expect_identical(res$kept, "hallmark__Homo_sapiens.qs2")
  expect_length(res$copied, 13L)
  expect_identical(omicsDesk:::md5_of(mine), my_md5)
})

test_that("geneset_status() sees every table through omicsCore", {
  skip_if_no_bundled_genesets()
  home <- local_desk_home()
  st <- geneset_status()
  expect_equal(nrow(st), 14L)
  expect_true(all(st$cached))
  expect_true(all(st$n_sets > 0L))
  expect_true(all(grepl("^MSigDB msigdbr", st$source)))
  expect_setequal(unique(st$organism), unname(omicsDesk:::DESK_GENESET_ORGANISMS))
})

test_that("import refuses bad names and unreadable tables before copying anything", {
  home <- local_desk_home()
  bad_name <- withr::local_tempfile(fileext = ".qs2")
  write_geneset_table(bad_name)
  expect_error(import_geneset_cache(bad_name), "Not a gene-set cache file name")

  dir <- withr::local_tempdir()
  wrong_db <- file.path(dir, "pfam__Homo_sapiens.qs2")
  write_geneset_table(wrong_db)
  expect_error(import_geneset_cache(wrong_db), "Unsupported database")

  garbage <- file.path(dir, "hallmark__Homo_sapiens.qs2")
  qs2::qs_save(list(not = "a table"), garbage)
  expect_error(import_geneset_cache(garbage), "Not a readable gene-set table")
  expect_false(file.exists(file.path(desk_paths()$genesets, "hallmark__Homo_sapiens.qs2")))

  expect_error(import_geneset_cache(file.path(dir, "nope")), "existing")
})

test_that("import copies a valid table and records where it came from", {
  home <- local_desk_home()
  dir <- withr::local_tempdir()
  f <- file.path(dir, "kegg__Mus_musculus.qs2")
  write_geneset_table(f, gs_source = "KEGG REST 2026-02-02", n_sets = 5L)
  expect_message(res <- import_geneset_cache(f), "local use only")
  expect_identical(res$database, "kegg")
  expect_identical(res$organism, "Mus musculus")
  expect_identical(res$n_sets, 5L)

  target <- desk_paths()$genesets
  expect_true(file.exists(file.path(target, "kegg__Mus_musculus.qs2")))
  rec <- omicsDesk:::manifest_files(omicsDesk:::read_manifest(target))
  expect_identical(rec$origin[rec$file == "kegg__Mus_musculus.qs2"], "import")
  expect_identical(rec$gs_source[rec$file == "kegg__Mus_musculus.qs2"], "KEGG REST 2026-02-02")

  # And omicsCore reads it.
  st <- withr::with_envvar(c(OMICSCORE_GENESET_CACHE = target),
                           omicsCore::geneset_cache_status("kegg", organism = "Mm"))
  expect_true(st$cached)
  expect_identical(st$source, "KEGG REST 2026-02-02")
})

test_that("import accepts a directory and validates all of it first", {
  home <- local_desk_home()
  dir <- withr::local_tempdir()
  write_geneset_table(file.path(dir, "hallmark__Homo_sapiens.qs2"))
  qs2::qs_save(data.frame(x = 1), file.path(dir, "reactome__Homo_sapiens.qs2"))
  expect_error(import_geneset_cache(dir, quiet = TRUE), "Not a readable")
  expect_false(file.exists(file.path(desk_paths()$genesets, "hallmark__Homo_sapiens.qs2")))

  unlink(file.path(dir, "reactome__Homo_sapiens.qs2"))
  res <- import_geneset_cache(dir, quiet = TRUE)
  expect_identical(res$file, "hallmark__Homo_sapiens.qs2")
})

test_that("export leaves live-KEGG tables behind unless told otherwise", {
  home <- local_desk_home()
  target <- omicsDesk:::ensure_dir(desk_paths()$genesets)
  write_geneset_table(file.path(target, "hallmark__Homo_sapiens.qs2"), gs_source = "MSigDB msigdbr 25.1.1")
  write_geneset_table(file.path(target, "kegg__Homo_sapiens.qs2"), gs_source = "KEGG REST 2026-03-03")

  dest <- withr::local_tempdir()
  expect_message(out <- export_geneset_cache(dest), "Skipped live-KEGG")
  expect_identical(basename(out), "hallmark__Homo_sapiens.qs2")

  dest2 <- withr::local_tempdir()
  expect_silent(out2 <- export_geneset_cache(dest2, include_kegg_live = TRUE))
  expect_setequal(basename(out2), c("hallmark__Homo_sapiens.qs2", "kegg__Homo_sapiens.qs2"))
})

test_that("export with nothing to export says so", {
  home <- local_desk_home()
  withr::local_envvar(OMICSDESK_HOME = withr::local_tempdir())
  # No bundled tables in this fake package dir: point sync at nothing.
  expect_error(
    withr::with_options(list(), {
      testthat::local_mocked_bindings(bundled_geneset_dir = function() "")
      export_geneset_cache(withr::local_tempdir())
    }),
    "No gene-set tables")
})
