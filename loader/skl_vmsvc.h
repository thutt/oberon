/* Copyright (c) 2021 Logic Magicians Software */
#if !defined(_SKL_VMSVC_H)
#define _SKL_VMSVC_H

#include "md.h"
#include "skl.h"

namespace skl {

    typedef struct vmsvc_desc_t { // SKLKernel.VMServiceDesc
        md::uint32 service;
    } vmsvc_desc_t;


    void op_vmsvc(cpu_t &cpu, md::uint32 inst, const char *mne);
    void vmsvc_bootstrap(void);
    void vmsvc_console(md::uint32 adr);
    void vmsvc_debug_log(md::uint32 adr);
    void vmsvc_early_systrap(md::uint32 adr);
    void vmsvc_early_hwdtrap(md::uint32 adr);
    void vmsvc_environment(md::uint32 adr);
    void vmsvc_file(md::uint32 adr);
    void vmsvc_terminate(md::uint32 adr);
    void vmsvc_trace_control(md::uint32 adr);
    void vmsvc_fill_memory(md::uint32 adr);
}
#endif
