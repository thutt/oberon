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


class Test(object):
    def __init__(self,
                 options,
                 test_group,        # { 'system' }
                 test_directory,    # Relative directory.
                 module_name,       # No '.Mod'.
                 manual_test,       # True  -> Test is run.
                                    # False -> Test is only run manually
                 module_compiles,   # True  -> Source module does compile.
                                    # False -> Source module does not  compile.
                 zero_rc_is_pass):  # True  -> Pass -> rc == 0, fail -> rc != 0.
                                    # False -> Pass -> rc != 0, fail -> rc == 0.
        assert(isinstance(test_group, str) and test_group in ("compiler",
                                                              "module",
                                                              "o3",
                                                              "system"))
        self._options         = options
        self._group           = test_group
        self._directory       = test_directory
        self._module_name     = module_name
        self._pathname        = os.path.join(options.skl_dir,
                                             test_directory,
                                             "%s.Mod" % (module_name))

        self._manual_test     = manual_test

        self._module_compiles = module_compiles

        # A positive test is successful when the return code (RC) is
        # zero.
        #
        # A negative test is successful when the RC is non-zero.
        #
        # Positive tests must pass True for this argument.
        # Negative tests must pass False for this argument.
        #
        self._zero_rc_is_pass = zero_rc_is_pass


def configure_parser():
    description = ("""

This program abstracts the module tests into a portable mechanism to
test Oberon modules because Bash associative arrarys are not available
on all supported operating systems.

Return Code:
0       : success
non-zero: failure
""")

    program   = "module-test-harness"
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


    o = parser.add_argument_group("Oberon Test Specification")
    o.add_argument("--system",
                   help     = ("Performs Oberon system testing. "),
                   action   = "store_true",
                   default  = False,
                   dest     = "arg_system_test")

    o.add_argument("--module",
                   help     = ("Performs Oberon module testing. "),
                   action   = "store_true",
                   default  = False,
                   dest     = "arg_module_test")

    o.add_argument("--compiler",
                   help     = ("Performs Oberon compiler testing. "),
                   action   = "store_true",
                   default  = False,
                   dest     = "arg_compiler_test")


    o = parser.add_argument_group("Concurrency")
    o.add_argument("--jobs", "-j",
                   help     = ("Maximum number of concurrent tests. "
                               "Defaults to the number of CPUs."),
                   type     = int,
                   action   = "store",
                   default  = os.cpu_count() or 1,
                   dest     = "arg_jobs")

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


# XXX Need another argument to indicate if the source should compile.
def add_test(test_definitions, options, group, reldir,
             module,
             manual_test,
             module_compiles,
             zero_rc_is_pass):
    module_definition = Test(options, group, reldir, module,
                             manual_test, module_compiles, zero_rc_is_pass)
    test_definitions.append(module_definition)


def add_system_tests(test_definitions, options):
    add_test(test_definitions, options, "system",
             "system/lms/tests",
             "StackOverflow",
             False,             # Not manual.
             True,              # Compiles.
             False)

def add_module_tests(test_definitions, options):
    add_test(test_definitions, options, "module",
             "system/lms/tests",
             "MemoryExhaust",
             False,
             True,              # Compiles.
             True)

    add_test(test_definitions, options, "module",
             "system/lms/tests",
             "MkTree",
             False,
             True,              # Compiles.
             True)

    add_test(test_definitions, options, "module",
             "system/lms/tests",
             "RealMath",
             False,
             True,              # Compiles.
             True)

    add_test(test_definitions, options, "module",
             "system/tests",
             "Random",
             False,
             True,              # Compiles.
             True)


