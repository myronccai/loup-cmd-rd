# loup-cmd-rd

The Windows `rd` (and `rmdir`) command recreated in
[Loup](https://code-craft.ai/references/loup): remove directories, empty
ones or (with `/S`) whole trees, using cmd's `\` paths, question, messages
and exit codes, on Linux. Symbolic links are removed, never followed.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is `host.dual` Loup built as a native binary. It uses the shared
Windows code in [`source/win/`](source/win/) (switch parser, wildcard
matcher, path helpers, messages), copied from
[loup-cmd-type](https://github.com/myronccai/loup-cmd-type).

## Requirements

- Loup 1.26.0 or later:

  ```sh
  curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
  ```

- `make`, and `clang` 17 or later for the native build.

## Usage

```sh
make build                     # native binary build/rd, and build/rmdir (a symlink to it)
make ci                        # check, unit tests, build, end-to-end tests
make run ARGS="/S /Q build/tmp/old"   # run from source (Stage0's interpreter)
```

Quote operands that contain `\` so that the Linux shell passes them
through. In this session `demo\cache` held a symbolic link to `demo\shared`:
the link went, `demo\shared` stayed.

```text
$ build/rd 'demo\empty'
$ build/rd 'demo\logs'; echo "ERRORLEVEL $?"
The directory is not empty.
ERRORLEVEL 145
$ echo n | build/rd /S 'demo\logs'
demo\logs, Are you sure (Y/N)? n
$ echo y | build/rd /S 'demo\logs'
demo\logs, Are you sure (Y/N)? y
$ build/rd /S /Q 'demo\cache'
$ find demo | sort
demo
demo/notes.txt
demo/shared
demo/shared/keep.txt
demo/work
demo/work/obj
demo/work/obj/t.o
$ build/rd 'demo\notes.txt'
The directory name is invalid.
$ build/rd 'demo\missing'; echo "ERRORLEVEL $?"
The system cannot find the file specified.
ERRORLEVEL 2
$ build/rmdir 'demo\missing\sub'; echo "ERRORLEVEL $?"
The system cannot find the path specified.
ERRORLEVEL 3
$ cd demo/work && ../../build/rd /S /Q .; cd ../..
The process cannot access the file because it is being used by another process.
$ find demo/work
demo/work
$ build/rd
The syntax of the command is incorrect.
$ build/rd '/?'
Remove directories.

RD [/S] [/Q] path [path ...]
RMDIR is the same command.

  path  A directory to remove. Without /S it must be empty.
  /S    Remove the directory with everything in it. Symbolic links
        inside it are removed, never followed.
  /Q    With /S, do not ask "Are you sure (Y/N)?" first.
$ build/rd --version
rd (loup-cmd-rd) 0.1.0
```

`rd [/S] [/Q] path [path ...]` (`rmdir` is the same command)

- Without `/S` a directory must be empty: otherwise `The directory is not
  empty.`
- `/S` removes the directory and everything in it. It first asks `PATH,
  Are you sure (Y/N)?` for each operand; `/Q` skips the question. Answers
  are read one line at a time from standard input (`y` or `n` in any case;
  anything else asks again; the end of input means no). An entry `/S`
  cannot remove is reported as `PATH - Access is denied.`, everything else
  goes, and the directories that still hold something stay.
- A symbolic link to a directory is removed itself (with or without `/S`),
  as Windows removes a junction; inside a tree, every link (to a directory,
  a file or nothing) is unlinked and never entered.
- A file, or a link to a file or to nothing: `The directory name is
  invalid.` A missing directory: `The system cannot find the file
  specified.`, or `... the path specified.` when its parent is missing too.
- The current directory (`.`) and the ones above it (`..`) are in use: `The
  process cannot access the file because it is being used by another
  process.` With `/S`, `.` is emptied first, as cmd does. The root directory
  is refused with `Access is denied.`
- rd does not expand wildcards: `*`, `?` and the other characters Windows
  forbids in names give `The filename, directory name, or volume label
  syntax is incorrect.`
- Operands accept `\` and `/`; `.` and `name\..` are resolved by name first.
  Switches start with `/` or `-` in any case and may be combined (`/S/Q`); a
  `/X` that is not one of rd's switches is a path, and `--` ends switch
  parsing. `/?` prints a short help; `--help` and `--version` work as the
  only argument.

Messages go to standard error. Exit status: `0` when every operand was
removed (or a question answered N), else the Windows error code of the last
failure, as cmd's RD sets it: `1` syntax error, `2` not found, `3` path not
found, `5` access denied, `32` in use, `123` invalid name, `145` not empty.

## Differences from the original

- `rmdir` is a symlink to the same binary (`build/rmdir`); both print `rd`
  in `--version`.
- Exit status: cmd's RD leaves `%ERRORLEVEL%` alone and only sets its exit
  code, and not always. A Linux program always has a status, so this one
  is always set. `The directory name is invalid.` is Windows code 267, which
  does not fit in a Linux exit status: it gives `1`. When `/S` cannot remove
  everything, Windows sets no code at all; this rd returns `5`.
- Answers are whole lines (Enter needed); cmd reacts to the key press. When
  standard input is not a terminal, the answer is echoed after the
  question. (The roadmap expected answers from piped input only, because
  Loup 1.26.0 can only read standard input whole; reading one line through
  a `sh` child makes the terminal work too.) The question is asked only
  after rd has checked that the directory exists.
- The root directory is never removed, and neither are `..` and the other
  directories above the current one (Windows removes what it can of them
  before it fails). Other ancestors of the current directory named by an
  absolute path are not recognised as in use.
- Read-only files inside a tree are removed (Linux only needs write
  permission on the directory); what cannot be removed is reported as
  `Access is denied.`, whatever the reason, because Loup 1.26.0's native
  `io.fs` reports none.
- No junctions, hard-link counts or 8.3 names; names are case-sensitive;
  trailing dots and spaces in names are kept; there are no drive letters.
- `/?` prints a short help text of this recreation, not Windows' own.
  Messages end with LF, not CRLF.
- `make run` uses Stage0's interpreter (`loup-bootstrap run`), where a child
  process gets no standard input: questions are answered N there, so use
  `/Q`. The self-hosted `loup run` cannot run rd correctly (it joins a
  child's arguments into an unquoted shell command).

## How it deletes safely

Loup 1.26.0 has no `lstat()`, and its native `io.fs.removeDir` is an
`rm -rf` that follows symbolic links into their targets. So rd never calls
it on anything but an empty directory: every entry of a tree is first
unlinked (`io.fs.remove`, which removes files and links of any kind and
leaves directories alone); only an entry that survives, is a directory and
is confirmed not to be a link (`test -h`) is entered; and a directory is
removed once it lists no entries. Success is checked on disk, since native
`io.fs` calls fail silently. The end-to-end tests point links out of the
tree and check that their targets stay unchanged.

## Layout

```text
source/main.loup               # entry point
source/appinfo.loup            # name, version, exit statuses (Windows error codes)
source/cli/args.loup           # /S /Q via win.switches
source/cli/usage.loup          # /? and --version text
source/cli/app.loup            # run(): parse, dispatch, exit status
source/commands/rd.loup        # operand_message(), action_for(), remove_operand(), run_rd()
source/commands/deltree.loup   # remove_tree() and friends: never follows a link
source/commands/prompt.loup    # the Y/N question, one line of stdin at a time
source/win/                    # shared Windows code: switches, wildcards, paths, messages
tests/*_test.loup              # unit tests (make test)
tests/e2e.sh                   # end-to-end tests of build/rd and build/rmdir (make e2e)
specs/rd/                      # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every build and test command and the conventions
for changing the code.
