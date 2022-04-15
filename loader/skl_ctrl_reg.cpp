/* Copyright (c) 2021, 2022 Logic Magicians Software */

#include "config.h"
#include "dialog.h"
#include "md.h"
#include "skl_flags.h"
#include "skl_cond.h"

namespace skl {
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


    struct skl_lcr_t : skl::instruction_t {
        int Rd;
        int R0;

        skl_lcr_t(cpu_t       *cpu_,
                  md::OINST    inst_,
                  const char **mne_) :
            skl::instruction_t(cpu_, inst_, mne_),
            Rd(field(inst_, 25, 21)),
            R0(field(inst_, 20, 16))
        {
        }


        virtual void interpret(void)
        {
            control_registers_t cr = static_cast<control_registers_t>(R0);
            md::uint32          v  = read_control_register(cpu, cr);

            write_integer_register(cpu, Rd, v);
            increment_pc(cpu, 1);
            dialog::trace("%xH: %s  CR%u, R%u", pc, mne, R0, Rd);
        }
    };


    struct skl_scr_t : skl::instruction_t {
        int Rd;
        int R0;

        skl_scr_t(cpu_t       *cpu_,
                  md::OINST    inst_,
                  const char **mne_) :
            skl::instruction_t(cpu_, inst_, mne_),
            Rd(field(inst_, 25, 21)),
            R0(field(inst_, 20, 16))
        {
        }


        virtual void interpret(void)
        {
            control_registers_t cr = static_cast<control_registers_t>(Rd);
            md::uint32          r0 = read_integer_register(cpu, R0);

            write_control_register(cpu, cr, r0);
            increment_pc(cpu, 1);
            dialog::trace("%xH: %s  R%u, CR%u", pc, mne, R0, cr);
        }
    };



    skl::instruction_t *
    op_ctrl_reg(cpu_t *cpu, md::OINST inst)
    {
        opc_t opc = static_cast<opc_t>(field(inst, 4, 0));

        switch (opc) {
        case OPC_LCR:
            return new skl_lcr_t(cpu, inst, mne);

        case OPC_SCR:
            return new skl_scr_t(cpu, inst, mne);


        default:
            dialog::not_implemented("%s: inst: %xH opcode: %xH",
                                    __func__, inst, opc);
        }
    }
}
