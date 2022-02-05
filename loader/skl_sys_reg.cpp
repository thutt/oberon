/* Copyright (c) 2021, 2022 Logic Magicians Software */

#include "config.h"
#include "dialog.h"
#include "md.h"
#include "o3.h"                 // XXX remove
#include "skl_flags.h"
#include "skl_cond.h"

namespace skl {

    void
    op_sys_reg(cpu_t &cpu, md::uint32 inst)
    {
        typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_sys_reg_opc.h"
#undef OPC
            N_OPCODES
        } opc_t;
        static const char *mne[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_sys_reg_opc.h"
#undef OPC
        };

        opc_t      opc = static_cast<opc_t>(field(inst, 4, 0));
        unsigned   Rd  = field(inst, 25, 21);

        switch (opc) {
        case OPC_EI:
            dialog::not_implemented("%s: ei");
            break;

        case OPC_DI:
            dialog::not_implemented("%s: di");
            break;

        case OPC_LCC:
            skl::write_integer_register(cpu, Rd, cpu._instruction_count);
            dialog::trace("%xH: %s  R%u", cpu.pc, mne[opc], Rd);
            break;
        }

        increment_pc(cpu, 1);
    }
}
