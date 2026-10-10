#!/usr/bin/python3 -B
#
# Copyright (c) 2026 Logic Magicians Software
#
#  Checks out a GitHub pull request into a scratch branch, generates
#  a review with 'diff-review', and shows it with 'view-review-tabs'.
#  See claude/review-request.text for the full specification this
#  script implements.
#
#  Uses only standard git commands -- no 'gh' (GitHub CLI) -- so a
#  pull request's head commit is fetched directly via the 'pull/N
#  /head' ref GitHub exposes for every pull request, which works
#  whether the pull request comes from a branch of this repository
#  or from a fork.
#
import argparse
import os
import shutil
import sys
import textwrap

import execute


DIFF_REVIEW_URL = "https://github.com/thutt/diff-review"

# Every line this script prints -- messages and captured subprocess
# output alike -- is wrapped to this width, regardless of the actual
# terminal width, so output is never left ragged against a narrower
# window and never relies on the terminal to wrap for it.
WRAP_WIDTH = 80


def print_wrapped(text, initial_indent="", subsequent_indent=""):
    wrapped = textwrap.fill(text,
                            width=WRAP_WIDTH,
                            initial_indent=initial_indent,
                            subsequent_indent=subsequent_indent,
                            break_long_words=False,
                            break_on_hyphens=False)
    print(wrapped)


def ensure_period(text):
    # Every message this script prints is a complete English
    # sentence; this is the one place a trailing period is added if
    # the caller's text does not already end in sentence-ending
    # punctuation, so callers do not each have to remember to do it.
    if len(text) > 0 and text[-1] not in ".!?":
        return text + "."
    return text


def fatal(msg):
    print_wrapped(ensure_period(msg),
                  initial_indent="fatal: ",
                  subsequent_indent="       ")
    sys.exit(1)


def warning(msg):
    print_wrapped(ensure_period(msg),
                  initial_indent="warning: ",
                  subsequent_indent="         ")


def dump_output(stdout, stderr):
    for line in stdout:
        print_wrapped(line,
                      initial_indent="  stdout: ",
                      subsequent_indent="          ")
    for line in stderr:
        print_wrapped(line,
                      initial_indent="  stderr: ",
                      subsequent_indent="          ")


def fail_command(label, rc, stdout, stderr):
    print_wrapped(ensure_period("%s failed (rc=%s)" % (label, rc)),
                  initial_indent="fatal: ",
                  subsequent_indent="       ")
    dump_output(stdout, stderr)
    sys.exit(1)


class HelpFormatter(argparse.RawDescriptionHelpFormatter):
    # Forces '--help' output to wrap at 'WRAP_WIDTH', regardless of
    # the actual terminal width -- the base class otherwise wraps to
    # the terminal's real width (or an 80-column default only when
    # there is no terminal at all, e.g. when piped).
    def __init__(self, prog):
        super().__init__(prog, width=WRAP_WIDTH)


def configure_parser():
    description = ("""

This program checks out a GitHub pull request into a scratch branch
of this repository, generates a review of it with 'diff-review', and
then shows that review with 'view-review-tabs'.

Return Code:
0       : success
non-zero: failure
""")

    program = "review-pull-request"
    parser  = argparse.ArgumentParser(usage=None,
                                      formatter_class=HelpFormatter,
                                      description=description,
                                      prog=program)

    o = parser.add_argument_group("Pull Request")
    o.add_argument("--pull-request",
                   help=     "Supplies the pull request number to review.",
                   type=     int,
                   required= True,
                   action=   "store",
                   dest=     "arg_pull_request")

    o.add_argument("--parent-branch",
                   help=    ("Supplies the branch the pull request's "
                             "topic branch was created from, used as "
                             "the parent to review against.  Defaults "
                             "to 'development'."),
                   action=  "store",
                   default= "development",
                   dest=    "arg_parent_branch")

    o = parser.add_argument_group("Review Notes Editor")
    o.add_argument("--note-editor",
                   help=    ("Supplies the editor used to take review "
                             "notes.  Defaults to 'emacs'."),
                   choices= ("emacs", "vim"),
                   action=  "store",
                   default= "emacs",
                   dest=    "arg_note_editor")

    o.add_argument("--note-editor-theme",
                   help=    ("Supplies the color theme used by the "
                             "review notes editor.  Must be one of: "
                             "solarized_dark, monokai, dracula, "
                             "gruvbox_dark, nord, tomorrow_night, "
                             "classic_green, classic_amber, light.  "
                             "Defaults to 'light'."),
                   choices= ("solarized_dark",
                             "monokai",
                             "dracula",
                             "gruvbox_dark",
                             "nord",
                             "tomorrow_night",
                             "classic_green",
                             "classic_amber",
                             "light"),
                   metavar= "THEME",
                   action=  "store",
                   default= "light",
                   dest=    "arg_note_editor_theme")

    o = parser.add_argument_group("Diff Review Tool")
    o.add_argument("--diff-review-root",
                   help=    ("Supplies the root directory containing "
                             "the 'diff-review' and 'view-review-tabs' "
                             "programs.  Required unless both are "
                             "directly executable via PATH.  See: " +
                             DIFF_REVIEW_URL),
                   action=  "store",
                   default= None,
                   dest=    "arg_diff_review_root")
    return parser


