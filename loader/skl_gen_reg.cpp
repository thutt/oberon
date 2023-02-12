/* Copyright (c) 2021, 2022, 2023 Logic Magicians Software */

#include <math.h>
#include <stdlib.h>

#include "dialog.h"
#include "o3.h"
#include "skl_flags.h"
#include "skl_gen_reg.h"

namespace skl {
        typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_gen_reg_opc.h"
#undef OPC
            N_OPCODES
        } opc_t;

        static const char *mnemonics[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_gen_reg_opc.h"
#undef OPC
        };


    struct skl_gen_reg_t : skl::instruction_t {
        int             Rd;
        int             R0;
        int             R1;
        register_bank_t bd;
        register_bank_t b0;
        register_bank_t b1;

        skl_gen_reg_t(md::OADDR pc_, md::OINST inst_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst_, 25, 21)),
            R0(field(inst_, 20, 16)),
            R1(field(inst_, 15, 11)),
            bd(static_cast<register_bank_t>(field(inst,  10, 10))),
            b0(static_cast<register_bank_t>(field(inst,   9,  9))),
            b1(static_cast<register_bank_t>(field(inst,   8,  8)))
        {
        }
    };


    struct skl_gen_reg_int_int_t : skl_gen_reg_t {
        skl_gen_reg_int_int_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_t(pc_, inst_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_INTEGER);
        }
    };


    struct skl_gen_reg_int_int_add_t : skl_gen_reg_int_int_t {
        skl_gen_reg_int_int_add_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_int_int_t(pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = l + r;

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            write_integer_register(cpu, Rd, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_gen_reg_int_int_sub_t : skl_gen_reg_int_int_t {
        skl_gen_reg_int_int_sub_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_int_int_t(pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = l - r;

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            write_integer_register(cpu, Rd, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_gen_reg_int_int_mul_t : skl_gen_reg_int_int_t {
        skl_gen_reg_int_int_mul_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_int_int_t(pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = l * r;

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            write_integer_register(cpu, Rd, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_gen_reg_int_int_div_t : skl_gen_reg_int_int_t {
        skl_gen_reg_int_int_div_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_int_int_t(pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = 0;

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            if (LIKELY(r != 0)) {
                v = static_cast<md::uint32>(O3::DIV(static_cast<md::int32>(l),
                                                    static_cast<md::int32>(r)));
                write_integer_register(cpu, Rd, v);
            } else {
                hardware_trap(cpu, CR2_DIVIDE_BY_ZERO);
            }

            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_gen_reg_int_int_mod_t : skl_gen_reg_int_int_t {
        skl_gen_reg_int_int_mod_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_int_int_t(pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = 0;

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            if (LIKELY(r != 0)) {
                v = static_cast<md::uint32>(O3::MOD(static_cast<md::int32>(l),
                                                    static_cast<md::int32>(r)));
                write_integer_register(cpu, Rd, v);
            } else {
                hardware_trap(cpu, CR2_DIVIDE_BY_ZERO);
            }

            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_gen_reg_int_int_cmp_t : skl_gen_reg_int_int_t {
        skl_gen_reg_int_int_cmp_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_int_int_t(pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = skl::synthesize_flags_int32(l, r);

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            write_integer_register(cpu, Rd, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_gen_reg_int_int_abs_t : skl_gen_reg_int_int_t {
        skl_gen_reg_int_int_abs_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_int_int_t(pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = static_cast<md::uint32>(abs(static_cast<int>(r)));

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            write_integer_register(cpu, Rd, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_gen_reg_int_real_t : skl_gen_reg_t {
        skl_gen_reg_int_real_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_t(pc_, inst_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }
    };


    struct skl_gen_reg_int_real_add_t : skl_gen_reg_int_real_t {
        skl_gen_reg_int_real_add_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_int_real_t(pc_, inst_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = l + r;

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            write_real_register(cpu, Rd, static_cast<int>(v));
            increment_pc(cpu, 1);
        }
    };


    struct skl_gen_reg_int_real_sub_t : skl_gen_reg_int_real_t {
        skl_gen_reg_int_real_sub_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_int_real_t(pc_, inst_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = l - r;

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            write_real_register(cpu, Rd, static_cast<int>(v));
            increment_pc(cpu, 1);
        }
    };


    struct skl_gen_reg_int_real_mul_t : skl_gen_reg_int_real_t {
        skl_gen_reg_int_real_mul_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_int_real_t(pc_, inst_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = l * r;

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            write_real_register(cpu, Rd, static_cast<int>(v));
            increment_pc(cpu, 1);
        }
    };


    struct skl_gen_reg_int_real_div_t : skl_gen_reg_int_real_t {
        skl_gen_reg_int_real_div_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_int_real_t(pc_, inst_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = 0;

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            if (LIKELY(r != 0)) {
                v = static_cast<md::uint32>(O3::DIV(static_cast<md::int32>(l),
                                                    static_cast<md::int32>(r)));
                write_real_register(cpu, Rd, static_cast<int>(v));
            } else {
                hardware_trap(cpu, CR2_DIVIDE_BY_ZERO);
            }

            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_gen_reg_int_real_mod_t : skl_gen_reg_int_real_t {
        skl_gen_reg_int_real_mod_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_int_real_t(pc_, inst_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = 0;

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            if (LIKELY(r != 0)) {
                v = static_cast<md::uint32>(O3::MOD(static_cast<md::int32>(l),
                                                    static_cast<md::int32>(r)));
                write_real_register(cpu, Rd, static_cast<int>(v));
            } else {
                hardware_trap(cpu, CR2_DIVIDE_BY_ZERO);
            }
            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_gen_reg_int_real_cmp_t : skl_gen_reg_int_real_t {
        skl_gen_reg_int_real_cmp_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_int_real_t(pc_, inst_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = synthesize_flags_int32(l, r);

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            write_real_register(cpu, Rd, static_cast<int>(v));
            increment_pc(cpu, 1);
        }
    };


    struct skl_gen_reg_int_real_abs_t : skl_gen_reg_int_real_t {
        skl_gen_reg_int_real_abs_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_int_real_t(pc_, inst_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = static_cast<md::uint32>(abs(static_cast<int>(r)));

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            write_real_register(cpu, Rd, static_cast<int>(v));
            increment_pc(cpu, 1);
        }
    };


    struct skl_gen_reg_real_t : skl_gen_reg_t {
        skl_gen_reg_real_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_t(pc_, inst_)
        {
        }

        void epilog(skl::cpuid_t cpuid, double v)
        {
            if (!skl::exception_raised(cpuid)) {
                if (bd == RB_INTEGER) {
                    write_integer_register(cpuid, Rd,
                                           static_cast<md::uint32>(v));
                } else {
                    write_real_register(cpuid, Rd, v);
                }
            }
            increment_pc(cpuid, 1);
        }
    };


    struct skl_gen_reg_real_add_t : skl_gen_reg_real_t {
        skl_gen_reg_real_add_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_real_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            double l = register_as_double(cpu, R0, b0);
            double r = register_as_double(cpu, R1, b1);
            double v = l + r;

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%f, %f, %f]\n", l, r, v);
            epilog(cpu, v);
        }
    };


    struct skl_gen_reg_real_sub_t : skl_gen_reg_real_t {
        skl_gen_reg_real_sub_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_real_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            double l = register_as_double(cpu, R0, b0);
            double r = register_as_double(cpu, R1, b1);
            double v = l - r;

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%f, %f, %f]\n", l, r, v);
            epilog(cpu, v);
        }
    };


    struct skl_gen_reg_real_mul_t : skl_gen_reg_real_t {
        skl_gen_reg_real_mul_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_real_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            double l = register_as_double(cpu, R0, b0);
            double r = register_as_double(cpu, R1, b1);
            double v = l * r;

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%f, %f, %f]\n", l, r, v);

            epilog(cpu, v);
        }
    };


    struct skl_gen_reg_real_div_t : skl_gen_reg_real_t {
        skl_gen_reg_real_div_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_real_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            double l = register_as_double(cpu, R0, b0);
            double r = register_as_double(cpu, R1, b1);
            double v;

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);

            if (LIKELY(r != 0)) {
                v = l / r;
                dialog::trace("[%f, %f, %f]\n", l, r, v);
                epilog(cpu, v);
            } else {
                hardware_trap(cpu, CR2_DIVIDE_BY_ZERO);
            }
        }
    };


    struct skl_gen_reg_real_mod_t : skl_gen_reg_real_t {
        skl_gen_reg_real_mod_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_real_t(pc_, inst_)
        {
            dialog::internal_error("%s: MOD operator on float type "
                                   "not allowed in Oberon.", __func__);
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
        }
    };


    struct skl_gen_reg_real_abs_t : skl_gen_reg_real_t {
        skl_gen_reg_real_abs_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_real_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            double r = register_as_double(cpu, R1, b1);
            double v = fabs(r);

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%f, %f]\n", r, v);

            epilog(cpu, v);
        }
    };


    struct skl_gen_reg_real_cmp_t : skl_gen_reg_real_t {
        skl_gen_reg_real_cmp_t(md::OADDR pc_, md::OINST inst_) :
            skl_gen_reg_real_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            double l = register_as_double(cpu, R0, b0);
            double r = register_as_double(cpu, R1, b1);
            double v = synthesize_flags_double(l, r);

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);
            dialog::trace("[%f, %f, 0%xH]\n", l, r,
                          static_cast<md::uint32>(v));

            epilog(cpu, v);
        }
    };


    skl::instruction_t *
    op_gen_reg(md::OADDR pc, md::uint32 inst)
    {
        register_bank_t b1  = static_cast<register_bank_t>(field(inst,   8,  8));
        register_bank_t b0  = static_cast<register_bank_t>(field(inst,   9,  9));
        register_bank_t bd  = static_cast<register_bank_t>(field(inst,  10, 10));
        opc_t           opc = static_cast<opc_t>(field(inst, 4, 0));

        if (LIKELY(compute_using(b0, b1) == RB_INTEGER)) {
            if (LIKELY(bd == RB_INTEGER)) {
                switch (opc) {
                case OPC_ADD: return new skl_gen_reg_int_int_add_t(pc, inst);
                case OPC_SUB: return new skl_gen_reg_int_int_sub_t(pc, inst);
                case OPC_MUL: return new skl_gen_reg_int_int_mul_t(pc, inst);
                case OPC_DIV: return new skl_gen_reg_int_int_div_t(pc, inst);
                case OPC_MOD: return new skl_gen_reg_int_int_mod_t(pc, inst);
                case OPC_CMP: return new skl_gen_reg_int_int_cmp_t(pc, inst);
                case OPC_ABS: return new skl_gen_reg_int_int_abs_t(pc, inst);

                default:
                    dialog::internal_error("%s: improper integer opcode", __func__);
                }
            } else {
                /* Compute using integer registers, write to floating
                 * point register.
                 */
                switch (opc) {
                case OPC_ADD: return new skl_gen_reg_int_real_add_t(pc, inst);
                case OPC_SUB: return new skl_gen_reg_int_real_sub_t(pc, inst); 
                case OPC_MUL: return new skl_gen_reg_int_real_mul_t(pc, inst);
                case OPC_DIV: return new skl_gen_reg_int_real_div_t(pc, inst);
                case OPC_MOD: return new skl_gen_reg_int_real_mod_t(pc, inst);
                case OPC_CMP: return new skl_gen_reg_int_real_cmp_t(pc, inst);
                case OPC_ABS: return new skl_gen_reg_int_real_abs_t(pc, inst);

                default:
                    dialog::internal_error("%s: improper opcode", __func__);
                }
            }
        } else {
            switch (opc) {
            case OPC_ADD: return new skl_gen_reg_real_add_t(pc, inst);
            case OPC_SUB: return new skl_gen_reg_real_sub_t(pc, inst);
            case OPC_MUL: return new skl_gen_reg_real_mul_t(pc, inst);
            case OPC_DIV: return new skl_gen_reg_real_div_t(pc, inst);
            case OPC_MOD: return new skl_gen_reg_real_mod_t(pc, inst);
            case OPC_CMP: return new skl_gen_reg_real_cmp_t(pc, inst);
            case OPC_ABS: return new skl_gen_reg_real_abs_t(pc, inst);

            default:
                dialog::internal_error("%s: improper real opcode", __func__);
            }
        }
    }
}
