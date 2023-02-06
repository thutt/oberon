/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <assert.h>
#include "setjmp.h"
#include "config.h"
#include "dialog.h"
#include "heap.h"
#include "o3.h"
#include "skl_vmsvc.h"

namespace skl {
    // Kernel.VMServiceTerminateDesc
    typedef struct vmsvc_terminate_desc_t : vmsvc_desc_t {
        md::uint32 rc;
    } vmsvc_terminate_desc_t;


    void
    vmsvc_terminate(md::OADDR adr)
    {
        md::HADDR               ptr   = heap::host_address(adr);
        vmsvc_terminate_desc_t *vmsvc = reinterpret_cast<vmsvc_terminate_desc_t *>(ptr);

        COMPILE_TIME_ASSERT(sizeof(int) >= sizeof(md::uint32));

        /* Print the actual exit code to stderr and return 120.  This
         * is done because POSIX only supports 8-bit return values,
         * but Oberon can exit with a value greater than 128 (the
         * number of bits generally allowed for user-space exit
         * codes).
         */
        if (vmsvc->rc != 0) {
            fprintf(stderr, "Oberon exited with return code: %u\n",
                    vmsvc->rc);
            config::quit(static_cast<unsigned char>(120));
        } else {
            config::quit(static_cast<unsigned char>(0));
        }
    }
}
