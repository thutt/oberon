/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <string.h>

#include "config.h"
#include "dialog.h"
#include "o3.h"
#include "heap.h"
#include "skl_instruction.h"
#include "skl_stack.h"

namespace skl {
    typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_stack_opc.h"
#undef OPC
        N_OPCODES
    } opc_t;

    static const char *mnemonics[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_stack_opc.h"
#undef OPC
    };

    static inline bool
    stack_access_ok(skl::cpuid_t cpuid, int n_words, bool push)
    {
        if (push) {
            return true;        // Stack bounds checking disabled.
        } else {
            return true;        // Stack bounds checking disabled.
        }
    }


    struct stack_frame_t  : skl::instruction_t {
        int Rd;
        int words;
        int n_words;

        stack_frame_t(md::OADDR pc_, md::OINST inst_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst_, 25, 21)),
            words(field(inst_, 20, 5)),
            n_words(1 + /* R31 */ 1 + /* Rd */ + words)
        {
        }
    };


    struct enter_t : stack_frame_t {

        enter_t(md::OADDR pc_, md::OINST inst_) :
            stack_frame_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            dialog::trace("%s: %s  R%u, %xH", decoded_pc, mne, Rd, words);

            if (stack_access_ok(cpuid, n_words, true)) {
                md::uint32 sp0 = read_integer_register(cpuid, SP);
                md::uint32 r31 = read_integer_register(cpuid, RETADR);
                md::uint32 rd0 = read_integer_register(cpuid, Rd);
                md::uint32 sp1 = sp0;
                md::uint32 rd1;

                sp1 -= static_cast<md::uint32>(sizeof(md::uint32));
                skl::write(cpuid, sp1, r31, sizeof(md::uint32));  /* Save return address. */

                sp1 -= static_cast<md::uint32>(sizeof(md::uint32));
                skl::write(cpuid, sp1, rd0, sizeof(md::uint32));   /* Save old SFP. */

                rd1 = sp1;

                sp1 -= static_cast<md::uint32>(words * /* Local variable space. */
                                               static_cast<int>(sizeof(md::uint32)));

                dialog::trace("[R%u: %xH -> %xH, R%u: %xH -> %xH]\n",
                              SFP, rd0, rd1, SP, sp0, sp1);

                write_integer_register(cpuid, SP, sp1); /* Set SP. */
                write_integer_register(cpuid, Rd, rd1); /* Set SFP. */

                if (skl_alpha) {
                    /* Zero out stack space in development builds.
                     * This is intended to be used for debugging.
                     * But, it could be made part of the VM, and then
                     * the compiler would not have to initialize local
                     * pointer variables -- as long as the NIL value
                     * is the same as the fill value.
                     */
                    memset(heap::host_address(sp1), '\xff', rd1 - sp1);
                }

                increment_pc(cpuid, 1);
            } else {
                /* Stack overflow exception. */
                dialog::not_implemented("stack overflow");
            }
        }
    };


    struct leave_t : stack_frame_t {
        leave_t(md::OADDR pc_, md::OINST inst_) :
            stack_frame_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            dialog::trace("%s: %s  R%u, %xH", decoded_pc, mne, Rd, words);

            if (stack_access_ok(cpuid, n_words, false)) {
                md::uint32 rd0 = read_integer_register(cpuid, Rd);
                md::uint32 sp0 = read_integer_register(cpuid, SP);
                md::uint32 rd1;
                md::uint32 sfp;
                md::uint32 r31;

                /* This code does some unnecessary work and can be improved. */

                sfp = rd0;

                rd1 = skl::read(cpuid, sfp, false, sizeof(md::uint32));   /* Old SFP. */
                sfp += static_cast<md::uint32>(sizeof(md::uint32));

                r31 = skl::read(cpuid, sfp, false, sizeof(md::uint32)); /* Restore return address. */
                sfp += static_cast<md::uint32>(sizeof(md::uint32));

                sfp += static_cast<md::uint32>(words * /* Remove arguments. */
                                               static_cast<int>(sizeof(md::uint32))); 

                dialog::trace("[R%u: %xH -> %xH,   R%u: %xH -> %xH]\n",
                              SFP, rd0, rd1, SP, sp0, sfp);
                write_integer_register(cpuid, RETADR, r31);
                write_integer_register(cpuid, Rd, rd1);
                write_integer_register(cpuid, SP, sfp);
                increment_pc(cpuid, 1);
            } else {
                /* Stack underflow exception. */
                dialog::not_implemented("stack underflow");
            }

        }
    };


    struct stack_op_t : skl::instruction_t {
        int Rd;

        stack_op_t(md::OADDR pc_, md::OINST inst_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst, 25, 21))
        {
        }

        void push_word(skl::cpuid_t cpuid, md::uint32 data)
        {
            md::uint32 sp  = read_integer_register(cpuid, SP);

            sp -= static_cast<md::uint32>(sizeof(md::uint32));
            skl::write(cpuid, sp, data, sizeof(md::uint32));
            write_integer_register(cpuid, SP, sp);
        }


        md::uint32 pop_word(skl::cpuid_t cpuid, md::uint32 &rsp)
        {
            md::uint32 sp;
            md::uint32 value;

            sp     = read_integer_register(cpuid, SP);
            rsp    = sp;
            value  = skl::read(cpuid, sp, false, sizeof(md::uint32));
            sp    += static_cast<md::uint32>(sizeof(md::uint32));
            write_integer_register(cpuid, SP, sp);

            return value;
        }
    };


    struct push_t : stack_op_t {
        push_t(md::OADDR pc_, md::OINST inst_) :
            stack_op_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            dialog::trace("%s: %s  R%u", decoded_pc, mne, Rd);
            if (stack_access_ok(cpuid, 1, true)) {
                md::uint32 sp;
                md::uint32 val = read_integer_register(cpuid, Rd);

                push_word(cpuid, val);
                sp = read_integer_register(cpuid, SP);
                dialog::trace("[ea: %xH  val: %xH]\n", sp, val);
            } else {
                dialog::not_implemented("stack overflow");
            }
            increment_pc(cpuid, 1);
        }
    };


    struct pushf_t : stack_op_t {
        pushf_t(md::OADDR pc_, md::OINST inst_) :
            stack_op_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            dialog::trace("%s: %s  F%u", decoded_pc, mne, Rd);
            if (LIKELY(stack_access_ok(cpuid, 1, true))) {
                union {
                    md::uint32 i;
                    float f;
                } v;
                md::uint32 sp;
                double     rvalue = read_real_register(cpuid, Rd);

                COMPILE_TIME_ASSERT(sizeof(float) == sizeof(md::uint32));
                COMPILE_TIME_ASSERT(skl_endian_little);

                v.f = static_cast<float>(rvalue);
                push_word(cpuid, v.i);
                sp = read_integer_register(cpuid, SP);
                dialog::trace("[ea: %xH  val: %f]\n", sp, v.f);
            } else {
                dialog::not_implemented("stack overflow");
            }
            increment_pc(cpuid, 1);
        }
    };


    struct pushd_t : stack_op_t {
        pushd_t(md::OADDR pc_, md::OINST inst_) :
            stack_op_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            dialog::trace("%s: %s  F%u", decoded_pc, mne, Rd);
            if (LIKELY(stack_access_ok(cpuid, 2, true))) {
                md::uint32 sp;
                md::uint32 lo;
                md::uint32 hi;
                double     value = read_real_register(cpuid, Rd);

                COMPILE_TIME_ASSERT(sizeof(double) == 2 * sizeof(md::uint32));
                COMPILE_TIME_ASSERT(skl_endian_little);
                md::decompose_double(value, lo, hi);
                push_word(cpuid, hi); /* Stack grows down; little endian order. */
                push_word(cpuid, lo);
                sp = read_integer_register(cpuid, SP);
                dialog::trace("[ea: %xH  val: %e]\n", sp, value);

            } else {
                dialog::not_implemented("stack overflow");
            }
            increment_pc(cpuid, 1);
        }
    };


    struct pop_t : stack_op_t {
        pop_t(md::OADDR pc_, md::OINST inst_) :
            stack_op_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            md::uint32      value;

            dialog::trace("%s: %s  R%u", decoded_pc, mne, Rd);
            if (stack_access_ok(cpuid, 1, true)) {
                md::uint32 sp;
                value = pop_word(cpuid, sp);
                dialog::trace("[ea: %xH  val: %xH]\n", sp, value);
                write_integer_register(cpuid, Rd, value);
            } else {
                dialog::not_implemented("stack overflow");
            }
            increment_pc(cpuid, 1);
        }
    };


    struct popf_t : stack_op_t {
        popf_t(md::OADDR pc_, md::OINST inst_) :
            stack_op_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            dialog::not_implemented(__func__);
        }
    };


    struct popd_t : stack_op_t {
        popd_t(md::OADDR pc_, md::OINST inst_) :
            stack_op_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            dialog::trace("%s: %s  F%u", decoded_pc, mne, Rd);
            if (LIKELY(stack_access_ok(cpuid, 2, true))) {
                md::uint32 lo;
                md::uint32 hi;
                md::uint32 sp_lo;
                md::uint32 sp_hi;
                double     value;

                COMPILE_TIME_ASSERT(sizeof(double) == 2 * sizeof(md::uint32));
                COMPILE_TIME_ASSERT(skl_endian_little);
                lo = pop_word(cpuid, sp_lo);
                hi = pop_word(cpuid, sp_hi);
                md::recompose_double(lo, hi, value);
                dialog::trace("[ea: %xH  val: %e]\n", sp_lo, value);
                write_real_register(cpuid, Rd, value);
            } else {
                dialog::not_implemented("stack overflow");
            }
            increment_pc(cpuid, 1);
        }
    };


    skl::instruction_t *
    op_stack(md::OADDR pc, md::OINST inst)
    {
        opc_t opc = static_cast<opc_t>(field(inst, 4, 0));

        switch (opc) {
        case OPC_ENTER: return new enter_t(pc, inst);
        case OPC_LEAVE: return new leave_t(pc, inst);
        case OPC_PUSH:  return new push_t(pc, inst);
        case OPC_POP:   return new pop_t(pc, inst);
        case OPC_PUSHF: return new pushf_t(pc, inst);
        case OPC_POPF:  return new popf_t(pc, inst);
        case OPC_PUSHD: return new pushd_t(pc, inst);
        case OPC_POPD:  return new popd_t(pc, inst);

        default:
            dialog::not_implemented("%s: inst: %xH opcode: %x#",
                                    __func__, inst, opc);
        }
    }
}
