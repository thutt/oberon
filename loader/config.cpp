/* Copyright (c) 2000, 2020, 2021, 2022 Logic Magicians Software */
#include <assert.h>
#include "config.h"

namespace config
{
    options_t flags = opt_none;
    const options_t &options = flags;
    jmp_buf module_init_jmpbuf;
    exit_data_t exit_data;

    void option_set(options_t opt)
    {
        assert(sizeof(int) == sizeof(options_t));
        flags = static_cast<options_t>(flags | opt);
    }

    void option_clear(options_t opt)
    {
        assert(sizeof(int) == sizeof(options_t));
        flags = static_cast<options_t>(flags & ~opt);
    }

    void
    quit(int rc)
    {
        exit_data.rc = rc;
        longjmp(exit_data.jmpbuf, 1);
        INFINITE_LOOP();
    }
}
