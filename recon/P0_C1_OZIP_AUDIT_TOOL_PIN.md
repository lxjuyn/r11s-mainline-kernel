# P0-C1 OZIP audit-tool pin

Date: 2026-07-30

This record documents a host-side source pin only. No dependency was installed, no tool was executed, and the R11s C.19 OZIP payload was not decrypted or extracted.

- Candidate: bkerler/oppo_ozip_decrypt
- Git commit: eb93b3f3fb7be3564cc546c88699ab4062a04928 (2022-11-07)
- Source archive: out/oppo_ozip_decrypt-eb93b3f3fb7be3564cc546c88699ab4062a04928.tar.gz
- Archive SHA-256: 7196a7fc7c112d3bc0869601ec8c048f802a95cfff91d89a32e09ebe52aaa9bd
- Commit tree: 7cb01ecc36c4c25bb85f6e43bcefe84e91d4042c
- Declared dependency: pycryptodome

Static review found the script reads input, creates temp/out directories next to the input, writes a ZIP output, and can remove and rename files. It must not run against the preserved original OZIP. Any future use needs a copied input, a disposable isolated work directory, a separately pinned dependency environment, recorded commands/hashes, and explicit scope approval for payload extraction.

The tool is third-party code, not an OPPO verification mechanism. Its availability does not establish firmware provenance, signature validity, compatible partitions, boot-chain behavior, or permission for device actions.
