#!/usr/bin/python3 -B
#
# Copyright (c) 2026 Logic Magicians Software
#
#  Provides a harness to test the SKL system.  Written for maximal
#  portability because modern Bash is not present on all OSes (looking
#  at you, Apple!)
#
import argparse
import os
import sys
import threading

import execute
import execute_pool


def fatal(msg):
    print("fatal: %s" % (msg))
    sys.exit(1)


def warning(msg):
    print("warning: %s" % (msg))


class Example(object):
    def __init__(self,
                 options,
                 group,
                 test_directory,    # Relative directory.
                 module_name):      # No '.Mod'.

        self._options     = options
        self._group       = group
        self._directory   = test_directory
        self._module_name = module_name
        self._pathname    = os.path.join(options.skl_dir,
                                         test_directory,
                                         "%s.Mod" % (module_name))


def configure_parser():
    description = ("""

This program compiles all the O3C gsa-examples test modules and dumps
the IR for them.

Return Code:
0       : success
non-zero: failure
""")

    program   = "skl-o3c-gsa-examples"
    formatter = argparse.RawDescriptionHelpFormatter
    parser    = argparse.ArgumentParser(usage           = None,
                                        formatter_class = formatter,
                                        description     = description,
                                        prog            = program)

    o = parser.add_argument_group("Output Options")
    o.add_argument("--verbose",
                   help    = ("Turns on verbose diagnostic output."),
                   action  = "store_true",
                   default = False,
                   dest    = "arg_verbose")

    o = parser.add_argument_group("Oberon Heap / Stack Info")
    o.add_argument("--heap-size-in-mb",
                   help     = ("Supplies heap size, in megabytes. "
                               "Must be in the range [4, 127]."),
                   type     = int,
                   required = False,
                   choices  = range(4, 127),
                   action   = "store",
                   default  = 64,
                   dest     = "arg_heap_size")

    o.add_argument("--stack-size-in-mb",
                   help     = ("Supplies stack size, in megabytes. "
                               "Must be in the range [2, 16]."),
                   type     = int,
                   choices  = range(2, 16),
                   action   = "store",
                   default  = 2,
                   dest     = "arg_stack_size")

    o = parser.add_argument_group("Test Specification")
    o.add_argument("--group",
                   help     = ("Supplies stack size, in megabytes. "
                               "Must be in the range [2, 16]."),
                   choices  = ("code",
                               "conditional",
                               "guard",
                               "hardware",
                               "logical",
                               "memory-access",
                               "memory-operations",
                               "miscellaneous",
                               "pseudo",
                               "region",
                               "set-arithmetic",
                               "system",
                               "trap",
                               "type-descriptor"),
                   action   = "append",
                   default  = [],
                   dest     = "arg_groups")

    o = parser.add_argument_group("Concurrency")
    o.add_argument("--jobs", "-j",
                   help    = ("Maximum number of concurrent compiles. "
                              "Defaults to the number of CPUs."),
                   type    = int,
                   action  = "store",
                   default = os.cpu_count() or 1,
                   dest    = "arg_jobs")

    # o = parser.add_argument_group("Oberon Test Specification")
    # # Add a group name so a directory can be run individually.


    parser.add_argument("tail",
                        help  = "Command line tail",
                        nargs = "*")
    return parser


def parse_arguments():
    parser                    = configure_parser()
    options                   = parser.parse_args()
    options.skl_dir           = os.environ["SKL_DIR"]
    options.skl_build_dir     = os.environ["SKL_BUILD_DIR"]
    options.skl_build_type    = os.environ["SKL_BUILD_TYPE"]
    options.skl_build_options = os.environ["SKL_BUILD_OPTIONS"]
    options.skl_search_path   = os.environ["SKL_SEARCH_PATH"]

    assert(options.skl_dir is not None)
    assert(options.skl_build_dir is not None)
    assert(options.skl_build_type is not None)

    options.skl_build_path = os.path.join(options.skl_build_dir,
                                          options.skl_build_type,
                                          options.skl_build_options)
    options.skl_oberon_path = os.path.join(options.skl_build_path,
                                           "loader", "oberon")
    return options


def add_examples(test_definitions, options, group, reldir, modules):
    assert(isinstance(modules, tuple))
    for module in modules:
        module_definition = Example(options, group, reldir, module)
        test_definitions.append(module_definition)


def add_arithmetic_tests(test_definitions, options):
    group    = "arithmetic"
    reldir   = "system/compiler/o3/gsa-examples/arithmetic"
    modules  = ("Aabs",
                "Aadd",
                "Aconvert",
                "Adiv",
                "Amod",
                "Amul",
                "Aneg",
                "Anot",
                "Aodd",
                "Asub")
    add_examples(test_definitions, options, group, reldir, modules)


