/* Copyright (c) 2021, 2022 Logic Magicians Software */

#include "config.h"
#include "dialog.h"
#include "heap.h"
#include "o3.h"
#include "skl_reg_mem.h"

namespace skl {
    typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_reg_mem_opc.h"
#undef OPC
        N_OPCODES
    } opc_t;

    static const char *mnemonics[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_reg_mem_opc.h"
#undef OPC
    };

    typedef union float_int_pun_little_endian_t {
        md::uint32 i;
        float      f;
    } float_int_pun_little_endian_t;


    static float
    read_little_endian_float(skl::cpuid_t cpu, md::OADDR addr)
    {
        float_int_pun_little_endian_t v;
        md::HADDR p = heap::heap_to_host(addr);

        COMPILE_TIME_ASSERT(skl_endian_little);
        COMPILE_TIME_ASSERT(sizeof(v.i) == sizeof(v.f));

        if (LIKELY(address_valid(addr, sizeof(v.f)))) {
            v.i = skl::read_4_ze(p);
            return v.f;
        } else {
            hardware_trap(cpu, CR2_OUT_OF_BOUNDS_READ);
            return 0; // Value ignored, because CPU does not return.
        }
    }


    static double
    read_little_endian_double(skl::cpuid_t cpu, md::OADDR addr)
    {
        double    value;
        md::HADDR p = heap::heap_to_host(addr);

        COMPILE_TIME_ASSERT(skl_endian_little);
        COMPILE_TIME_ASSERT(sizeof(value) == 2 * sizeof(md::uint32));

        if (LIKELY(address_valid(addr, sizeof(value)))) {
            md::OADDR  hi_offs = static_cast<md::OADDR>(sizeof(md::uint32));
            md::uint32 lo      = skl::read_4_ze(p);
            md::uint32 hi      = skl::read_4_ze(p + hi_offs);

            md::recompose_double(lo, hi, value);
            return value;
        } else {
            hardware_trap(cpu, CR2_OUT_OF_BOUNDS_READ);
            return 0; // Value ignored, because CPU does not return.
        }
    }


    static void
    write_little_endian_float(skl::cpuid_t cpu, md::OADDR addr, float value)
    {
        float_int_pun_little_endian_t v;
        md::HADDR p = heap::heap_to_host(addr);

        COMPILE_TIME_ASSERT(skl_endian_little);
        COMPILE_TIME_ASSERT(sizeof(v.i) == sizeof(v.f));

        if (LIKELY(address_valid(addr, sizeof(value)))) {
            v.f = value;
            skl::write_4(cpu, p, v.i);
        } else {
            hardware_trap(cpu, CR2_OUT_OF_BOUNDS_WRITE);
        }
    }


    static void
    write_little_endian_double(skl::cpuid_t cpu, md::OADDR addr, double value)
    {
        md::HADDR p = heap::heap_to_host(addr);

        COMPILE_TIME_ASSERT(skl_endian_little);
        COMPILE_TIME_ASSERT(sizeof(value) == 2 * sizeof(md::uint32));

        if (LIKELY(address_valid(addr, sizeof(value)))) {
            md::uint32 lo;
            md::uint32 hi;
            md::OADDR  hi_offs = static_cast<md::OADDR>(sizeof(md::uint32));

            md::decompose_double(value, lo, hi);
            skl::write_4(cpu, p, lo);
            skl::write_4(cpu, p + hi_offs, hi);
        } else {
            hardware_trap(cpu, CR2_OUT_OF_BOUNDS_WRITE);
        }
    }


    typedef struct reg_mem_decode_t {
        int         Rd;
        int         Rbase;
        int         Rindex;
        int         scale;      // { 0, 1, 2, 3 } (scale of 1, 2, 4, 8)
    } reg_mem_decode_t;


    struct skl_reg_mem_t : skl::instruction_t {
        const reg_mem_decode_t  decode;

        skl_reg_mem_t(skl::cpuid_t cpuid_,
                      md::OADDR    pc_,
                      md::OINST    inst_,
                      const reg_mem_decode_t &decode_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            decode(decode_)
        {
        }
    };


    struct skl_lwi_t : skl_reg_mem_t {
        md::uint32 cdata;

        skl_lwi_t(skl::cpuid_t cpuid_,
                  md::OADDR    pc_,
                  md::OINST    inst_,
                  const reg_mem_decode_t &decode_) :
            skl_reg_mem_t(cpuid_, pc_, inst_, decode_),
            cdata(skl::read(cpuid_, pc + 4, false, sizeof(md::uint32)))
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 value;
            value = read_integer_register(cpu, decode.Rbase) + cdata;
            write_integer_register(cpu, decode.Rd, value);
            dialog::trace("%s: %s  R%u + %xH, R%u", decoded_pc, mne,
                          decode.Rbase, cdata, decode.Rd);
            dialog::trace("[%xH]\n", value);
            increment_pc(cpu, 2);
        }
    };


    struct skl_lfi_t : skl_reg_mem_t {
        double value;

        skl_lfi_t(skl::cpuid_t cpuid_,
                  md::OADDR    pc_,
                  md::OINST    inst_,
                  const reg_mem_decode_t &decode_) :
            skl_reg_mem_t(cpuid_, pc_, inst_, decode_)
        {
            value = read_little_endian_float(cpuid_, pc + 4);
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            dialog::trace("%s: %s  %f, F%u", decoded_pc, mne, value,
                          decode.Rd);
            dialog::trace("\n");
            write_real_register(cpu, decode.Rd, value);
            increment_pc(cpu, 2);
        }
    };


    struct skl_ldi_t : skl_reg_mem_t {
        double value;

        skl_ldi_t(skl::cpuid_t cpuid_,
                  md::OADDR    pc_,
                  md::OINST    inst_,
                  const reg_mem_decode_t &decode_) :
            skl_reg_mem_t(cpuid_, pc_, inst_, decode_)
        {
            value = read_little_endian_double(cpuid_, pc + 4);
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            dialog::trace("%s: %s  %f, F%u", decoded_pc, mne, value,
                          decode.Rd);
            dialog::trace("\n");
            write_real_register(cpu, decode.Rd, value);
            increment_pc(cpu, 3);
        }
    };


    struct skl_load_store_t : skl_reg_mem_t {
        int offset;

        skl_load_store_t(skl::cpuid_t cpuid_,
                         md::OADDR    pc_,
                         md::OINST    inst_,
                         const reg_mem_decode_t &decode_) :
            skl_reg_mem_t(cpuid_, pc_, inst_, decode_),
            offset(static_cast<int>(skl::read(cpuid_, pc + 4, false,
                                              static_cast<int>(sizeof(md::uint32)))))
        {
        }
    };


    struct skl_load_int_t : skl_load_store_t {
        skl_load_int_t(skl::cpuid_t cpuid_,
                       md::OADDR    pc_,
                       md::OINST    inst_,
                       const reg_mem_decode_t &decode_) :
            skl_load_store_t(cpuid_, pc_, inst_, decode_)
        {
        }


        void load(skl::cpuid_t cpu, bool sign_extend, int size)
        {
            md::uint32 value;
            char       sign = '+';
            int        offs = offset;
            md::OADDR  ea   = skl::compute_effective_address(cpu, decode.Rbase,
                                                             decode.Rindex,
                                                             decode.scale,
                                                             offset);

            if (offset < 0) {
                sign   = '-';
                offs   = -offset;
            }

            dialog::trace("%s: %s  (R%u + R%u:%u %c %xH), R%u",
                          decoded_pc, mne, decode.Rbase, decode.Rindex,
                          decode.scale, sign, offs, decode.Rd);


            value = skl::read(cpu, ea, sign_extend, size);
            if (LIKELY(!skl::exception_raised(cpu))) {
                dialog::trace("[ea: %xH, value: %xH]\n", ea, value);
                write_integer_register(cpu, decode.Rd, value);
                increment_pc(cpu, 2);
            }
        }
    };


    struct skl_store_int_t : skl_load_store_t {
        skl_store_int_t(skl::cpuid_t cpuid_,
                        md::OADDR    pc_,
                        md::OINST    inst_,
                        const reg_mem_decode_t &decode_) :
            skl_load_store_t(cpuid_, pc_, inst_, decode_)
        {
        }


        void
        store(skl::cpuid_t cpu, bool integer, int size)
        {
            char       sign = '+';
            int        offs = offset;
            md::OADDR  ea   = skl::compute_effective_address(cpu, decode.Rbase,
                                                             decode.Rindex,
                                                             decode.scale,
                                                             offset);
            md::uint32 value = read_integer_register(cpu, decode.Rd);

            if (offs < 0) {
                offs = -offs;
                sign   = '-';
            }

            dialog::trace("%s: %s  R%u, (R%u + R%u:%u %c %xH)",
                          decoded_pc, mne, decode.Rd, decode.Rbase, decode.Rindex,
                          decode.scale, sign, offs);
            dialog::trace("[value: %xH, ea: %xH]\n", value, ea);

            skl::write(cpu, ea, value, size);
            if (LIKELY(!skl::exception_raised(cpu))) {
                increment_pc(cpu, 2);
            }
        }
    };


    struct skl_load_real_t : skl_load_store_t {
        skl_load_real_t(skl::cpuid_t cpuid_,
                        md::OADDR    pc_,
                        md::OINST    inst_,
                        const reg_mem_decode_t &decode_) :
            skl_load_store_t(cpuid_, pc_, inst_, decode_)
        {
        }


        void
        load(skl::cpuid_t cpu, int size)
        {
            char      sign  = '+';
            int       offs  = offset;
            double    value = 0;
            md::OADDR ea    = skl::compute_effective_address(cpu, decode.Rbase,
                                                             decode.Rindex,
                                                             decode.scale,
                                                             offset);

            COMPILE_TIME_ASSERT(sizeof(float) == sizeof(md::uint32) &&
                                sizeof(double) == 2 * sizeof(float));

            if (offset < 0) {
                sign   = '-';
                offs = -offs;
            }

            dialog::trace("%s: %s  (R%u + R%u:%u %c %xH), F%u ",
                          decoded_pc, mne, decode.Rbase, decode.Rindex,
                          decode.scale, sign, offset, decode.Rd);

            COMPILE_TIME_ASSERT(skl_endian_little);
            if (size == sizeof(double)) {
                value = skl::read_little_endian_double(cpu, ea);
            } else {
                value =read_little_endian_float(cpu, ea);
            }
            dialog::trace("[ea: %xH, value: %f]\n", ea, value);
            if (LIKELY(!skl::exception_raised(cpu))) {
                write_real_register(cpu, decode.Rd, value);
                increment_pc(cpu, 2);
            }
        }
    };


    struct skl_store_real_t : skl_load_store_t {
        skl_store_real_t(skl::cpuid_t cpuid_,
                         md::OADDR    pc_,
                         md::OINST    inst_,
                         const reg_mem_decode_t &decode_) :
            skl_load_store_t(cpuid_, pc_, inst_, decode_)
        {
        }


        void
        store(skl::cpuid_t cpu, int size)
        {
            O3::decode_pc_t decoded_pc;
            double          value;
            int             R0   = decode.Rd;
            char            sign = '+';
            int             offs = offset;
            md::OADDR       ea   = skl::compute_effective_address(cpu, decode.Rbase,
                                                                  decode.Rindex,
                                                                  decode.scale,
                                                                  offset);

            COMPILE_TIME_ASSERT(sizeof(float) == sizeof(md::uint32) &&
                                sizeof(double) == 2 * sizeof(float));

            if (offs < 0) {
                sign   = '-';
                offs = -offs;
            }
            dialog::trace("%s: %s  F%u, (R%u + R%u:%u %c %xH)",
                          decoded_pc, mne, R0, decode.Rbase, decode.Rindex,
                          decode.scale, sign, offset);

            value = read_real_register(cpu, R0);
            dialog::trace("[value: %f, ea: %xH]\n", value, ea);

            if (size == sizeof(double)) {
                skl::write_little_endian_double(cpu, ea, value);
            } else {
                float flt = static_cast<float>(value);
                skl::write_little_endian_float(cpu, ea, flt);
            }
            if (LIKELY(!skl::exception_raised(cpu))) {
                increment_pc(cpu, 2);
            }
        }
    };


    struct skl_lb_t : skl_load_int_t {
        skl_lb_t(skl::cpuid_t cpuid_,
                 md::OADDR    pc_,
                 md::OINST    inst_,
                 const reg_mem_decode_t &decode_) :
            skl_load_int_t(cpuid_, pc_, inst_, decode_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            load(cpu, true, sizeof(md::uint8));
        }
    };


    struct skl_lbu_t : skl_load_int_t {
        skl_lbu_t(skl::cpuid_t cpuid_,
                  md::OADDR    pc_,
                  md::OINST    inst_,
                  const reg_mem_decode_t &decode_) :
            skl_load_int_t(cpuid_, pc_, inst_, decode_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            load(cpu, false, sizeof(md::uint8));
        }
    };


    struct skl_lh_t : skl_load_int_t {
        skl_lh_t(skl::cpuid_t cpuid_,
                 md::OADDR    pc_,
                 md::OINST    inst_,
                 const reg_mem_decode_t &decode_) :
            skl_load_int_t(cpuid_, pc_, inst_, decode_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            load(cpu, true, sizeof(md::uint16));
        }
    };


    struct skl_lhu_t : skl_load_int_t {
        skl_lhu_t(skl::cpuid_t cpuid_,
                  md::OADDR    pc_,
                  md::OINST    inst_,
                  const reg_mem_decode_t &decode_) :
            skl_load_int_t(cpuid_, pc_, inst_, decode_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            load(cpu, false, sizeof(md::uint16));
        }
    };


    struct skl_lw_t : skl_load_int_t {
        skl_lw_t(skl::cpuid_t cpuid_,
                 md::OADDR    pc_,
                 md::OINST    inst_,
                 const reg_mem_decode_t &decode_) :
            skl_load_int_t(cpuid_, pc_, inst_, decode_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            load(cpu, true, sizeof(md::uint32));
        }
    };


    struct skl_lf_t : skl_load_real_t {
        skl_lf_t(skl::cpuid_t cpuid_,
                 md::OADDR    pc_,
                 md::OINST    inst_,
                 const reg_mem_decode_t &decode_) :
            skl_load_real_t(cpuid_, pc_, inst_, decode_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            load(cpu, sizeof(float));
        }
    };


    struct skl_ld_t : skl_load_real_t {
        skl_ld_t(skl::cpuid_t cpuid_,
                 md::OADDR    pc_,
                 md::OINST    inst_,
                 const reg_mem_decode_t &decode_) :
            skl_load_real_t(cpuid_, pc_, inst_, decode_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            load(cpu, sizeof(double));
        }
    };


    struct skl_sb_t : skl_store_int_t {
        skl_sb_t(skl::cpuid_t cpuid_,
                 md::OADDR    pc_,
                 md::OINST    inst_,
                 const reg_mem_decode_t &decode_) :
            skl_store_int_t(cpuid_, pc_, inst_, decode_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            store(cpu, true, sizeof(md::uint8));
        }
    };


    struct skl_sd_t : skl_store_real_t {
        skl_sd_t(skl::cpuid_t cpuid_,
                 md::OADDR    pc_,
                 md::OINST    inst_,
                 const reg_mem_decode_t &decode_) :
            skl_store_real_t(cpuid_, pc_, inst_, decode_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            store(cpu, sizeof(double));
        }
    };


    struct skl_sf_t : skl_store_real_t {
        skl_sf_t(skl::cpuid_t cpuid_,
                 md::OADDR    pc_,
                 md::OINST    inst_,
                 const reg_mem_decode_t &decode_) :
            skl_store_real_t(cpuid_, pc_, inst_, decode_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            store(cpu, sizeof(float));
        }
    };


    struct skl_sh_t : skl_store_int_t {
        skl_sh_t(skl::cpuid_t cpuid_,
                 md::OADDR    pc_,
                 md::OINST    inst_,
                 const reg_mem_decode_t &decode_) :
            skl_store_int_t(cpuid_, pc_, inst_, decode_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            store(cpu, true, sizeof(md::uint16));
        }
    };


    struct skl_sw_t : skl_store_int_t {
        skl_sw_t(skl::cpuid_t cpuid_,
                 md::OADDR    pc_,
                 md::OINST    inst_,
                 const reg_mem_decode_t &decode_) :
            skl_store_int_t(cpuid_, pc_, inst_, decode_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            store(cpu, true, sizeof(md::uint32));
        }
    };


    struct skl_la_t : skl_load_int_t {
        skl_la_t(skl::cpuid_t cpuid_,
                 md::OADDR    pc_,
                 md::OINST    inst_,
                 const reg_mem_decode_t &decode_) :
            skl_load_int_t(cpuid_, pc_, inst_, decode_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            char       sign    = '+';
            int        loffset = offset;
            md::OADDR  ea      = skl::compute_effective_address(cpu,
                                                                decode.Rbase,
                                                                decode.Rindex,
                                                                decode.scale,
                                                                offset);
            write_integer_register(cpu, decode.Rd, ea);
            if (loffset < 0) {
                sign   = '-';
                loffset = -loffset;
            }

            dialog::trace("%s: %s  (R%u + R%u:%u %c %xH), R%u",
                          decoded_pc, mne, decode.Rbase, decode.Rindex,
                          decode.scale, sign, loffset, decode.Rd);
            dialog::trace("[ea: %xH]\n", ea);
            increment_pc(cpu, 2);
        }
    };


    skl::instruction_t *
    op_reg_mem(skl::cpuid_t cpu, md::OADDR pc, md::OINST inst)
    {
        opc_t opc = static_cast<opc_t>(field(inst, 4, 0));
        reg_mem_decode_t decode;

        decode.Rd     = field(inst, 25, 21);
        decode.Rbase  = field(inst, 20, 16);
        decode.Rindex = field(inst, 15, 11);
        decode.scale  = field(inst, 7, 6); // { 0, 1, 2, 3 }.

        switch (opc) {
        case OPC_LB:  return new skl_lb_t(cpu, pc, inst, decode);
        case OPC_LBU: return new skl_lbu_t(cpu, pc, inst, decode);
        case OPC_LD:  return new skl_ld_t(cpu, pc, inst, decode);
        case OPC_LDI: return new skl_ldi_t(cpu, pc, inst, decode);
        case OPC_LF:  return new skl_lf_t(cpu, pc, inst, decode);
        case OPC_LFI: return new skl_lfi_t(cpu, pc, inst, decode);
        case OPC_LH:  return new skl_lh_t(cpu, pc, inst, decode);
        case OPC_LHU: return new skl_lhu_t(cpu, pc, inst, decode);
        case OPC_LW:  return new skl_lw_t(cpu, pc, inst, decode);
        case OPC_LWI: return new skl_lwi_t(cpu, pc, inst, decode);
        case OPC_SB:  return new skl_sb_t(cpu, pc, inst, decode);
        case OPC_SD:  return new skl_sd_t(cpu, pc, inst, decode);
        case OPC_SF:  return new skl_sf_t(cpu, pc, inst, decode);
        case OPC_SH:  return new skl_sh_t(cpu, pc, inst, decode);
        case OPC_SW:  return new skl_sw_t(cpu, pc, inst, decode);
        case OPC_LA:  return new skl_la_t(cpu, pc, inst, decode);

        default:
            dialog::not_implemented("%s: inst: %xH opcode: %xH",
                                    __func__, inst, opc);
        }
    }
}
