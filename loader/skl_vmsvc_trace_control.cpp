/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <assert.h>

#include "config.h"
#include "dialog.h"
#include "heap.h"
#include "o3.h"
#include "skl_vmsvc.h"

namespace skl {

    typedef struct vmsvc_trace_control_desc_t : vmsvc_desc_t {
        bool trace_enable;
    } vmsvc_trace_control_desc_t;


    void
    vmsvc_trace_control(md::OADDR adr)
    {
        md::HADDR                   ptr   = heap::host_address(adr);
        vmsvc_trace_control_desc_t *vmsvc = reinterpret_cast<vmsvc_trace_control_desc_t *>(ptr);

        if (skl_trace) {
            if (vmsvc->trace_enable) {
                config::option_set(config::opt_trace_cpu);
            } else {
                config::option_clear(config::opt_trace_cpu);
            }
        }
    }
}
