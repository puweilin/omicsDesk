# omicsDesk 0.1.0

* Align the desktop distribution with omicsApp f3c2ff4, including applied
  per-layer QC, analysis provenance, reproducible scripts and smaller worker payloads.
* Use independent multisession workers on desktop systems, including macOS;
  doctor now verifies an actual child process and the current PDF toolchain.
* Keep imported gene-set tables across sync, status checks, upgrades and restarts;
  honour custom cache directories and check staged writes.
* Include all current optional engine groups, including RNA import and plot helpers.
* Verify bundle checksums and platform before installing; replace first-party
  packages even when their development versions have not changed.
* Build in isolated directories, record upstream provenance, and verify the final
  ZIP with real analyses, independent-process script replay and optional browser checks.
* Companion omicsCore fixes enforce offline mode, invalidate stale in-memory
  gene sets and remove the remote MathJax dependency from default HTML reports.
* Companion omicsApp fixes restore saved analyses on the first session flush
  and retain their layer and model controls when browser inputs initialise.

# omicsDesk 0.0.0.9000

* First skeleton: `launch()`, `doctor()`, `install_offline()`, the gene-set
  cache helpers, the bundled MSigDB tables, and the bundle builder in
  `tools/`.
