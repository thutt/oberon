/* Copyright (c) 2000, 2020-2021 Logic Magicians Software */
#if !defined(_DIALOG_H)
#define _DIALOG_H

#include <stdarg.h>
#include "config.h"

namespace dialog
{
    void fatal(const char *fmt, ...);
    void warning(const char *fmt, ...);
    void progress(const char *fmt, ...);
    void print(const char *fmt, ...);
    void diagnostic(const char *fmt, ...);
    void not_implemented(const char *fmt, ...);
    void not_reachable(const char *fmt, ...);
    void internal_error(const char *fmt, ...);

    void trace__(const char *fmt, va_list args); /* Trace instructions. */
    void cpu__(const char *fmt, va_list args); /* State of CPU. */

    static inline void
    trace(const char *fmt, ...)
    {
        if (skl_trace) {
            va_list args;
            va_start(args, fmt);
            trace__(fmt, args);
            va_end(args);
        }
    }

    static inline void
    cpu(const char *fmt, ...)
    {
        if (skl_trace) {
            va_list args;
            va_start(args, fmt);
            cpu__(fmt, args);
            va_end(args);
        }
    }
}
#endif
