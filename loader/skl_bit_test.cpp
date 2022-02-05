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


    static void
    op_btmi_btmci_btmsi(cpu_t                &cpu,
                        md::uint32            inst,
                        const char           *mne,
                        bit_test_memory_op_t  op)
    {
        const unsigned   Rd   = field(inst, 25, 21);
        const unsigned   C    = field(inst, 20, 16);
        const unsigned   R1   = field(inst, 15, 11);
        const md::uint32 addr = read_integer_register(cpu, R1);
        md::uint32       b;
        O3::decode_pc_t  decoded_pc;

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  %xH, (R%u), R%u", decoded_pc, mne, C, R1, Rd);
        b = bit_test_memory(addr, C, op);
        if (!cpu.exception_raised) {
            write_integer_register(cpu, Rd, b);
            increment_pc(cpu, 1);
        }
    }


    static void
    op_bt(cpu_t &cpu, md::uint32 inst, const char *mne)
    {
        const unsigned   Rd   = field(inst, 25, 21);
        const unsigned   R0   = field(inst, 20, 16);
        const unsigned   R1   = field(inst, 15, 11);
        const md::uint32 r0   = read_integer_register(cpu, R0);
        const md::uint32 r1   = read_integer_register(cpu, R1);
        md::uint32       b;
        O3::decode_pc_t      decoded_pc;

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  R%u, R%u, R%u", decoded_pc, mne, R0, R1, Rd);
        b = bit_test(r1, r0);
        write_integer_register(cpu, Rd, b);
        increment_pc(cpu, 1);
    }


    static void
    op_bti(cpu_t &cpu, md::uint32 inst, const char *mne)
    {
        const unsigned   Rd   = field(inst, 25, 21);
        const unsigned   C    = field(inst, 20, 16);
        const unsigned   R1   = field(inst, 15, 11);
        const md::uint32 v    = read_integer_register(cpu, R1);
        md::uint32       b;
        O3::decode_pc_t      decoded_pc;

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  %xH, R%u, R%u", decoded_pc, mne, C, R1, Rd);
        b = bit_test(v, C);
        write_integer_register(cpu, Rd, b);
        increment_pc(cpu, 1);
    }


    static void
    op_btm_btmc_btms(cpu_t                &cpu,
                     md::uint32            inst,
                     const char           *mne,
                     bit_test_memory_op_t  op)
    {
        const unsigned   Rd   = field(inst, 25, 21);
        const unsigned   R0   = field(inst, 20, 16);
        const unsigned   R1   = field(inst, 15, 11);
        const md::uint32 bit  = read_integer_register(cpu, R0) & md::MaxSet;
        const md::uint32 addr = read_integer_register(cpu, R1);
        md::uint32       b;
        O3::decode_pc_t  decoded_pc;

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  R%u, (R%u), R%u", decoded_pc, mne, R0, R1, Rd);
        b = bit_test_memory(addr, bit, op);
        if (!cpu.exception_raised) {
            write_integer_register(cpu, Rd, b);
            increment_pc(cpu, 1);
        }
    }


    void
    op_bit_test(cpu_t &cpu, md::uint32 inst)
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
            op_bt(cpu, inst, mne[opc]);
            break;

        case OPC_BTI:
            op_bti(cpu, inst, mne[opc]);
            break;

        case OPC_BTM:
            op_btm_btmc_btms(cpu, inst, mne[opc], bt_read);
            break;

        case OPC_BTMI:
            op_btmi_btmci_btmsi(cpu, inst, mne[opc], bt_read);
            break;

        case OPC_BTMC:
            op_btm_btmc_btms(cpu, inst, mne[opc], bt_clear);
            break;

        case OPC_BTMCI:
            op_btmi_btmci_btmsi(cpu, inst, mne[opc], bt_clear);
            break;

        case OPC_BTMS:
            op_btm_btmc_btms(cpu, inst, mne[opc], bt_set);
            break;

        case OPC_BTMSI:
            op_btmi_btmci_btmsi(cpu, inst, mne[opc], bt_set);
            break;

        default:
            dialog::not_implemented("%s: inst: %xH %s",
                                    __func__, inst, mne[opc]);
        }
    }
}
