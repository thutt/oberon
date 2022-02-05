/* Copyright (c) 2000, 2020, 2021, 2022 Logic Magicians Software */

#if !defined(_CONFIG_H)
#define _CONFIG_H
#include <stdlib.h>
#include <setjmp.h>

/* NO SKL FILES SHOULD BE INCLUDED HERE! */

#include "buildenv.h"


namespace config
{
    enum options_t
    {
        opt_none                 = 0,
        opt_ignore_helper_fixups = 1 << 0,
        opt_dump_heap            = 1 << 1,
        opt_progress             = 1 << 2,
        opt_diagnostic           = 1 << 3,
        opt_trace_cpu            = 1 << 4,
        opt_instruction_count    = 1 << 5
    };

    typedef struct exit_data_t {
        int     rc;
        jmp_buf jmpbuf;
    } exit_data_t;

    extern const options_t &options;
    extern jmp_buf module_init_jmpbuf;
    extern jmp_buf exit_jmpbuf;
    extern exit_data_t exit_data;

    void option_set(options_t opt);
    void option_clear(options_t opt);
    void NORETURN quit(int rc); /* Quit interpreter with return code. */
}
#endif
