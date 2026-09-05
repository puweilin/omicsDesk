# A real, tiny bundle: one package built on the fly, a local repository
# with an index, a BUNDLE record. install_offline() must install it into
# a library of our choosing and leave the record in the desk folder.

make_fake_bundle <- function(dir, r_minor = omicsDesk:::r_minor_version(),
                             with_pandoc = TRUE) {
  pkg <- file.path(dir, "src", "fakepkg")
  dir.create(file.path(pkg, "R"), recursive = TRUE)
  writeLines(c("Package: fakepkg", "Version: 0.1.0", "Title: Fake",
               "Description: A package for the installer test.",
               "License: MIT + file LICENSE", "Encoding: UTF-8",
               "Author: test", "Maintainer: test <test@example.org>"),
             file.path(pkg, "DESCRIPTION"))
  writeLines(c("YEAR: 2026", "COPYRIGHT HOLDER: test"), file.path(pkg, "LICENSE"))
  writeLines("hello <- function() 'hi'", file.path(pkg, "R", "hello.R"))
  writeLines("export(hello)", file.path(pkg, "NAMESPACE"))

  bundle <- file.path(dir, "bundle")
  src_contrib <- file.path(bundle, "repo", "src", "contrib")
  dir.create(src_contrib, recursive = TRUE)
  withr::with_dir(src_contrib, {
    r_bin <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R")
    status <- system2(r_bin, c("CMD", "build", "--no-build-vignettes", "--no-manual", shQuote(pkg)),
                      stdout = FALSE, stderr = FALSE)
    stopifnot(identical(status, 0L))
  })
  tools::write_PACKAGES(src_contrib, type = "source", verbose = FALSE)
  write.dcf(rbind(c(Bundle = "omicsDesk", Version = "0.0.0.9000", RMinor = r_minor,
                    Platform = R.version$platform, Built = "2026-01-01 00:00:00",
                    Packages = "fakepkg (0.1.0)")),
            file.path(bundle, "BUNDLE"))
  if (with_pandoc) {
    dir.create(file.path(bundle, "pandoc"))
    writeLines("#!/bin/sh\necho pandoc 0.0", file.path(bundle, "pandoc", "pandoc"))
  }
  bundle
}

test_that("install_offline() installs from the bundle's repository into the given library", {
  skip_on_cran()
  home <- local_desk_home()
  work <- withr::local_tempdir()
  bundle <- make_fake_bundle(work)
  lib <- file.path(work, "lib")
  old_libs <- .libPaths()
  withr::defer(.libPaths(old_libs))

  expect_message(res <- install_offline(bundle, lib = lib, quiet = TRUE), "is installed")
  expect_true(dir.exists(file.path(lib, "fakepkg")))
  expect_identical(res$installed, "fakepkg")
  expect_identical(normalizePath(res$lib), normalizePath(lib))

  record <- read.dcf(file.path(home, "BUNDLE"))
  expect_identical(unname(record[1L, "Packages"]), "fakepkg (0.1.0)")
  expect_identical(normalizePath(unname(record[1L, "Library"])), normalizePath(lib))
  expect_true(file.exists(file.path(home, "pandoc", "pandoc")))

  # Second run: nothing to do.
  expect_message(install_offline(bundle, lib = lib, quiet = TRUE), "already installed")
})

test_that("a bundle for another R minor version is refused unless forced", {
  skip_on_cran()
  home <- local_desk_home()
  work <- withr::local_tempdir()
  bundle <- make_fake_bundle(work, r_minor = "1.0", with_pandoc = FALSE)
  expect_error(install_offline(bundle, lib = file.path(work, "lib")), "built for R 1.0")
})

test_that("a folder that is not a bundle is refused", {
  expect_error(install_offline(withr::local_tempdir()), "No BUNDLE file")
})
