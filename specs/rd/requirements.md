# Requirements: rd

## Introduction

`rd` (also `rmdir`) is the cmd.exe built-in that removes directories: empty
ones, or with `/S` whole trees. This repository recreates it in Loup for
Linux, keeping Windows' operand syntax (`\` separators, `/S /Q` switches,
`/?` help), its question, messages and exit codes. It is the third Windows
command in the loup-cmd series and uses the shared Windows code in
`source/win/`, copied from loup-cmd-type. Removing trees on Linux must be
safe: rd never follows a symbolic link.

## Requirements

### Requirement 1: Remove empty directories

**User Story:** As a cmd user, I want `rd old` to remove an empty directory.

#### Acceptance Criteria

1. WHEN rd is given an empty directory, THE program SHALL remove it, print
   nothing and exit 0.
2. WHEN the directory is not empty and `/S` is not given, THE program SHALL
   print `The directory is not empty.` and leave it (exit 145).
3. WHEN rd is given several operands, THE program SHALL handle them in
   command-line order and go on after a failure.
4. THE program SHALL accept `\` and `/` as separators, ignore separators at
   the end, and resolve `.` and `name\..` by name.

### Requirement 2: Remove trees (/S, /Q)

**User Story:** As a cmd user, I want `rd /S /Q build` to remove a whole
tree, and to be asked first when I leave out `/Q`.

#### Acceptance Criteria

1. WHEN `/S` is given, THE program SHALL remove the directory and
   everything in it.
2. WHEN `/S` is given without `/Q`, THE program SHALL first ask
   `PATH, Are you sure (Y/N)? ` (PATH as typed, with `\`) on standard
   output and read one line of standard input: Y removes, N skips the
   operand, anything else asks again, and the end of input means N. WHEN
   standard input is not a terminal, THE program SHALL echo the answer.
3. THE program SHALL ask only about an operand it can act on (it exists and
   is a directory or a link to one).
4. WHEN an entry inside the tree cannot be removed, THE program SHALL print
   `PATH - Access is denied.`, remove everything else, keep the
   directories that still hold something, and exit 5.
5. `/Q` without `/S` SHALL change nothing.

### Requirement 3: Symbolic links

**User Story:** As a Linux user, I want rd never to delete anything outside
the tree I named, whatever links the tree contains.

#### Acceptance Criteria

1. WHEN an operand is a symbolic link to a directory, THE program SHALL
   remove the link only, with or without `/S` (as Windows removes a
   junction).
2. WHEN `/S` meets a symbolic link inside the tree (to a directory, a file
   or nothing), THE program SHALL remove the link and SHALL NOT enter it.
3. THE program SHALL descend only into entries confirmed to be real
   directories, and SHALL remove a directory only once it lists no entries.
4. WHEN an operand is a link to a file or to nothing, THE program SHALL
   print `The directory name is invalid.`

### Requirement 4: Errors and exit codes

**User Story:** As a script author, I want Windows' messages and exit codes.

#### Acceptance Criteria

1. WHEN the directory does not exist, THE program SHALL print
   `The system cannot find the file specified.` (2), or
   `The system cannot find the path specified.` (3) when its parent is
   missing or is not a directory.
2. WHEN the operand is a file, THE program SHALL print
   `The directory name is invalid.` (exit 1: Windows' 267 does not fit).
3. WHEN the operand is empty or contains `< > : " | ? *` or a control
   character, THE program SHALL print
   `The filename, directory name, or volume label syntax is incorrect.`
   (123); rd does not expand wildcards.
4. WHEN the operand is the current directory or one above it (`.`, `..`),
   THE program SHALL print `The process cannot access the file because it
   is being used by another process.` (32), after emptying `.` when `/S`
   is given.
5. WHEN the operand is the root directory, THE program SHALL remove nothing
   and print `Access is denied.` (5); WHEN a directory cannot be removed
   for another reason, also `Access is denied.`
6. WHEN no operand is given, THE program SHALL print
   `The syntax of the command is incorrect.` (1).
7. THE program SHALL write messages to standard error and exit with the
   code of the last failure, or 0.

### Requirement 5: Switches

**User Story:** As a cmd user, I want the usual switch syntax and `rd /?`.

#### Acceptance Criteria

1. THE program SHALL accept `/S` and `/Q` with `/` or `-` in any case,
   anywhere on the line, and combined (`/S/Q`); every other argument,
   including an undeclared `/X`, and everything after `--` SHALL be a
   directory name.
2. WHEN `/?` or `-?` appears, THE program SHALL print a short help text and
   exit 0 without removing anything.
3. WHEN `--version` is the only argument, THE program SHALL print
   `rd (loup-cmd-rd) 0.1.0`; `--help` alone SHALL print the help.
4. THE build SHALL also provide the command as `rmdir` (a symbolic link).
