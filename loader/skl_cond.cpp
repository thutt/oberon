/* Copyright (c) 2021, 2022 Logic Magicians Software */

#include "config.h"
#include "dialog.h"
#include "md.h"
#include "skl_flags.h"
#include "skl_cond.h"

namespace skl {
    typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_cond_opc.h"
#undef OPC
        N_OPCODES
    } opc_t;

    static const char *mne[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_cond_opc.h"
#undef OPC
    };


    struct skl_conditional_set_t : skl::instruction_t {
        int Rd;
        int R0;

        skl_conditional_set_t(md::OADDR    pc_,
                              md::OINST    inst_,
                              const char **mne_) :
            skl::instruction_t(pc_, inst_, mne_),
            Rd(field(inst, 25, 21)),
            R0(field(inst, 20, 16))
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            md::uint32 R0v   = read_integer_register(cpu, R0);
            bool       value = relation[opc](R0v);

            write_integer_register(cpu, Rd, value);
            increment_pc(cpu, 1);
            dialog::trace("%xH: %s  R%u, R%u  [%xH, %u]\n",
                          cpu->pc, mne, R0, Rd, R0v, value);
        }
    };


    skl::instruction_t *
    op_conditional_set(cpu_t *cpu, md::OINST inst)
    {
        COMPILE_TIME_ASSERT(N_OPCODES == (sizeof(relation) /
                                          sizeof(relation[0])));

        return new skl_conditional_set_t(cpu->pc, inst, mne);
    }
}
