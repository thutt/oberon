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


    md::OADDR
    compute_effective_address(md::uint32 base,
                              md::uint32 index,
                              int        scale,
                              int        offset)
    {
        return (base +
                (index << static_cast<md::uint32>(scale)) +
                static_cast<md::uint32>(offset));
    }


    static NOINLINE float
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


    static NOINLINE double
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

    static NOINLINE void
    write_little_endian_float(skl::cpuid_t cpu, md::OADDR addr, float value)
    {
        float_int_pun_little_endian_t v;
        md::HADDR p = heap::heap_to_host(addr);

        COMPILE_TIME_ASSERT(skl_endian_little);
        COMPILE_TIME_ASSERT(sizeof(v.i) == sizeof(v.f));

        if (LIKELY(address_valid(addr, sizeof(value)))) {
            v.f = value;
            skl::write_4(p, v.i);
        } else {
            hardware_trap(cpu, CR2_OUT_OF_BOUNDS_WRITE);
        }
    }


    static NOINLINE void
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
            skl::write_4(p, lo);
            skl::write_4(p + hi_offs, hi);
        } else {
            hardware_trap(cpu, CR2_OUT_OF_BOUNDS_WRITE);
        }
    }


    struct skl_reg_mem_t : skl::instruction_t {
        int Rd;
        int Rbase;
        int Rindex;
        int scale;

        skl_reg_mem_t(skl::cpuid_t cpuid_,
                      md::OADDR    pc_,
                      md::OINST    inst_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst, 25, 21)),
            Rbase(field(inst, 20, 16)),
            Rindex(field(inst, 15, 11)),
            scale(field(inst, 7, 6)) // { 0, 1, 2, 3 }, scale: { 1, 2, 4, 8}.
        {
        }
    };


    struct skl_lwi_t : skl_reg_mem_t {
        md::uint32 cdata;

        skl_lwi_t(skl::cpuid_t cpuid_,
                  md::OADDR    pc_,
                  md::OINST    inst_) :
            skl_reg_mem_t(cpuid_, pc_, inst_),
            cdata(skl::read(cpuid_, pc + 4, false, sizeof(md::uint32)))
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 value;
            value = read_integer_register(cpu, Rbase) + cdata;
            write_integer_register(cpu, Rd, value);
            dialog::trace("%s: %s  R%u + %xH, R%u", decoded_pc, mne,
                          Rbase, cdata, Rd);
            dialog::trace("[%xH]\n", value);
            increment_pc(cpu, 2);
        }
    };


    struct skl_lfi_t : skl_reg_mem_t {
        double value;

        skl_lfi_t(skl::cpuid_t cpuid_,
                  md::OADDR    pc_,
                  md::OINST    inst_) :
            skl_reg_mem_t(cpuid_, pc_, inst_)
        {
            value = read_little_endian_float(cpuid_, pc + 4);
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            dialog::trace("%s: %s  %f, F%u\n", decoded_pc, mne, value, Rd);
            write_real_register(cpu, Rd, value);
            increment_pc(cpu, 2);
        }
    };


    struct skl_ldi_t : skl_reg_mem_t {
        double value;

        skl_ldi_t(skl::cpuid_t cpuid_,
                  md::OADDR    pc_,
                  md::OINST    inst_) :
            skl_reg_mem_t(cpuid_, pc_, inst_)
        {
            value = read_little_endian_double(cpuid_, pc + 4);
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            dialog::trace("%s: %s  %f, F%u\n", decoded_pc, mne, value, Rd);
            write_real_register(cpu, Rd, value);
            increment_pc(cpu, 3);
        }
    };


    struct skl_load_store_t : skl_reg_mem_t {
        int offset;

        skl_load_store_t(skl::cpuid_t cpuid_,
                         md::OADDR    pc_,
                         md::OINST    inst_) :
            skl_reg_mem_t(cpuid_, pc_, inst_),
            offset(static_cast<int>(skl::read(cpuid_, pc + 4, false,
                                              static_cast<int>(sizeof(md::uint32)))))
        {
        }
    };


    template<typename T, bool sign_extend>
    struct skl_load_int_t : skl_load_store_t {
        skl_load_int_t(skl::cpuid_t cpuid_,
                       md::OADDR    pc_,
                       md::OINST    inst_) :
            skl_load_store_t(cpuid_, pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            char       sign  = '+';
            int        offs  = offset;
            md::uint32 base  = read_integer_register(cpu, Rbase);
            md::uint32 index = read_integer_register(cpu, Rindex);
            md::OADDR  ea    = compute_effective_address(base, index,
                                                         scale, offset);

            if (offset < 0) {
                sign   = '-';
                offs   = -offset;
            }

            dialog::trace("%s: %s  (R%u + R%u:%u %c %xH), R%u",
                          decoded_pc, mne, Rbase, Rindex,
                          scale, sign, offs, Rd);

            if (address_valid(ea, sizeof(T))) {
                md::uint32 value;
                md::HADDR  p = heap::heap_to_host(ea);

                switch (sizeof(T)) {
                case 1:
                    if (sign_extend) {
                        value = skl::read_1_se(p);
                    } else {
                        value = skl::read_1_ze(p);
                    }
                    break;

                case 2:
                    if (sign_extend) {
                        value = skl::read_2_se(p);
                    } else {
                        value = skl::read_2_ze(p);
                    }
                    break;

                case 4:
                    value = skl::read_4_ze(p);
                    break;
                }
                dialog::trace("[ea: %xH, value: %xH]\n", ea, value);
                write_integer_register(cpu, Rd, value);
                increment_pc(cpu, 2);
            } else {
                hardware_trap(cpu, CR2_OUT_OF_BOUNDS_READ);
            }
        }
    };


    template<typename T>
    struct skl_store_int_t : skl_load_store_t {
        skl_store_int_t(skl::cpuid_t cpuid_,
                        md::OADDR    pc_,
                        md::OINST    inst_) :
            skl_load_store_t(cpuid_, pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpu)
        {
            char       sign  = '+';
            int        offs  = offset;
            md::uint32 value = read_integer_register(cpu, Rd);
            md::uint32 base  = read_integer_register(cpu, Rbase);
            md::uint32 index = read_integer_register(cpu, Rindex);
            md::OADDR  ea    = compute_effective_address(base, index,
                                                         scale, offset);

            if (offs < 0) {
                offs = -offs;
                sign   = '-';
            }

            dialog::trace("%s: %s  R%u, (R%u + R%u:%u %c %xH)",
                          decoded_pc, mne, Rd, Rbase, Rindex,
                          scale, sign, offs);
            dialog::trace("[value: %xH, ea: %xH]\n", value, ea);

            if (address_valid(ea, sizeof(T))) {
                md::HADDR p = heap::heap_to_host(ea);

                switch (sizeof(T)) {
                case 1: {
                    md::uint8 v = static_cast<md::uint8>(value);
                    skl::write_1(p, v);
                    break;
                }

                case 2: {
                    md::uint16 v = static_cast<md::uint16>(value);
                    skl::write_2(p, v);
                    break;
                }

                case 4: {
                    skl::write_4(p, value);
                    break;
                }
                }

                increment_pc(cpu, 2);
            } else {
                hardware_trap(cpu, CR2_OUT_OF_BOUNDS_WRITE);
            }
        }
    };


    template<typename T>
    struct skl_load_real_t : skl_load_store_t {
        skl_load_real_t(skl::cpuid_t cpuid_,
                        md::OADDR    pc_,
                        md::OINST    inst_) :
            skl_load_store_t(cpuid_, pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            char       sign  = '+';
            int        offs  = offset;
            double     value = 0;
            md::uint32 base  = read_integer_register(cpu, Rbase);
            md::uint32 index = read_integer_register(cpu, Rindex);
            md::OADDR  ea    = compute_effective_address(base, index,
                                                         scale, offset);

            if (offset < 0) {
                sign   = '-';
                offs = -offs;
            }

            dialog::trace("%s: %s  (R%u + R%u:%u %c %xH), F%u ",
                          decoded_pc, mne, Rbase, Rindex,
                          scale, sign, offset, Rd);

            if (sizeof(T) == sizeof(double)) {
                value = read_little_endian_double(cpu, ea);
            } else {
                value =read_little_endian_float(cpu, ea);
            }

            dialog::trace("[ea: %xH, value: %f]\n", ea, value);
            if (LIKELY(!skl::exception_raised(cpu))) {
                write_real_register(cpu, Rd, value);
                increment_pc(cpu, 2);
            }
        }
    };


    template<typename T>
    struct skl_store_real_t : skl_load_store_t {
        skl_store_real_t(skl::cpuid_t cpuid_,
                         md::OADDR    pc_,
                         md::OINST    inst_) :
            skl_load_store_t(cpuid_, pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            O3::decode_pc_t decoded_pc;
            double          value;
            int             R0    = Rd;
            char            sign  = '+';
            int             offs  = offset;
            md::uint32      base  = read_integer_register(cpu, Rbase);
            md::uint32      index = read_integer_register(cpu, Rindex);
            md::OADDR       ea    = compute_effective_address(base, index,
                                                              scale, offset);

            if (offs < 0) {
                sign   = '-';
                offs = -offs;
            }
            dialog::trace("%s: %s  F%u, (R%u + R%u:%u %c %xH)",
                          decoded_pc, mne, R0, Rbase, Rindex,
                          scale, sign, offset);

            value = read_real_register(cpu, R0);
            dialog::trace("[value: %f, ea: %xH]\n", value, ea);

            if (sizeof(T) == sizeof(double)) {
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


    template<typename T>
    struct skl_la_t : skl_load_store_t {
        skl_la_t(skl::cpuid_t cpuid_,
                 md::OADDR    pc_,
                 md::OINST    inst_) :
            skl_load_store_t(cpuid_, pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            char       sign    = '+';
            int        loffset = offset;
            md::uint32 base    = read_integer_register(cpu, Rbase);
            md::uint32 index   = read_integer_register(cpu, Rindex);
            md::OADDR  ea      = compute_effective_address(base, index,
                                                           scale, offset);

            write_integer_register(cpu, Rd, ea);
            if (loffset < 0) {
                sign   = '-';
                loffset = -loffset;
            }

            dialog::trace("%s: %s  (R%u + R%u:%u %c %xH), R%u",
                          decoded_pc, mne, Rbase,
                          Rindex, scale, sign, loffset,
                          Rd);
            dialog::trace("[ea: %xH]\n", ea);
            increment_pc(cpu, 2);
        }
    };


    skl::instruction_t *
    op_reg_mem(skl::cpuid_t cpu, md::OADDR pc, md::OINST inst)
    {
        opc_t opc = static_cast<opc_t>(field(inst, 4, 0));

        switch (opc) {
        case OPC_LB:
            return new skl_load_int_t<md::int8, true>(cpu, pc, inst);

        case OPC_LBU:
            return new skl_load_int_t<md::int8, false>(cpu, pc, inst);

        case OPC_LD:
            return new skl_load_real_t<double>(cpu, pc, inst);

        case OPC_LDI:
            return new skl_ldi_t(cpu, pc, inst);

        case OPC_LF:
            return new skl_load_real_t<float>(cpu, pc, inst);

        case OPC_LFI:
            return new skl_lfi_t(cpu, pc, inst);

        case OPC_LH:
            return new skl_load_int_t<md::int16, true>(cpu, pc, inst);

        case OPC_LHU:
            return new skl_load_int_t<md::uint16, false>(cpu, pc, inst);

        case OPC_LW:
            return new skl_load_int_t<md::int32, true>(cpu, pc, inst);

        case OPC_LWI:
            return new skl_lwi_t(cpu, pc, inst);

        case OPC_SB:
            return new skl_store_int_t<md::int8>(cpu, pc, inst);

        case OPC_SD:
            return new skl_store_real_t<double>(cpu, pc, inst);

        case OPC_SF:
            return new skl_store_real_t<float>(cpu, pc, inst);

        case OPC_SH:
            return new skl_store_int_t<md::int16>(cpu, pc, inst);

        case OPC_SW:
            return new skl_store_int_t<md::int32>(cpu, pc, inst);

        case OPC_LA:
            return new skl_la_t<md::uint32>(cpu, pc, inst);

        default:
            dialog::not_implemented("%s: inst: %xH opcode: %xH",
                                    __func__, inst, opc);
        }
    }
}
