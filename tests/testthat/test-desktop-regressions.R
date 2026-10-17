test_that("all upstream optional engine groups are available offline", {
  groups <- getFromNamespace("OPTIONAL_GROUPS", "omicsCore")
  imports <- trimws(sub("\\s*\\(.*", "", strsplit(
    utils::packageDescription("omicsDesk")$Imports, ",")[[1L]]))
  # patchwork is a hard dependency of omicsCore itself.
  core <- utils::packageDescription("omicsCore")
  core_imports <- trimws(sub("\\s*\\(.*", "", strsplit(core$Imports, ",")[[1L]]))
  expect_length(setdiff(unique(unlist(groups)), c(imports, core_imports)), 0L)
})

test_that("an imported table survives status, doctor and launch preparation", {
  skip_if_no_bundled_genesets()
  local_desk_home()
  sync_geneset_cache()
  incoming <- withr::local_tempdir()
  path <- file.path(incoming, "kegg__Homo_sapiens.qs2")
  write_geneset_table(path, gs_source = "KEGG REST local import", n_sets = 2L)
  import_geneset_cache(path, quiet = TRUE)
  target <- file.path(desk_paths()$genesets, basename(path))
  checksum <- unname(tools::md5sum(target))
  expect_equal(geneset_status()$n_sets[geneset_status()$database == "kegg" &
                                      geneset_status()$organism == "Homo sapiens"], 2L)
  doctor(workers = FALSE, quiet = TRUE)
  omicsDesk:::desk_env()
  expect_identical(unname(tools::md5sum(target)), checksum)
  rows <- omicsDesk:::manifest_files(omicsDesk:::read_manifest(dirname(target)))
  expect_equal(rows$origin[rows$file == basename(path)], "import")
})

test_that("an unchanged bundled table can be upgraded but unknown provenance is kept", {
  local_desk_home()
  source <- withr::local_tempdir()
  target <- withr::local_tempdir()
  path <- file.path(source, "hallmark__Homo_sapiens.qs2")
  write_geneset_table(path, n_sets = 2L)
  sync_geneset_cache(target, source)
  write_geneset_table(path, n_sets = 4L)
  expect_equal(sync_geneset_cache(target, source)$copied, basename(path))
  expect_equal(omicsDesk:::geneset_table_info(file.path(target, basename(path)))$n_sets, 4L)
  writeLines('{"files":[{"file":"hallmark__Homo_sapiens.qs2","md5":"old"}]}',
             file.path(target, "MANIFEST.json"))
  write_geneset_table(path, n_sets = 5L)
  expect_equal(sync_geneset_cache(target, source)$kept, basename(path))
})

test_that("an explicit cache directory receives tables used by the app", {
  local_desk_home()
  cache <- withr::local_tempdir()
  withr::local_envvar(OMICSCORE_GENESET_CACHE = cache)
  env <- omicsDesk:::desk_env()
  expect_equal(env[["OMICSCORE_GENESET_CACHE"]], cache)
  expect_true(all(geneset_status()$cached))
  expect_setequal(list.files(cache, pattern = "\\.qs2$"), omicsDesk:::expected_geneset_files())
})

test_that("desktop launches use independent workers and restore the plan on errors", {
  local_desk_home()
  old <- future::plan()
  pid <- NULL
  testthat::local_mocked_bindings(
    run_app = function(...) {
      expect_equal(list(...)$workers, 0L)
      expect_s3_class(future::plan(), "multisession")
      pid <<- future::value(future::future(Sys.getpid()))
      stop("simulated app failure")
    }, refresh_pandoc_lookup = function() invisible(NULL))
  expect_error(launch(workers = 1L, quiet = TRUE), "simulated app failure")
  expect_false(identical(pid, Sys.getpid()))
  expect_identical(class(future::plan()), class(old))
  expect_identical(body(future::plan()), body(old))
  expect_identical(Sys.getenv("OMICSCORE_OFFLINE", unset = NA_character_), NA_character_)
})

test_that("invalid launch arguments fail before touching disk or starting workers", {
  local_desk_home()
  testthat::local_mocked_bindings(run_app = function(...) stop("app must not start"))
  for (value in list(NA, Inf, -1, 0.5, "2", c(1, 2), NULL)) {
    expect_error(launch(workers = value), "workers")
  }
  expect_error(launch(online = NA), "online")
  expect_error(launch(data_dir = NA_character_), "data_dir")
  expect_error(import_geneset_cache(NA_character_), "path")
  expect_error(doctor(workers = NA), "workers")
})

test_that("doctor starts a real process", {
  skip_on_cran()
  local_desk_home()
  status <- omicsDesk:::check_worker()
  expect_true(status$ok, info = status$detail)
  expect_false(identical(status$pid, status$parent_pid))
})

test_that("integrity failures and platform mismatches stop before installation", {
  local_desk_home()
  env <- new.env(parent = globalenv())
  sys.source(system.file("bundle", "INSTALL.R", package = "omicsDesk"), envir = env)
  bundle <- withr::local_tempdir()
  writeLines("original", file.path(bundle, "content"))
  hash <- unname(tools::md5sum(file.path(bundle, "content")))
  writeLines(paste0(hash, "  content"), file.path(bundle, "MD5SUMS"))
  expect_true(env$verify_bundle_integrity(bundle))
  writeLines("changed", file.path(bundle, "content"))
  expect_error(env$verify_bundle_integrity(bundle), "checksum mismatch")
  writeLines(paste0(hash, "  ../content"), file.path(bundle, "MD5SUMS"))
  expect_error(env$verify_bundle_integrity(bundle), "Unsafe")
  unlink(file.path(bundle, "MD5SUMS"))
  expect_error(env$verify_bundle_integrity(bundle, required = TRUE), "Missing MD5SUMS")
  write.dcf(rbind(c(Bundle = "omicsDesk", Version = "0.1.0", RMinor = env$r_minor(),
                    Platform = "another-platform", Packages = "fakepkg (1.0)")),
            file.path(bundle, "BUNDLE"))
  lib <- file.path(bundle, "library-must-not-be-created")
  expect_error(env$install_offline_bundle(bundle, lib = lib), "for this platform")
  expect_false(dir.exists(lib))
})