def parse_arguments():
    parser  = configure_parser()
    options = parser.parse_args()
    return options


def resolve_tool(name, root):
    # Returns the absolute pathname of an executable named 'name',
    # either under 'root' (when the caller supplied one) or found on
    # PATH.  Returns None when it cannot be found/is not executable,
    # leaving the caller to report the failure with the exact wording
    # the specification requires.
    if root is not None:
        root_abs = os.path.abspath(os.path.expanduser(root))
        path     = os.path.join(root_abs, name)
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
        return None
    else:
        return shutil.which(name)


def report_tool_not_found(tool_name):
    fatal("The '%s' program must be in PATH, or '--diff-review-root' "
          "must be specified to use this tool.  See: %s"
          % (tool_name, DIFF_REVIEW_URL))


def check_clean_tree(git, env):
    (stdout, stderr, rc) = execute.process([git, "status", "--porcelain"],
                                           env)
    if rc != 0:
        fail_command("Checking the source tree for local changes",
                     rc, stdout, stderr)

    dirty     = []
    untracked = []
    for line in stdout:
        if len(line) == 0:
            continue
        status = line[0:2]
        path   = line[3:]
        if status == "??":
            untracked.append(path)
        else:
            dirty.append(path)

    if len(dirty) > 0:
        fatal("The source tree has staged or unstaged changes; "
              "stash or commit them before a review can be "
              "performed: " + ", ".join(dirty))

    if len(untracked) > 0:
        warning("The source tree has untracked files; git does not "
                "track them, so if this pull request also writes any "
                "of them, it is not known how git will process them -- "
                "they may be corrupted by the review process: " +
                ", ".join(untracked))


def note_current_branch(git, env):
    (stdout, stderr, rc) = execute.process([git, "rev-parse",
                                            "--abbrev-ref", "HEAD"], env)
    if rc != 0:
        fail_command("Determining the current branch", rc, stdout, stderr)
    return stdout[0].strip()


def branch_exists(git, name, env):
    (stdout, stderr, rc) = execute.process([git, "show-ref", "--verify",
                                            "--quiet",
                                            "refs/heads/%s" % (name)],
                                           env)
    return rc == 0


def fetch_pull_request(git, pull_request, review_branch, env):
    refspec = "pull/%d/head:%s" % (pull_request, review_branch)
    (stdout, stderr, rc) = execute.process([git, "fetch", "origin", refspec],
                                           env)
    if rc != 0:
        fail_command("Fetching pull request %d" % (pull_request),
                     rc, stdout, stderr)


def determine_top_of_tree(git, parent_branch, review_branch, env):
    # ${TOT}: the common ancestor of the parent branch and the review
    # branch -- the point at which the pull request's own commits
    # begin, so '${TOT}..HEAD' reviews only those commits.
    (stdout, stderr, rc) = execute.process([git, "fetch", "origin",
                                            parent_branch], env)
    if rc != 0:
        fail_command("Fetching '%s'" % (parent_branch), rc, stdout, stderr)

    (stdout, stderr, rc) = execute.process([git, "merge-base",
                                            "origin/%s" % (parent_branch),
                                            review_branch], env)
    if rc != 0:
        fail_command("Determining the common ancestor with '%s'"
                     % (parent_branch), rc, stdout, stderr)

    top_of_tree = stdout[0].strip()
    if len(top_of_tree) == 0:
        fatal("Could not determine the common ancestor SHA with "
              "'%s'." % (parent_branch))
    return top_of_tree


def checkout_branch(git, name, env):
    (stdout, stderr, rc) = execute.process([git, "checkout", name], env)
    if rc != 0:
        fail_command("Switching to branch '%s'" % (name), rc, stdout, stderr)


def delete_branch(git, name, env):
    (stdout, stderr, rc) = execute.process([git, "branch", "-D", name], env)
    if rc != 0:
        fail_command("Deleting branch '%s'" % (name), rc, stdout, stderr)


def restore_and_cleanup(git, current_branch, review_branch, env):
    # Switching back and deleting the review branch can take a while
    # on a large repository, so let the user know it is happening
    # rather than leaving them staring at a silent, idle screen.
    print_wrapped("Cleaning up: switching back to '%s' and removing "
                  "'%s'.  This may take a moment..."
                  % (current_branch, review_branch))
    checkout_branch(git, current_branch, env)
    # This is also called from an exception handler, where the review
    # branch may never have been fully created (e.g. the fetch that
    # creates it was itself what failed or was interrupted) -- only
    # try to delete it if it actually exists, so cleanup after such a
    # failure does not itself fail by trying to delete a branch that
    # was never there.
    if branch_exists(git, review_branch, env):
        delete_branch(git, review_branch, env)


