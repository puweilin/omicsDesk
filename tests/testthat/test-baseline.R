test_that("source builds refuse version and revision drift", {
  env <- new.env(parent = globalenv())
  sys.source(source_tree_file("tools", "baseline.R"), env)
  root <- withr::local_tempdir()
  upstream <- withr::local_tempdir()
  sha <- paste(rep("a", 40), collapse = "")
  write.dcf(rbind(c(Package = "omicsDesk", Version = "0.2.0", `Config/omicsDesk/UpstreamRef` = sha)),
            file.path(root, "DESCRIPTION"))
  for (pkg in c("omicsCore", "omicsApp")) {
    dir <- file.path(upstream, "packages", pkg)
    dir.create(dir, recursive = TRUE)
    write.dcf(rbind(c(Package = pkg, Version = "0.2.0")), file.path(dir, "DESCRIPTION"))
  }
  expect_identical(env$check_upstream_baseline(root, upstream, sha), sha)
  expect_error(env$check_upstream_baseline(root, upstream, paste0(sha, " dirty")), "pinned baseline")
  expect_warning(env$check_upstream_baseline(root, upstream, "other", TRUE), "Development build")
  write.dcf(rbind(c(Package = "omicsApp", Version = "0.1.0")),
            file.path(upstream, "packages", "omicsApp", "DESCRIPTION"))
  expect_error(env$check_upstream_baseline(root, upstream, sha), "Version baseline mismatch")
})

test_that("doctor distinguishes missing source records from a wrong shared revision", {
  local_desk_home()
  ref <- utils::packageDescription("omicsDesk", fields = "Config/omicsDesk/UpstreamRef")
  testthat::local_mocked_bindings(package_source_sha = function(pkg) ref)
  d <- doctor(workers = FALSE, quiet = TRUE)
  expect_true(d$ok[d$check == "upstream source"])
  testthat::local_mocked_bindings(package_source_sha = function(pkg) if (pkg == "omicsCore") ref else "other")
  d <- doctor(workers = FALSE, quiet = TRUE)
  expect_false(d$ok[d$check == "upstream source"])
  expect_true(d$required[d$check == "upstream source"])
})
