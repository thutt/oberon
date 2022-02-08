/* Copyright (c) 2022 Logic Magicians Software */

#include "config.h"
#include "dialog.h"
#include "md.h"
#include "skl_flags.h"
#include "skl_cond.h"

namespace skl {
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


    struct skl_sys_reg_t : skl::instruction_t {
        unsigned    Rd;

        skl_sys_reg_t(cpu_t       *cpu_,
                      md::uint32   inst_,
                      const char **mne_) :
            skl::instruction_t(cpu_, inst_, mne_),
            Rd(field(inst_, 25, 21))
        {
        }


        virtual void interpret(void)
        {
            skl::write_integer_register(cpu, Rd, cpu->_instruction_count);
            dialog::trace("%xH: %s  R%u", pc, mne, Rd);
            increment_pc(cpu, 1);
        }
    };

    skl::instruction_t *
    op_sys_reg(cpu_t *cpu, md::uint32 inst)
    {
        opc_t opc = static_cast<opc_t>(field(inst, 4, 0));

        switch (opc) {
        case OPC_EI:
            dialog::not_implemented("%s: ei");

        case OPC_DI:
            dialog::not_implemented("%s: di");

        case OPC_LCC:
            return new skl_sys_reg_t(cpu, inst, mne);

        default:
            dialog::not_implemented("%s: inst: %xH opcode: %x#",
                                    __func__, inst, opc);
        }
    }
}
