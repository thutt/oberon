/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <assert.h>
#include "config.h"
#include "dialog.h"
#include "heap.h"
#include "o3.h"
#include "skl_vmsvc.h"

namespace skl {
    typedef enum vmsvc_operation_t {
#define VMSVC(_op) VMSVC_##_op,
#include "skl_vmsvc_operation.h"
#undef VMSVC
        N_VMSVC_OPERATIONS
    } vmsvc_operation_t;

    static const char *operations[N_VMSVC_OPERATIONS] = {
#define VMSVC(_op) #_op,
#include "skl_vmsvc_operation.h"
#undef VMSVC
    };


    struct skl_vmsvc_t : skl::instruction_t {
        unsigned R0;

        skl_vmsvc_t(cpu_t       *cpu_,
                    md::uint32   inst_,
                    const char **mne_) :
            skl::instruction_t(cpu_, inst_, mne_),
            R0(field(inst_, 20, 16))
        {
        }


        virtual void interpret(void)
        {
            md::uint32        svc;
            const md::uint32  adr       = read_integer_register(cpu, R0);
            const char       *operation = "invalid vmsvc";

            svc = skl::read(adr, false, sizeof(md::uint32));

            if (svc < N_VMSVC_OPERATIONS) {
                operation = operations[svc];
            }

            dialog::trace("%s: %s  R%u", decoded_pc, mne, R0);
            dialog::trace("[%s]\n", operation);

            switch (svc) {
            case VMSVC_BOOTSTRAP:
                vmsvc_bootstrap();
                break;

            case VMSVC_TRACE_CONTROL:
                vmsvc_trace_control(adr);
                break;

            case VMSVC_EARLY_SYSTRAP:
                vmsvc_early_systrap(adr);
                break;

            case VMSVC_DEBUG_LOG:
                vmsvc_debug_log(adr);
                break;

            case VMSVC_TERMINATE:
                vmsvc_terminate(adr);
                break;

            case VMSVC_TIME:
                dialog::not_implemented("%s: time", __func__);
                break;

            case VMSVC_DIRECTORY:
                dialog::not_implemented("%s: directory", __func__);
                break;

            case VMSVC_FILE:
                vmsvc_file(adr);
                break;

            case VMSVC_CONSOLE:
                vmsvc_console(adr);
                break;

            case VMSVC_FILL_MEMORY:
                vmsvc_fill_memory(adr);
                break;

            case VMSVC_EARLY_HWDTRAP:
                vmsvc_early_hwdtrap(adr);
                break;

            case VMSVC_ENVIRONMENT:
                vmsvc_environment(adr);
                break;

            default:
                dialog::not_implemented("unhandled vmsvc", __func__);
                break;
            }
            increment_pc(cpu, 1);
        }
    };


    skl::instruction_t *
    op_vmsvc(cpu_t *cpu, md::uint32 inst, const char **mne)
    {
        return new skl_vmsvc_t(cpu, inst, mne);
    }
}