def add_compiler_tests(test_definitions, options):
    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTArrayTrap",
             False,             # Manual
             True,              # Compiles.
             False)             # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTAssertTrap",
             False,             # Manual
             True,              # Compiles.
             False)             # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTBitsetRangeFail",
             False,             # Manual
             True,              # Compiles.
             False)             # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTConditionCode",
             False,             # Manual
             True,              # Compiles.
             True)             # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTDivZero",
             False,             # Manual
             True,              # Compiles.
             False)             # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTDumpHeap",
             True,              # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTDynArrLength",
             False,             # Manual
             True,              # Compiles.
             False)             # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTDynamicArray",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTEmpty",
             True,              # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTEnvironment",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTExclude",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTFileIO",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTFingerprint",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTFor",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTGC",
             True,              # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTGetOpt",
             True,              # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTImport",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTIncDec",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTInstructionCount",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTInvalidOpcode",
             False,             # Manual
             True,              # Compiles.
             False)             # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTMissingMethod",
             False,             # Manual
             False,             # Does not compile..
             False)             # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTMultidim",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTNest",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTOOBRead",
             False,             # Manual
             True,              # Compiles.
             False)             # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTOOBWrite",
             False,             # Manual
             True,              # Compiles.
             False)             # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTOpenArray",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTPathnames",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTProcedure",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTRange",
             False,             # Manual
             True,              # Compiles.
             False)             # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTReal",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTReturn",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTRotate",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTSET",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTSetCtor",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTString",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTTDCodeGen",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTTrapNil",
             False,             # Manual
             True,              # Compiles.
             False)             # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success

    add_test(test_definitions, options, "compiler",
             "system/compiler/skl/tests",
             "CTTypeDesc",
             True,              # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success


def add_o3_tests(test_definitions, options):
    # Compiler not released, so this cannot actually be used.
    add_test(test_definitions, options, "o3",
             "compiler/o3/regression",
             "CTTypeDesc",
             False,             # Manual
             True,              # Compiles.
             True)              # True  -> rc == 0 -> success
                                # False -> rc != 0 -> success


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
    (stdout, stderr, rc) = execute.process(cmd, env=env)
    return (stdout, stderr, rc)


def dump_list(prefix, lines):
    result = []
    for l in lines:
        result.append("%s%s" % (prefix, l))
    return result


def dump(stdout, stderr, rc):
    # Returns lines rather than printing them: test_module() runs on
    # a worker thread (see perform_test()), and printing directly
    # from there would interleave with other tests running at the
    # same time.
    lines = dump_list("  stdout:", stdout)
    lines.extend(dump_list("  stderr:", stderr))
    lines.append("  rc    :  %s" % (rc))
    return lines


def compile_module(options, module):
    return execute_oberon(options, None, [ "SKL.Compile", module ])


def test_module(options, test):
    # Runs on a worker thread (see perform_test()).  Output is
    # returned rather than printed directly, so the caller can print
    # each test's lines as one uninterrupted block instead of
    # interleaving them with other tests running at the same time.
    # For the same reason, failure is returned rather than reported
    # via fatal(): sys.exit() from a worker thread only terminates
    # that thread, not the process, so aggregation and the final
    # exit have to happen back on the main thread.
    lines = []
    if test._manual_test:
        lines.append("Manual mode: '%s'" % (test._module_name))
        return (test, True, lines)

    lines.append("*** Building: '%s'" % (test._module_name))
    (stdout, stderr, rc) = compile_module(options, test._pathname)
    if rc != 0:
        if test._module_compiles:
            lines.append("**** Module was expected to compile, "
                         "but did not '%s'" % (test._pathname))
            lines.extend(dump(stdout, stderr, rc))
            return (test, False, lines)
        else:
            # The module was not expected to compile, and it did not.
            pass
    else:
        if not test._module_compiles:
            lines.append("**** Module was not expected to compile, "
                         "but it did '%s'" % (test._pathname))
            lines.extend(dump(stdout, stderr, rc))
            return (test, False, lines)
        else:
            # The module was not expected to compile, and it did.
            pass

    # Run module.
    lines.append("*** Executing: '%s'" % (test._module_name))
    (stdout, stderr, rc) = execute_oberon(options,
                                          os.path.join(options.skl_dir,
                                                       test._directory),
                                          [ "%s.Test" %
                                            (test._module_name) ])
    if test._zero_rc_is_pass:
        # To pass, the RC must be 0.
        if rc != 0:
            lines.append("**** Test failed at runtime: '%s'" % (test._pathname))
            lines.extend(dump(stdout, stderr, rc))
            return (test, False, lines)
    else:
        # To pass, the RC must be non-zero.
        if rc == 0:
            lines.append("**** Test did not fail as expected: '%s'" %
                         (test._pathname))
            lines.extend(dump(stdout, stderr, rc))
            return (test, False, lines)
    lines.append("*** Test passed: '%s'" % (test._module_name))
    return (test, True, lines)


def perform_test(options, test_definitions, group):
    selected = [test for test in test_definitions if test._group == group]

    print_lock = threading.Lock()
    failures   = []

    def handle_outcome(outcome):
        if not outcome.ok:
            # A bug in test_module() itself (not an ordinary test
            # failure, which comes back as 'success == False' above)
            # -- still must not be lost silently.
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
        fatal("%d test(s) failed: %s" % (len(failures), paths))



def main():
    options  = parse_arguments()

    test_definitions = [ ]
    add_system_tests(test_definitions, options)
    add_module_tests(test_definitions, options)
    add_compiler_tests(test_definitions, options)
    add_o3_tests(test_definitions, options) # These are not
                                            # implemented as of this
                                            # commit.

    if options.arg_system_test:
        perform_test(options, test_definitions, "system")

    if options.arg_module_test:
        perform_test(options, test_definitions, "module")

    if options.arg_compiler_test:
        perform_test(options, test_definitions, "compiler")


if __name__ == "__main__":
    sys.exit(main())