def add_conditional_tests(test_definitions, options):
    group   = "conditional"
    reldir  = "system/compiler/o3/gsa-examples/conditional"
    modules = ("Ceql",
               "Cgeq",
               "Cgtr",
               "Cleq",
               "Clss",
               "Cneq")
    add_examples(test_definitions, options, group, reldir, modules)


def add_guard_tests(test_definitions, options):
    group   = "guard"
    reldir  = "system/compiler/o3/gsa-examples/guard"
    modules = ("Gcase",
               "Gfalse",
               "Gtrue")
    add_examples(test_definitions, options, group, reldir, modules)


def add_hardware_tests(test_definitions, options):
    group   = "hardware"
    reldir  = "system/compiler/o3/gsa-examples/hardware"
    modules = ("Hget",
               "Hgetreg",
               "Hmemr",
               "Hmemw",
               "Hput",
               "Hputreg")
    add_examples(test_definitions, options, group, reldir, modules)


def add_logical_tests(test_definitions, options):
    group   = "logical"
    reldir  = "system/compiler/o3/gsa-examples/logical"
    modules = ("Aasl",
               "Aasr",
               "Alsl",
               "Alsr",
               "Arol",
               "Aror")
    add_examples(test_definitions, options, group, reldir, modules)


def add_memory_access_tests(test_definitions, options):
    group   = "memory-access"
    reldir  ="system/compiler/o3/gsa-examples/memory-access"
    modules = ("Melement",
               "Mfield",
               "Mheap",
               "Mnonlocal",
               "Mvarparm")
    add_examples(test_definitions, options, group, reldir, modules)


def add_memory_operations_tests(test_definitions, options):
    group   = "memory-operations"
    reldir  = "system/compiler/o3/gsa-examples/memory-operations"
    modules = ("Madr",
               "Marraycopy",
               "Mdynarrlen",
               "Mheaptag",
               "Mcreatenlm",
               "Mdeletenlm",
               "Mnewarray",
               "Mnewdynarray",
               "Mnewrecord",
               "Mrecordcopy",
               "Mstringcopy",
               "Mtbpadr",
               "Minitialize")
    add_examples(test_definitions, options, group, reldir, modules)


def add_miscellaneous_tests(test_definitions, options):
    group   = "miscellaneous"
    reldir  = "system/compiler/o3/gsa-examples/miscellaneous"
    modules = ("Gcall",
               "Gcap",
               "Gcopy",
               "Ggate",
               "Gimport")
    add_examples(test_definitions, options, group, reldir, modules)


def add_pseudo_tests(test_definitions, options):
    group   = "pseudo"
    reldir  = "system/compiler/o3/gsa-examples/pseudo"
    modules = ("Pmayalias", )
    add_examples(test_definitions, options, group, reldir, modules)


def add_region_tests(test_definitions, options):
    group   = "region"
    reldir  = "system/compiler/o3/gsa-examples/region"
    modules = ("Mcasereg",
               "Menter",
               "Mexit",
               "Mgreg")
    add_examples(test_definitions, options, group, reldir, modules)


def add_set_arithmetic_tests(test_definitions, options):
    group   = "set-arithmetic"
    reldir  = "system/compiler/o3/gsa-examples/set-arithmetic"
    modules = ("Sconvert",
               "Sdiff",
               "Selement",
               "Sexcl",
               "Sincl",
               "Sintersection",
               "Sneg",
               "Srange",
               "Ssub",
               "Sunion")
    add_examples(test_definitions, options, group, reldir, modules)


def add_system_tests(test_definitions, options):
    group   = "system"
    reldir  = "system/compiler/o3/gsa-examples/system"
    modules = ("Gbit",
               "Gcondcode",
               "Gfinalize",
               "Gmove",
               "Gnewblock",
               "Gresetbit",
               "Gsetbit")
    add_examples(test_definitions, options, group, reldir, modules)


def add_trap_tests(test_definitions, options):
    group   = "trap"
    reldir  = "system/compiler/o3/gsa-examples/trap"
    modules = ("Tassert",
               "Tcase",
               "Teguard",
               "Thalt",
               "Tiguard",
               "Tindex",
               "Treturn",
               "Twith")
    add_examples(test_definitions, options, group, reldir, modules)


def add_type_descriptor_tests(test_definitions, options):
    group   = "type-descriptor"
    reldir  = "system/compiler/o3/gsa-examples/type-descriptor"
    modules = ("Ginitarr",
               "Ginitdarr",
               "Ginitrec")
    add_examples(test_definitions, options, group, reldir, modules)


