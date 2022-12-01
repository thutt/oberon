/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <assert.h>
#include "dialog.h"
#include "o3.h"
#include "skl_flags.h"
#include "skl_jump.h"

namespace skl {
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


    struct skl_jal_t : skl::instruction_t {
        int             Rd;
        md::OADDR       destination;
        md::OADDR       return_addr;

        skl_jal_t(md::OADDR    pc_,
                  md::OINST    inst_,
                  const char **mne_) :
            skl::instruction_t(pc_, inst_, mne_)
        {
            Rd          = field(inst, 25, 21);
            destination = skl::read(pc_ + 4, false, sizeof(md::uint32));
            return_addr = pc + 2 * static_cast<md::OADDR>(sizeof(md::uint32));
            assert(Rd == RETADR);
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            O3::decode_pc_t decoded_ra;
            O3::decode_pc_t decoded_new;

            O3::decode_pc(return_addr, decoded_ra);
            O3::decode_pc(destination, decoded_new);
            dialog::trace("%s: %s  %xH", decoded_pc, mne, destination);
            dialog::trace("[pc := %s, retpc := %s]\n", decoded_new, decoded_ra);
            write_integer_register(cpu, RETADR, return_addr);
            cpu->pc = destination;
        }
    };

    struct skl_conditional_jump_t : skl::instruction_t {
        int             rel;
        int             R0;
        md::OADDR       addr;
        md::OADDR       destination;

        skl_conditional_jump_t(md::OADDR    pc_,
                               opc_t        rel_,
                               md::OINST    inst_,
                               const char **mne_) :
            skl::instruction_t(pc_, inst_, mne_),
            rel(rel_),
            R0(field(inst, 20, 16)),
            addr(skl::read(pc + 4, false, sizeof(md::uint32))),
            destination(pc +
                        2 * static_cast<md::OADDR>(sizeof(md::uint32)) + addr)
        {
        }

        virtual void interpret(skl::cpu_t *cpu)
        {
            O3::decode_pc_t decoded_da;
            md::uint32      flags          = read_integer_register(cpu, R0);
            bool            compare_result = relation[rel](flags);

            O3::decode_pc(destination, decoded_da);

            dialog::trace("%s: %s  R%u, %xH", decoded_pc, mne, R0, addr);
            dialog::trace("[%xH, %s]  ZSCO: %u%u%u%u [taken: %u]\n",
                          flags, decoded_da,
                          flag(flags, ZF),
                          flag(flags, SF),
                          flag(flags, CF),
                          flag(flags, OF),
                          compare_result);
            if (compare_result) {
                cpu->pc = destination;
            } else {
                increment_pc(cpu, 2);
            }
        }
    };


    struct skl_jump_t : skl::instruction_t {
        md::OADDR       addr;
        md::OADDR       destination;

        skl_jump_t(md::OADDR    pc_,
                   md::OINST    inst_,
                   const char **mne_) :
            skl::instruction_t(pc_, inst_, mne_),
            addr(skl::read(pc + 4, false, sizeof(md::uint32))),
            destination(pc + (2 * static_cast<md::OADDR>(sizeof(md::uint32))) +
                        addr)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            O3::decode_pc_t decoded_da;

            O3::decode_pc(destination, decoded_da);
            dialog::trace("%s: %s  %xH", decoded_pc, mne, addr);
            dialog::trace("[%s]\n", decoded_da);
            cpu->pc = destination;
        }
    };


    skl::instruction_t *
    op_jump(cpu_t *cpu, md::OINST inst)
    {
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
            return new skl_conditional_jump_t(cpu->pc, opc, inst, mne);

        case OPC_J:
            return new skl_jump_t(cpu->pc, inst, mne);

        case OPC_JAL:
            return new skl_jal_t(cpu->pc, inst, mne);

        default:
            dialog::not_implemented("%s: inst: %xH opcode: %xH",
                                    __func__, inst, opc);
        }
    }
}
