/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <assert.h>
#include "dialog.h"
#include "o3.h"
#include "skl_jral.h"

namespace skl {
    static bool
    trapnil(cpu_t &cpu, unsigned opc, unsigned R0)
    {
        md::uint32 r0 = read_integer_register(cpu, R0);

        if (UNLIKELY(r0 == 0)) {      // If pointer is NIL....
            software_trap(cpu, opc);
        }
        return r0 == 0;         // true => trap raised.
    }


    static bool
    traprange(cpu_t &cpu, unsigned opc, unsigned subcl, unsigned R0)
    {
        md::uint32 r0    = read_integer_register(cpu, R0);
        int        value = static_cast<int>(r0);
        bool       ok;

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

        if (UNLIKELY(!ok)) {    // If pointer is NIL....
            software_trap(cpu, opc);
        }
        return !ok;             // true => trap raised.
    }


    static bool
    traparray(cpu_t &cpu, unsigned opc, unsigned R0, unsigned Rd)
    {
        md::uint32 r0 = read_integer_register(cpu, R0);
        md::uint32 rd = read_integer_register(cpu, Rd);
        bool       ok;

        ok = (static_cast<int>(r0) >= 0 && // Non-negative index
              r0 <= rd);                   // R0 is x[R0]. Rd is LEN(x).

        if (UNLIKELY(!ok)) {    // If array index is out-of-bounds.
            software_trap(cpu, opc);
        }
        return !ok;             // true => trap raised.
    }

    void
    op_systrap(cpu_t &cpu, md::uint32 inst)
    {
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
        unsigned        Rd    = field(inst, 25, 21);
        unsigned        R0    = field(inst, 20, 16);
        opc_t           opc   = static_cast<opc_t>(field(inst, 15,  8));
        unsigned        subcl = field(inst, 7, 0);
        O3::decode_pc_t decoded_pc;
        bool            trapped = false;

        O3::decode_pc(cpu.pc, decoded_pc);

        switch (opc) {
        case OPC_TRAPGUARD:
        case OPC_TRAPNIL:
            assert(Rd == 0);
            dialog::trace("%s: %s  R%u, %u\n", decoded_pc, mne[opc], R0, subcl);
            trapped = trapnil(cpu, opc, R0);
            break;

        case OPC_TRAPRANGE:
            dialog::trace("%s: %s  R%u, %u\n", decoded_pc, mne[opc], R0, subcl);
            trapped = traprange(cpu, opc, subcl, R0);
            break;

        case OPC_TRAPARRAY:
            dialog::trace("%s: %s  R%u, R%u\n", decoded_pc, mne[opc], R0, Rd);
            trapped = traparray(cpu, opc, R0, Rd);
            break;

        default:
            dialog::internal_error("%s: Unsupported systrap opcode: %d",
                                   __func__, opc);
        }
        if (!trapped) {
            increment_pc(cpu, 1);
        }
    }
}
