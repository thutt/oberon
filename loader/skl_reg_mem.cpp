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

    static const char *mne[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_reg_mem_opc.h"
#undef OPC
    };


    typedef struct reg_mem_decode_t {
        int         Rd;
        int         Rbase;
        int         Rindex;
        int         scale;      // { 0, 1, 2, 3 } (scale of 1, 2, 4, 8)
    } reg_mem_decode_t;


    struct skl_reg_mem_t : skl::instruction_t {
        const reg_mem_decode_t  decode;

        skl_reg_mem_t(md::OADDR    pc_,
                      md::OINST    inst_,
                      const char **mne_,
                      const reg_mem_decode_t &decode_) :
            skl::instruction_t(pc_, inst_, mne_),
            decode(decode_)
        {
        }
    };


    struct skl_lwi_t : skl_reg_mem_t {
        md::uint32 cdata;
        md::uint32 value;


        skl_lwi_t(md::OADDR    pc_,
                  md::OINST    inst_,
                  const char **mne_,
                  const reg_mem_decode_t &decode_) :
            skl_reg_mem_t(pc_, inst_, mne_, decode_),
            cdata(skl::read(pc + 4, false, sizeof(md::uint32)))
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
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


        skl_lfi_t(md::OADDR    pc_,
                  md::OINST    inst_,
                  const char **mne_,
                  const reg_mem_decode_t &decode_) :
            skl_reg_mem_t(pc_, inst_, mne_, decode_)
        {
            union {
                md::uint32 i;
                float      f;
            } v;
            COMPILE_TIME_ASSERT(sizeof(v.i) == sizeof(v.f));
            v.i   = skl::read(pc + 4, false, sizeof(md::uint32));
            value = v.f;
        }


        virtual void interpret(skl::cpu_t *cpu)
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


        skl_ldi_t(md::OADDR    pc_,
                  md::OINST    inst_,
                  const char **mne_,
                  const reg_mem_decode_t &decode_) :
            skl_reg_mem_t(pc_, inst_, mne_, decode_)
        {
            md::uint32 lo = skl::read(pc + 4, false, sizeof(md::uint32));
            md::uint32 hi = skl::read(pc + 8, false, sizeof(md::uint32));
            md::recompose_double(lo, hi, value);
        }


        virtual void interpret(skl::cpu_t *cpu)
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

        skl_load_store_t(md::OADDR    pc_,
                         md::OINST    inst_,
                         const char **mne_,
                         const reg_mem_decode_t &decode_) :
            skl_reg_mem_t(pc_, inst_, mne_, decode_),
            offset(static_cast<int>(skl::read(pc + 4, false,
                                              static_cast<int>(sizeof(md::uint32)))))
        {
        }
    };


    struct skl_load_int_t : skl_load_store_t {
        skl_load_int_t(md::OADDR    pc_,
                       md::OINST    inst_,
                       const char **mne_,
                       const reg_mem_decode_t &decode_) :
            skl_load_store_t(pc_, inst_, mne_, decode_)
        {
        }


        void load(cpu_t *cpu, bool sign_extend, int size)
        {
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

            if (LIKELY(address_valid(ea, size))) {
                md::uint32 value = skl::read(ea, sign_extend, size);

                dialog::trace("[ea: %xH, value: %xH]\n", ea, value);
                write_integer_register(cpu, decode.Rd, value);
                increment_pc(cpu, 2);
            } else {
                hardware_trap(cpu, CR2_OUT_OF_BOUNDS_READ);
            }
        }
    };


    struct skl_store_int_t : skl_load_store_t {
        md::uint32 value;

        skl_store_int_t(md::OADDR    pc_,
                        md::OINST    inst_,
                        const char **mne_,
                        const reg_mem_decode_t &decode_) :
            skl_load_store_t(pc_, inst_, mne_, decode_)
        {
        }


        void
        store(cpu_t *cpu, bool integer, int size)
        {
            char       sign = '+';
            int        offs = offset;
            md::OADDR  ea   = skl::compute_effective_address(cpu, decode.Rbase,
                                                             decode.Rindex,
                                                             decode.scale,
                                                             offset);

            value = read_integer_register(cpu, decode.Rd);
            if (offs < 0) {
                offs = -offs;
                sign   = '-';
            }

            dialog::trace("%s: %s  R%u, (R%u + R%u:%u %c %xH)",
                          decoded_pc, mne, decode.Rd, decode.Rbase, decode.Rindex,
                          decode.scale, sign, offs);
            dialog::trace("[value: %xH, ea: %xH]\n", value, ea);

            if (LIKELY(address_valid(ea, size))) {
                skl::write(ea, value, size);
                increment_pc(cpu, 2);
            } else {
                hardware_trap(cpu, CR2_OUT_OF_BOUNDS_WRITE);
            }
        }
    };


    struct skl_load_real_t : skl_load_store_t {
        skl_load_real_t(md::OADDR    pc_,
                        md::OINST    inst_,
                        const char **mne_,
                        const reg_mem_decode_t &decode_) :
            skl_load_store_t(pc_, inst_, mne_, decode_)
        {
        }


        double read_real_little_endian(cpu_t *cpu, md::OADDR ea, int size)
        {
            union {
                md::uint32 i[2];
                float      f;
            } v;
            double d;

            v.i[0] = skl::read(ea, false, sizeof(md::uint32));
            if (size == sizeof(double)) {
                v.i[1] = skl::read(ea +
                                   static_cast<md::OADDR>(sizeof(md::uint32)),
                                   false, sizeof(md::uint32));
                md::recompose_double(v.i[0], v.i[1], d);
            } else {
                d = v.f;
            }
            return d;
        }


        void load(cpu_t *cpu, int size)
        {
            char       sign = '+';
            int        offs = offset;
            md::OADDR  ea   = skl::compute_effective_address(cpu, decode.Rbase,
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

            if (LIKELY(address_valid(ea, size))) {
                double value = 0;
                COMPILE_TIME_ASSERT(skl_endian_little);
                value = read_real_little_endian(cpu, ea, size);
                dialog::trace("[ea: %xH, value: %f]\n", ea, value);
                write_real_register(cpu, decode.Rd, value);
                increment_pc(cpu, 2);
            } else {
                hardware_trap(cpu, CR2_OUT_OF_BOUNDS_READ);
            }
        }
    };


    struct skl_store_real_t : skl_load_store_t {
        skl_store_real_t(md::OADDR    pc_,
                         md::OINST    inst_,
                         const char **mne_,
                         const reg_mem_decode_t &decode_) :
            skl_load_store_t(pc_, inst_, mne_, decode_)
        {
        }


        void
        store(cpu_t *cpu, int size)
        {
            O3::decode_pc_t decoded_pc;
            double          value;
            int             R0   = decode.Rd;
            char            sign = '+';
            int             offs = offset;
            md::OADDR  ea   = skl::compute_effective_address(cpu, decode.Rbase,
                                                             decode.Rindex,
                                                             decode.scale,
                                                             offset);

            if (offs < 0) {
                sign   = '-';
                offs = -offs;
            }
            dialog::trace("%s: %s  F%u, (R%u + R%u:%u %c %xH)",
                          decoded_pc, mne, R0, decode.Rbase, decode.Rindex,
                          decode.scale, sign, offset);

            value = read_real_register(cpu, R0);
            dialog::trace("[value: %f, ea: %xH]\n", value, ea);

            if (LIKELY(address_valid(ea, size))) {
                md::uint32 lo;
                md::uint32 hi;

                COMPILE_TIME_ASSERT(sizeof(float) == sizeof(md::uint32) &&
                                    sizeof(double) == 2 * sizeof(float));

                if (size == sizeof(double)) {
                    md::decompose_double(value, lo, hi);
                    COMPILE_TIME_ASSERT(skl_endian_little);
                    skl::write(ea, lo, sizeof(md::uint32));
                    skl::write(ea +
                               static_cast<md::OADDR>(sizeof(md::uint32)),
                               hi, sizeof(md::uint32));
                } else {
                    union {
                        md::uint32 i;
                        float f;
                    } v;
                    v.f = static_cast<float>(value);
                    skl::write(ea, v.i, sizeof(md::uint32));
                }
                increment_pc(cpu, 2);
            } else {
                hardware_trap(cpu, CR2_OUT_OF_BOUNDS_WRITE);
            }
        }
    };


    struct skl_lb_t : skl_load_int_t {

        skl_lb_t(md::OADDR    pc_,
                 md::OINST    inst_,
                 const char **mne_,
                 const reg_mem_decode_t &decode_) :
            skl_load_int_t(pc_, inst_, mne_, decode_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            load(cpu, true, sizeof(md::uint8));
        }
    };


    struct skl_lbu_t : skl_load_int_t {

        skl_lbu_t(md::OADDR    pc_,
                  md::OINST    inst_,
                  const char **mne_,
                  const reg_mem_decode_t &decode_) :
            skl_load_int_t(pc_, inst_, mne_, decode_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            load(cpu, false, sizeof(md::uint8));
        }
    };


    struct skl_lh_t : skl_load_int_t {

        skl_lh_t(md::OADDR    pc_,
                 md::OINST    inst_,
                 const char **mne_,
                 const reg_mem_decode_t &decode_) :
            skl_load_int_t(pc_, inst_, mne_, decode_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            load(cpu, true, sizeof(md::uint16));
        }
    };


    struct skl_lhu_t : skl_load_int_t {

        skl_lhu_t(md::OADDR    pc_,
                  md::OINST    inst_,
                  const char **mne_,
                  const reg_mem_decode_t &decode_) :
            skl_load_int_t(pc_, inst_, mne_, decode_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            load(cpu, false, sizeof(md::uint16));
        }
    };


    struct skl_lw_t : skl_load_int_t {

        skl_lw_t(md::OADDR    pc_,
                 md::OINST    inst_,
                 const char **mne_,
                 const reg_mem_decode_t &decode_) :
            skl_load_int_t(pc_, inst_, mne_, decode_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            load(cpu, true, sizeof(md::uint32));
        }
    };


    struct skl_lf_t : skl_load_real_t {

        skl_lf_t(md::OADDR    pc_,
                 md::OINST    inst_,
                 const char **mne_,
                 const reg_mem_decode_t &decode_) :
            skl_load_real_t(pc_, inst_, mne_, decode_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            load(cpu, sizeof(float));
        }
    };


    struct skl_ld_t : skl_load_real_t {

        skl_ld_t(md::OADDR    pc_,
                 md::OINST    inst_,
                 const char **mne_,
                 const reg_mem_decode_t &decode_) :
            skl_load_real_t(pc_, inst_, mne_, decode_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            load(cpu, sizeof(double));
        }
    };


    struct skl_sb_t : skl_store_int_t {

        skl_sb_t(md::OADDR    pc_,
                 md::OINST    inst_,
                 const char **mne_,
                 const reg_mem_decode_t &decode_) :
            skl_store_int_t(pc_, inst_, mne_, decode_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            store(cpu, true, sizeof(md::uint8));
        }
    };


    struct skl_sd_t : skl_store_real_t {

        skl_sd_t(md::OADDR    pc_,
                 md::OINST    inst_,
                 const char **mne_,
                 const reg_mem_decode_t &decode_) :
            skl_store_real_t(pc_, inst_, mne_, decode_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            store(cpu, sizeof(double));
        }
    };


    struct skl_sf_t : skl_store_real_t {

        skl_sf_t(md::OADDR    pc_,
                 md::OINST    inst_,
                 const char **mne_,
                 const reg_mem_decode_t &decode_) :
            skl_store_real_t(pc_, inst_, mne_, decode_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            store(cpu, sizeof(float));
        }
    };


    struct skl_sh_t : skl_store_int_t {

        skl_sh_t(md::OADDR    pc_,
                 md::OINST    inst_,
                 const char **mne_,
                 const reg_mem_decode_t &decode_) :
            skl_store_int_t(pc_, inst_, mne_, decode_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            store(cpu, true, sizeof(md::uint16));
        }
    };


    struct skl_sw_t : skl_store_int_t {

        skl_sw_t(md::OADDR    pc_,
                 md::OINST    inst_,
                 const char **mne_,
                 const reg_mem_decode_t &decode_) :
            skl_store_int_t(pc_, inst_, mne_, decode_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            store(cpu, true, sizeof(md::uint32));
        }
    };


    struct skl_la_t : skl_load_int_t {

        skl_la_t(md::OADDR    pc_,
                 md::OINST    inst_,
                 const char **mne_,
                 const reg_mem_decode_t &decode_) :
            skl_load_int_t(pc_, inst_, mne_, decode_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
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
    op_reg_mem(cpu_t *cpu, md::OINST inst)
    {
        opc_t opc = static_cast<opc_t>(field(inst, 4, 0));
        reg_mem_decode_t decode;

        decode.Rd     = field(inst, 25, 21);
        decode.Rbase  = field(inst, 20, 16);
        decode.Rindex = field(inst, 15, 11);
        decode.scale  = field(inst, 7, 6); // { 0, 1, 2, 3 }.

        switch (opc) {
        case OPC_LB:
            return new skl_lb_t(cpu->pc, inst, mne, decode);

        case OPC_LBU:
            return new skl_lbu_t(cpu->pc, inst, mne, decode);

        case OPC_LD:
            return new skl_ld_t(cpu->pc, inst, mne, decode);

        case OPC_LDI:
            return new skl_ldi_t(cpu->pc, inst, mne, decode);

        case OPC_LF:
            return new skl_lf_t(cpu->pc, inst, mne, decode);

        case OPC_LFI:
            return new skl_lfi_t(cpu->pc, inst, mne, decode);

        case OPC_LH:
            return new skl_lh_t(cpu->pc, inst, mne, decode);

        case OPC_LHU:
            return new skl_lhu_t(cpu->pc, inst, mne, decode);

        case OPC_LW:
            return new skl_lw_t(cpu->pc, inst, mne, decode);

        case OPC_LWI:
            return new skl_lwi_t(cpu->pc, inst, mne, decode);

        case OPC_SB:
            return new skl_sb_t(cpu->pc, inst, mne, decode);

        case OPC_SD:
            return new skl_sd_t(cpu->pc, inst, mne, decode);

        case OPC_SF:
            return new skl_sf_t(cpu->pc, inst, mne, decode);

        case OPC_SH:
            return new skl_sh_t(cpu->pc, inst, mne, decode);

        case OPC_SW:
            return new skl_sw_t(cpu->pc, inst, mne, decode);

        case OPC_LA:
            return new skl_la_t(cpu->pc, inst, mne, decode);

        default:
            dialog::not_implemented("%s: inst: %xH opcode: %xH",
                                    __func__, inst, opc);
        }
    }
}
