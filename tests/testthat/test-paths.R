test_that("the desk folder defaults to ~/omicsDesk and follows OMICSDESK_HOME", {
  withr::local_envvar(OMICSDESK_HOME = NA)
  expect_identical(desk_home(), path.expand("~/omicsDesk"))

  withr::local_envvar(OMICSDESK_HOME = "/tmp/elsewhere")
  expect_identical(desk_home(), "/tmp/elsewhere")
  p <- desk_paths()
  expect_identical(p$home, "/tmp/elsewhere")
  expect_identical(p$projects, file.path("/tmp/elsewhere", "projects"))
  expect_identical(p$genesets, file.path("/tmp/elsewhere", "genesets"))
  expect_identical(p$pandoc, file.path("/tmp/elsewhere", "pandoc"))
})

test_that("desk_paths() creates nothing", {
  home <- local_desk_home()
  desk_paths()
  expect_false(dir.exists(file.path(home, "projects")))
})

test_that("pandoc_in() finds an executable only where there is one", {
  dir <- withr::local_tempdir()
  expect_identical(omicsDesk:::pandoc_in(dir), "")
  expect_identical(omicsDesk:::pandoc_in(""), "")
  exe <- if (.Platform$OS.type == "windows") "pandoc.exe" else "pandoc"
  writeLines("", file.path(dir, exe))
  expect_identical(omicsDesk:::pandoc_in(dir), file.path(dir, exe))
})
