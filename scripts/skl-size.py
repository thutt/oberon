#!/usr/bin/python3
#
# Copyright (c) 2022 Logic Magicians Software
#
import argparse
import os
import sys

import execute


def fatal(msg):
    print("fatal: %s" % (msg))
    sys.exit(1)


def warning(msg):
    print("warning: %s" % (msg))


class Artifact(object):
    def __init__(self, options, root, pathname):
        self._options  = options
        self._pathname = pathname
        self._valid    = os.path.exists(self._pathname)
        self._sections = {
            ".bss"          : None,
            ".data"         : None,
            ".fini"         : None,
            ".fini_array"   : None,
            ".init"         : None,
            ".init_array"   : None,
            ".plt"          : None,
            ".plt.got"      : None,
            ".rodata"       : None,
            ".text"         : None
        }

        root = os.path.dirname(root)
        self._relpath = self._pathname.replace("%s%s" % (root, os.path.sep), "")

        self.objdump()

    def add_to_text(self, sname):
        if sname in self._sections:
            self._sections[".text"] += self._sections[sname]

    def objdump(self):
        cmd = [ "/usr/bin/objdump",
                "--section-headers", self._pathname ]

        if self._valid:
            (stdout, stderr, rc) = execute.process(cmd)
            assert(rc == 0)
            # The lines output by 'objdump', and matched by the loop
            # below will look like this:
            #
            #   10 .init         0000001a  00000000004010f0  00000000004010f0  000010f0  2**2
            #   13 .text         000073e2  0000000000401420  0000000000401420  00001420  2**4
            #   14 .fini         00000009  0000000000408804  0000000000408804  00008804  2**2
            #   15 .rodata       000029ab  0000000000408820  0000000000408820  00008820  2**5
            #   19 .init_array   00000010  000000000060ede8  000000000060ede8  0000ede8  2**3
            #   19 .init_array   00000010  000000000060ede8  000000000060ede8  0000ede8  2**3
            #   20 .fini_array   00000008  000000000060edf8  000000000060edf8  0000edf8  2**3
            #   20 .fini_array   00000008  000000000060edf8  000000000060edf8  0000edf8  2**3
            #   25 .data         00000828  000000000060f1a0  000000000060f1a0  0000f1a0  2**5
            #   26 .bss          00000e08  000000000060f9e0  000000000060f9e0  0000f9c8  2**5
            #
            # The size is the first number column, in columns [18, 26).  In base 16.

            for l in stdout:
                for s in self._sections:
                    if s in l:
                        self._sections[s] = int(l[18:26],16)

            # Fixup .text to include other sections known to be code.
            self.add_to_text(".fini");
            self.add_to_text(".init");
            self.add_to_text(".plt");
            self.add_to_text(".plt_got");

    def values(self):
        if self._valid:
            return (self._sections[".text"],
                    self._sections[".rodata"],
                    self._sections[".data"],
                    self._sections[".bss"])
        else:
            return None



def configure_parser():
    description = ("""

This script allows one to measure the size of executables produced for
this project.  It can also be used to compare different source trees
so that progress on code / data growth can be tracked on commit.

Return Code:
0       : success
non-zero: failure
""")

    program   = "size"
    formatter = argparse.RawDescriptionHelpFormatter
    parser    = argparse.ArgumentParser(usage           = None,
                                        formatter_class = formatter,
                                        description     = description,
                                        prog            = program)

    o = parser.add_argument_group("Output Options")
    o.add_argument("--verbose",
                   help    = ("Turns on verbose diagnostic output"),
                   action  = "store_true",
                   default = False,
                   dest    = "arg_verbose")

    o.add_argument("--compare",
                   help     = "Comparison root build output directory.",
                   action   = "store",
                   default  = None,
                   required = False,
                   dest     = "arg_compare_path")

    o.add_argument("--skl-build-path",
                   help     = "Root of build output directory.",
                   action   = "store",
                   required = True,
                   dest     = "arg_skl_build_path")

    parser.add_argument("tail",
                        help  = "Command line tail",
                        nargs = "*")
    return parser


