/* Copyright (c) 2021, 2022, 2023 Logic Magicians Software */

#include <math.h>
#include <stdlib.h>

#include "dialog.h"
#include "o3.h"
#include "skl_flags.h"
#include "skl_fp_reg.h"

namespace skl {
        typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_fp_reg_opc.h"
#undef OPC
            N_OPCODES
        } opc_t;

        static const char *mnemonics[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_fp_reg_opc.h"
#undef OPC
        };


    struct skl_fp_reg_t : skl::instruction_t {
        int             Rd;
        int             R0;
        int             R1;
        register_bank_t bd;
        register_bank_t b0;
        register_bank_t b1;

        skl_fp_reg_t(md::OADDR pc_, md::OINST inst_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst_, 25, 21)),
            R0(field(inst_, 20, 16)),
            R1(field(inst_, 15, 11)),
            bd(static_cast<register_bank_t>(field(inst,  10, 10))),
            b0(static_cast<register_bank_t>(field(inst,   9,  9))),
            b1(static_cast<register_bank_t>(field(inst,   8,  8)))
        {
        }

        void epilog(skl::cpuid_t cpuid, double v)
        {
            write_real_register(cpuid, Rd, v);
            increment_pc(cpuid, 1);
        }
    };


    struct skl_fp_reg_arctan_t : skl_fp_reg_t {
        skl_fp_reg_arctan_t(md::OADDR pc_, md::OINST inst_) :
            skl_fp_reg_t(pc_, inst_)
        {
        }

        virtual void interpret(skl::cpuid_t cpuid)
        {
            double l = read_real_register(cpuid, R0);
            double v = atan(l);
            dialog::trace("%s: %s  F%u, F%u", decoded_pc, mne,
                          R0, Rd);
            dialog::trace("[%f, %f]\n", l, v);
            epilog(cpuid, v);
        }
    };


    struct skl_fp_reg_cos_t : skl_fp_reg_t {
        skl_fp_reg_cos_t(md::OADDR pc_, md::OINST inst_) :
            skl_fp_reg_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            double l = read_real_register(cpuid, R0);
            double v = cos(l);
            dialog::trace("%s: %s  F%u, F%u", decoded_pc, mne,
                          R0, Rd);
            dialog::trace("[%f, %f]\n", l, v);
            epilog(cpuid, v);
        }
    };


    struct skl_fp_reg_exp_t : skl_fp_reg_t {
        skl_fp_reg_exp_t(md::OADDR pc_, md::OINST inst_) :
            skl_fp_reg_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            double l = read_real_register(cpuid, R0);
            double v = exp(l);
            dialog::trace("%s: %s  F%u, F%u", decoded_pc, mne,
                          R0, Rd);
            dialog::trace("[%f, %f]\n", l, v);
            epilog(cpuid, v);
        }
    };


    struct skl_fp_reg_ln_t : skl_fp_reg_t {
        skl_fp_reg_ln_t(md::OADDR pc_, md::OINST inst_) :
            skl_fp_reg_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            double l = read_real_register(cpuid, R0);
            double v = log(l);
            dialog::trace("%s: %s  F%u, F%u", decoded_pc, mne,
                          R0, Rd);
            dialog::trace("[%f, %f]\n", l, v);
            epilog(cpuid, v);
        }
    };


    struct skl_fp_reg_sin_t : skl_fp_reg_t {
        skl_fp_reg_sin_t(md::OADDR pc_, md::OINST inst_) :
            skl_fp_reg_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            double l = read_real_register(cpuid, R0);
            double v = sin(l);
            dialog::trace("%s: %s  F%u, F%u", decoded_pc, mne,
                          R0, Rd);
            dialog::trace("[%f, %f]\n", l, v);
            epilog(cpuid, v);
        }
    };


    struct skl_fp_reg_sqrt_t : skl_fp_reg_t {
        skl_fp_reg_sqrt_t(md::OADDR pc_, md::OINST inst_) :
            skl_fp_reg_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            double l = read_real_register(cpuid, R0);
            double v = sqrt(l);
            dialog::trace("%s: %s  F%u, F%u", decoded_pc, mne,
                          R0, Rd);
            dialog::trace("[%f, %f]\n", l, v);
            epilog(cpuid, v);
        }
    };


    struct skl_fp_reg_tan_t : skl_fp_reg_t {
        skl_fp_reg_tan_t(md::OADDR pc_, md::OINST inst_) :
            skl_fp_reg_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpuid)
        {
            double l = read_real_register(cpuid, R0);
            double v = tan(l);
            dialog::trace("%s: %s  F%u, F%u", decoded_pc, mne,
                          R0, Rd);
            dialog::trace("[%f, %f]\n", l, v);
            epilog(cpuid, v);
        }
    };


    skl::instruction_t *
    op_fp_reg(md::OADDR pc, md::uint32 inst)
    {
        opc_t opc = static_cast<opc_t>(field(inst, 4, 0));

        switch (opc) {
        case OPC_ARCTAN: return new skl_fp_reg_arctan_t(pc, inst);
        case OPC_COS   : return new skl_fp_reg_cos_t(pc, inst);
        case OPC_EXP   : return new skl_fp_reg_exp_t(pc, inst);
        case OPC_LN    : return new skl_fp_reg_ln_t(pc, inst);
        case OPC_SIN   : return new skl_fp_reg_sin_t(pc, inst);
        case OPC_SQRT  : return new skl_fp_reg_sqrt_t(pc, inst);
        case OPC_TAN   : return new skl_fp_reg_tan_t(pc, inst);
        default:
                dialog::internal_error("%s: improper real opcode", __func__);
        }
    }
}
