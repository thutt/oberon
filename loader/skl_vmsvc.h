/* Copyright (c) 2021, 2022 Logic Magicians Software */
#if !defined(_SKL_VMSVC_H)
#define _SKL_VMSVC_H

#include "md.h"
#include "skl_instruction.h"
#include "skl.h"

namespace skl {

    typedef struct vmsvc_desc_t { // SKLKernel.VMServiceDesc
        md::uint32 service;
    } vmsvc_desc_t;


    skl::instruction_t *op_vmsvc(cpu_t *cpu, md::OINST inst, const char **mne);
    void vmsvc_bootstrap(void);
    void vmsvc_console(md::OADDR adr);
    void vmsvc_debug_log(md::OADDR adr);
    void vmsvc_directory(md::OADDR adr);
    void vmsvc_early_hwdtrap(md::OADDR adr);
    void vmsvc_early_systrap(md::OADDR adr);
    void vmsvc_environment(md::OADDR adr);
    void vmsvc_file(md::OADDR adr);
    void vmsvc_fill_memory(md::OADDR adr);
    void vmsvc_terminate(md::OADDR adr);
    void vmsvc_trace_control(md::OADDR adr);
}
#endif
