/* Copyright (c) 2021, 2022 Logic Magicians Software */

#include <math.h>
#include <stdlib.h>

#include "dialog.h"
#include "o3.h"
#include "skl_gen_reg.h"

namespace skl {
    typedef md::uint32 (*arithmetic_int_fn)(md::uint32 l, md::uint32 r);
    typedef double (*arithmetic_double_fn)(double l, double r);

#define OPC(_t) static md::uint32 _t##_int(md::uint32 l, md::uint32 r);
#include "skl_gen_reg_opc.h"
#undef OPC

#define OPC(_t) static double _t##_double(double l, double r);
#include "skl_gen_reg_opc.h"
#undef OPC

    static arithmetic_int_fn arithmetic_int[] = {
#define OPC(_t) _t##_int,
#include "skl_gen_reg_opc.h"
#undef OPC
    };

    static arithmetic_double_fn arithmetic_double[] = {
#define OPC(_t) _t##_double,
#include "skl_gen_reg_opc.h"
#undef OPC
    };


    static unsigned
    synthesize_overflow_int32(md::int32 l, md::int32 r)
    {
        unsigned sign_mask = left_shift(1, 31);
        bool     ls        = (l & sign_mask) != 0;       // Left sign.
        bool     rs        = (r & sign_mask) != 0;       // Right sign.
        bool     resS      = ((l - r) & sign_mask) != 0; // Result sign.

        return (ls != rs) && (ls != resS);
    }


    static md::uint32
    synthesize_flags_int32(md::uint32 l, md::uint32 r)
    {
        md::int32  ll = static_cast<md::int32>(l);
        md::int32  lr = static_cast<md::int32>(r);
        md::uint32 ZF = (ll - lr) == 0;                    // Zero flag.
        md::uint32 SF = (ll - lr) < 0;                     // Sign flag.
        md::uint32 CF = l < r;                             // Carry flag.
        md::uint32 OF = synthesize_overflow_int32(ll, lr); // Overflow flag.
        return ((ZF << 0) |
                (SF << 1) |
                (CF << 2) |
                (OF << 3));
    }


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


    static md::uint32
    ABS_int(md::uint32 l, md::uint32 r)
    {
        return abs(static_cast<int>(r));
    }


    static md::uint32
    ADD_int(md::uint32 l, md::uint32 r)
    {
        return l + r;
    }


    static md::uint32
    SUB_int(md::uint32 l, md::uint32 r)
    {
        return l - r;
    }


    static md::uint32
    MUL_int(md::uint32 l, md::uint32 r)
    {
        return l * r;
    }


    static md::uint32
    DIV_int(md::uint32 l, md::uint32 r)
    {
        if (LIKELY(r != 0)) {
            return O3::DIV(l, r);
        } else {
            hardware_trap(cpu, CR2_DIVIDE_BY_ZERO);
            return 0;           // Silence compiler.
        }
    }


    static md::uint32
    MOD_int(md::uint32 l, md::uint32 r)
    {
        if (LIKELY(r != 0)) {
            return O3::MOD(l, r);
        } else {
            hardware_trap(cpu, CR2_DIVIDE_BY_ZERO);
            return 0;           // Silence compiler.
        }
    }


    static md::uint32
    CMP_int(md::uint32 l, md::uint32 r)
    {
        return synthesize_flags_int32(l, r);
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
            hardware_trap(cpu, CR2_DIVIDE_BY_ZERO);
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


    void
    op_gen_reg(cpu_t &cpu, md::uint32 inst)
    {
        typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_gen_reg_opc.h"
#undef OPC
            N_OPCODES
        } opc_t;
        static const char *mne[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_gen_reg_opc.h"
#undef OPC
        };
        opc_t           opc = static_cast<opc_t>(field(inst, 4, 0));
        unsigned        Rd  = field(inst, 25, 21);
        unsigned        R0  = field(inst, 20, 16);
        unsigned        R1  = field(inst, 15, 11);
        register_bank_t bd  = static_cast<register_bank_t>(field(inst, 10, 10));
        register_bank_t b0  = static_cast<register_bank_t>(field(inst,  9,  9));
        register_bank_t b1  = static_cast<register_bank_t>(field(inst,  8,  8));
        O3::decode_pc_t decoded_pc;

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  %s%u, %s%u, %s%u", decoded_pc, mne[opc],
                      reg_bank[b0], R0,
                      reg_bank[b1], R1,
                      reg_bank[bd], Rd);
        if (false) {
            dialog::not_implemented("%s: handle overflow?", __func__);
        }
        if (compute_using(b0, b1) == RB_INTEGER) {
            md::uint32 l = register_as_integer(cpu, R0, b0);
            md::uint32 r = register_as_integer(cpu, R1, b1);;
            md::uint32 v = arithmetic_int[opc](l, r);

            dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
            if (bd == RB_INTEGER) {
                write_integer_register(cpu, Rd, v);
            } else {
                write_real_register(cpu, Rd, static_cast<int>(v));
            }
        } else {
            double l = register_as_double(cpu, R0, b0);
            double r = register_as_double(cpu, R1, b1);
            double v = arithmetic_double[opc](l, r);

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
            if (!cpu.exception_raised) {
                if (bd == RB_INTEGER) {
                    write_integer_register(cpu, Rd, v);
                } else {
                    write_real_register(cpu, Rd, v);
                }
            }
        }
        increment_pc(cpu, 1);
    }
}
