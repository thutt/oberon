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

    typedef md::uint32 (*int_opc_fn_t)(md::uint32 l,
                                       md::uint32 r,
                                       bool &fault);

#define OPC(_t) static md::uint32 oper_##_t(md::uint32 l,       \
                                            md::uint32 r,       \
                                            bool &fault);
#include "skl_int_reg_opc.h"
#undef OPC

    int_opc_fn_t operation[N_OPCODES] = {
#define OPC(_t) oper_##_t,
#include "skl_int_reg_opc.h"
#undef OPC
    };


    // XXX TODO: special ize subclasses to remove indirect call of operand.
    struct skl_int_reg_t : skl::instruction_t {
        int          Rd;
        int          R0;
        int          R1;
        int_opc_fn_t operation;

        skl_int_reg_t(md::OADDR    pc_,
                      md::OINST   inst_,
                      const char **mne_,
                      int_opc_fn_t operation_) :
            skl::instruction_t(pc_, inst_, mne_),
            Rd(field(inst_, 25, 21)),
            R0(field(inst_, 20, 16)),
            R1(field(inst_, 15, 11)),
            operation(operation_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            md::uint32       v;
            bool             fault = false;
            const md::uint32 l     = read_integer_register(cpu, R0);
            const md::uint32 r     = read_integer_register(cpu, R1);

            dialog::trace("%s: %s  R%u, R%u, R%u", decoded_pc, mne, R0, R1, Rd);

            v = operation(l, r, fault);
            write_integer_register(cpu, Rd, v);
            if (LIKELY(!fault)) {
                increment_pc(cpu, 1);
            }
        }
    };


    static md::uint32
    oper_AND(md::uint32 l, md::uint32 r, bool &fault)
    {
        md::uint32 v = l & r;
        dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
        return v;
    }


    static md::uint32
    oper_ASH(md::uint32 l, md::uint32 r, bool &fault)
    {
        unsigned v;

        if (static_cast<md::int8>(r) >= 0) {
            v = left_shift(l, static_cast<int>(r));
            dialog::trace("[%xH, %xH, %xH left]\n", l, r, v);
        } else {
            /* Arithmetic shift; do not use right_shift(). */
            v = static_cast<unsigned>(static_cast<md::int32>(l) >>
                                      (-static_cast<md::int8>(r) & 31));
            dialog::trace("[%xH, %xH, %xH right]\n", l, r, v);
        }
        return v;
    }


    static md::uint32
    oper_CMPS(md::uint32 l, md::uint32 r, bool &fault)
    {
        md::uint32 v;
        md::HADDR  lp;
        md::HADDR  rp;
        int        llen;
        int        rlen;
        bool       zf;          // Zero flag.
        bool       cf;          // Carry flag.
        bool       of;          // Overflow flag.
        bool       sf;          // Sign flag.
        bool       valid;

        lp   = heap::heap_to_host(l);
        llen = static_cast<int>(strlen(reinterpret_cast<const char *>(lp)));
        rp   = heap::heap_to_host(r);
        rlen = static_cast<int>(strlen(reinterpret_cast<const char *>(rp)));
        valid = (address_valid(l,
                               static_cast<int>(sizeof(md::uint8))) &&
                 address_valid(l + static_cast<md::OADDR>(llen),
                               static_cast<int>(sizeof(md::uint8))) &&
                 address_valid(r,
                               static_cast<int>(sizeof(md::uint8))) &&
                 address_valid(r + static_cast<md::OADDR>(rlen),
                               static_cast<int>(sizeof(md::uint8))));

        if (LIKELY(valid)) {
            int compare = strcmp(reinterpret_cast<const char *>(lp),
                                 reinterpret_cast<const char *>(rp));
            if (compare == 0) {
                zf = true;
                cf = false;
                of = false;
                sf = false;
            } else if (compare > 0) {
                zf = false;
                cf = false;
                of = false;
                sf = false;
            } else {
                /* result < 0 */
                zf = false;
                cf = false;
                of = false;
                sf = true;
            }
            v = create_flags(zf, sf, cf, of);
        } else {
            v     = create_flags(0, 0, 0, 0);
            fault = true;
            hardware_trap(&cpu, CR2_OUT_OF_BOUNDS_READ);
        }
        dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
        return v;
    }


    static md::uint32
    oper_BITSET(md::uint32 l, md::uint32 r, bool &fault)
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
            v = static_cast<md::uint32>(((1UL << (r - l + 1UL)) - 1UL) << l);
        } else {
            v     = ~0U;
            fault = true;
            software_trap(&cpu, 12);
        }
        dialog::trace("[%xH, %xH]    value: %xH]\n", l, r, v);
        return v;
    }


    static md::uint32
    oper_LSH(md::uint32 l, md::uint32 r, bool &fault)
    {
        unsigned v;

        if (static_cast<md::int8>(r) >= 0) {
            v = left_shift(l, static_cast<int>(r));
            dialog::trace("[%xH, %xH, %xH left]\n", l, r, v);
        } else {
            v = right_shift(l, -static_cast<md::int8>(r));
            dialog::trace("[%xH, %xH, %xH right]\n", l, r, v);
        }
        return v;
    }


    static md::uint32
    oper_NOR(md::uint32 l, md::uint32 r, bool &fault)
    {
        md::uint32 v = ~(l | r);
        dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
        return v;
    }


    static md::uint32
    oper_OR(md::uint32 l, md::uint32 r, bool &fault)
    {
        md::uint32 v = l | r;
        dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
        return v;
    }


    static md::uint32
    oper_ROT(md::uint32 l, md::uint32 r, bool &fault)
    {
        /* Rotate l by r.  If r is positive, rotate left.  If r is
         * negative, rotate right.
         *
         * Shifting is limited to 31 bits.
         */
        int      n_bits      = 32;
        bool     rotate_left = static_cast<md::int32>(r) >= 0;
        int      bits        = abs(static_cast<int>(r)) % n_bits;
        unsigned lbits;
        unsigned rbits;
        if (rotate_left) {
            lbits = left_shift(l, bits);
            rbits = right_shift(l, n_bits - bits);
        } else {
            lbits = right_shift(l, bits);
            rbits = left_shift(l, n_bits - bits);
        }
        dialog::trace("[%xH | %xH -> %xH]\n",
                      lbits, rbits, lbits | rbits);
        return lbits | rbits;
    }


    static md::uint32
    oper_XOR(md::uint32 l, md::uint32 r, bool &fault)
    {
        md::uint32 v = l ^ r;
        dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
        return v;
    }


    skl::instruction_t *
    op_int_reg(cpu_t *cpu, md::OINST inst) // XXX remove cpu argument!
    {
        const opc_t opc = static_cast<opc_t>(field(inst, 4, 0));

        assert(opc >= 0 && opc < N_OPCODES);
        return new skl_int_reg_t(cpu->pc, inst, mne, operation[opc]);
    }
}
