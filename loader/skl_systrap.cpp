/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <assert.h>
#include "dialog.h"
#include "o3.h"
#include "skl_jral.h"

namespace skl {
    typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_systrap_opc.h"
#undef OPC
        N_OPCODES
    } opc_t;

    static const char *mnemonics[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_systrap_opc.h"
#undef OPC
    };


    struct skl_trap_t : skl::instruction_t {
        int Rd;
        int R0;
        int subcl;

        skl_trap_t(md::OADDR pc_, md::OINST inst_) :
            skl::instruction_t(pc_, inst_, mnemonics),
            Rd(field(inst, 25, 21)),
            R0(field(inst, 20, 16)),
            subcl(field(inst, 7, 0))
        {
            /* Reinitialize 'opc' because it is in a different place
             * than the rest of the instructions.
             */
            opc = field(inst, 15,  8);
            mne = mnemonics[opc];
        }


        void epilog(skl::cpuid_t cpu, bool trapped)
        {
            if (LIKELY(!trapped)) {
                increment_pc(cpu, 1);
            } else {
                software_trap(cpu, opc);
            }
        }
    };


    struct skl_trapnil_t : skl_trap_t {

        skl_trapnil_t(md::OADDR pc_, md::OINST inst_) :
            skl_trap_t(pc_, inst_)
        {
            assert(Rd == 0);
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 r0 = read_integer_register(cpu, R0);
            bool trapped = r0 == 0;         // true => trap raised.

            dialog::trace("%s: %s  R%u, %u\n", decoded_pc, mne, R0, subcl);
            epilog(cpu, trapped);
        }
    };


    struct skl_traprange_t : skl_trap_t {

        skl_traprange_t(md::OADDR pc_, md::OINST inst_) :
            skl_trap_t(pc_, inst_)
        {
        }
    };


    struct skl_traprange_sint_t : skl_traprange_t {

        skl_traprange_sint_t(md::OADDR pc_, md::OINST inst_) :
            skl_traprange_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 r0    = read_integer_register(cpu, R0);
            int        value = static_cast<int>(r0);
            bool       ok    = -128 <= value && value <= 127;

            dialog::trace("%s: %s  R%u, %u\n", decoded_pc, mne, R0, subcl);
            epilog(cpu, !ok);
        }
    };


    struct skl_traprange_int_t : skl_traprange_t {

        skl_traprange_int_t(md::OADDR pc_, md::OINST inst_) :
            skl_traprange_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 r0    = read_integer_register(cpu, R0);
            int        value = static_cast<int>(r0);
            bool       ok    = -32768 <= value && value <= 32767;

            dialog::trace("%s: %s  R%u, %u\n", decoded_pc, mne, R0, subcl);
            epilog(cpu, !ok);
        }
    };


    struct skl_traprange_lint_t : skl_traprange_t {

        skl_traprange_lint_t(md::OADDR pc_, md::OINST inst_) :
            skl_traprange_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            /* LONGINT types can never exceed their range. */
            bool ok = true;
            dialog::trace("%s: %s  R%u, %u\n", decoded_pc, mne, R0, subcl);
            epilog(cpu, !ok);
        }
    };


    struct skl_traprange_bitset_t : skl_traprange_t {

        skl_traprange_bitset_t(md::OADDR pc_, md::OINST inst_) :
            skl_traprange_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 r0    = read_integer_register(cpu, R0);
            int        value = static_cast<int>(r0);
            bool       ok    = 0 <= value && value <= 31;

            dialog::trace("%s: %s  R%u, %u\n", decoded_pc, mne, R0, subcl);
            epilog(cpu, !ok);
        }
    };


    struct skl_traparray_t : skl_trap_t {

        skl_traparray_t(md::OADDR pc_, md::OINST inst_) :
            skl_trap_t(pc_, inst_)
        {
        }


        virtual void interpret(skl::cpuid_t cpu)
        {
            md::uint32 r0 = read_integer_register(cpu, R0);
            md::uint32 rd = read_integer_register(cpu, Rd);
            bool       ok;

            ok = (static_cast<int>(r0) >= 0 && // Non-negative index
                  r0 <= rd);                   // R0 is index (x[R0]). Rd is LEN(x).

            dialog::trace("%s: %s  R%u, R%u\n", decoded_pc, mne, R0, Rd);
            epilog(cpu, !ok);
        }
    };


    skl::instruction_t *
    op_systrap(md::OADDR pc, md::OINST inst)
    {
        opc_t opc = static_cast<opc_t>(field(inst, 15,  8));

        switch (opc) {
        case OPC_TRAPGUARD:
        case OPC_TRAPNIL: return new skl_trapnil_t(pc, inst);

        case OPC_TRAPRANGE: {
            int subcl = field(inst, 7, 0);

            switch (subcl) {
            case 4 : return new skl_traprange_sint_t(pc, inst);
            case 5 : return new skl_traprange_int_t(pc, inst);
            case 6 : return new skl_traprange_lint_t(pc, inst);
            case 9 : return new skl_traprange_bitset_t(pc, inst);
            default: dialog::internal_error("%s: traprange (subcl: %u)",
                                            __func__, subcl);
            }
        }

        case OPC_TRAPARRAY:
            return new skl_traparray_t(pc, inst);

        default:
            dialog::internal_error("%s: Unsupported systrap opcode: %d",
                                   __func__, opc);
        }
    }
}