def run_diff_review(diff_review, pull_request, top_of_tree, env):
    review_root = os.path.expanduser("~/review/oberon-review")
    cmd = [diff_review,
           "-R", review_root,
           "-r", str(pull_request),
           "-c", "%s..HEAD" % (top_of_tree)]
    (stdout, stderr, rc) = execute.process(cmd, env)
    return (stdout, stderr, rc, os.path.join(review_root, str(pull_request)))


def run_view_review_tabs(view_review_tabs, note_editor, note_editor_theme,
                         review_directory, env):
    notes_file = os.path.join(review_directory, "notes.text")
    cmd = [view_review_tabs,
           "--note-editor", note_editor,
           "--note-editor-theme", note_editor_theme,
           "--note-file", notes_file,
           "--diff-dir", review_directory]
    (stdout, stderr, rc) = execute.process(cmd, env)
    return (stdout, stderr, rc, notes_file)


def main():
    options     = parse_arguments()
    options.git = shutil.which("git")
    if options.git is None:
        fatal("The 'git' program must be in PATH.")

    # Nothing here overrides any environment variable, and this
    # script is single-threaded, so there is no need for a private
    # copy of the environment (contrast execute_pool-based callers
    # elsewhere, which override specific variables per call and so
    # must not mutate the one os.environ every thread shares) --
    # 'os.environ' itself is passed straight through.
    env = os.environ

    diff_review = resolve_tool("diff-review", options.arg_diff_review_root)
    if diff_review is None:
        report_tool_not_found("diff-review")

    view_review_tabs = resolve_tool("view-review-tabs",
                                    options.arg_diff_review_root)
    if view_review_tabs is None:
        report_tool_not_found("view-review-tabs")

    check_clean_tree(options.git, env)

    current_branch = note_current_branch(options.git, env)
    review_branch   = "diff-review@pr-%d" % (options.arg_pull_request)

    if branch_exists(options.git, review_branch, env):
        fatal("Branch '%s' already exists; remove it before a review "
              "can be performed." % (review_branch))

    # From here on, this script may create the review branch, switch
    # to it, and run external tools against it -- so from here on,
    # any failure, interruption (e.g. Ctrl-C), or unexpected exception
    # must still leave the repository back on the original branch
    # with the review branch removed, rather than abandoning it
    # half-finished.  This is called from both the normal control
    # flow below and from the exception handlers further down, so it
    # is made idempotent -- safe to call more than once -- rather
    # than relying on every caller to call it at most once.
    cleaned_up = False

    def do_cleanup():
        nonlocal cleaned_up
        if not cleaned_up:
            cleaned_up = True
            restore_and_cleanup(options.git, current_branch,
                                review_branch, env)

    try:
        fetch_pull_request(options.git, options.arg_pull_request,
                           review_branch, env)

        if not branch_exists(options.git, review_branch, env):
            fatal("Branch '%s' does not exist after fetching pull "
                  "request %d." % (review_branch,
                                   options.arg_pull_request))

        top_of_tree = determine_top_of_tree(options.git,
                                            options.arg_parent_branch,
                                            review_branch, env)

        checkout_branch(options.git, review_branch, env)

        result = run_diff_review(diff_review, options.arg_pull_request,
                                 top_of_tree, env)
        (stdout, stderr, rc, review_directory) = result
        if rc != 0:
            print_wrapped(ensure_period("Diff-review failed (rc=%s)"
                                        % (rc)),
                          initial_indent="fatal: ",
                          subsequent_indent="       ")
            dump_output(stdout, stderr)
            do_cleanup()
            sys.exit(1)

        result = run_view_review_tabs(view_review_tabs,
                                      options.arg_note_editor,
                                      options.arg_note_editor_theme,
                                      review_directory, env)
        (stdout, stderr, rc, notes_file) = result
        if rc != 0:
            print_wrapped(ensure_period("View-review-tabs failed "
                                        "(rc=%s)" % (rc)),
                          initial_indent="fatal: ",
                          subsequent_indent="       ")
            dump_output(stdout, stderr)
            do_cleanup()
            sys.exit(1)

        do_cleanup()

        if os.path.exists(notes_file):
            print_wrapped("Review notes were taken in '%s'."
                          % (notes_file))
    except KeyboardInterrupt:
        print_wrapped("Interrupted.")
        do_cleanup()
        sys.exit(130)
    except SystemExit:
        do_cleanup()
        raise
    except Exception:
        do_cleanup()
        raise


if __name__ == "__main__":
    sys.exit(main())
