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

    static unsigned
    bit_test(unsigned v, int b)
    {
        unsigned r = right_shift(v, b) & 1;
        dialog::trace("[%u, %xH]  [result: %d]\n", b, v, r);
        return r;
    }


    static unsigned
    bit_test_memory_read(skl::cpuid_t         cpuid,
                         md::OADDR            ea,
                         int                  b)
    {
        const md::uint32 v = skl::read(cpuid, ea, true, sizeof(md::uint32));
        unsigned         r = right_shift(v, b) & 1;

        dialog::trace("[%u, (ea: %xH, value: %xH)]  [%d]\n", b, ea, v, r);
        return r;
    }


    static unsigned
    bit_test_memory_clear(skl::cpuid_t         cpuid,
                          md::OADDR            ea,
                          int                  b)
    {
        const md::uint32 v    = skl::read(cpuid, ea, true, sizeof(md::uint32));
        unsigned         r    = right_shift(v, b) & 1;
        unsigned         mask = ~left_shift(1, b);
        md::uint32       nv   = (v & static_cast<md::uint32>(mask));

        dialog::trace("[%u, (ea: %xH, value: %xH)]  [%d]\n", b, ea, v, r);
        if (!skl::exception_raised(cpuid)) {
            skl::write(cpuid, ea, nv, sizeof(md::uint32));
        }
        return r;
    }


    static unsigned
    bit_test_memory_set(skl::cpuid_t         cpuid,
                          md::OADDR            ea,
                          int                  b)
    {
        const md::uint32 v    = skl::read(cpuid, ea, true, sizeof(md::uint32));
        unsigned         r    = right_shift(v, b) & 1;
        unsigned         mask = left_shift(1, b);
        md::uint32       nv   = (v | static_cast<md::uint32>(mask));

        dialog::trace("[%u, (ea: %xH, value: %xH)]  [%d]\n", b, ea, v, r);
        if (!skl::exception_raised(cpuid)) {
            skl::write(cpuid, ea, nv, sizeof(md::uint32));
        }
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
            const md::uint32 r0 = read_integer_register(cpu, R0) & md::MaxSet;
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


    struct skl_btm_base_t : skl::instruction_t {
        int                  Rd;
        int                  R0;
        int                  R1;

        skl_btm_base_t(md::OADDR              pc_,
                       md::OINST              inst_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst, 25, 21)),
            R0(field(inst, 20, 16)),
            R1(field(inst, 15, 11))
        {
        }

        void epilog(skl::cpuid_t cpuid, unsigned b)
        {
            if (!skl::exception_raised(cpuid)) {
                write_integer_register(cpuid, Rd, b);
                increment_pc(cpuid, 1);
            }
        }
    };


    struct skl_btm_read_t : skl_btm_base_t {
        skl_btm_read_t(md::OADDR pc_, md::OINST inst_) :
            skl_btm_base_t(pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpuid)
        {
            const md::uint32 bit  = read_integer_register(cpuid, R0) & md::MaxSet;
            const md::OADDR  addr = read_integer_register(cpuid, R1);
            unsigned         b;

            dialog::trace("%s: %s  R%u, (R%u), R%u", decoded_pc, mne, R0, R1, Rd);
            b = bit_test_memory_read(cpuid, addr, static_cast<int>(bit));
            epilog(cpuid, b);
        }
    };


    struct skl_btm_clear_t : skl_btm_base_t {
        skl_btm_clear_t(md::OADDR pc_, md::OINST inst_) :
            skl_btm_base_t(pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpuid)
        {
            const md::uint32 bit  = read_integer_register(cpuid, R0) & md::MaxSet;
            const md::OADDR  addr = read_integer_register(cpuid, R1);
            unsigned         b;

            dialog::trace("%s: %s  R%u, (R%u), R%u", decoded_pc, mne, R0, R1, Rd);
            b = bit_test_memory_clear(cpuid, addr, static_cast<int>(bit));
            epilog(cpuid, b);
        }
    };


    struct skl_btm_set_t : skl_btm_base_t {
        skl_btm_set_t(md::OADDR pc_, md::OINST inst_) :
            skl_btm_base_t(pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpuid)
        {
            const md::uint32 bit  = read_integer_register(cpuid, R0) & md::MaxSet;
            const md::OADDR  addr = read_integer_register(cpuid, R1);
            unsigned         b;

            dialog::trace("%s: %s  R%u, (R%u), R%u", decoded_pc, mne, R0, R1, Rd);
            b = bit_test_memory_set(cpuid, addr, static_cast<int>(bit));
            epilog(cpuid, b);
        }
    };


    struct skl_btmi_base_t : skl::instruction_t {
        int                  Rd;
        int                  C;
        int                  R1;

        skl_btmi_base_t(md::OADDR            pc_,
                        md::OINST            inst_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst, 25, 21)),
            C(field(inst, 20, 16)),
            R1(field(inst, 15, 11))
        {
        }

        void epilog(skl::cpuid_t cpuid, unsigned b)
        {
            if (!skl::exception_raised(cpuid)) {
                write_integer_register(cpuid, Rd, b);
                increment_pc(cpuid, 1);
            }
            dialog::trace("%s: %s  %xH, (R%u), R%u\n", decoded_pc, mne, C, R1, Rd);
        }
    };


    struct skl_btmi_read_t : skl_btmi_base_t {
        skl_btmi_read_t(md::OADDR pc_, md::OINST inst_) :
            skl_btmi_base_t(pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpuid)
        {
            const md::OADDR addr = read_integer_register(cpuid, R1);
            unsigned        b    = bit_test_memory_read(cpuid, addr, C);

            epilog(cpuid, b);
        }
    };


    struct skl_btmi_clear_t : skl_btmi_base_t {
        skl_btmi_clear_t(md::OADDR pc_, md::OINST inst_) :
            skl_btmi_base_t(pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpuid)
        {
            const md::OADDR addr = read_integer_register(cpuid, R1);
            unsigned        b    = bit_test_memory_clear(cpuid, addr, C);

            epilog(cpuid, b);
        }
    };


    struct skl_btmi_set_t : skl_btmi_base_t {
        skl_btmi_set_t(md::OADDR pc_, md::OINST inst_) :
            skl_btmi_base_t(pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpuid)
        {
            const md::OADDR addr = read_integer_register(cpuid, R1);
            unsigned        b    = bit_test_memory_set(cpuid, addr, C);

            epilog(cpuid, b);
        }
    };


    skl::instruction_t *
    op_bit_test(md::OADDR pc, md::OINST inst)
    {
        opc_t     opc = static_cast<opc_t>(field(inst, 4, 0));

        switch (opc) {
        case OPC_BT:    return new skl_bt_t(pc, inst);
        case OPC_BTI:   return new skl_bti_t(pc, inst);
        case OPC_BTM:   return new skl_btm_read_t(pc, inst);
        case OPC_BTMI:  return new skl_btmi_read_t(pc, inst);
        case OPC_BTMC:  return new skl_btm_clear_t(pc, inst);
        case OPC_BTMCI: return new skl_btmi_clear_t(pc, inst);
        case OPC_BTMS:  return new skl_btm_set_t(pc, inst);
        case OPC_BTMSI: return new skl_btmi_set_t(pc, inst);

        default:
            dialog::not_implemented("%s: inst: %xH opcode: %xH",
                                    __func__, inst, opc);
        }
    }
}
