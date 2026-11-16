# Restored baseline checks

The user requested exact rollback to pre-gap-buffer XVI2 and untouched recovered
VTUI. Do not modernize those sources as part of the rollback. Provenance is in
docs/RESTORATION.md. The previous gap-buffer suites were removed with the code
they exercised; do not claim that they cover the restored editors.

Run `prove -v t/*.t` to verify exact source/binary identities. Build XVI2 with
pinned Prog8 12.0.1 and default optimization. VTUI is an archival recovery, not
a reproducible compilation of the recovered source. Record any later change to
that boundary explicitly rather than silently patching the historical source.
