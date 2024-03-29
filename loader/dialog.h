/* Copyright (c) 2000, 2020-2022 Logic Magicians Software */
#if !defined(_DIALOG_H)
#define _DIALOG_H

#include <stdarg.h>
#include "config.h"

namespace dialog
{
    void NORETURN fatal(const char *fmt, ...);
    void warning(const char *fmt, ...);
    void print(const char *fmt, ...);
    void NORETURN not_implemented(const char *fmt, ...);
    void NORETURN not_reachable(const char *fmt, ...);
    void NORETURN internal_error(const char *fmt, ...);

    void progress__(const char *fmt, va_list args);
    void diagnostic__(const char *fmt, va_list args);
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


    static inline void
    progress(const char *fmt, ...)
    {
        if (skl_alpha &&
            config::options & config::opt_progress) {
            va_list args;
            va_start(args, fmt);
            progress__(fmt, args);
            va_end(args);
        }
    }


    static inline void
    diagnostic(const char *fmt, ...)
    {
        if (skl_alpha &&
            config::options & config::opt_diagnostic) {
            va_list args;
            va_start(args, fmt);
            diagnostic__(fmt, args);
            va_end(args);
        }
    }
}
#endif
