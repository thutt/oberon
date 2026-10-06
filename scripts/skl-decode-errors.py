#!/usr/bin/python3 -Bu
#
# Copyright (c) 2026 Logic Magicians Software
#
#  Stdin -> stdout filter for 'skl-skl-oc'.  Never changes or drops a
#  line of the compiler's own output -- it only appends a
#  human-readable annotation after each error line, decoding:
#
#    * the numeric error code, by name/description, read directly
#      from SKLERR.Mod (so there is exactly one place those
#      descriptions are maintained);
#
#    * the raw character 'pos' into a 1-based line:column, by
#      reading the source file that was being compiled when the
#      error occurred.
#
#  This exists entirely outside the compiler and the interpreter.
#  SKLCMDIO.Mark()'s printed format (what the Oberon System's
#  Edit.Locate and other in-system tooling read) is untouched -- this
#  script only post-processes a copy of that text for a shell user.
#
#  '-u' (unbuffered) above: this sits in an interactive pipeline; a
#  user watching 'skl-skl-oc' run should see output as it is
#  produced, not buffered up until the whole batch finishes.
#
import os
import re
import sys

ERROR_RE    = re.compile(r'pos\s*(\d+)\s*err\s*(\d+)')
COMPILING_RE = re.compile(r'^(\S+)\s+compiling\b')
ERRDEF_RE   = re.compile(r'^\s*(\w+)\*\s*=\s*(\d+)\s*;\s*(.*)$')


def load_error_table():
    # Returns {code: (name, description)}, parsed from SKLERR.Mod.
    # Returns an empty dict (decoding silently skipped, lines still
    # passed through unchanged) if SKLERR.Mod cannot be found/read --
    # this tool must never be the reason compiler output goes missing.
    skl_dir = os.environ.get("SKL_DIR")
    if not skl_dir:
        return {}

    pathname = os.path.join(skl_dir, "system", "compiler", "skl",
                            "SKLERR.Mod")
    table = {}
    try:
        with open(pathname, "r") as f:
            for line in f:
                m = ERRDEF_RE.match(line)
                if m:
                    name, code, comment = m.groups()
                    comment = comment.replace("(*", "").replace("*)", "")
                    table[int(code)] = (name, comment.strip())
    except OSError:
        return {}
    return table


def line_col(pathname, pos):
    # Converts a raw character offset into a 1-based (line, column),
    # or None if the source file cannot be read.
    try:
        with open(pathname, "rb") as f:
            data = f.read(pos)
    except OSError:
        return None
    line = data.count(b"\n") + 1
    col  = pos - (data.rfind(b"\n") + 1) + 1
    return (line, col)


def main():
    errors       = load_error_table()
    current_file = None

    for raw in sys.stdin:
        line = raw.rstrip("\n")
        sys.stdout.write(raw)

        m = COMPILING_RE.match(line)
        if m:
            current_file = m.group(1)
            continue

        m = ERROR_RE.search(line)
        if m:
            pos  = int(m.group(1))
            code = int(m.group(2))
            name, desc = errors.get(code, ("?", "unknown error code"))

            where = "%s:?:?" % (current_file) if current_file else "?"
            if current_file:
                lc = line_col(current_file, pos)
                if lc:
                    where = "%s:%d:%d" % (current_file, lc[0], lc[1])

            print("    -> %s: %s -- %s" % (where, name, desc))

    return 0


if __name__ == "__main__":
    sys.exit(main())
