#!/usr/bin/env bash
# End-to-end tests: run the built binary and compare its standard output
# (byte for byte), and where given its standard error, and exit status with
# the expected ones. Every case runs in a fresh fixture tree under $TMP, and
# the tree is checked afterwards: rd only ever touches paths under $TMP.
# Symbolic links in the tree lead to $TMP/outside, which must never change.
#
# usage: tests/e2e.sh BINARY

set -u
BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# check_file NAME STATUS EXPECTED_FILE [ARGS...]
# Runs BINARY ARGS... with standard input from the file named by $IN
# (default: /dev/null) and compares standard output with EXPECTED_FILE.
# If $WANT_ERR is set, standard error must equal it too.
check_file() {
    local name=$1 want_status=$2 want_file=$3
    shift 3
    "$BIN" "$@" < "${IN:-/dev/null}" > "$TMP/out" 2> "$TMP/err"
    local status=$?
    local err_ok=1
    if [ -n "${WANT_ERR+set}" ]; then
        printf '%s' "$WANT_ERR" > "$TMP/want_err"
        cmp -s "$TMP/want_err" "$TMP/err" || err_ok=0
    fi
    if [ "$status" -eq "$want_status" ] && cmp -s "$want_file" "$TMP/out" && [ "$err_ok" -eq 1 ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $name (exit $status, expected $want_status)"
        diff <(od -c "$want_file") <(od -c "$TMP/out") | sed 's/^/    /' | head -20
        if [ "$err_ok" -eq 0 ]; then
            diff <(od -c "$TMP/want_err") <(od -c "$TMP/err") | sed 's/^/    stderr /' | head -20
        fi
        sed 's/^/    stderr: /' "$TMP/err" | head -5
    fi
}

# check NAME STATUS EXPECTED_STDOUT [ARGS...]
# As check_file, with the expected output given as a string. Bash strings
# cannot hold NUL bytes; use check_file for output that contains them.
check() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    check_file "$name" "$want_status" "$TMP/want" "$@"
}

# check_both NAME STATUS EXPECTED_STDOUT EXPECTED_STDERR [ARGS...]
check_both() {
    local name=$1 want_status=$2 want_out=$3
    local WANT_ERR=$4
    shift 4
    check "$name" "$want_status" "$want_out" "$@"
}

# The fixture tree, rebuilt before every case, and the directory its links
# lead to.
W="$TMP/w"
O="$TMP/outside"
reset() {
    cd "$TMP" && chmod -R u+w "$W" 2>/dev/null; rm -rf "$W" "$O"
    mkdir -p "$O/keep"
    printf 'top\n' > "$O/top.txt"
    printf 'precious\n' > "$O/keep/p.txt"
    mkdir -p "$W/empty" "$W/full/sub/deep"
    printf 'a\n' > "$W/full/a.txt"
    printf 'b\n' > "$W/full/sub/b.txt"
    printf 'c\n' > "$W/full/sub/deep/c.txt"
    ln -s "$O" "$W/full/sub/to_outside"
    ln -s "$O/top.txt" "$W/full/to_file"
    ln -s nowhere "$W/full/dangling"
    ln -s "$O" "$W/dirlink"
    ln -s nowhere "$W/dangling"
    printf 'f\n' > "$W/file.txt"
    cd "$W"
}

# A tree as one line per entry: `dir/`, `link->target` or `file=content`.
state_of() {
    (cd "$1" && find . -mindepth 1 | LC_ALL=C sort | while read -r p; do
        if [ -L "$p" ]; then echo "${p#./}->$(readlink "$p" | sed "s|^$TMP/|\$TMP/|")"
        elif [ -d "$p" ]; then echo "${p#./}/"
        else echo "${p#./}=$(cat "$p")"; fi
    done)
}
OUTSIDE=$'keep/\nkeep/p.txt=precious\ntop.txt=top'

