test_that("with_envvar() sets for the call and restores after it, including unset", {
  withr::local_envvar(OMICSDESK_TEST_A = "before", OMICSDESK_TEST_B = NA)
  seen <- omicsDesk:::with_envvar(
    c(OMICSDESK_TEST_A = "during", OMICSDESK_TEST_B = "new"),
    Sys.getenv(c("OMICSDESK_TEST_A", "OMICSDESK_TEST_B")))
  expect_identical(unname(seen), c("during", "new"))
  expect_identical(Sys.getenv("OMICSDESK_TEST_A"), "before")
  expect_identical(Sys.getenv("OMICSDESK_TEST_B", unset = NA), NA_character_)
})

test_that("with_envvar() restores even when the code errors", {
  withr::local_envvar(OMICSDESK_TEST_A = "before")
  expect_error(omicsDesk:::with_envvar(c(OMICSDESK_TEST_A = "during"), stop("boom")), "boom")
  expect_identical(Sys.getenv("OMICSDESK_TEST_A"), "before")
})

test_that("env_or() prefers a non-empty variable", {
  withr::local_envvar(OMICSDESK_TEST_A = "", OMICSDESK_TEST_B = "set")
  expect_identical(omicsDesk:::env_or("OMICSDESK_TEST_A", "default"), "default")
  expect_identical(omicsDesk:::env_or("OMICSDESK_TEST_B", "default"), "set")
})
