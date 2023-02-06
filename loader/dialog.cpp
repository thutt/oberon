/* Copyright (c) 2000, 2020, 2021, 2022, 2023 Logic Magicians Software */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "config.h"
#include "dialog.h"

namespace dialog
{
    void
    fatal(const char *fmt, ...)
    {
        va_list args;

        fflush(stdout);
        fprintf(stderr, "\nfatal error: ");
        va_start(args, fmt);
        vfprintf(stderr, fmt, args);
        fprintf(stderr, "\n");
        va_end(args);
        config::quit(118);
    }


    void
    not_reachable(const char *fmt, ...)
    {
        va_list args;

        fflush(stdout);
        fprintf(stderr, "\nNOT REACHABLE: ");
        va_start(args, fmt);
        vfprintf(stderr, fmt, args);
        fprintf(stderr, "\n");
        va_end(args);
        config::quit(117);
    }


    void
    not_implemented(const char *fmt, ...)
    {
        va_list args;

        fflush(stdout);
        fprintf(stderr, "\nNOT IMPLEMENTED: ");
        va_start(args, fmt);
        vfprintf(stderr, fmt, args);
        fprintf(stderr, "\n");
        va_end(args);
        config::quit(116);
    }


    void
    internal_error(const char *fmt, ...)
    {
        va_list args;

        fflush(stdout);
        fprintf(stderr, "\nInternal Error: ");
        va_start(args, fmt);
        vfprintf(stderr, fmt, args);
        fprintf(stderr, "\n");
        va_end(args);
        config::quit(115);
    }


    void
    warning(const char *fmt, ...)
    {
        va_list args;

        fflush(stdout);
        fprintf(stderr, "\nwarning: ");
        va_start(args, fmt);
        vfprintf(stderr, fmt, args);
        fprintf(stderr, "\n");
        va_end(args);
    }


    void
    progress__(const char *fmt, va_list args)
    {
        vfprintf(stdout, fmt, args);
    }


    void
    print(const char *fmt, ...)
    {
        va_list args;

        va_start(args, fmt);
        vfprintf(stdout, fmt, args);
        va_end(args);
    }


    void
    diagnostic__(const char *fmt, va_list args)
    {
        fprintf(stderr, "diagnostic: ");
        vfprintf(stderr, fmt, args);
    }


    void
    trace__(const char *fmt, va_list args)
    {
        static bool label = true; // Label first line, and every line after '\n'.

        if (config::options & config::opt_trace_cpu) {
            bool col1 = label;
            int n_char;
            if (label) {
                fprintf(stderr, "trace: ");
            }
            label = fmt[strlen(fmt) - 1] == '\n';
            n_char = vfprintf(stderr, fmt, args);
            if (col1 && !label) {
                /* Pad column 1 so column 2 is always at same offset */
                const int col1_width = 50;
                if (n_char >= col1_width) {
                    /* If the number of characters printed already
                     * exceed the colum1 position, have only a single
                     * character space.
                     */
                    n_char = col1_width - 1;
                }
                fprintf(stderr, "%*s", col1_width - n_char, " ");
            }
        }
    }


    void
    cpu__(const char *fmt, va_list args)
    {
        static bool label = true;

        if (config::options & config::opt_trace_cpu) {
            if (label) {
                fprintf(stderr, "cpu: ");
                label = false;
            }
            vfprintf(stderr, fmt, args);
            label = fmt[strlen(fmt) - 1] == '\n';
        }
    }
}
