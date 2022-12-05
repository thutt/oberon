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

    static const char *mnemonics[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_ctrl_reg_opc.h"
#undef OPC
    };


    struct skl_control_reg_t : skl::instruction_t {
        int Rd;
        int R0;

        skl_control_reg_t(md::OADDR pc_, md::OINST inst_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst_, 25, 21)),
            R0(field(inst_, 20, 16))
        {
        }
    };


    struct skl_lcr_t : skl_control_reg_t {
        skl_lcr_t(md::OADDR pc_, md::OINST inst_) :
            skl_control_reg_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            control_registers_t cr = static_cast<control_registers_t>(R0);
            md::uint32          v  = read_control_register(cpu, cr);

            write_integer_register(cpu, Rd, v);
            dialog::trace("%xH: %s  CR%u, R%u\n", skl::program_counter(cpu),
                          mne, R0, Rd);
            increment_pc(cpu, 1);
        }
    };


    struct skl_scr_t : skl_control_reg_t {
        skl_scr_t(md::OADDR pc_, md::OINST inst_) :
            skl_control_reg_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            control_registers_t cr = static_cast<control_registers_t>(Rd);
            md::uint32          r0 = read_integer_register(cpu, R0);

            write_control_register(cpu, cr, r0);
            dialog::trace("%xH: %s  R%u, CR%u\n", skl::program_counter(cpu),
                          mne, R0, cr);
            increment_pc(cpu, 1);
        }
    };



    skl::instruction_t *
    op_ctrl_reg(md::OADDR pc, md::OINST inst)
    {
        opc_t opc = static_cast<opc_t>(field(inst, 4, 0));

        switch (opc) {
        case OPC_LCR: return new skl_lcr_t(pc, inst);
        case OPC_SCR: return new skl_scr_t(pc, inst);

        default:
            dialog::not_implemented("%s: inst: %xH opcode: %xH",
                                    __func__, inst, opc);
        }
    }
}
