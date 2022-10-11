#!/usr/bin/python3
# Copyright (c) 2022 Logic Magicians Software
#
#  This tool reads 'gsa-instruction.template' and a MetaPost file for
#  each instruction.  The file is used to produce graphical
#  representations of the GSA data structure for the instruction.
#  
#  It also produces a depdency file that is is included into the build
#  process to set up relationships to ensure that the documentation is
#  rebuilt when needed.
#
import argparse
import sys

def configure_parser():
    description = ("""

This script creates MetaPost files for drawing GSA instructions in the
GSA compiler documentation.

Return Code:
0       : success
non-zero: failure
""")

    program   = "gsa-instruction"
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

    o.add_argument("--makefile-include",
                   help     = ("Include files used by GSA Doc Makefile"),
                   action   = "store",
                   required = True,
                   dest     = "arg_include")

    o = parser.add_argument_group("Input Options")
    o.add_argument("--template",
                   help     = "Input template file",
                   action   = "store",
                   required = True,
                   dest     = "arg_template")


    parser.add_argument("tail",
                        help  = "Command line tail",
                        nargs = "*")
    return parser


def parse_arguments():
    parser  = configure_parser()
    options = parser.parse_args()

    return options


def read_template(template):
    with open(template, "r") as fp:
        lines = fp.read()

    return lines.split('\n')


def main():
    options  = parse_arguments()

    templates = read_template(options.arg_template)

    include = open(options.arg_include, "w")
    include.write("GSAINSTMP\t=")

    for line in templates:
        if line.startswith("#"):
            continue            # Ignore comments
        if len(line) == 0:
            break               # End of file.

        fields      = line.split('|')
        output      = fields[0]
        instruction = fields[1]
        ops         = fields[2]
        results     = fields[3]
        ares        = results.split(',')
        aops        = []
        if len(ops) > 0:
            aops = ops.split(',')

        include.write("\t\\\n\tgen-gsa-instruction-%s.mp" % (output))
        with open("gen-gsa-instruction-%s.mp" % (output), "w") as fp:
            fp.write("input gsa-instruction-prologue.mp;\n");
            fp.write("n_res=%d;\n" % (len(ares)))
            fp.write("n_op=%d;\n"  % (len(aops)))
            fp.write("boxit.inst(btex$\\strut "
                     "\\rm{\\$%s}$ etex);\n" % (instruction))
            fp.write("circleit.res[0](btex$\\strut "
                     "\\rm{res}_d$ etex);\n")
            fp.write("circleit.res[1](btex$\\strut "
                     "\\rm{\\$%s}$ etex);\n" % (instruction))
            fp.write("circleit.op[0](btex$\\strut \\rm{op}_d$ etex);\n")

            i = 1
            for operand in aops:
                fp.write("circleit.op[%d](btex$\\strut "
                         "\\rm{%s}$ etex);\n" % (i, operand))
                i += 1

            if len(ares) > 1:
                i = 2
                for res in ares:
                    fp.write("circleit.res[%d](btex$\\strut "
                             "\\rm{%s}$ etex);\n" % (i, res))
                    i += 1;
                
            fp.write("input gsa-instruction-epilogue.mp;\n");

    include.write("\n\n")
    include.close()

    return 0




if __name__ == "__main__":
    sys.exit(main())

