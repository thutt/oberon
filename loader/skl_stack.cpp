/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <string.h>

#include "config.h"
#include "dialog.h"
#include "o3.h"
#include "heap.h"
#include "skl_stack.h"

namespace skl {

    static inline bool
    stack_access_ok(unsigned n_words, bool push)
    {
        return true;        // Stack bounds disabled.
    }


    static void
    op_enter(cpu_t &cpu, md::uint32 inst, const char *mne)
    {
        unsigned Rd      = field(inst, 25, 21);
        unsigned words   = field(inst, 20, 5);
        unsigned n_words = (1 + /* R31 */ 1 + /* Rd */ + words);
        O3::decode_pc_t decoded_pc;

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  R%u, %xH", decoded_pc, mne, Rd, words);

        if (stack_access_ok(n_words, true)) {
            md::uint32 sp0 = read_integer_register(cpu, SP);
            md::uint32 r31 = read_integer_register(cpu, RETADR);
            md::uint32 rd0 = read_integer_register(cpu, Rd);
            md::uint32 sp1 = sp0;
            md::uint32 rd1;

            sp1 -= sizeof(md::uint32);
            write(sp1, r31, sizeof(md::uint32));  /* Save return address. */

            sp1 -= sizeof(md::uint32);
            write(sp1, rd0, sizeof(md::uint32));   /* Save old SFP. */

            rd1 = sp1;

            sp1 -= words * sizeof(md::uint32);    /* Local variable space. */

            dialog::trace("[R%u: %xH -> %xH, R%u: %xH -> %xH]\n",
                          SFP, rd0, rd1, SP, sp0, sp1);

            write_integer_register(cpu, SP, sp1); /* Set SP. */
            write_integer_register(cpu, Rd, rd1); /* Set SFP. */

            if (skl_alpha) {
                /* XXX When different build types are supported, zero
                 * out stack space in development-style builds.  This
                 * is intended to be used for debugging.  But, it
                 * could be made part of the VM, and then the compiler
                 * would not have to initialize local pointer
                 * variables -- as long as the NIL value is the same
                 * as the fill value.
                 */
                memset(heap::host_address(sp1), '\xff', rd1 - sp1);  /* Zero new stack space */
            }

            increment_pc(cpu, 1);
        } else {
            /* Stack overflow exception. */
            dialog::not_implemented("stack overflow");
        }

    }

    static void
    op_leave(cpu_t &cpu, md::uint32 inst, const char *mne)
    {
        unsigned Rd      = field(inst, 25, 21);
        unsigned words   = field(inst, 20, 5);
        unsigned n_words = (1 + /* R31 */ 1 + /* Rd */ + words);
        O3::decode_pc_t decoded_pc;

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  R%u, %xH", decoded_pc, mne, Rd, words);

        if (stack_access_ok(n_words, false)) {
            md::uint32 rd0 = read_integer_register(cpu, Rd);
            md::uint32 sp0 = read_integer_register(cpu, SP);
            md::uint32 rd1;
            md::uint32 sfp;
            md::uint32 r31;

            /* This code does some unnecessary work and can be improved. */

            sfp = rd0;

            rd1 = skl::read(sfp, false, sizeof(md::uint32));   /* Old SFP. */
            sfp += sizeof(md::uint32);

            r31 = skl::read(sfp, false, sizeof(md::uint32)); /* Restore return address. */
            sfp += sizeof(md::uint32);

            sfp += words * sizeof(md::uint32);   /* Remove arguments. */

            dialog::trace("[R%u: %xH -> %xH,   R%u: %xH -> %xH]\n",
                          SFP, rd0, rd1, SP, sp0, sfp);
            write_integer_register(cpu, RETADR, r31);
            write_integer_register(cpu, Rd, rd1);
            write_integer_register(cpu, SP, sfp);
            increment_pc(cpu, 1);
        } else {
            /* Stack underflow exception. */
            dialog::not_implemented("stack underflow");
        }

    }


    static void
    push_word(cpu_t &cpu, md::uint32 data)
    {
        md::uint32 sp  = read_integer_register(cpu, SP);

        sp -= sizeof(md::uint32);
        write(sp, data, sizeof(md::uint32));
        write_integer_register(cpu, SP, sp);
    }


    static void
    op_push(cpu_t &cpu, md::uint32 inst, const char *mne)
    {
        unsigned        Rd = field(inst, 25, 21);
        O3::decode_pc_t decoded_pc;

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  R%u", decoded_pc, mne, Rd);
        if (stack_access_ok(1, true)) {
            md::uint32 sp;
            md::uint32 val = read_integer_register(cpu, Rd);

            push_word(cpu, val);
            sp = read_integer_register(cpu, SP);
            dialog::trace("[ea: %xH  val: %xH]\n", sp, val);

        } else {
            dialog::not_implemented("stack overflow");
        }
        increment_pc(cpu, 1);
    }


    static md::uint32
    pop_word(cpu_t &cpu, md::uint32 &rsp)
    {
        md::uint32 sp;
        md::uint32 value;

        sp     = read_integer_register(cpu, SP);
        rsp    = sp;
        value  = skl::read(sp, false, sizeof(md::uint32));
        sp    += sizeof(md::uint32);
        write_integer_register(cpu, SP, sp);

        return value;
    }


