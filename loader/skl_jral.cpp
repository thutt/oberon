/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <assert.h>
#include "dialog.h"
#include "o3.h"
#include "skl_jral.h"

namespace skl {
    typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_jral_opc.h"
#undef OPC
        N_OPCODES
    } opc_t;
    static const char *mne[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_jral_opc.h"
#undef OPC
    };


    struct skl_jral_t : skl::instruction_t {
        int       Rd;
        int       R0;
        md::OADDR return_addr;
        md::OADDR new_pc;

        skl_jral_t(cpu_t      *cpu_,
                   md::OINST   inst_,
                   const char **mne_) :
            skl::instruction_t(cpu_, inst_, mne_),
            Rd(field(inst_, 25, 21)),
            R0(field(inst_, 20, 16)),
            return_addr(pc + static_cast<md::OADDR>(sizeof(md::uint32)))
        {
        }


        virtual void interpret(void)
        {
            O3::decode_pc_t decoded_ra;
            O3::decode_pc_t decoded_new;

            O3::decode_pc(return_addr, decoded_ra);
            O3::decode_pc(new_pc, decoded_new);
            new_pc = read_integer_register(cpu, R0);

            dialog::trace("%s: %s  R%u, R%u", decoded_pc, mne, R0, Rd);
            dialog::trace("[pc := %s, retpc := %s]\n", decoded_new, decoded_ra);

            write_integer_register(cpu, Rd, return_addr);
            cpu->pc = new_pc;
        }
    };


    skl::instruction_t *
    op_jral(cpu_t *cpu, md::OINST inst)
    {
        /* If new opcodes added, this code needs investigation. */
        COMPILE_TIME_ASSERT(sizeof(mne) / sizeof(mne[0]) == 1);
        return new skl_jral_t(cpu, inst, mne);
    }
}
