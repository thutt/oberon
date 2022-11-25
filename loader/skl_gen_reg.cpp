/* Copyright (c) 2021, 2022 Logic Magicians Software */

#include <math.h>
#include <stdlib.h>

#include "dialog.h"
#include "o3.h"
#include "skl_gen_reg.h"

namespace skl {
        typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_gen_reg_opc.h"
#undef OPC
            N_OPCODES
        } opc_t;

    typedef double (*arithmetic_double_fn)(double l, double r);

#define OPC(_t) static double _t##_double(double l, double r);
#include "skl_gen_reg_opc.h"
#undef OPC

    static arithmetic_double_fn arithmetic_double[] = {
#define OPC(_t) _t##_double,
#include "skl_gen_reg_opc.h"
#undef OPC
    };


    static unsigned
    synthesize_overflow_int32(md::int32 l, md::int32 r)
    {
        unsigned sign_mask = left_shift(1, 31);
        int      res       = l - r; // Result sign.
        unsigned not_equal = static_cast<unsigned>(l ^ r);
        unsigned sign_diff = static_cast<unsigned>(l ^ res);

        return !!((not_equal & sign_diff) & sign_mask);
    }


    static md::uint32
    synthesize_flags_int32(md::uint32 l, md::uint32 r)
    {
        md::int32  ll = static_cast<md::int32>(l);
        md::int32  lr = static_cast<md::int32>(r);
        md::uint32 ZF = ll == lr;                          // Zero flag.
        md::uint32 SF = (ll - lr) < 0;                     // Sign flag.
        md::uint32 CF = l < r;                             // Carry flag.
        md::uint32 OF = synthesize_overflow_int32(ll, lr); // Overflow flag.
        return ((ZF << 0) |
                (SF << 1) |
                (CF << 2) |
                (OF << 3));
    }


    struct skl_gen_reg_t : skl::instruction_t {
        int             Rd;
        int             R0;
        int             R1;
        register_bank_t bd;
        register_bank_t b0;
        register_bank_t b1;

        skl_gen_reg_t(cpu_t           *cpu_,
                      md::OINST        inst_,
                      const char      **mne_,
                      register_bank_t  bd_,
                      register_bank_t  b0_,
                      register_bank_t  b1_) :
            skl::instruction_t(cpu_, inst_, mne_),
            Rd(field(inst_, 25, 21)),
            R0(field(inst_, 20, 16)),
            R1(field(inst_, 15, 11)),
            bd(bd_),
            b0(b0_),
            b1(b1_)
        {
        }
    };


    struct skl_gen_reg_int_int_t : skl_gen_reg_t {
        skl_gen_reg_int_int_t(cpu_t           *cpu_,
                              md::OINST       inst_,
                              const char      **mne_,
                              register_bank_t  bd_,
                              register_bank_t  b0_,
                              register_bank_t  b1_) :
            skl_gen_reg_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_INTEGER);
        }
    };


    struct skl_gen_reg_int_int_add_t : skl_gen_reg_int_int_t {
        skl_gen_reg_int_int_add_t(cpu_t           *cpu_,
                                  md::OINST       inst_,
                                  const char      **mne_,
                                  register_bank_t  bd_,
                                  register_bank_t  b0_,
                                  register_bank_t  b1_) :
            skl_gen_reg_int_int_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
        }

        virtual void interpret(void)
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
        skl_gen_reg_int_int_sub_t(cpu_t           *cpu_,
                                  md::OINST       inst_,
                                  const char      **mne_,
                                  register_bank_t  bd_,
                                  register_bank_t  b0_,
                                  register_bank_t  b1_) :
            skl_gen_reg_int_int_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
        }

        virtual void interpret(void)
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
        skl_gen_reg_int_int_mul_t(cpu_t           *cpu_,
                                  md::OINST       inst_,
                                  const char      **mne_,
                                  register_bank_t  bd_,
                                  register_bank_t  b0_,
                                  register_bank_t  b1_) :
            skl_gen_reg_int_int_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
        }

        virtual void interpret(void)
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
        skl_gen_reg_int_int_div_t(cpu_t           *cpu_,
                                  md::OINST       inst_,
                                  const char      **mne_,
                                  register_bank_t  bd_,
                                  register_bank_t  b0_,
                                  register_bank_t  b1_) :
            skl_gen_reg_int_int_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
        }

        virtual void interpret(void)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v;

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
        skl_gen_reg_int_int_mod_t(cpu_t           *cpu_,
                                  md::OINST       inst_,
                                  const char      **mne_,
                                  register_bank_t  bd_,
                                  register_bank_t  b0_,
                                  register_bank_t  b1_) :
            skl_gen_reg_int_int_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
        }

        virtual void interpret(void)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v;

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
        skl_gen_reg_int_int_cmp_t(cpu_t           *cpu_,
                                  md::OINST       inst_,
                                  const char      **mne_,
                                  register_bank_t  bd_,
                                  register_bank_t  b0_,
                                  register_bank_t  b1_) :
            skl_gen_reg_int_int_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
        }

        virtual void interpret(void)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v = synthesize_flags_int32(l, r);

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
        skl_gen_reg_int_int_abs_t(cpu_t           *cpu_,
                                  md::OINST       inst_,
                                  const char      **mne_,
                                  register_bank_t  bd_,
                                  register_bank_t  b0_,
                                  register_bank_t  b1_) :
            skl_gen_reg_int_int_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
        }

        virtual void interpret(void)
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
        skl_gen_reg_int_real_t(cpu_t           *cpu_,
                               md::OINST       inst_,
                               const char      **mne_,
                               register_bank_t  bd_,
                               register_bank_t  b0_,
                               register_bank_t  b1_) :
            skl_gen_reg_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }
    };


    struct skl_gen_reg_int_real_add_t : skl_gen_reg_int_real_t {
        skl_gen_reg_int_real_add_t(cpu_t           *cpu_,
                                   md::OINST       inst_,
                                   const char      **mne_,
                                   register_bank_t  bd_,
                                   register_bank_t  b0_,
                                   register_bank_t  b1_) :
            skl_gen_reg_int_real_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }


        virtual void interpret(void)
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
        skl_gen_reg_int_real_sub_t(cpu_t           *cpu_,
                                   md::OINST       inst_,
                                   const char      **mne_,
                                   register_bank_t  bd_,
                                   register_bank_t  b0_,
                                   register_bank_t  b1_) :
            skl_gen_reg_int_real_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }


        virtual void interpret(void)
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
        skl_gen_reg_int_real_mul_t(cpu_t           *cpu_,
                                   md::OINST       inst_,
                                   const char      **mne_,
                                   register_bank_t  bd_,
                                   register_bank_t  b0_,
                                   register_bank_t  b1_) :
            skl_gen_reg_int_real_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }


        virtual void interpret(void)
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
        skl_gen_reg_int_real_div_t(cpu_t           *cpu_,
                                   md::OINST       inst_,
                                   const char      **mne_,
                                   register_bank_t  bd_,
                                   register_bank_t  b0_,
                                   register_bank_t  b1_) :
            skl_gen_reg_int_real_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }


        virtual void interpret(void)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v;

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
        skl_gen_reg_int_real_mod_t(cpu_t           *cpu_,
                                   md::OINST       inst_,
                                   const char      **mne_,
                                   register_bank_t  bd_,
                                   register_bank_t  b0_,
                                   register_bank_t  b1_) :
            skl_gen_reg_int_real_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }


        virtual void interpret(void)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v;

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
        skl_gen_reg_int_real_cmp_t(cpu_t           *cpu_,
                                   md::OINST       inst_,
                                   const char      **mne_,
                                   register_bank_t  bd_,
                                   register_bank_t  b0_,
                                   register_bank_t  b1_) :
            skl_gen_reg_int_real_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }


        virtual void interpret(void)
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
        skl_gen_reg_int_real_abs_t(cpu_t           *cpu_,
                                   md::OINST       inst_,
                                   const char      **mne_,
                                   register_bank_t  bd_,
                                   register_bank_t  b0_,
                                   register_bank_t  b1_) :
            skl_gen_reg_int_real_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
            assert(b0 == RB_INTEGER && b1 == RB_INTEGER && bd == RB_DOUBLE);
        }


        virtual void interpret(void)
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
        skl_gen_reg_real_t(cpu_t           *cpu_,
                           md::OINST        inst_,
                           const char      **mne_,
                           register_bank_t  bd_,
                           register_bank_t  b0_,
                           register_bank_t  b1_) :
            skl_gen_reg_t(cpu_, inst_, mne_, bd_, b0_, b1_)
        {
        }


        virtual void interpret(void)
        {
            double l = register_as_double(cpu, R0, b0);
            double r = register_as_double(cpu, R1, b1);
            double v = arithmetic_double[opc](l, r);

            dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne,
                          reg_bank[b0], R0,
                          reg_bank[b1], R1,
                          reg_bank[bd], Rd);

            switch (opc) {
            case OPC_ADD:
            case OPC_SUB:
            case OPC_MUL:
            case OPC_DIV:
            case OPC_MOD:
            case OPC_ABS:
                dialog::trace("[%f, %f, %f]\n", l, r, v);
                break;

            case OPC_CMP:
                dialog::trace("[%f, %f, 0%xH]\n", l, r,
                              static_cast<md::uint32>(v));
                break;

            default:
                dialog::not_implemented("%s: unhandled decode?", __func__);
            }

            if (!cpu->exception_raised) {
                if (bd == RB_INTEGER) {
                    write_integer_register(cpu, Rd,
                                           static_cast<md::uint32>(v));
                } else {
                    write_real_register(cpu, Rd, v);
                }
            }
            increment_pc(cpu, 1);
        }
    };


    static unsigned
    synthesize_overflow_double(double l, double r)
    {
        int t0 = (r >= 0) && (l >= md::MinLReal() + r);
        int t1 = (r < 0)  && (l <= md::MaxLReal() + r);
        return !t0 && !t1;
    }


    static md::uint32
    synthesize_flags_double(double l, double r)
    {
        double     delta = (l - r);
        md::uint32 ZF    = delta == 0;                    // Zero flag.
        md::uint32 SF    = delta < 0;                     // Sign flag.
        md::uint32 CF    = l < r;                         // Carry flag.
        md::uint32 OF = synthesize_overflow_double(l, r); // Overflow flag.

        return ((ZF << 0) |
                (SF << 1) |
                (CF << 2) |
                (OF << 3));
    }
    static double
    ABS_double(double l, double r)
    {
        return fabs(r);
    }


    static double
    ADD_double(double l, double r)
    {
        return l + r;
    }


    static double
    SUB_double(double l, double r)
    {
        return l - r;
    }


    static double
    MUL_double(double l, double r)
    {
        return l * r;
    }


    static double
    DIV_double(double l, double r)
    {
        if (LIKELY(r != 0)) {
            return l / r;
        } else {
            hardware_trap(&cpu, CR2_DIVIDE_BY_ZERO);
            return 0;           // Silence compiler.
        }
    }


    static double
    MOD_double(double l, double r)
    {
        dialog::internal_error("%s: MOD operator on float type "
                               "not allowed in Oberon.", __func__);
        return 0;
    }


    static double
    CMP_double(double l, double r)
    {
        return synthesize_flags_double(l, r);
    }


    skl::instruction_t *
    op_gen_reg(cpu_t *cpu, md::uint32 inst)
    {
        static const char *mne[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_gen_reg_opc.h"
#undef OPC
        };
        register_bank_t b1  = static_cast<register_bank_t>(field(inst,   8,  8));
        register_bank_t b0  = static_cast<register_bank_t>(field(inst,   9,  9));
        register_bank_t bd  = static_cast<register_bank_t>(field(inst,  10, 10));
        opc_t           opc = static_cast<opc_t>(field(inst, 4, 0));

        if (LIKELY(compute_using(b0, b1) == RB_INTEGER)) {
            if (LIKELY(bd == RB_INTEGER)) {
                switch (opc) {
                case OPC_ADD:
                    return new skl_gen_reg_int_int_add_t(cpu, inst, mne,
                                                         bd, b0, b1);

                case OPC_SUB:
                    return new skl_gen_reg_int_int_sub_t(cpu, inst, mne,
                                                         bd, b0, b1);

                case OPC_MUL:
                    return new skl_gen_reg_int_int_mul_t(cpu, inst, mne,
                                                         bd, b0, b1);

                case OPC_DIV:
                    return new skl_gen_reg_int_int_div_t(cpu, inst, mne,
                                                         bd, b0, b1);

                case OPC_MOD:
                    return new skl_gen_reg_int_int_mod_t(cpu, inst, mne,
                                                         bd, b0, b1);

                case OPC_CMP:
                    return new skl_gen_reg_int_int_cmp_t(cpu, inst, mne,
                                                         bd, b0, b1);

                case OPC_ABS:
                    return new skl_gen_reg_int_int_abs_t(cpu, inst, mne,
                                                         bd, b0, b1);

                default:
                    dialog::internal_error("%s: improper opcode", __func__);
                }
            } else {
                /* Compute using integer registers, write to floating
                 * point register.
                 */
                switch (opc) {
                case OPC_ADD:
                    return new skl_gen_reg_int_real_add_t(cpu, inst, mne,
                                                          bd, b0, b1);

                case OPC_SUB:
                    return new skl_gen_reg_int_real_sub_t(cpu, inst, mne,
                                                          bd, b0, b1);

                case OPC_MUL:
                    return new skl_gen_reg_int_real_mul_t(cpu, inst, mne,
                                                          bd, b0, b1);

                case OPC_DIV:
                    return new skl_gen_reg_int_real_div_t(cpu, inst, mne,
                                                          bd, b0, b1);

                case OPC_MOD:
                    return new skl_gen_reg_int_real_mod_t(cpu, inst, mne,
                                                          bd, b0, b1);

                case OPC_CMP:
                    return new skl_gen_reg_int_real_cmp_t(cpu, inst, mne,
                                                          bd, b0, b1);

                case OPC_ABS:
                    return new skl_gen_reg_int_real_abs_t(cpu, inst, mne,
                                                          bd, b0, b1);

                default:
                    dialog::internal_error("%s: improper opcode", __func__);
                }
            }
        } else {
            return new skl_gen_reg_real_t(cpu, inst, mne, bd, b0, b1);
        }
    }
}
