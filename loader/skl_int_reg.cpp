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
    static const char *mnemonics[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_int_reg_opc.h"
#undef OPC
    };


    struct skl_int_reg_base_t : skl::instruction_t {
        int          Rd;
        int          R0;
        int          R1;

        skl_int_reg_base_t(md::OADDR pc_, md::OINST inst_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst_, 25, 21)),
            R0(field(inst_, 20, 16)),
            R1(field(inst_, 15, 11))
        {
        }
    };


    struct skl_int_reg_and_t : skl::skl_int_reg_base_t {
        skl_int_reg_and_t(md::OADDR pc_, md::OINST inst_) :
            skl_int_reg_base_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            const md::uint32 l     = read_integer_register(cpu, R0);
            const md::uint32 r     = read_integer_register(cpu, R1);
            md::uint32       v     = l & r;

            dialog::trace("%s: %s  R%u, R%u, R%u",
                          decoded_pc, mne, R0, R1, Rd);

            write_integer_register(cpu, Rd, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_int_reg_ash_t : skl::skl_int_reg_base_t {
        skl_int_reg_ash_t(md::OADDR pc_, md::OINST inst_) :
            skl_int_reg_base_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            const md::uint32 l     = read_integer_register(cpu, R0);
            const md::uint32 r     = read_integer_register(cpu, R1);
            md::uint32       v;

            dialog::trace("%s: %s  R%u, R%u, R%u",
                          decoded_pc, mne, R0, R1, Rd);

            if (static_cast<md::int8>(r) >= 0) {
                v = left_shift(l, static_cast<int>(r));
                dialog::trace("[%xH, %xH, %xH left]\n", l, r, v);
            } else {
                /* Arithmetic shift; do not use right_shift(). */
                v = static_cast<unsigned>(static_cast<md::int32>(l) >>
                                          (-static_cast<md::int8>(r) & 31));
                dialog::trace("[%xH, %xH, %xH right]\n", l, r, v);
            }
            write_integer_register(cpu, Rd, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_int_reg_cmps_t : skl::skl_int_reg_base_t {
        skl_int_reg_cmps_t(md::OADDR pc_, md::OINST inst_) :
            skl_int_reg_base_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            const md::uint32 l = read_integer_register(cpu, R0);
            const md::uint32 r = read_integer_register(cpu, R1);
            md::uint32       v;
            md::HADDR        lp;
            md::HADDR        rp;
            int              llen;
            int              rlen;
            bool             zf; // Zero flag.
            bool             cf; // Carry flag.
            bool             of; // Overflow flag.
            bool             sf; // Sign flag.
            bool             valid;

            dialog::trace("%s: %s  R%u, R%u, R%u", decoded_pc, mne, R0, R1, Rd);

            lp   = heap::heap_to_host(l);
            llen = static_cast<int>(strlen(reinterpret_cast<const char *>(lp)));
            rp   = heap::heap_to_host(r);
            rlen = static_cast<int>(strlen(reinterpret_cast<const char *>(rp)));
            valid = (address_valid(l, static_cast<int>(sizeof(md::uint8))) &&
                     address_valid(l + static_cast<md::OADDR>(llen),
                                   static_cast<int>(sizeof(md::uint8))) &&
                     address_valid(r, static_cast<int>(sizeof(md::uint8))) &&
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
                dialog::trace("[%xH, %xH, %xH]\n", l, r, v);
                write_integer_register(cpu, Rd, v);
                increment_pc(cpu, 1);
            } else {
                hardware_trap(cpu, CR2_OUT_OF_BOUNDS_READ);
            }
        }
    };


    struct skl_int_reg_bitset_t : skl::skl_int_reg_base_t {
        skl_int_reg_bitset_t(md::OADDR pc_, md::OINST inst_) :
            skl_int_reg_base_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 l = read_integer_register(cpu, R0);
            md::uint32 r = read_integer_register(cpu, R1);
            md::uint32 v;

            dialog::trace("%s: %s  R%u, R%u, R%u", decoded_pc, mne, R0, R1, Rd);

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
                dialog::trace("[%xH, %xH]    value: %xH]\n", l, r, v);
                write_integer_register(cpu, Rd, v);
                increment_pc(cpu, 1);
            } else {
                software_trap(cpu, 12);
            }
        }
    };


    struct skl_int_reg_lsh_t : skl::skl_int_reg_base_t {
        skl_int_reg_lsh_t(md::OADDR pc_, md::OINST inst_) :
            skl_int_reg_base_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            const md::uint32 l     = read_integer_register(cpu, R0);
            const md::uint32 r     = read_integer_register(cpu, R1);
            md::uint32       v;

            dialog::trace("%s: %s  R%u, R%u, R%u", decoded_pc, mne, R0, R1, Rd);
            if (static_cast<md::int8>(r) >= 0) {
                v = left_shift(l, static_cast<int>(r));
                dialog::trace("[%xH, %xH, %xH left]\n", l, r, v);
            } else {
                v = right_shift(l, -static_cast<md::int8>(r));
                dialog::trace("[%xH, %xH, %xH right]\n", l, r, v);
            }

            write_integer_register(cpu, Rd, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_int_reg_nor_t : skl::skl_int_reg_base_t {
        skl_int_reg_nor_t(md::OADDR pc_, md::OINST inst_) :
            skl_int_reg_base_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            const md::uint32 l = read_integer_register(cpu, R0);
            const md::uint32 r = read_integer_register(cpu, R1);
            md::uint32       v = ~(l | r);

            dialog::trace("%s: %s  R%u, R%u, R%u", decoded_pc, mne, R0, R1, Rd);

            write_integer_register(cpu, Rd, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_int_reg_or_t : skl::skl_int_reg_base_t {
        skl_int_reg_or_t(md::OADDR pc_, md::OINST inst_) :
            skl_int_reg_base_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            const md::uint32 l = read_integer_register(cpu, R0);
            const md::uint32 r = read_integer_register(cpu, R1);
            md::uint32       v = l | r;

            dialog::trace("%s: %s  R%u, R%u, R%u", decoded_pc, mne, R0, R1, Rd);

            write_integer_register(cpu, Rd, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_int_reg_rot_t : skl::skl_int_reg_base_t {
        skl_int_reg_rot_t(md::OADDR pc_, md::OINST inst_) :
            skl_int_reg_base_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            const md::uint32 l           = read_integer_register(cpu, R0);
            const md::uint32 r           = read_integer_register(cpu, R1);
            int              n_bits      = 32;
            bool             rotate_left = static_cast<md::int32>(r) >= 0;
            int              bits        = abs(static_cast<int>(r)) % n_bits;
            unsigned         lbits;
            unsigned         rbits;
            md::uint32       v;

            dialog::trace("%s: %s  R%u, R%u, R%u", decoded_pc, mne, R0, R1, Rd);

            /* Rotate l by r.  If r is positive, rotate left.  If r is
             * negative, rotate right.
             *
             * Shifting is limited to 31 bits.
             */
            if (rotate_left) {
                lbits = left_shift(l, bits);
                rbits = right_shift(l, n_bits - bits);
            } else {
                lbits = right_shift(l, bits);
                rbits = left_shift(l, n_bits - bits);
            }
            dialog::trace("[%xH | %xH -> %xH]\n",
                          lbits, rbits, lbits | rbits);
            v = lbits | rbits;
            write_integer_register(cpu, Rd, v);
            increment_pc(cpu, 1);
        }
    };


    struct skl_int_reg_xor_t : skl::skl_int_reg_base_t {
        skl_int_reg_xor_t(md::OADDR pc_, md::OINST inst_) :
            skl_int_reg_base_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            const md::uint32 l = read_integer_register(cpu, R0);
            const md::uint32 r = read_integer_register(cpu, R1);
            md::uint32       v = l ^ r;

            dialog::trace("%s: %s  R%u, R%u, R%u",
                          decoded_pc, mne, R0, R1, Rd);

            write_integer_register(cpu, Rd, v);
            increment_pc(cpu, 1);
        }
    };


    skl::instruction_t *
    op_int_reg(md::OADDR pc, md::OINST inst)
    {
        const opc_t opc = static_cast<opc_t>(field(inst, 4, 0));

        assert(opc >= 0 && opc < N_OPCODES);
        switch (opc) {
        case OPC_AND:    return new skl_int_reg_and_t(pc, inst);
        case OPC_ASH:    return new skl_int_reg_ash_t(pc, inst);
        case OPC_BITSET: return new skl_int_reg_bitset_t(pc, inst);
        case OPC_CMPS:   return new skl_int_reg_cmps_t(pc, inst);
        case OPC_LSH:    return new skl_int_reg_lsh_t(pc, inst);
        case OPC_NOR:    return new skl_int_reg_nor_t(pc, inst);
        case OPC_OR:     return new skl_int_reg_or_t(pc, inst);
        case OPC_ROT:    return new skl_int_reg_rot_t(pc, inst);
        case OPC_XOR:    return new skl_int_reg_xor_t(pc, inst);

        default:
            dialog::internal_error("%s: improper opcode", __func__);
        }
    }
}
