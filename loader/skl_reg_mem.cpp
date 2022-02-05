/* Copyright (c) 2021, 2022 Logic Magicians Software */

#include "config.h"
#include "dialog.h"
#include "heap.h"
#include "o3.h"
#include "skl_reg_mem.h"

namespace skl {
    typedef struct reg_mem_decode_t {
        unsigned int  Rd;
        unsigned int  Rbase;
        unsigned int  Rindex;
        unsigned int  scale;    // { 1, 2, 4, 8 }
        const char   *mne;
    } reg_mem_decode_t;


    static void
    read_integer(cpu_t                  &cpu,
                 const reg_mem_decode_t &decode,
                 bool                    sign_extend,
                 md::uint32              offset,
                 unsigned                size)
    {
        char            sign   = '+';
        O3::decode_pc_t decoded_pc;

        if (offset < 0) {
            sign   = '-';
        }

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  (R%u + R%u:%u %c %xH), R%u",
                      decoded_pc, decode.mne, decode.Rbase, decode.Rindex,
                      decode.scale, sign, offset, decode.Rd);

        if (LIKELY(address_valid(cpu.ea, size))) {
            md::uint32 value = skl::read(cpu.ea, sign_extend, size);
            dialog::trace("[ea: %xH, value: %xH]\n", cpu.ea, value);
            write_integer_register(cpu, decode.Rd, value);
            increment_pc(cpu, 2);
        } else {
            hardware_trap(cpu, CR2_OUT_OF_BOUNDS_READ);
        }
    }


    double
    read_real_little_endian(cpu_t &cpu, unsigned size)
    {
        union {
            md::uint32 i[2];
            float      f;
        } v;
        double d;

        v.i[0] = skl::read(cpu.ea, false, sizeof(md::uint32));
        if (size == sizeof(double)) {
            v.i[1] = skl::read(cpu.ea + sizeof(md::uint32),
                               false, sizeof(md::uint32));
            md::recompose_double(v.i[0], v.i[1], d);
        } else {
            d = v.f;
        }
        return d;
    }


    static void
    read_real(cpu_t                  &cpu,
              const reg_mem_decode_t &decode,
              md::uint32              offset,
              unsigned                size)
    {
        char            sign   = '+';
        O3::decode_pc_t decoded_pc;

        COMPILE_TIME_ASSERT(sizeof(float) == sizeof(md::uint32) &&
                            sizeof(double) == 2 * sizeof(float));

        if (offset < 0) {
            sign   = '-';
        }

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  (R%u + R%u:%u %c %xH), F%u ",
                      decoded_pc, decode.mne, decode.Rbase, decode.Rindex,
                      decode.scale, sign, offset, decode.Rd);

        if (LIKELY(address_valid(cpu.ea, size))) {
            double value = 0;
            COMPILE_TIME_ASSERT(skl_endian_little);
            value = read_real_little_endian(cpu, size);
            dialog::trace("[ea: %xH, value: %f]\n", cpu.ea, value);
            write_real_register(cpu, decode.Rd, value);
            increment_pc(cpu, 2);
        } else {
            hardware_trap(cpu, CR2_OUT_OF_BOUNDS_READ);
        }
    }


    static void
    load(cpu_t                  &cpu,
         const reg_mem_decode_t &decode,
         bool                    integer, // true = > integer load
         bool                    sign_extend,
         unsigned                size)
    {
        int offset = skl::read(cpu.pc + 4, false, sizeof(md::uint32));

        assert(!(!integer && sign_extend)); // real => !sign_extend

        compute_effective_address(cpu,
                                  read_integer_register(cpu, decode.Rbase),
                                  read_integer_register(cpu, decode.Rindex),
                                  decode.scale, offset);
        watchpoint(EA_LOAD, cpu.wp, cpu.ea);
        if (LIKELY(integer)) {
            read_integer(cpu, decode, sign_extend, offset, size);
        } else {
            read_real(cpu, decode, offset, size);
        }
    }

    static void
    op_lb(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        load(cpu, decode, true, true, sizeof(md::uint8));
    }


    static void
    op_lbu(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        load(cpu, decode, true, false, sizeof(md::uint8));
    }


    static void
    op_ld(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        load(cpu, decode, false, false, sizeof(double));
    }


    static void
    op_ldi(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        md::uint32      lo = skl::read(cpu.pc + 4, false, sizeof(md::uint32));
        md::uint32      hi = skl::read(cpu.pc + 8, false, sizeof(md::uint32));
        double          value;
        O3::decode_pc_t decoded_pc;

        md::recompose_double(lo, hi, value);

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  %f, F%u", decoded_pc, decode.mne, value,
                      decode.Rd);
        dialog::trace("\n");
        write_real_register(cpu, decode.Rd, value);
        increment_pc(cpu, 3);
    }


    static void
    op_lf(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        load(cpu, decode, false, false, sizeof(float));
    }


    static void
    op_lfi(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        double          value  = 0;
        O3::decode_pc_t decoded_pc;
        union {
            md::uint32 i;
            float      f;
        } v;
        COMPILE_TIME_ASSERT(sizeof(v.i) == sizeof(v.f));
        v.i   = skl::read(cpu.pc + 4, false, sizeof(md::uint32));
        value = v.f;

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  %f, F%u", decoded_pc, decode.mne, value,
                      decode.Rd);
        dialog::trace("\n");
        write_real_register(cpu, decode.Rd, value);
        increment_pc(cpu, 2);
    }


    static void
    op_lh(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        load(cpu, decode, true, true, sizeof(md::uint16));
    }


    static void
    op_lhu(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        load(cpu, decode, true, false, sizeof(md::uint16));
    }


    static void
    op_lw(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        load(cpu, decode, true, true, sizeof(md::uint32));
    }


    static void
    op_lwi(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        unsigned    cdata = skl::read(cpu.pc + 4, false, sizeof(md::uint32));
        md::uint32  value = read_integer_register(cpu, decode.Rbase) + cdata;
        O3::decode_pc_t decoded_pc;

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  R%u + %xH, R%u", decoded_pc, decode.mne,
                      decode.Rbase, cdata, decode.Rd);
        dialog::trace("[%xH]\n", value);
        write_integer_register(cpu, decode.Rd, value);
        increment_pc(cpu, 2);
    }


    static void
    store_integer(cpu_t &cpu, const reg_mem_decode_t &decode,
                  md::uint32 offset, unsigned size)
    {
        unsigned int    R0     = decode.Rd;
        char            sign   = '+';
        O3::decode_pc_t decoded_pc;
        md::uint32      value;

        if (offset < 0) {
            sign   = '-';
        }

        O3::decode_pc(cpu.pc, decoded_pc);

        dialog::trace("%s: %s  R%u, (R%u + R%u:%u %c %xH)",
                      decoded_pc, decode.mne, R0, decode.Rbase, decode.Rindex,
                      decode.scale, sign, offset);

        value = read_integer_register(cpu, R0);
        dialog::trace("[value: %xH, ea: %xH]\n", value, cpu.ea);

        if (LIKELY(address_valid(cpu.ea, size))) {
            write(cpu.ea, value, size);
            increment_pc(cpu, 2);
        } else {
            hardware_trap(cpu, CR2_OUT_OF_BOUNDS_WRITE);
        }
    }


    static void
    store_real(cpu_t                  &cpu,
               const reg_mem_decode_t &decode,
               md::uint32              offset,
               unsigned                size)
    {
        unsigned int    R0     = decode.Rd;
        char            sign   = '+';
        O3::decode_pc_t decoded_pc;
        double          value;

        if (offset < 0) {
            sign   = '-';
        }

        O3::decode_pc(cpu.pc, decoded_pc);

        dialog::trace("%s: %s  F%u, (R%u + R%u:%u %c %xH)",
                      decoded_pc, decode.mne, R0, decode.Rbase, decode.Rindex,
                      decode.scale, sign, offset);

        value = read_real_register(cpu, R0);
        dialog::trace("[value: %f, ea: %xH]\n", value, cpu.ea);

        if (LIKELY(address_valid(cpu.ea, size))) {
            md::uint32 lo;
            md::uint32 hi;

            COMPILE_TIME_ASSERT(sizeof(float) == sizeof(md::uint32) &&
                                sizeof(double) == 2 * sizeof(float));

            if (size == sizeof(double)) {
                md::decompose_double(value, lo, hi);
                COMPILE_TIME_ASSERT(skl_endian_little);
                write(cpu.ea, lo, sizeof(md::uint32));
                write(cpu.ea + sizeof(md::uint32), hi, sizeof(md::uint32));
            } else {
                union {
                    md::uint32 i;
                    float f;
                } v;
                v.f = value;
                write(cpu.ea, v.i, sizeof(md::uint32));
            }

            increment_pc(cpu, 2);
        } else {
            hardware_trap(cpu, CR2_OUT_OF_BOUNDS_WRITE);
        }
    }


    static void
    store(cpu_t &cpu, const reg_mem_decode_t &decode, bool integer, unsigned size)
    {
        int             offset = skl::read(cpu.pc + 4, false, sizeof(md::uint32));

        compute_effective_address(cpu,
                                  read_integer_register(cpu, decode.Rbase),
                                  read_integer_register(cpu, decode.Rindex),
                                  decode.scale, offset);
        watchpoint(EA_STORE, cpu.wp, cpu.ea);

        if (offset < 0) {
            offset = -offset;
        }

        if (LIKELY(integer)) {
            store_integer(cpu, decode, offset, size);
        } else {
            store_real(cpu, decode, offset, size);
        }
    }


    static void
    op_sb(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        store(cpu, decode, true, sizeof(md::uint8));
    }


    static void
    op_sd(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        store(cpu, decode, false, sizeof(double));
    }


    static void
    op_sf(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        store(cpu, decode, false, sizeof(float));
    }


    static void
    op_sh(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        store(cpu, decode, true, sizeof(md::uint16));
    }


    static void
    op_sw(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        store(cpu, decode, true, sizeof(md::uint32));
    }


    static void
    op_la(cpu_t &cpu, const reg_mem_decode_t &decode)
    {
        int          offset = skl::read(cpu.pc + 4, false, sizeof(md::uint32));
        char         sign   = '+';
        O3::decode_pc_t decoded_pc;

        compute_effective_address(cpu,
                                  read_integer_register(cpu, decode.Rbase),
                                  read_integer_register(cpu, decode.Rindex),
                                  decode.scale, offset);
        watchpoint(EA_COMPUTE, cpu.wp, cpu.ea);
        write_integer_register(cpu, decode.Rd, cpu.ea);
        if (offset < 0) {
            sign   = '-';
            offset = -offset;
        }

        O3::decode_pc(cpu.pc, decoded_pc);
        dialog::trace("%s: %s  (R%u + R%u:%u %c %xH), R%u",
                      decoded_pc, decode.mne, decode.Rbase, decode.Rindex,
                      decode.scale, sign, offset, decode.Rd);
        dialog::trace("[ea: %xH]\n", cpu.ea);
        increment_pc(cpu, 2);
    }


    void
    op_reg_mem(cpu_t &cpu, md::uint32 inst)
    {
        typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_reg_mem_opc.h"
#undef OPC
            N_OPCODES
        } opc_t;
        static const char *mne[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_reg_mem_opc.h"
#undef OPC
        };
        opc_t opc = static_cast<opc_t>(field(inst, 4, 0));
        reg_mem_decode_t decode;

        decode.mne    = mne[opc];
        decode.Rd     = field(inst, 25, 21);
        decode.Rbase  = field(inst, 20, 16);
        decode.Rindex = field(inst, 15, 11);
        decode.scale  = 1 << field(inst, 7, 6); // { 1, 2, 4, 8 }.

        switch (opc) {
        case OPC_LB:
            op_lb(cpu, decode);
            break;

        case OPC_LBU:
            op_lbu(cpu, decode);
            break;

        case OPC_LD:
            op_ld(cpu, decode);
            break;

        case OPC_LDI:
            op_ldi(cpu, decode);
            break;

        case OPC_LF:
            op_lf(cpu, decode);
            break;

        case OPC_LFI:
            op_lfi(cpu, decode);
            break;

        case OPC_LH:
            op_lh(cpu, decode);
            break;

        case OPC_LHU:
            op_lhu(cpu, decode);
            break;

        case OPC_LW:
            op_lw(cpu, decode);
            break;

        case OPC_LWI:
            op_lwi(cpu, decode);
            break;

        case OPC_SB:
            op_sb(cpu, decode);
            break;

        case OPC_SD:
            op_sd(cpu, decode);
            break;

        case OPC_SF:
            op_sf(cpu, decode);
            break;

        case OPC_SH:
            op_sh(cpu, decode);
            break;

        case OPC_SW:
            op_sw(cpu, decode);
            break;

        case OPC_LA:
            op_la(cpu, decode);
            break;

        default:
            dialog::not_implemented("%s: inst: %xH %s",
                                    __func__, inst, mne[opc]);
        }
    }
}