def parse_arguments():
    parser          = configure_parser()
    options         = parser.parse_args()
    options.skl_dir = os.environ["SKL_DIR"] # Guaranteed set by wrapper.
    return options


def gather_artifacts(options, root):
    images = (
        os.path.join(root, "loader", "oberon"),
        os.path.join(root, "disasm", "disasm")
    )

    artifacts = { }
    for img in images:
        artifact = Artifact(options, root, img)
        artifacts[artifact._relpath] = artifact

    return artifacts


def program_name_width(artifacts):
    width = 0
    for pname in artifacts:

        width = max(width, len(artifacts[pname]._relpath))
    return width


def header(width, field_width):
    print("%*s  %*s  %*s  %*s  %*s" % (width, "",
                                       field_width, ".text",
                                       field_width, ".rodata",
                                       field_width, ".data",
                                       field_width, ".bss"))

def scale(n):
    if abs(n) > 1024 * 1024 * 1024:  # Gb
        suffix = "G"
        v = "%d" % (n / (1024 * 1024 * 1024))
    elif abs(n) > 1024 * 1024:
        suffix = "M"
        v = "%d" % (n / (1024 * 1024))
    elif abs(n) > 1024:
        suffix = "K"
        v = "%d" % (n / 1024)
    else:
        suffix = ""
        v = "%d" % (n)


    return "%s%s" % (v, suffix) # At most, 6 characters (i.e.: '-1024M')


def compare(base, modi):
    assert(len(base) == len(modi))
    width = program_name_width(base)
    field_width = 14

    print("")
    header(width, field_width)
    for pname in base:
        bartifact = base[pname]
        bres      = bartifact.values()

        if pname in modi:
            martifact = modi[pname]
            mres      = martifact.values()
        else:
            martifact = None
            mres      = None

        if bres is not None and mres is not None:
            delta = (mres[0] - bres[0],
                     mres[1] - bres[1],
                     mres[2] - bres[2],
                     mres[3] - bres[3])
            text   = "%6s%8s" % (scale(mres[0]), "(%s)" % (scale(delta[0])))
            rodata = "%6s%8s" % (scale(mres[1]), "(%s)" % (scale(delta[1])))
            data   = "%6s%8s" % (scale(mres[2]), "(%s)" % (scale(delta[2])))
            bss    = "%6s%8s" % (scale(mres[3]), "(%s)" % (scale(delta[3])))
            print("%-*s  %-*s  %-*s  %-*s  %-*s" %
                  (width, bartifact._relpath,
                   field_width, text,   # .text
                   field_width, rodata, # .rodata
                   field_width, data,   # .data
                   field_width, bss))    # .bss
        else:
            if bres is None:
                print("%*s     MISSING: %s" % (width, bartifact._relpath,
                                               bartifact._pathname))
            else:
                assert(mres is None)
                print("%*s     MISSING: %s" % (width, bartifact._relpath,
                                               "modified image"))
    print("")


def report(artifacts):
    width = program_name_width(artifacts)
    print("")
    field_width = 8
    header(width, field_width)
    for pname in artifacts:
        artifact = artifacts[pname]
        res = artifact.values()
        if res is not None:
            print("%*s  %*s  %*s  %*s  %*s" %
                  (width, artifact._relpath,
                   field_width, scale(res[0]), # .text
                   field_width, scale(res[1]), # .rodata
                   field_width, scale(res[2]), # .data
                   field_width, scale(res[3]))) # .bss
        else:
            print("%*s     <MISSING: %s>" % (width, artifact._relpath,
                                             artifact._pathname))
    print("")


def main():
    options  = parse_arguments()

    modi = gather_artifacts(options, options.arg_skl_build_path)
    if options.arg_compare_path is not None:
        base = gather_artifacts(options, options.arg_compare_path)
        compare(base, modi)
    else:
        report(modi)
    return 0

if __name__ == "__main__":
    sys.exit(main())
