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

    static const char *mne[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_stack_opc.h"
#undef OPC
    };

    static inline bool
    stack_access_ok(skl::cpu_t *cpu, int n_words, bool push)
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

        stack_frame_t(md::OADDR    pc_,
                      md::OINST    inst_,
                      const char **mne_) :
            skl::instruction_t(pc_, inst_, mne_),
            Rd(field(inst_, 25, 21)),
            words(field(inst_, 20, 5)),
            n_words(1 + /* R31 */ 1 + /* Rd */ + words)
        {
        }
    };


    struct enter_t : stack_frame_t {

        enter_t(md::OADDR    pc_,
                md::OINST    inst_,
                const char **mne_) :
            stack_frame_t(pc_, inst_, mne_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            dialog::trace("%s: %s  R%u, %xH", decoded_pc, mne, Rd, words);

            if (stack_access_ok(cpu, n_words, true)) {
                md::uint32 sp0 = read_integer_register(cpu, SP);
                md::uint32 r31 = read_integer_register(cpu, RETADR);
                md::uint32 rd0 = read_integer_register(cpu, Rd);
                md::uint32 sp1 = sp0;
                md::uint32 rd1;

                sp1 -= static_cast<md::uint32>(sizeof(md::uint32));
                skl::write(sp1, r31, sizeof(md::uint32));  /* Save return address. */

                sp1 -= static_cast<md::uint32>(sizeof(md::uint32));
                skl::write(sp1, rd0, sizeof(md::uint32));   /* Save old SFP. */

                rd1 = sp1;

                sp1 -= static_cast<md::uint32>(words * /* Local variable space. */
                                               static_cast<int>(sizeof(md::uint32)));

                dialog::trace("[R%u: %xH -> %xH, R%u: %xH -> %xH]\n",
                              SFP, rd0, rd1, SP, sp0, sp1);

                write_integer_register(cpu, SP, sp1); /* Set SP. */
                write_integer_register(cpu, Rd, rd1); /* Set SFP. */

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

                increment_pc(cpu, 1);
            } else {
                /* Stack overflow exception. */
                dialog::not_implemented("stack overflow");
            }
        }
    };


    struct leave_t : stack_frame_t {
        leave_t(md::OADDR    pc_,
                md::OINST    inst_,
                const char **mne_) :
            stack_frame_t(pc_, inst_, mne_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            dialog::trace("%s: %s  R%u, %xH", decoded_pc, mne, Rd, words);

            if (stack_access_ok(cpu, n_words, false)) {
                md::uint32 rd0 = read_integer_register(cpu, Rd);
                md::uint32 sp0 = read_integer_register(cpu, SP);
                md::uint32 rd1;
                md::uint32 sfp;
                md::uint32 r31;

                /* This code does some unnecessary work and can be improved. */

                sfp = rd0;

                rd1 = skl::read(sfp, false, sizeof(md::uint32));   /* Old SFP. */
                sfp += static_cast<md::uint32>(sizeof(md::uint32));

                r31 = skl::read(sfp, false, sizeof(md::uint32)); /* Restore return address. */
                sfp += static_cast<md::uint32>(sizeof(md::uint32));

                sfp += static_cast<md::uint32>(words * /* Remove arguments. */
                                               static_cast<int>(sizeof(md::uint32))); 

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
    };


    struct stack_op_t : skl::instruction_t {
        int Rd;

        stack_op_t(md::OADDR    pc_,
                   md::OINST    inst_,
                   const char **mne_) :
            skl::instruction_t(pc_, inst_, mne_),
            Rd(field(inst, 25, 21))
        {
        }

        void push_word(cpu_t *cpu, md::uint32 data)
        {
            md::uint32 sp  = read_integer_register(cpu, SP);

            sp -= static_cast<md::uint32>(sizeof(md::uint32));
            skl::write(sp, data, sizeof(md::uint32));
            write_integer_register(cpu, SP, sp);
        }


        md::uint32 pop_word(cpu_t *cpu, md::uint32 &rsp)
        {
            md::uint32 sp;
            md::uint32 value;

            sp     = read_integer_register(cpu, SP);
            rsp    = sp;
            value  = skl::read(sp, false, sizeof(md::uint32));
            sp    += static_cast<md::uint32>(sizeof(md::uint32));
            write_integer_register(cpu, SP, sp);

            return value;
        }
    };


    struct push_t : stack_op_t {
        push_t(md::OADDR    pc_,
               md::OINST    inst_,
               const char **mne_) :
            skl::stack_op_t(pc_, inst_, mne_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            dialog::trace("%s: %s  R%u", decoded_pc, mne, Rd);
            if (stack_access_ok(cpu, 1, true)) {
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
    };


    struct pushf_t : stack_op_t {
        pushf_t(md::OADDR    pc_,
                md::OINST    inst_,
                const char **mne_) :
            skl::stack_op_t(pc_, inst_, mne_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            dialog::trace("%s: %s  F%u", decoded_pc, mne, Rd);
            if (LIKELY(stack_access_ok(cpu, 1, true))) {
                union {
                    md::uint32 i;
                    float f;
                } v;
                md::uint32 sp;
                double     rvalue = read_real_register(cpu, Rd);

                COMPILE_TIME_ASSERT(sizeof(float) == sizeof(md::uint32));
                COMPILE_TIME_ASSERT(skl_endian_little);

                v.f = static_cast<float>(rvalue);
                push_word(cpu, v.i);
                sp = read_integer_register(cpu, SP);
                dialog::trace("[ea: %xH  val: %f]\n", sp, v.f);
            } else {
                dialog::not_implemented("stack overflow");
            }
            increment_pc(cpu, 1);
        }
    };


    struct pushd_t : stack_op_t {
        pushd_t(md::OADDR    pc_,
                md::OINST    inst_,
                const char **mne_) :
            skl::stack_op_t(pc_, inst_, mne_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            dialog::trace("%s: %s  F%u", decoded_pc, mne, Rd);
            if (LIKELY(stack_access_ok(cpu, 2, true))) {
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
    };


    struct pop_t : stack_op_t {
        pop_t(md::OADDR    pc_,
              md::OINST    inst_,
              const char **mne_) :
            skl::stack_op_t(pc_, inst_, mne_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            md::uint32      value;

            dialog::trace("%s: %s  R%u", decoded_pc, mne, Rd);
            if (stack_access_ok(cpu, 1, true)) {
                md::uint32 sp;
                value = pop_word(cpu, sp);
                dialog::trace("[ea: %xH  val: %xH]\n", sp, value);
                write_integer_register(cpu, Rd, value);
            } else {
                dialog::not_implemented("stack overflow");
            }
            increment_pc(cpu, 1);
        }
    };


    struct popf_t : stack_op_t {
        popf_t(md::OADDR    pc_,
               md::OINST    inst_,
               const char **mne_) :
            skl::stack_op_t(pc_, inst_, mne_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            dialog::not_implemented(__func__);
        }
    };


    struct popd_t : stack_op_t {
        popd_t(md::OADDR    pc_,
               md::OINST    inst_,
               const char **mne_) :
            skl::stack_op_t(pc_, inst_, mne_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            dialog::trace("%s: %s  F%u", decoded_pc, mne, Rd);
            if (LIKELY(stack_access_ok(cpu, 2, true))) {
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
    };


    skl::instruction_t *
    op_stack(cpu_t *cpu, md::OINST inst)
    {
        opc_t opc = static_cast<opc_t>(field(inst, 4, 0));

        switch (opc) {
        case OPC_ENTER:
            return new enter_t(cpu->pc, inst, mne);

        case OPC_LEAVE:
            return new leave_t(cpu->pc, inst, mne);

        case OPC_PUSH:
            return new push_t(cpu->pc, inst, mne);

        case OPC_POP:
            return new pop_t(cpu->pc, inst, mne);

        case OPC_PUSHF:
            return new pushf_t(cpu->pc, inst, mne);

        case OPC_POPF:
            return new popf_t(cpu->pc, inst, mne);

        case OPC_PUSHD:
            return new pushd_t(cpu->pc, inst, mne);

        case OPC_POPD:
            return new popd_t(cpu->pc, inst, mne);

        default:
            dialog::not_implemented("%s: inst: %xH opcode: %x#",
                                    __func__, inst, opc);
        }
    }
}
