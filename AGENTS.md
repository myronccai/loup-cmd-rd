# AGENTS.md

This repository recreates the Windows `rd` (and `rmdir`) command in the
Loup programming language, as part of the loup-cmd series of example
applications. The program is `host.dual` Loup built as a native executable
for Linux, with cmd's switch, path and message conventions, its question
and exit codes. It removes trees without ever following a symbolic link.
`source/win/` is a copy of the shared Windows code (master: loup-cmd-type).

## Skills

| Skill | Location | Use it when |
|-------|----------|-------------|
| `loup-programmer` | [skills/loup-programmer/SKILL.md](skills/loup-programmer/SKILL.md) | Writing, reviewing, debugging or explaining Loup code: `.lpscr`, `.loup`, `.lphc`, `.lpweb` or `.lpfree` source files, `.lppkg` manifests, `@mode(...)` directives, or the `loup` / `loup-bootstrap` commands. |

Read `skills/loup-programmer/SKILL.md` before writing or changing any Loup code
in this repository. It links to detailed references under
`skills/loup-programmer/references/` for syntax, types and ownership, execution
modes and projects, errors and diagnostics, the standard library, and common
mistakes. Load those only as needed.

## Code layout

```text
.
├── package.lppkg                # Loup manifest: name, version, toolchain, [build] entry, [test] pattern
├── Makefile                     # run, check, test, build, e2e, ci, clean
├── source/                      # all Loup code; modules import each other by path from here
│   ├── main.loup                # entry point: func main() calls run(runtime.args())
│   ├── appinfo.loup             # APP_NAME, APP_VERSION, APP_SUMMARY, exit statuses (Windows codes)
│   ├── cli/
│   │   ├── args.loup            # struct Options, rd_switches() (/S /Q), parse_args()
│   │   ├── usage.loup           # usage() (the /? help text), version_line()
│   │   └── app.loup             # run(): parse, /? and --version, run_rd, exit status
│   ├── commands/
│   │   ├── rd.loup              # operand_message(), action_for(), remove_operand(), run_rd()
│   │   ├── deltree.loup         # remove_tree(): unlink first, enter only real directories
│   │   └── prompt.loup          # Y/N question; read_line() via a `sh` child
│   └── win/                     # shared Windows code (a copy; see below)
│       ├── switches.loup        # cmd switch parser: /S -s /A:H /AH /T 10 /S/Q /? --
│       ├── wildcard.loup        # Win32 wildcard matcher, expand(), find_recursive()
│       ├── paths.loup           # fs_path(), display_path(), split/join helpers
│       └── messages.loup        # Windows message texts
├── tests/
│   ├── *_test.loup              # unit tests: func test_*(): void (win_*_test.loup test source/win/)
│   └── e2e.sh                   # end-to-end tests of the native binary
├── specs/rd/                    # requirements.md, design.md, tasks.md for the command
├── skills/loup-programmer/      # the Loup skill and its references
├── .github/workflows/ci.yml     # installs Loup and runs `make ci`
└── build/                       # build output (git-ignored); unit tests write fixtures to build/tmp/
```

## Build, run and test

Prerequisites: Loup 1.26.0 (`loup` and `loup-bootstrap` on `PATH`), `make`,
and `clang` 17 or later for native builds.

