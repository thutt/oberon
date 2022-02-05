/* Copyright (c) 2021 Logic Magicians Software */

#include "config.h"
#include "dialog.h"
#include "md.h"
#include "skl_flags.h"
#include "skl_cond.h"

namespace skl {

    void
    op_conditional_set(cpu_t &cpu, md::uint32 inst)
    {
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

        opc_t      opc   = static_cast<opc_t>(field(inst, 4, 0));
        unsigned   Rd    = field(inst, 25, 21);
        unsigned   R0    = field(inst, 20, 16);
        md::uint32 R0v   = register_as_integer(cpu, R0, RB_INTEGER);
        bool       value = relation[opc](R0v);

        COMPILE_TIME_ASSERT(N_OPCODES == (sizeof(relation) /
                                          sizeof(relation[0])));

        dialog::trace("%xH: %s  R%u, R%u", cpu.pc, mne[opc], R0, Rd);

        write_integer_register(cpu, Rd, value);
        dialog::trace("[%xH, %u]\n", R0v, value);
        increment_pc(cpu, 1);
    }
}
