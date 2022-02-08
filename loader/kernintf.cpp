/* Copyright (c) 2000, 2021, 2022 Logic Magicians Software */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
#include "config.h"
#include "heap.h"
#include "objinfo.h"
#include "dialog.h"
#include "dump.h"
#include "o3.h"
#include "md.h"
#include "kernintf.h"
#include "skl.h"
#include "o3.h"

namespace kernintf
{
    void
    init_module(O3::module_t *m)
    {
        md::uint8  *oname = heap::host_address(m->name);
        const char *mname = reinterpret_cast<const char *>(oname);
        md::uint32 init_fn = O3::lookup_command(m, mname);

        assert(strcmp(O3::bootstrap_symbol[0].name, "BootstrapModuleInit") == 0);

        /* The module initialization functions return to the bootstrap
         * loader with a VMSVC instruction.  Make the return address
         * on the stack noticeable for these functions, since it will
         * never be used.
         */
        skl::write_integer_register(&skl::cpu, skl::RETADR, 0xdeadbeef);

        /* Set R28 to the module initialization function, and invoke
         * SKLKernel.BootstrapModuleInit.  That function will invoke
         * it the module initialization through R28.  When control
         * returns to SKLKernel.BootstrapModuleInit, a VMSVC
         * 'Bootstrap' operation will return control to the bootstrap
         * system.
         */
        skl::write_integer_register(&skl::cpu, 28, init_fn);

        if (setjmp(config::module_init_jmpbuf) == 0) {
            skl::execute(&skl::cpu, O3::bootstrap_symbol[0].adr);
        } else {
            /* longjmp() has returned here.
             * Return to caller to continue bootstrapping.
             */
            ++O3::n_inited;
        }
    }
}