Loup Lite comes from <https://github.com/code-craft-ai-company/loup-releases>;
[README.md](README.md#installing-loup-lite) has the install commands.

| Task | Command | Notes |
|------|---------|-------|
| Run from source | `make run ARGS="/S /Q build/tmp/old"` | `loup-bootstrap run source/main.loup -- ARGS` (Stage0: questions read no stdin there, use `/Q`) |
| Type-check | `make check` | checks `source/main.loup` and every module it imports; tests are not checked |
| Run all tests | `make test` | every `tests/*_test.loup`, one at a time (`--no-parallel`) |
| Run matching tests | `make test TEST_ARGS="--filter operand"` | tests whose name contains `operand` |
| Run one test file | `make test TEST_ARGS="--file tests/deltree_test.loup"` | |
| Build | `make build` | native binary at `build/rd`, and `build/rmdir` (a symlink) |
| Run the binary | `build/rd /S 'build\tmp\old'` | quote `\` and `/?` in the shell |
| End-to-end tests | `make e2e` | runs `tests/e2e.sh build/rd`, each case in a fresh tree under `$TMP`: stdout byte for byte, stderr exactly |
| Everything CI runs | `make ci` | check, test, build, e2e, then `build/rd --version` |
| Clean | `make clean` | removes `build/`, `.temp/` and `.loup-cache/` |

Run `make ci` before reporting a change as done. `loup run` and the native
build do not support the same things, so a change can pass `make test` and
still fail `make build`.

Do not call `loup test` or `loup check` directly on Linux x86-64. There `loup`
is the self-hosted driver: it refuses `check`, and its test runner cannot
resolve this project's imports. The Makefile uses `loup-bootstrap` (Stage0) for
both, and sets `LOUPPATH=source` for tests. Keep `--no-parallel`: Stage0's
parallel test runner fails these tests at random.

## Making a change

1. Update the spec in `specs/rd/` (see
   [specs/README.md](specs/README.md)).
2. Change the code under `source/`.
3. Add or update unit tests in `tests/` and cases in `tests/e2e.sh`.
4. Run `make ci`.
5. Tick the finished tasks in the spec's `tasks.md`.

Keep behaviour in functions that return values (`operand_message` returns
the message or `""` without changing anything; `remove_operand` and
`remove_tree` return the lines to print) so unit tests can check it; only
`run_rd` and `ask_yes_no` print.

**Deleting is dangerous.** Tests must only remove paths under `build/tmp/`
(unit tests) or `$TMP` (e2e), and never run `rd /S` on `.` or a path you
did not create for the purpose: `rd /S /Q .` empties the current
directory, as cmd's does. Never call `io.fs.removeDir` on anything but a
directory that `is_real_dir` accepted and that lists no entries: natively
it is an `rm -rf` that follows symbolic links. Keep every new deletion path
unlink-first, as `commands/deltree.loup` explains.

`source/win/` is a copy of the shared Windows code: do not change it here
alone. Improvements go to loup-cmd-type (the master) and
`ccai-examples/shared/windows/`, then get copied back.

## Conventions

- Every source file is `@mode(host.dual)` with the `.loup` extension. Only
  `source/main.loup` has a `main()`.
- Modules import each other by path from `source/`:
  `from win.switches import (parse_switches);`. Tests import them the same
  way. Do not use relative imports (`from .args import ...`): the
  self-hosted `loup run` on Linux x86-64 fails on them.
- Windows conventions: switches via `win.switches` (a `/X` that is not
  declared is a path); operands go through `fs_path()` before file access;
  every printed path goes through `display_path()`; messages use Windows'
  wording from `win.messages`; usage errors are ERRORLEVEL 1.
- Struct fields read from another module must be `pub`.
- The native build supports less than `loup run` does. For example,
  `list.is_empty()` fails native codegen (`E-CODEGEN-UNHANDLED-METHOD`; use
  `len() == 0`), a `sort` comparator that captures a list of structs crashes,
  `system.text` functions (`parseInt`, `padStart`) do not link, a struct
  literal outside its own module gets a wrong layout, file operations
  (`remove`, `removeDir`) fail silently instead of throwing (check the disk
  afterwards), and `IoError` cannot be caught.
- Keep `APP_VERSION` in `source/appinfo.loup` equal to `version` in
  `package.lppkg`.
- The skill's examples use the `loup init` layout (`src/`, `tests/`, and
  `from ..src.x import` in tests). This project uses `source/` and
  `tests/` with plain imports; follow this file.
- The skill documents toolchain 1.25.1; this template targets 1.26.0. When
  they disagree, trust the toolchain's behaviour.