def add_code_tests(test_definitions, options):
    group   = "code"
    reldir  = "system/compiler/o3/gsa-examples/code"
    modules = ("straight",
               "if",
               "looping")
    add_examples(test_definitions, options, group, reldir, modules)


def execute_oberon(options, additional_search_path, arguments):
    # Build a private copy of the environment for this call, rather
    # than mutating os.environ in place: this function runs
    # concurrently (see perform_test()), and os.environ is shared by
    # every thread in the process.  Two concurrent calls mutating it
    # in place could race, so that one thread's subprocess forks
    # with the *other* thread's search path or heap size.
    search_path        = options.skl_search_path
    env                = dict(os.environ)
    env["LMS_OBERON_HEAP_SIZE"]  = str(options.arg_heap_size)
    env["LMS_OBERON_STACK_SIZE"] = str(options.arg_stack_size)
    env["SKL_SEARCH_PATH"]       = "%s:%s" % (search_path,
                                              additional_search_path)

    cmd = [options.skl_oberon_path, "--" ] + arguments
    if options.arg_verbose:
        print("EXEC: '%s'" % (' '.join(cmd)))
    (stdout, stderr, rc) = execute.process(cmd, env=env)
    return (stdout, stderr, rc)


def dump_list(prefix, lines):
    for l in lines:
        print("%s%s" % (prefix, l))


def dump(stdout, stderr, rc):
    dump_list("  stdout:", stdout)
    dump_list("  stderr:", stderr)
    print("  rc    : ", rc)


def compile_module(options, module):
    cmd = [ "O3.Compile", "-c", "GSA", module ]
    return execute_oberon(options, None, cmd)


def test_module(options, test):
    # Runs on a worker thread (see perform_test()).  Output is
    # returned rather than printed directly, so the caller can print
    # each test's lines as one uninterrupted block instead of
    # interleaving them with other tests running at the same time.
    # For the same reason, failure is returned rather than reported
    # via fatal(): sys.exit() from a worker thread only terminates
    # that thread, not the process, so aggregation and the final
    # exit have to happen back on the main thread.
    lines = ["*** Building: '%s'" % (test._module_name)]
    (stdout, stderr, rc) = compile_module(options, test._pathname)
    success = (rc == 0)
    if not success:
        lines.append("**** Module '%s' failed to compile" % (test._pathname))
        lines.extend("  stdout:%s" % l for l in stdout)
        lines.extend("  stderr:%s" % l for l in stderr)
        lines.append("  rc    :  %s" % (rc))
    return (test, success, lines)


def perform_test(options, test_definitions, groups):
    assert(len(groups) == 0 or isinstance(groups, list))
    selected = [test for test in test_definitions
               if len(groups) == 0 or test._group in groups]

    print_lock = threading.Lock()
    failures   = []

    def handle_outcome(outcome):
        if not outcome.ok:
            # A bug in test_module()/compile_module() itself (not an
            # ordinary compile failure, which comes back as 'success
            # == False' above) -- still must not be lost silently.
            test = outcome.args[1]
            with print_lock:
                print("*** Building: '%s'" % (test._module_name))
                print("**** Exception: %s" % (outcome.exception))
            failures.append(test)
            return

        (test, success, lines) = outcome.result
        with print_lock:
            for line in lines:
                print(line)
        if not success:
            failures.append(test)

    pool = execute_pool.ExecutePool(max_workers=options.arg_jobs)
    for test in selected:
        pool.submit(test_module, options, test, callback=handle_outcome)
    pool.join()
    pool.shutdown()

    if failures:
        paths = ", ".join(test._pathname for test in failures)
        fatal("%d module(s) failed to compile: %s" % (len(failures), paths))


def main():
    options  = parse_arguments()

    test_definitions = [ ]

    add_arithmetic_tests(test_definitions, options)
    add_conditional_tests(test_definitions, options)
    add_guard_tests(test_definitions, options)
    add_hardware_tests(test_definitions, options)
    add_logical_tests(test_definitions, options)
    add_memory_access_tests(test_definitions, options)
    add_memory_operations_tests(test_definitions, options)
    add_miscellaneous_tests(test_definitions, options)
    add_pseudo_tests(test_definitions, options)
    add_region_tests(test_definitions, options)
    add_set_arithmetic_tests(test_definitions, options)
    add_system_tests(test_definitions, options)
    add_trap_tests(test_definitions, options)
    add_type_descriptor_tests(test_definitions, options)
    add_code_tests(test_definitions, options)

    perform_test(options, test_definitions, options.arg_groups)


if __name__ == "__main__":
    sys.exit(main())
