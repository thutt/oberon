/* Copyright (c) 2021 Logic Magicians Software */
#include <assert.h>
#include "setjmp.h"
#include "config.h"
#include "dialog.h"
#include "heap.h"
#include "o3.h"
#include "skl_vmsvc.h"

namespace skl {

    void
    vmsvc_bootstrap(void)
    {

        /* The VMSVC 'bootstrap' function is used to initialize a
         * small set of low-level modules before the rest of the
         * Oberon system can be used.  Clear the stack after each
         * module is initialized so that it does not increase in size
         * with each module.
         */
        initialize_stack();
        longjmp(config::module_init_jmpbuf, 1);

        dialog::not_reachable(__func__);
    }
}
