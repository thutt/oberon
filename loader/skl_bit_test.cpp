/* Copyright (c) 2021, 2022 Logic Magicians Software */

#include "dialog.h"
#include "o3.h"
#include "skl_bit_test.h"

namespace skl {
    typedef enum bit_test_memory_op_t {
        bt_read,                // Read bit only.
        bt_clear,               // Clear after read.
        bt_set                  // Set after read.
    } bit_test_memory_op_t;


    static unsigned
    bit_test(md::uint32 v, unsigned b)
    {
        unsigned r = right_shift(v, b) & 1;
        dialog::trace("[%u, %xH]  [result: %d]\n", b, v, r);
        return r;
    }


    struct skl_bt_t : skl::instruction_t {
        unsigned   Rd;
        unsigned   R0;
        unsigned   R1;

        skl_bt_t(cpu_t       *cpu_,
                 md::uint32   inst_,
                 const char **mne_) :
            skl::instruction_t(cpu_, inst_, mne_),
            Rd(field(inst, 25, 21)),
            R0(field(inst, 20, 16)),
            R1(field(inst, 15, 11))
        {
        }

        virtual void interpret(void)
        {
            const md::uint32 r0 = read_integer_register(cpu, R0);
            const md::uint32 r1 = read_integer_register(cpu, R1);
            md::uint32       b  = bit_test(r1, r0);

            write_integer_register(cpu, Rd, b);
            increment_pc(cpu, 1);
            dialog::trace("%s: %s  R%u, R%u, R%u", decoded_pc, mne, R0, R1, Rd);
        }
    };


    struct skl_bti_t : skl::instruction_t {
        unsigned   Rd;
        unsigned   C;
        unsigned   R1;

        skl_bti_t(cpu_t      *cpu_,
                 md::uint32   inst_,
                 const char **mne_) :
            skl::instruction_t(cpu_, inst_, mne_),
            Rd(field(inst, 25, 21)),
            C(field(inst, 20, 16)),
            R1(field(inst, 15, 11))
        {
        }


        virtual void interpret(void)
        {
            const md::uint32 v = read_integer_register(cpu, R1);
            md::uint32       b = bit_test(v, C);

            write_integer_register(cpu, Rd, b);
            increment_pc(cpu, 1);
            dialog::trace("%s: %s  %xH, R%u, R%u", decoded_pc, mne, C, R1, Rd);
        }
    };


    static unsigned
    bit_test_memory(md::uint32 ea, unsigned b, bit_test_memory_op_t op)
    {
        const md::uint32 v = skl::read(ea, true, sizeof(md::uint32));
        unsigned         r = right_shift(v, b) & 1;

        dialog::trace("[%u, (ea: %xH, value: %xH)]  [%d]\n", b, ea, v, r);
        if (!cpu.exception_raised) {
            switch (op) {
            case bt_read:
                break;          // nop

            case bt_clear: {
                unsigned   mask  = ~left_shift(1, b);
                md::uint32 nv = (v & static_cast<md::uint32>(mask));
                write(ea, nv, sizeof(md::uint32));
                break;
            }

            case bt_set: {
                unsigned   mask = left_shift(1, b);
                md::uint32 nv   = (v | static_cast<md::uint32>(mask));
                write(ea, nv, sizeof(md::uint32));
                break;
            }
            }
        }
        return r;
    }


    struct skl_btm_family_t : skl::instruction_t {
        unsigned             Rd;
        unsigned             R0;
        unsigned             R1;
        bit_test_memory_op_t op;

        skl_btm_family_t(cpu_t                 *cpu_,
                         md::uint32             inst_,
                         const char           **mne_,
                         bit_test_memory_op_t   op_) :
            skl::instruction_t(cpu_, inst_, mne_),
            Rd(field(inst, 25, 21)),
            R0(field(inst, 20, 16)),
            R1(field(inst, 15, 11)),
            op(op_)
        {
        }


        virtual void interpret(void)
        {
            const md::uint32 bit  = read_integer_register(cpu, R0) & md::MaxSet;
            const md::uint32 addr = read_integer_register(cpu, R1);
            md::uint32       b;

            b = bit_test_memory(addr, bit, op);
            if (!cpu->exception_raised) {
                write_integer_register(cpu, Rd, b);
                increment_pc(cpu, 1);
            }
            dialog::trace("%s: %s  R%u, (R%u), R%u", decoded_pc, mne, R0, R1, Rd);
        }
    };


    struct skl_btmi_family_t : skl::instruction_t {
        unsigned             Rd;
        unsigned             C;
        unsigned             R1;
        bit_test_memory_op_t op;

        skl_btmi_family_t(cpu_t                 *cpu_,
                          md::uint32             inst_,
                          const char           **mne_,
                          bit_test_memory_op_t   op_) :
            skl::instruction_t(cpu_, inst_, mne_),
            Rd(field(inst, 25, 21)),
            C(field(inst, 20, 16)),
            R1(field(inst, 15, 11)),
            op(op_)
        {
        }


        virtual void interpret(void)
        {
            const md::uint32 addr = read_integer_register(cpu, R1);
            md::uint32       b    = bit_test_memory(addr, C, op);
            if (!cpu->exception_raised) {
                write_integer_register(cpu, Rd, b);
                increment_pc(cpu, 1);
            }
            dialog::trace("%s: %s  %xH, (R%u), R%u", decoded_pc, mne, C, R1, Rd);
        }
    };


    skl::instruction_t *
    op_bit_test(cpu_t *cpu, md::uint32 inst)
    {
        typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_bit_test_opc.h"
#undef OPC
            N_OPCODES
        } opc_t;
        static const char *mne[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_bit_test_opc.h"
#undef OPC
        };
        opc_t opc = static_cast<opc_t>(field(inst, 4, 0));

        switch (opc) {
        case OPC_BT:
            return new skl_bt_t(cpu, inst, mne);

        case OPC_BTI:
            return new skl_bti_t(cpu, inst, mne);

        case OPC_BTM:
            return new skl_btm_family_t(cpu, inst, mne, bt_read);

        case OPC_BTMI:
            return new skl_btmi_family_t(cpu, inst, mne, bt_read);

        case OPC_BTMC:
            return new skl_btm_family_t(cpu, inst, mne, bt_clear);

        case OPC_BTMCI:
            return new skl_btmi_family_t(cpu, inst, mne, bt_clear);

        case OPC_BTMS:
            return new skl_btm_family_t(cpu, inst, mne, bt_set);

        case OPC_BTMSI:
            return new skl_btmi_family_t(cpu, inst, mne, bt_set);

        default:
            dialog::not_implemented("%s: inst: %xH opcode: %xH",
                                    __func__, inst, opc);
        }
    }
}
