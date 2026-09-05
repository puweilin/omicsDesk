test_that("doctor() reports every check and passes on a complete machine", {
  skip_if_no_bundled_genesets()
  home <- local_desk_home()
  d <- doctor(workers = FALSE, quiet = TRUE)
  expect_s3_class(d, "desk_doctor")
  expect_true(all(c("check", "ok", "required", "detail", "fix") %in% colnames(d)))
  expect_true("R version" %in% d$check)
  expect_true(all(paste0("packages: ", names(omicsDesk:::DESK_BACKENDS)) %in% d$check))
  expect_true(all(c("gene sets", "HTML reports", "PDF reports", "projects folder") %in% d$check))
  expect_false("background worker" %in% d$check)

  pkg_rows <- d[startsWith(d$check, "packages: "), ]
  expect_true(all(pkg_rows$ok), info = paste(pkg_rows$detail[!pkg_rows$ok], collapse = "; "))
  expect_true(d$ok[d$check == "gene sets"], info = d$detail[d$check == "gene sets"])
  expect_true(d$ok[d$check == "projects folder"])
  expect_false(d$required[d$check == "PDF reports"])
})

test_that("a missing engine is named, with the fix", {
  home <- local_desk_home()
  testthat::local_mocked_bindings(has_pkg = function(pkg) pkg != "DESeq2")
  d <- doctor(workers = FALSE, quiet = TRUE)
  row <- d[d$check == "packages: rnaseq", ]
  expect_false(row$ok)
  expect_match(row$detail, "missing: DESeq2")
  expect_match(row$fix, "INSTALL.R")
  expect_true(d$ok[d$check == "packages: proteomics"])
})

test_that("a bundle built for another R is caught", {
  home <- local_desk_home()
  write.dcf(rbind(c(Bundle = "omicsDesk", Version = "9.9.9", RMinor = "9.9",
                    Platform = "test", Built = "never")),
            file.path(home, "BUNDLE"))
  d <- doctor(workers = FALSE, quiet = TRUE)
  row <- d[d$check == "R version", ]
  expect_false(row$ok)
  expect_match(row$detail, "built for R 9.9")
})

test_that("printing marks required failures and offers fixes", {
  home <- local_desk_home()
  testthat::local_mocked_bindings(has_pkg = function(pkg) pkg != "GSVA")
  d <- doctor(workers = FALSE, quiet = TRUE)
  out <- capture.output(print(d))
  expect_true(any(grepl("^\\[!!\\] packages: enrichment", out)))
  expect_true(any(grepl("^\\[ok\\] R version", out)))
  expect_true(any(grepl("To fix:", out)))
  expect_true(any(grepl("packages: enrichment: run the bundle", out)))
})

test_that("the worker check sees the same library", {
  skip_on_cran()
  home <- local_desk_home()
  w <- omicsDesk:::check_worker()
  expect_true(w$ok, info = w$detail)
})
