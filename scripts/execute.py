# Copyright (c) 2022 Logic Magicians Software
#
import os
import subprocess


def process(cmd):
    assert(isinstance(cmd, list))
    assert(os.path.exists(cmd[0]))
    p = subprocess.Popen(cmd,
                         universal_newlines = False,
                         shell  = False,
                         stdin  = subprocess.PIPE,
                         stdout = subprocess.PIPE,
                         stderr = subprocess.PIPE)
    (stdout, stderr) = p.communicate(None)

    # None is returned when no pipe is attached to stdout/stderr.
    if stdout is None:
        stdout = ''
    else:
        stdout = stdout.decode("UTF-8")

    if stderr is None:
        stderr = ''
    else:
        stderr = stderr.decode("UTF-8")

    rc = p.returncode

    # stdout block becomes a list of lines.  For Windows, delete
    # carriage-return so that regexes will match '$' correctly.
    #
    return (stdout.replace("\r", "").split("\n"),
            stderr.replace("\r", "").split("\n"),
            rc)
