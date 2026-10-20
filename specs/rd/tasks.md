# Tasks: rd

- [x] 1. Copy the shared Windows code into `source/win/` (f601bf9)
  - _Requirements: 1.4, 5.1_
- [x] 2. Parse `/S` and `/Q`
  - _Requirements: 5.1, 5.2, 5.3_
- [x] 3. Decide per operand without changing anything: names, missing, files, links, `.`, `..`, the root
  - _Requirements: 1.2, 3.4, 4.1–4.6_
- [x] 4. Remove empty directories and links to directories; verify on disk
  - _Requirements: 1.1, 3.1, 4.5_
- [x] 5. `/S`: unlink first, enter only confirmed directories, rmdir when empty; report leftovers
  - _Requirements: 2.1, 2.4, 3.2, 3.3_
- [x] 6. The `Are you sure (Y/N)?` question, one line of stdin at a time; `/Q`
  - _Requirements: 2.2, 2.3, 2.5_
- [x] 7. Exit codes; several operands; the `rmdir` link
  - _Requirements: 1.3, 4.7, 5.4_
- [x] 8. Unit tests and end-to-end tests of the native binary (link targets outside the tree)
  - _Requirements: all_
