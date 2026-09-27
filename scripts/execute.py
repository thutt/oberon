# Copyright (c) 2022-2026 Logic Magicians Software
#
import os
import subprocess


def process(cmd, env):
    # 'env' must be a complete environment (e.g. a copy of
    # os.environ with overrides applied by the caller), not a
    # partial one -- Popen() replaces the child's environment with
    # it rather than merging.  There is deliberately no default: a
    # caller that means to inherit the ambient environment must say
    # so explicitly (env=os.environ), rather than get that behavior
    # implicitly by omitting the argument.  That matters here in
    # particular because building a private copy of the environment
    # per-call, instead of mutating os.environ in place, is what
    # makes it safe to call this concurrently from multiple threads
    # with different 'env' values -- a caller that forgets 'env' and
    # silently falls back to mutating shared state is exactly the
    # bug this signature is meant to make impossible to write by
    # accident.
    assert(isinstance(cmd, list))
    assert(os.path.exists(cmd[0]))
    p = subprocess.Popen(cmd,
                         universal_newlines = False,
                         shell  = False,
                         stdin  = subprocess.PIPE,
                         stdout = subprocess.PIPE,
                         stderr = subprocess.PIPE,
                         env    = env)
    (stdout, stderr) = p.communicate(None)

    # None is returned when no pipe is attached to stdout/stderr.
    if stdout is None:
        stdout = ''
    else:
        stdout = stdout.decode("UTF-8", errors="backslashreplace")

    if stderr is None:
        stderr = ''
    else:
        stderr = stderr.decode("UTF-8", errors="backslashreplace")

    rc = p.returncode

    # stdout block becomes a list of lines.  For Windows, delete
    # carriage-return so that regexes will match '$' correctly.
    #
    return (stdout.replace("\r", "").split("\n"),
            stderr.replace("\r", "").split("\n"),
            rc)
