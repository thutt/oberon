/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <assert.h>
#include <string.h>
#include <stdlib.h>

#include "dialog.h"
#include "o3.h"
#include "heap.h"
#include "skl_flags.h"
#include "skl_int_reg.h"

namespace skl {
        typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_int_reg_opc.h"
#undef OPC
            N_OPCODES
        } opc_t;
        static const char *mne[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_int_reg_opc.h"
#undef OPC
        };
    typedef md::uint32 (*int_opc_fn_t)(md::uint32 l, md::uint32 r);

#define OPC(_t) static md::uint32 oper_##_t(md::uint32 l, md::uint32 r);
#include "skl_int_reg_opc.h"
#undef OPC

    int_opc_fn_t operation[N_OPCODES] = {
#define OPC(_t) oper_##_t,
#include "skl_int_reg_opc.h"
#undef OPC
    };

    static md::uint32
    oper_AND(md::uint32 l, md::uint32 r)
    {
        md::uint32 v = l & r;
        dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
        return v;
    }


    static md::uint32
    oper_ASH(md::uint32 l, md::uint32 r)
    {
        md::uint32 v;

        if (static_cast<md::int8>(r) >= 0) {
            v = left_shift(l, r);
            dialog::trace("[%xH, %xH, %xH left]\n", l, r, v);
        } else {
            /* Arithmetic shift; do not use right_shift(). */
            v = static_cast<md::int32>(l) >> (-static_cast<md::int8>(r) & 31);
            dialog::trace("[%xH, %xH, %xH right]\n", l, r, v);
        }
        return v;
    }


    static md::uint32
    oper_CMPS(md::uint32 l, md::uint32 r)
    {
        md::uint32  v;
        md::uint8  *lp;
        md::uint8  *rp;
        size_t      llen;
        size_t      rlen;
        bool        zf;         // Zero flag.
        bool        cf;         // Carry flag.
        bool        of;         // Overflow flag.
        bool        sf;         // Sign flag.
        bool        valid;

        lp   = heap::heap_to_host(l);
        llen = strlen(reinterpret_cast<const char *>(lp));
        rp   = heap::heap_to_host(r);
        rlen = strlen(reinterpret_cast<const char *>(rp));
        valid = (address_valid(l, sizeof(md::uint8))        &&
                 address_valid(l + llen, sizeof(md::uint8)) &&
                 address_valid(r, sizeof(md::uint8))        &&
                 address_valid(r + rlen, sizeof(md::uint8)));

        if (LIKELY(valid)) {
            v = strcmp(reinterpret_cast<const char *>(lp),
                       reinterpret_cast<const char *>(rp));
            if (v == 0) {
                zf = true;
                cf = false;
                of = false;
                sf = false;
            } else if (v > 0) {
                zf = false;
                cf = false;
                of = false;
                sf = false;
            } else {
                /* result < 0 */
                zf = true;
                cf = true;
                of = false;
                sf = true;
            }
            v = create_flags(zf, sf, cf, of);
        } else {
            v = create_flags(0, 0, 0, 0);
            hardware_trap(cpu, CR2_OUT_OF_BOUNDS_READ);
        }
        dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
        return v;
    }


    static md::uint32
    oper_BITSET(md::uint32 l, md::uint32 r)
    {
        md::uint32 v;

        // md::MaxSet must be one less than a power-of-2.
        COMPILE_TIME_ASSERT(((md::MaxSet + 1) & md::MaxSet) == 0);

        l &= md::MaxSet;        // Constrain to md::MaxSet
        r &= md::MaxSet;        // Constrain to md::MaxSet
        COMPILE_TIME_ASSERT(md::MaxSet <= 31);
        if (LIKELY(l <= r)) {
            /* The following expression can overflow md::uint32.  Compute
             * as 64-bit value and then coerce to 32-bit value.
             *
             * Do not use left_shift() due to potential overflow.
             */
            COMPILE_TIME_ASSERT(sizeof(1)   == sizeof(md::uint32) &&
                                sizeof(1UL) == sizeof(md::uint64));
            v = ((1UL << (r - l + 1UL)) - 1UL) << l;
        } else {
            v = ~0;
            software_trap(cpu, 12);
        }
        dialog::trace("[%xH, %xH]    value: %xH]\n", l, r, v);
        return v;
    }


    static md::uint32
    oper_LSH(md::uint32 l, md::uint32 r)
    {
        md::uint32 v;

        if (static_cast<md::int8>(r) >= 0) {
            v = left_shift(l, r);
            dialog::trace("[%xH, %xH, %xH left]\n", l, r, v);
        } else {
            v = right_shift(l, -static_cast<md::int8>(r));
            dialog::trace("[%xH, %xH, %xH right]\n", l, r, v);
        }
        return v;
    }


    static md::uint32
    oper_NOR(md::uint32 l, md::uint32 r)
    {
        md::uint32 v = ~(l | r);
        dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
        return v;
    }


    static md::uint32
    oper_OR(md::uint32 l, md::uint32 r)
    {
        md::uint32 v = l | r;
        dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
        return v;
    }


    static md::uint32
    oper_ROT(md::uint32 l, md::uint32 r)
    {
        /* Rotate l by r.  If r is positive, rotate left.  If r is
         * negative, rotate right.
         *
         * Shifting is limited to 31 bits.
         */
        const md::uint32 n_bits      = 32;
        bool             rotate_left = static_cast<md::int32>(r) >= 0;
        md::uint32       bits        = abs(static_cast<int>(r)) % n_bits;
        md::uint32       lbits;
        md::uint32       rbits;
        if (rotate_left) {
            lbits = left_shift(l, bits);
            rbits = right_shift(l, n_bits - bits);
        } else {
            lbits = right_shift(l, bits);
            rbits = left_shift(l, n_bits - bits);
        }
        return lbits | rbits;
    }


    static md::uint32
    oper_XOR(md::uint32 l, md::uint32 r)
    {
        md::uint32 v = l ^ r;
        dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
        return v;
    }


    void
    op_int_reg(cpu_t &cpu, md::uint32 inst)
    {
        O3::decode_pc_t  decoded_pc;
        const unsigned   Rd  = field(inst, 25, 21);
        const unsigned   R0  = field(inst, 20, 16);
        const unsigned   R1  = field(inst, 15, 11);
        const opc_t      opc = static_cast<opc_t>(field(inst, 4, 0));
        const md::uint32 l   = read_integer_register(cpu, R0);
        const md::uint32 r   = read_integer_register(cpu, R1);
        md::uint32       v;

        dialog::trace("%s: %s  R%u, R%u, R%u",
                      decoded_pc, mne[opc], R0, R1, Rd);
        assert(opc >= 0 && opc < N_OPCODES);
        v = operation[opc](l, r);
        write_integer_register(cpu, Rd, v);

        O3::decode_pc(cpu.pc, decoded_pc);
        increment_pc(cpu, 1);
    }
}
