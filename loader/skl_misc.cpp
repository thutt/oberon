/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <assert.h>
#include "dialog.h"
#include "skl_misc.h"
#include "skl_vmsvc.h"

namespace skl {
    typedef enum opc_t {
#define OPC(_t) OPC_##_t,
#include "skl_misc_opc.h"
#undef OPC
        N_OPCODES
    } opc_t;

    static const char *mnemonics[N_OPCODES] = {
#define OPC(_t) #_t,
#include "skl_misc_opc.h"
#undef OPC
    };


    skl::instruction_t *
    op_misc(md::OADDR pc, md::OINST inst)
    {
        opc_t opc = static_cast<opc_t>(field(inst, 4, 0));

        switch (opc) {
        case OPC_BREAK: dialog::not_implemented("break");
        case OPC_WAIT:  dialog::not_implemented("wait");
        case OPC_ERET:  dialog::not_implemented("eret");
        case OPC_VMSVC: return op_vmsvc(pc, inst, mnemonics);
            
        default:
            dialog::not_implemented("%s: inst: %xH opcode: %xH",
                                    __func__, inst, opc);
        }
    }
}
