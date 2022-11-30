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

    static const char *mne[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_systrap_opc.h"
#undef OPC
    };


    struct skl_trap_t : skl::instruction_t {
        int Rd;
        int R0;
        int subcl;

        skl_trap_t(md::OADDR    pc_,
                   md::OINST    inst_,
                   const char **mne_) :
            skl::instruction_t(pc_, inst_, mne_),
            Rd(field(inst, 25, 21)),
            R0(field(inst, 20, 16)),
            subcl(field(inst, 7, 0))
        {
            /* Reinitialize 'opc' because it is in a different place
             * than the rest of the instructions.
             */
            opc = field(inst, 15,  8);
            mne = mne_[opc];
        }
    };


    struct skl_trapnil_t : skl_trap_t {

        skl_trapnil_t(md::OADDR    pc_,
                      md::OINST    inst_,
                      const char **mne_) :
            skl_trap_t(pc_, inst_, mne_)
        {
            assert(Rd == 0);
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            md::uint32 r0 = read_integer_register(cpu, R0);
            bool trapped = r0 == 0;         // true => trap raised.

            dialog::trace("%s: %s  R%u, %u\n", decoded_pc, mne, R0, subcl);
            if (LIKELY(!trapped)) {
                increment_pc(cpu, 1);
            } else {
                software_trap(cpu, opc);
            }
        }
    };


    struct skl_traprange_t : skl_trap_t {

        skl_traprange_t(md::OADDR    pc_,
                        md::OINST    inst_,
                        const char **mne_) :
            skl_trap_t(pc_, inst_, mne_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            md::uint32 r0    = read_integer_register(cpu, R0);
            int        value = static_cast<int>(r0);
            bool       ok;
            bool       trapped;

            switch (subcl) {
            case 4:                 // 1 byte signed integer.
                ok = -128 <= value && value <= 127;
                break;

            case 5:                 // 2 byte signed integer.
                ok = -32768 <= value && value <= 32767;
                break;

            case 6:                 // 4 byte signed integer.
                ok = true;          // It cannot be out-of-range!
                break;

            case 9:                 // 32 bit bitset.
                ok = 0 <= value && value <= 31;
                break;

            default:                // All others invalid.
                ok = false;
                dialog::internal_error("%s: Invalid 'traprange' encoding (subcl: %u)",
                                       __func__, subcl);
            }
            dialog::trace("%s: %s  R%u, %u\n", decoded_pc, mne, R0, subcl);
            trapped = !ok;             // true => trap raised.
            if (LIKELY(!trapped)) {
                increment_pc(cpu, 1);
            } else {
                software_trap(cpu, opc);
            }
        }
    };


    struct skl_traparray_t : skl_trap_t {

        skl_traparray_t(md::OADDR    pc_,
                        md::OINST    inst_,
                        const char **mne_) :
            skl_trap_t(pc_, inst_, mne_)
        {
        }


        virtual void interpret(skl::cpu_t *cpu)
        {
            md::uint32 r0 = read_integer_register(cpu, R0);
            md::uint32 rd = read_integer_register(cpu, Rd);
            bool       ok;
            bool       trapped;

            ok = (static_cast<int>(r0) >= 0 && // Non-negative index
                  r0 <= rd);                   // R0 is index (x[R0]). Rd is LEN(x).

            dialog::trace("%s: %s  R%u, R%u\n", decoded_pc, mne, R0, Rd);
            trapped = !ok;             // true => trap raised.
            if (LIKELY(!trapped)) {
                increment_pc(cpu, 1);
            } else {
                software_trap(cpu, opc);
            }
        }
    };


    skl::instruction_t *
    op_systrap(cpu_t *cpu, md::OINST inst)
    {
        opc_t opc = static_cast<opc_t>(field(inst, 15,  8));

        switch (opc) {
        case OPC_TRAPGUARD:
        case OPC_TRAPNIL:
            return new skl_trapnil_t(cpu->pc, inst, mne);

        case OPC_TRAPRANGE:
            return new skl_traprange_t(cpu->pc, inst, mne);

        case OPC_TRAPARRAY:
            return new skl_traparray_t(cpu->pc, inst, mne);

        default:
            dialog::internal_error("%s: Unsupported systrap opcode: %d",
                                   __func__, opc);
        }
    }
}
