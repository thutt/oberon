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
    static const char *mnemonics[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_jral_opc.h"
#undef OPC
    };


    struct skl_jral_t : skl::instruction_t {
        int       Rd;
        int       R0;
        md::OADDR return_addr;

        skl_jral_t(md::OADDR pc_, md::OINST inst_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst_, 25, 21)),
            R0(field(inst_, 20, 16)),
            return_addr(pc_ + static_cast<md::OADDR>(sizeof(md::uint32)))
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            O3::decode_pc_t decoded_ra;
            O3::decode_pc_t decoded_new;
            md::OADDR       new_pc = read_integer_register(cpuid, R0);

            O3::decode_pc(return_addr, decoded_ra);
            O3::decode_pc(new_pc, decoded_new);

            dialog::trace("%s: %s  R%u, R%u", decoded_pc, mne, R0, Rd);
            dialog::trace("[pc := %s, retpc := %s]\n", decoded_new, decoded_ra);

            write_integer_register(cpuid, Rd, return_addr);
            skl::set_program_counter(cpuid, new_pc);
        }
    };


    skl::instruction_t *
    op_jral(md::OADDR pc, md::OINST inst)
    {
        /* If new opcodes added, this code needs investigation. */
        COMPILE_TIME_ASSERT(sizeof(mnemonics) / sizeof(mnemonics[0]) == 1);
        return new skl_jral_t(pc, inst);
    }
}
