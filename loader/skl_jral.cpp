/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <assert.h>
#include "dialog.h"
#include "o3.h"
#include "skl_jral.h"

namespace skl {
    void
    op_jral(cpu_t &cpu, md::uint32 inst)
    {
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
        opc_t       opc         = OPC_JRAL;
        unsigned    Rd          = field(inst, 25, 21);
        unsigned    R0          = field(inst, 20, 16);
        md::uint32  return_addr = cpu.pc + sizeof(md::uint32);
        md::uint32  new_pc      = read_integer_register(cpu, R0);
        O3::decode_pc_t decoded_pc;
        O3::decode_pc_t decoded_new;
        O3::decode_pc_t decoded_ra;

        O3::decode_pc(cpu.pc, decoded_pc);
        O3::decode_pc(new_pc, decoded_new);
        O3::decode_pc(return_addr, decoded_ra);
        dialog::trace("%s: %s  R%u, R%u", decoded_pc, mne[opc], R0, Rd);
        dialog::trace("[pc := %s, retpc := %s]\n", decoded_new, decoded_ra);

        // TODO: Check for new_pc alignment and raise alignment fault.


        write_integer_register(cpu, Rd, return_addr);
        cpu.pc = new_pc;
    }
}