# check_state NAME EXPECTED: the tree after the last case; the directory
# outside must be untouched.
check_state() {
    local got
    got=$(state_of "$W")
    if [ "$got" = "$2" ] && [ "$(state_of "$O")" = "$OUTSIDE" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $1 (tree)"
        diff <(echo "$2") <(echo "$got") | sed 's/^/    /'
        diff <(echo "$OUTSIDE") <(state_of "$O") | sed 's/^/    outside /'
    fi
}

# without TEXT...: the starting tree minus the lines that contain one of
# the texts.
START=$(cat <<'EOT'
dangling->nowhere
dirlink->$TMP/outside
empty/
file.txt=f
full/
full/a.txt=a
full/dangling->nowhere
full/sub/
full/sub/b.txt=b
full/sub/deep/
full/sub/deep/c.txt=c
full/sub/to_outside->$TMP/outside
full/to_file->$TMP/outside/top.txt
EOT
)
without() {
    local out="$START" name
    for name in "$@"; do
        out=$(echo "$out" | grep -v -F -e "$name")
    done
    echo "$out"
}
FULL_GONE=$(without full/)

printf 'y\n' > "$TMP/yes"; printf 'n\n' > "$TMP/no"; printf 'what\ny\n' > "$TMP/retry"
printf 'y\nn\n' > "$TMP/yn"
sure() { echo "$1, Are you sure (Y/N)? ${2-}"; }
nf='The system cannot find the file specified.'
np='The system cannot find the path specified.'
invalid_dir='The directory name is invalid.'
invalid='The filename, directory name, or volume label syntax is incorrect.'
in_use='The process cannot access the file because it is being used by another process.'

# Help and version; rmdir is the same program.
reset
"$BIN" '/?' > "$TMP/help" 2>&1
if [ "$(head -1 "$TMP/help")" = 'Remove directories.' ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: /? help"; fi
check      "-? among operands"  0 "$(cat "$TMP/help")"$'\n'     /S /Q full '-?'
check_state "-? removes nothing" "$START"
check      "--help"             0 "$(cat "$TMP/help")"$'\n'     --help
check      "--version"          0 $'rd (loup-cmd-rd) 0.1.0\n'   --version

# Without /S: empty directories only.
reset; check_both "empty directory" 0 '' ''                     empty
check_state "empty directory" "$(without empty/)"
reset; check_both "not empty"   145 '' $'The directory is not empty.\n' full
check_state "not empty" "$START"
reset; check_both "/Q alone does not recurse" 145 '' $'The directory is not empty.\n' /Q 'full\sub\deep'
reset; check_both "backslashes and a trailing separator" 0 '' '' 'full\sub\deep\..\..\..\empty\'
check_state "backslashes and a trailing separator" "$(without empty/)"
reset; check_both "absolute path" 0 '' ''                       "$W/empty"
check_state "absolute path" "$(without empty/)"
reset; mkdir e2; check_both "several, all removed" 0 '' ''      empty e2
check_state "several, all removed" "$(without empty/)"

# Symbolic links are removed, never followed.
reset; check_both "link to a directory" 0 '' ''                 dirlink
check_state "link to a directory" "$(without dirlink)"
reset; check_both "link with /S /Q" 0 '' ''                     /S /Q dirlink
check_state "link with /S /Q" "$(without dirlink)"
reset; IN="$TMP/yes" check_both "link with a trailing separator" 0 "$(sure 'dirlink\' y)"$'\n' '' /S 'dirlink\'
check_state "link with a trailing separator" "$(without dirlink)"
reset; check_both "dangling link" 1 '' "$invalid_dir"$'\n'      dangling
check_state "dangling link" "$START"
reset; check_both "link to a file" 1 '' "$invalid_dir"$'\n'     /S /Q 'full\to_file'
check_state "link to a file" "$START"

# /S removes the whole tree; links inside it are unlinked.
reset; check_both "/S /Q"       0 '' ''                         /S /Q full
check_state "/S /Q" "$FULL_GONE"
reset; check_both "/s/q combined, any case" 0 '' ''             /s/q 'full\'
check_state "/s/q combined, any case" "$FULL_GONE"
reset; check_both "-s -q"       0 '' ''                         -q full -s
check_state "-s -q" "$FULL_GONE"
reset; chmod a-w full/a.txt; check_both "/S /Q with a read-only file" 0 '' '' /S /Q full
check_state "/S /Q with a read-only file" "$FULL_GONE"
reset; check_both "/S /Q on an empty directory" 0 '' ''         /S /Q empty
check_state "/S /Q on an empty directory" "$(without empty/)"
reset; check_both "/S /Q a subdirectory" 0 '' ''                /S /Q 'full\sub'
check_state "/S /Q a subdirectory" "$(without full/sub)"
reset; mkdir -p 'sp ace/in ner'; ln -s "$O" 'sp ace/in ner/a link'; printf 'x\n' > 'sp ace/$(x) ;'
check_both "names with spaces"  0 '' ''                         /S /Q 'sp ace'
check_state "names with spaces" "$START"

# Without /Q, /S asks first; the answer is a line of standard input.
reset; IN="$TMP/yes" check_both "yes" 0 "$(sure full y)"$'\n' '' /S full
check_state "yes" "$FULL_GONE"
reset; IN="$TMP/no" check_both "no" 0 "$(sure full n)"$'\n' ''  /S full
check_state "no" "$START"
reset; check_both "end of input is no" 0 "$(sure full)"$'\n' '' /S full
check_state "end of input is no" "$START"
reset; IN="$TMP/retry" check "asks again" 0 "$(sure 'full\sub' what)
$(sure 'full\sub' y)
"                                                               /S full/sub
check_state "asks again" "$(without full/sub)"
reset; IN="$TMP/yn" check "one question per directory" 0 "$(sure empty y)
$(sure full n)
"                                                               /S empty full
check_state "one question per directory" "$(without empty/)"
reset; check_both "no question for a missing one" 2 '' "$nf"$'\n' /S nope

# The current directory and the ones above it are in use; /S empties `.`.
reset; cd full; check_both "/S /Q ." 32 '' "$in_use"$'\n'       /S /Q .
cd "$W"; check_state "/S /Q ." "$(without full/a full/d full/s full/t)"
reset; cd full/sub; check_both "plain ." 32 '' "$in_use"$'\n'   .
check_both "dot-dot"            32 '' "$in_use"$'\n'            /S /Q ..
check_both "back to ." 32 '' "$in_use"$'\n'                     'deep\..'
cd "$W"; check_state "nothing removed in use" "$START"
reset; check_both "the root"    5 '' $'Access is denied.\n'     '\'
check_state "the root" "$START"

# Errors and exit statuses (the Windows error codes; the last failure wins).
reset; check_both "no operand"  1 '' $'The syntax of the command is incorrect.\n'
reset; check_both "switches only" 1 '' $'The syntax of the command is incorrect.\n' /S /Q
reset; check_both "missing"     2 '' "$nf"$'\n'                 nope
reset; check_both "missing parent" 3 '' "$np"$'\n'              'nope\x'
reset; check_both "file as parent" 3 '' "$np"$'\n'              'file.txt\x'
reset; check_both "a file"      1 '' "$invalid_dir"$'\n'        file.txt
reset; check_both "wildcard"    123 '' "$invalid"$'\n'          'full*'
reset; check_both "empty operand" 123 '' "$invalid"$'\n'        ''
reset; check_both "found and missing" 2 '' "$nf"$'\n'           /S /Q full nope empty
check_state "found and missing" "$(without full/ full/a full/d full/s full/t empty/)"
reset; check_both "missing then not empty" 145 '' "$nf"$'\n'$'The directory is not empty.\n' nope full
reset; mkdir -- -x; check_both "unknown switch is a directory" 0 '' '' -x
check_state "unknown switch is a directory" "$START"
reset; mkdir -- -s; check_both "-- ends switches" 0 '' ''       /Q -- -s
check_state "-- ends switches" "$START"

# What /S cannot remove is reported, and the rest goes.
if [ "$(id -u)" != 0 ]; then
    reset; chmod a-w full/sub
    check_both "read-only subdirectory" 5 '' 'full\sub\deep - Access is denied.
full\sub\b.txt - Access is denied.
full\sub\to_outside - Access is denied.
'                                                               /S /Q full
    chmod u+w full/sub
    check_state "read-only subdirectory" $'dangling->nowhere\ndirlink->$TMP/outside\nempty/\nfile.txt=f\nfull/\nfull/sub/\nfull/sub/b.txt=b\nfull/sub/deep/\nfull/sub/to_outside->$TMP/outside'
    reset; chmod a-w .
    check_both "read-only parent" 5 '' $'Access is denied.\n'   empty
    chmod u+w .
    check_state "read-only parent" "$START"
fi

# rmdir is rd.
reset; BIN_RD=$BIN; BIN=$(dirname "$BIN")/rmdir
check_both "rmdir"              0 '' ''                         /s /q full
check_state "rmdir" "$FULL_GONE"
check      "rmdir --version"    0 $'rd (loup-cmd-rd) 0.1.0\n'   --version
BIN=$BIN_RD

echo "e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
