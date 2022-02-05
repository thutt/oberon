/* Copyright (c) 2021 Logic Magicians Software */

#include "config.h"
#include "dialog.h"
#include "md.h"
#include "o3.h"                 // XXX remove
#include "skl_flags.h"
#include "skl_cond.h"

namespace skl {

    void
    op_ctrl_reg(cpu_t &cpu, md::uint32 inst)
    {
        typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_ctrl_reg_opc.h"
#undef OPC
            N_OPCODES
        } opc_t;
        static const char *mne[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_ctrl_reg_opc.h"
#undef OPC
        };

        opc_t      opc = static_cast<opc_t>(field(inst, 4, 0));
        unsigned   Rd  = field(inst, 25, 21);
        unsigned   R0  = field(inst, 20, 16);
        md::uint32 r0;

        switch (opc) {
        case OPC_LCR: {
            control_registers_t cr = static_cast<control_registers_t>(R0);
            md::uint32          v  = read_control_register(cpu, cr);

            dialog::trace("%xH: %s  CR%u, R%u", cpu.pc, mne[opc], R0, Rd);
            write_integer_register(cpu, Rd, v);
            break;
        }

        case OPC_SCR:
            control_registers_t cr = static_cast<control_registers_t>(Rd);
            r0 = read_integer_register(cpu, R0);

            dialog::trace("%xH: %s  R%u, CR%u", cpu.pc, mne[opc], R0, cr);
            write_control_register(cpu, cr, r0);
            break;
        }

        increment_pc(cpu, 1);
    }
}
