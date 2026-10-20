# Design: rd

## Overview

`main()` passes `runtime.args()` to `cli.app.run`, which parses them with the
shared switch parser (`win.switches`: `flag("S")`, `flag("Q")`), handles
`/?` and `--version`, and calls `commands.rd.run_rd`. For each operand
`run_rd` asks `operand_message` whether it can be removed (without changing
anything); if so, `action_for` picks the action and `remove_operand` asks
the question (`/S` without `/Q`) and removes. Only `run_rd` prints; the exit
status comes from the last line printed.

## Modules

| Module | Contents |
|---|---|
| `source/main.loup` | entry point: `run(runtime.args())` |
| `source/appinfo.loup` | name, version, summary, exit statuses (Windows error codes) |
| `source/cli/args.loup` | `Options` (`recurse`, `quiet`, operands), `rd_switches()`, `parse_args` |
| `source/cli/usage.loup` | `usage()` (this recreation's own short help), `version_line()` |
| `source/cli/app.loup` | `run()`: parse, help/version, run, exceptions to status 1 |
| `source/commands/rd.loup` | `target_path`, `is_current_or_above`, `operand_message`, `action_for`, `remove_operand`, `status_for`, `run_rd` |
| `source/commands/deltree.loup` | `sorted_names`, `entry_present`, `is_symlink`, `is_real_dir`, `unlink_quietly`, `remove_empty_dir`, `remove_contents`, `remove_tree` |
| `source/commands/prompt.loup` | `ask_yes_no`, `sure_question`, `parse_answer` (from loup-cmd-del) |
| `source/win/` | the shared Windows code: switches, wildcards, paths, messages |

## Deciding (`operand_message`, `action_for`)

In order: an empty operand or a forbidden character → invalid name;
`target_path` (`\` → `/`, `.` and `name/..` resolved by name); `/` → access
denied; `.` and `..`-only paths → in use (except `.` with `/S`, which is
emptied first); no directory entry (`entry_present`, which also sees a
dangling link through the parent's `listDir`) → file or path not found; not
a directory (`isDir` follows links, so a link to a file or to nothing lands
here) → directory name invalid; a link to a directory → remove the link; a
directory that `test -h` cannot classify → access denied; not empty without
`/S` → not empty.

Actions: `ACT_RMDIR` (empty directory), `ACT_UNLINK` (link to a directory),
`ACT_TREE` (`/S`), `ACT_CONTENTS` (`/S .`: empty it, then report in use).

## Deleting safely (`deltree`)

Loup 1.26.0's io.fs has no `lstat()`; `exists`/`isDir` follow links, and
the native `removeDir` is a stat()-based `rm -rf` that would follow a link
into its target. `remove_contents(dir)` therefore, for each name in byte
order:

1. unlinks it (`io.fs.remove` is unlink(2) natively, `remove_file` in
   Stage0): files and links of every kind go, directories stay;
2. if it is still there, is a directory and `test -h` answers exactly "not
   a link" (`is_real_dir`), descends with `remove_tree`;
3. afterwards lists the directory again: whatever is left (and was not
   already reported by the subdirectory's own walk) is reported as
   `PATH - Access is denied.`

`remove_tree(dir)` calls `removeDir` only when `remove_contents` left
nothing, so it is a plain rmdir there. Every step is checked on disk:
native io.fs fails silently, Stage0 throws `IoError` (caught).

## Exit status

`status_for(line)` maps the last printed line (`MSG` or `PATH - MSG`) to
the Windows error code: 2, 3, 5, 32, 123, 145; anything else (syntax,
directory name invalid = 267) is 1.

## Differences from the original

- cmd's RD does not change `%ERRORLEVEL%` and sets its exit code only
  sometimes; this program always exits with the code. 267 becomes 1. A
  partly failed `/S` gives 5 (Windows: no code).
- Answers are whole lines; the answer is echoed when standard input is not
  a terminal; the question comes after the existence checks.
- The root directory, `..` and other relative ancestors of the current
  directory are refused outright; absolute ancestors are not detected.
- No junctions, attributes or 8.3 names; names are case-sensitive; trailing
  dots and spaces are kept; no drive letters.
- Every failure to remove is `Access is denied.` (no reason is available).
- `/?` prints a short help text of this recreation; `--help`/`--version`
  alone are series conventions; `rmdir` is a symlink; messages end with LF.

## Error handling

Every failure is reported per operand and processing continues. An
unexpected exception is printed on standard error and gives status 1.

## Testing

- `tests/args_test.loup`: `/S`, `/Q`, combined, `-s`, `/S:x` is a path, `/?`, `--`.
- `tests/rd_test.loup`: invalid characters, `target_path`,
  `is_current_or_above`, `status_for`, `operand_message` and `action_for`
  on a fixture under `build/tmp/`.
- `tests/deltree_test.loup`: link detection and `remove_tree` on a fixture
  whose links lead out of the tree (their targets must survive).
- `tests/prompt_test.loup`, `tests/app_test.loup`, `tests/win_*_test.loup`.
- `tests/e2e.sh`: runs the native binary (and the `rmdir` link) in a fresh
  fixture under `$TMP` per case, with links to `$TMP/outside`, and checks
  standard output, standard error, the exit code, the resulting tree and
  that `$TMP/outside` is unchanged.
