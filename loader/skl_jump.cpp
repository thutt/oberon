/* Copyright (c) 2021 Logic Magicians Software */
#include <assert.h>
#include "dialog.h"
#include "o3.h"
#include "skl_flags.h"
#include "skl_jump.h"

namespace skl {
    static void
    op_jal(cpu_t &cpu, md::uint32 inst, const char *mne)
    {
        UNUSED unsigned Rd          = field(inst, 25, 21);
        md::uint32      addr        = skl::read(cpu.pc + 4, false, sizeof(md::uint32));
        md::uint32      return_addr = cpu.pc + 2 * sizeof(md::uint32);
        O3::decode_pc_t decoded_pc;
        O3::decode_pc_t decoded_ra;
        O3::decode_pc_t decoded_new;

        assert(Rd == RETADR);
        O3::decode_pc(cpu.pc, decoded_pc);
        O3::decode_pc(return_addr, decoded_ra);
        O3::decode_pc(addr, decoded_new);
        dialog::trace("%s: %s  %xH", decoded_pc, mne, addr);
        dialog::trace("[pc := %s, retpc := %s]\n", decoded_new, decoded_ra);
        write_integer_register(cpu, RETADR, return_addr);
        cpu.pc = addr;
    }


    static void
    op_conditional_jump(cpu_t      &cpu,
                        unsigned    rel,
                        md::uint32  inst,
                        const char *mne)
    {
        unsigned    R0        = field(inst, 20, 16);
        md::uint32  flags     = read_integer_register(cpu, R0);
        md::uint32  addr      = skl::read(cpu.pc + 4, false, sizeof(md::uint32));
        md::uint32  dest_addr = cpu.pc + 2 * sizeof(md::uint32) + addr;
        bool        result    = relation[rel](flags);
        O3::decode_pc_t decoded_pc;
        O3::decode_pc_t decoded_da;

        O3::decode_pc(cpu.pc, decoded_pc);
        O3::decode_pc(dest_addr, decoded_da);
        dialog::trace("%s: %s  R%u, %xH", decoded_pc, mne, R0, addr);
        dialog::trace("[%xH, %s]  ZSCO: %u%u%u%u [taken: %u]\n",
                      flags, decoded_da,
                      flag(flags, ZF),
                      flag(flags, SF),
                      flag(flags, CF),
                      flag(flags, OF),
                      result);

        if (result) {
            cpu.pc = dest_addr;
        } else {
            increment_pc(cpu, 2);
        }
    }


    static void
    op_j(cpu_t &cpu, md::uint32 inst, const char *mne)
    {
        md::uint32  addr      = skl::read(cpu.pc + 4, false, sizeof(md::uint32));
        md::uint32  dest_addr = cpu.pc + 2 * sizeof(md::uint32) + addr;
        O3::decode_pc_t decoded_pc;
        O3::decode_pc_t decoded_da;

        O3::decode_pc(cpu.pc, decoded_pc);
        O3::decode_pc(dest_addr, decoded_da);
        dialog::trace("%s: %s  %xH", decoded_pc, mne, addr);
        dialog::trace("[%s]\n", decoded_da);
        cpu.pc = dest_addr;
    }


    void
    op_jump(cpu_t &cpu, md::uint32 inst)
    {
        typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_jump_opc.h"
#undef OPC
            N_OPCODES
        } opc_t;
        static const char *mne[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_jump_opc.h"
#undef OPC
        };
        opc_t opc = static_cast<opc_t>(field(inst, 4, 0));

        switch (opc) {
        case OPC_JEQ:
        case OPC_JNE:
        case OPC_JLT:
        case OPC_JGE:
        case OPC_JLE:
        case OPC_JGT:
        case OPC_JLTU:
        case OPC_JGEU:
        case OPC_JLEU:
        case OPC_JGTU:
            op_conditional_jump(cpu, opc, inst, mne[opc]);
            break;

        case OPC_J:
            op_j(cpu, inst, mne[opc]);
            break;

        case OPC_JAL:
            op_jal(cpu, inst, mne[opc]);
            break;

        default:
            dialog::not_implemented("%s: inst: %xH %s",
                                    __func__, inst, mne[opc]);
        }
    }
}
