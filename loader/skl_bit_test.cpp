/* Copyright (c) 2021, 2022 Logic Magicians Software */

#include "dialog.h"
#include "o3.h"
#include "skl_bit_test.h"

namespace skl {
    typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_bit_test_opc.h"
#undef OPC
        N_OPCODES
    } opc_t;

    static const char *mnemonics[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_bit_test_opc.h"
#undef OPC
    };

    typedef enum bit_test_memory_op_t {
        bt_read,                // Read bit only.
        bt_clear,               // Clear after read.
        bt_set                  // Set after read.
    } bit_test_memory_op_t;


    static unsigned
    bit_test(unsigned v, int b)
    {
        unsigned r = right_shift(v, b) & 1;
        dialog::trace("[%u, %xH]  [result: %d]\n", b, v, r);
        return r;
    }


    struct skl_bt_t : skl::instruction_t {
        int   Rd;
        int   R0;
        int   R1;

        skl_bt_t(md::OADDR    pc_,
                 md::OINST    inst_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst, 25, 21)),
            R0(field(inst, 20, 16)),
            R1(field(inst, 15, 11))
        {
        }

        virtual void interpret(skl::cpuid_t cpu)
        {
            const md::uint32 r0 = read_integer_register(cpu, R0);
            const md::uint32 r1 = read_integer_register(cpu, R1);
            unsigned         b;

            dialog::trace("%s: %s  R%u, R%u, R%u", decoded_pc, mne, R0, R1, Rd);
            b = bit_test(r1, static_cast<int>(r0));
            write_integer_register(cpu, Rd, b);
            increment_pc(cpu, 1);
        }
    };


    struct skl_bti_t : skl::instruction_t {
        int   Rd;
        int   C;
        int   R1;

        skl_bti_t(md::OADDR pc_, md::OINST inst_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst, 25, 21)),
            C(field(inst, 20, 16)),
            R1(field(inst, 15, 11))
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            const md::uint32 v = read_integer_register(cpu, R1);
            md::uint32       b;

            dialog::trace("%s: %s  %xH, R%u, R%u", decoded_pc, mne, C, R1, Rd);
            b = bit_test(v, C);
            write_integer_register(cpu, Rd, b);
            increment_pc(cpu, 1);
        }
    };


    static unsigned
    bit_test_memory(skl::cpuid_t         cpuid,
                    md::OADDR            ea,
                    int                  b,
                    bit_test_memory_op_t op)
    {
        const md::uint32 v = skl::read(cpuid, ea, true, sizeof(md::uint32));
        unsigned         r = right_shift(v, b) & 1;

        dialog::trace("[%u, (ea: %xH, value: %xH)]  [%d]\n", b, ea, v, r);
        if (!skl::exception_raised(cpuid)) {
            switch (op) {
            case bt_read:
                break;          // nop

            case bt_clear: {
                unsigned   mask  = ~left_shift(1, b);
                md::uint32 nv = (v & static_cast<md::uint32>(mask));
                skl::write(cpuid, ea, nv, sizeof(md::uint32));
                break;
            }

            case bt_set: {
                unsigned   mask = left_shift(1, b);
                md::uint32 nv   = (v | static_cast<md::uint32>(mask));
                skl::write(cpuid, ea, nv, sizeof(md::uint32));
                break;
            }
            }
        }
        return r;
    }


    struct skl_btm_family_t : skl::instruction_t {
        int                  Rd;
        int                  R0;
        int                  R1;
        bit_test_memory_op_t op;

        skl_btm_family_t(md::OADDR              pc_,
                         md::OINST              inst_,
                         bit_test_memory_op_t   op_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst, 25, 21)),
            R0(field(inst, 20, 16)),
            R1(field(inst, 15, 11)),
            op(op_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            const md::uint32 bit  = read_integer_register(cpuid, R0) & md::MaxSet;
            const md::OADDR  addr = read_integer_register(cpuid, R1);
            unsigned         b;

            dialog::trace("%s: %s  R%u, (R%u), R%u", decoded_pc, mne, R0, R1, Rd);
            b = bit_test_memory(cpuid, addr, static_cast<int>(bit), op);
            if (!skl::exception_raised(cpuid)) {
                write_integer_register(cpuid, Rd, b);
                increment_pc(cpuid, 1);
            }
        }
    };


    struct skl_btmi_family_t : skl::instruction_t {
        int                  Rd;
        int                  C;
        int                  R1;
        bit_test_memory_op_t op;

        skl_btmi_family_t(md::OADDR            pc_,
                          md::OINST            inst_,
                          bit_test_memory_op_t op_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst, 25, 21)),
            C(field(inst, 20, 16)),
            R1(field(inst, 15, 11)),
            op(op_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            const md::OADDR addr = read_integer_register(cpuid, R1);
            unsigned        b    = bit_test_memory(cpuid, addr, C, op);

            if (!skl::exception_raised(cpuid)) {
                write_integer_register(cpuid, Rd, b);
                increment_pc(cpuid, 1);
            }
            dialog::trace("%s: %s  %xH, (R%u), R%u\n", decoded_pc, mne, C, R1, Rd);
        }
    };


    skl::instruction_t *
    op_bit_test(md::OADDR pc, md::OINST inst)
    {
        opc_t     opc = static_cast<opc_t>(field(inst, 4, 0));

        switch (opc) {
        case OPC_BT:    return new skl_bt_t(pc, inst);
        case OPC_BTI:   return new skl_bti_t(pc, inst);
        case OPC_BTM:   return new skl_btm_family_t(pc, inst, bt_read);
        case OPC_BTMI:  return new skl_btmi_family_t(pc, inst, bt_read);
        case OPC_BTMC:  return new skl_btm_family_t(pc, inst, bt_clear);
        case OPC_BTMCI: return new skl_btmi_family_t(pc, inst, bt_clear);
        case OPC_BTMS:  return new skl_btm_family_t(pc, inst, bt_set);
        case OPC_BTMSI: return new skl_btmi_family_t(pc, inst, bt_set);

        default:
            dialog::not_implemented("%s: inst: %xH opcode: %xH",
                                    __func__, inst, opc);
        }
    }
}
