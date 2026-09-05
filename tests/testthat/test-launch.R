test_that("desk_env() derives the app's variables from the desk folder", {
  home <- local_desk_home()
  env <- omicsDesk:::desk_env()
  expect_identical(env[["OMICSAPP_DATA_DIR"]], file.path(home, "projects"))
  expect_identical(env[["OMICSCORE_GENESET_CACHE"]], file.path(home, "genesets"))
  expect_identical(env[["OMICSCORE_GENESET_TTL_DAYS"]], "0")
  expect_identical(env[["OMICSCORE_OFFLINE"]], "1")
  expect_false("RSTUDIO_PANDOC" %in% names(env))
})

test_that("online = TRUE leaves the refresh knobs alone", {
  home <- local_desk_home()
  env <- omicsDesk:::desk_env(online = TRUE)
  expect_false(any(c("OMICSCORE_GENESET_TTL_DAYS", "OMICSCORE_OFFLINE") %in% names(env)))
})

test_that("a data_dir argument and pre-set variables win over the defaults", {
  home <- local_desk_home()
  env <- omicsDesk:::desk_env(data_dir = "/somewhere/else")
  expect_identical(env[["OMICSAPP_DATA_DIR"]], "/somewhere/else")

  withr::local_envvar(OMICSAPP_DATA_DIR = "/preset/projects",
                      OMICSCORE_GENESET_CACHE = "/preset/genesets")
  env <- omicsDesk:::desk_env()
  expect_identical(env[["OMICSAPP_DATA_DIR"]], "/preset/projects")
  expect_identical(env[["OMICSCORE_GENESET_CACHE"]], "/preset/genesets")
})

test_that("a pandoc in the desk folder is offered to rmarkdown, unless the caller chose one", {
  home <- local_desk_home()
  pandoc_dir <- omicsDesk:::ensure_dir(desk_paths()$pandoc)
  exe <- if (.Platform$OS.type == "windows") "pandoc.exe" else "pandoc"
  writeLines("", file.path(pandoc_dir, exe))
  expect_identical(omicsDesk:::desk_env()[["RSTUDIO_PANDOC"]], pandoc_dir)

  withr::local_envvar(RSTUDIO_PANDOC = "/my/own/pandoc")
  expect_false("RSTUDIO_PANDOC" %in% names(omicsDesk:::desk_env()))
})

test_that("launch() runs the app under the desk environment and restores it afterwards", {
  home <- local_desk_home()
  captured <- NULL
  testthat::local_mocked_bindings(
    run_app = function(...) {
      captured <<- list(
        args = list(...),
        env = Sys.getenv(c("OMICSAPP_DATA_DIR", "OMICSCORE_GENESET_CACHE",
                           "OMICSCORE_GENESET_TTL_DAYS", "OMICSCORE_OFFLINE"),
                         unset = NA))
      invisible(NULL)
    },
    refresh_pandoc_lookup = function() invisible(NULL)
  )

  expect_message(launch(project = "x.omp", port = 4242L, workers = 0L), "omicsDesk")
  expect_identical(captured$args$project, "x.omp")
  expect_identical(captured$args$port, 4242L)
  expect_identical(captured$args$workers, 0L)
  expect_false(captured$args$launch.browser)
  expect_identical(unname(captured$env["OMICSAPP_DATA_DIR"]), file.path(home, "projects"))
  expect_identical(unname(captured$env["OMICSCORE_GENESET_TTL_DAYS"]), "0")
  expect_identical(unname(captured$env["OMICSCORE_OFFLINE"]), "1")
  expect_true(dir.exists(file.path(home, "projects")))

  after <- Sys.getenv(c("OMICSAPP_DATA_DIR", "OMICSCORE_GENESET_CACHE",
                        "OMICSCORE_GENESET_TTL_DAYS", "OMICSCORE_OFFLINE"), unset = NA)
  expect_true(all(is.na(after)))
})

test_that("launch(quiet = TRUE) prints nothing", {
  home <- local_desk_home()
  testthat::local_mocked_bindings(run_app = function(...) invisible(NULL),
                                  refresh_pandoc_lookup = function() invisible(NULL))
  expect_silent(launch(quiet = TRUE, workers = 0L))
})