    static void
    op_pop(cpu_t &cpu, md::uint32 inst, const char *mne)
    {
        unsigned        Rd = field(inst, 25, 21);
        O3::decode_pc_t decoded_pc;
        md::uint32      value;

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  R%u", decoded_pc, mne, Rd);
        if (stack_access_ok(1, true)) {
            md::uint32 sp;
            value = pop_word(cpu, sp);
            dialog::trace("[ea: %xH  val: %xH]\n", sp, value);
            write_integer_register(cpu, Rd, value);
        } else {
            dialog::not_implemented("stack overflow");
        }
        increment_pc(cpu, 1);
    }


    static void
    op_pushf(cpu_t &cpu, md::uint32 inst, const char *mne)
    {
        unsigned        Rd = field(inst, 25, 21);
        O3::decode_pc_t decoded_pc;

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  F%u", decoded_pc, mne, Rd);
        if (LIKELY(stack_access_ok(1, true))) {
            union {
                md::uint32 i;
                float f;
            } v;
            md::uint32 sp;
            double     rvalue = read_real_register(cpu, Rd);

            COMPILE_TIME_ASSERT(sizeof(float) == sizeof(md::uint32));
            COMPILE_TIME_ASSERT(skl_endian_little);

            v.f = rvalue;
            push_word(cpu, v.i);
            sp = read_integer_register(cpu, SP);
            dialog::trace("[ea: %xH  val: %f]\n", sp, v.f);
        } else {
            dialog::not_implemented("stack overflow");
        }
        increment_pc(cpu, 1);
    }


    static void
    op_popf(cpu_t &cpu, md::uint32 inst, const char *mne)
    {
        dialog::not_implemented(__func__);
    }


    static void
    op_pushd(cpu_t &cpu, md::uint32 inst, const char *mne)
    {
        unsigned        Rd = field(inst, 25, 21);
        O3::decode_pc_t decoded_pc;

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  F%u", decoded_pc, mne, Rd);
        if (LIKELY(stack_access_ok(2, true))) {
            md::uint32 sp;
            md::uint32 lo;
            md::uint32 hi;
            double     value = read_real_register(cpu, Rd);

            COMPILE_TIME_ASSERT(sizeof(double) == 2 * sizeof(md::uint32));
            COMPILE_TIME_ASSERT(skl_endian_little);
            md::decompose_double(value, lo, hi);
            push_word(cpu, hi); /* Stack grows down; little endian order. */
            push_word(cpu, lo);
            sp = read_integer_register(cpu, SP);
            dialog::trace("[ea: %xH  val: %e]\n", sp, value);

        } else {
            dialog::not_implemented("stack overflow");
        }
        increment_pc(cpu, 1);
    }


    static void
    op_popd(cpu_t &cpu, md::uint32 inst, const char *mne)
    {
        unsigned        Rd = field(inst, 25, 21);
        O3::decode_pc_t decoded_pc;

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  F%u", decoded_pc, mne, Rd);
        if (LIKELY(stack_access_ok(2, true))) {
            md::uint32 lo;
            md::uint32 hi;
            md::uint32 sp_lo;
            md::uint32 sp_hi;
            double     value;

            COMPILE_TIME_ASSERT(sizeof(double) == 2 * sizeof(md::uint32));
            COMPILE_TIME_ASSERT(skl_endian_little);
            lo = pop_word(cpu, sp_lo);
            hi = pop_word(cpu, sp_hi);
            md::recompose_double(lo, hi, value);
            dialog::trace("[ea: %xH  val: %e]\n", sp_lo, value);
            write_real_register(cpu, Rd, value);
        } else {
            dialog::not_implemented("stack overflow");
        }
        increment_pc(cpu, 1);
    }


    void
    op_stack(cpu_t &cpu, md::uint32 inst)
    {
        typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_stack_opc.h"
#undef OPC
            N_OPCODES
        } opc_t;
        static const char *mne[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_stack_opc.h"
#undef OPC
        };
        opc_t opc = static_cast<opc_t>(field(inst, 4, 0));

        switch (opc) {
        case OPC_ENTER:
            op_enter(cpu, inst, mne[opc]);
            break;

        case OPC_LEAVE:
            op_leave(cpu, inst, mne[opc]);
            break;

        case OPC_PUSH:
            op_push(cpu, inst, mne[opc]);
            break;

        case OPC_POP:
            op_pop(cpu, inst, mne[opc]);
            break;

        case OPC_PUSHF:
            op_pushf(cpu, inst, mne[opc]);
            break;

        case OPC_POPF:
            op_popf(cpu, inst, mne[opc]);
            break;

        case OPC_PUSHD:
            op_pushd(cpu, inst, mne[opc]);
            break;

        case OPC_POPD:
            op_popd(cpu, inst, mne[opc]);
            break;

        default:
            dialog::not_implemented("%s: inst: %xH %s",
                                    __func__, inst, mne[opc]);
        }
    }
}
