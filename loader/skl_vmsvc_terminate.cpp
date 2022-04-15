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
        config::quit(static_cast<int>(vmsvc->rc));
    }
}
