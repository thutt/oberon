/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <assert.h>

#include "config.h"
#include "heap.h"
#include "o3.h"
#include "md.h"
#include "skl.h"
#include "skl_bit_test.h"
#include "skl_cond.h"
#include "skl_ctrl_reg.h"
#include "skl_gen_reg.h"
#include "skl_instruction.h"
#include "skl_int_reg.h"
#include "skl_jral.h"
#include "skl_jump.h"
#include "skl_misc.h"
#include "skl_reg_mem.h"
#include "skl_stack.h"
#include "skl_sys_reg.h"
#include "skl_systrap.h"

namespace skl {
    typedef enum opcode_class_t { // bits 31..26
#define OC(_t) OC_##_t,
#include "skl_opcode_class.h"
#undef OC
        N_OPCODE_CLASSES
    } opcode_class_t;

    md::OADDR initial_stack_bot;
    md::OADDR initial_stack_top;

    const char *reg_bank[2] = {
        "R",
        "F"
    };

    cpu_t    cpu;
    memory_t memory;


    void
    initialize_memory(md::OADDR membeg, int n_bytes)
    {
        memory.beg     = membeg;
        memory.end     = membeg + static_cast<md::OADDR>(n_bytes);
        memory.n_bytes = n_bytes;
    }


    static void
    dump_cpu_stack(cpu_t *cpu)
    {
        const int       default_stack_words = 32;
        int             i;
        O3::decode_pc_t decoded_pc;
        md::uint32      v;
        md::uint32      p;
        md::uint32      sp                  = read_integer_register(cpu, SP);
        md::uint32      sfp                 = read_integer_register(cpu, SFP);
        int             stack_words         = default_stack_words;
        md::uint32      next_sfp            = sfp;

        if (sp >= initial_stack_top - sizeof(md::uint32)) {
            /* At startup, with an empty stack, SP will be one word
             * above the topmost stack element, because the SP is
             * predecrement.
             */
            stack_words = 0;
        } else {
            stack_words = static_cast<int>((initial_stack_top - sp) /
                                           static_cast<int>(sizeof(md::uint32)));
        }

        if (stack_words > 0) {
            dialog::cpu("Stack [%xH..%xH) [%xH words]\n",
                        initial_stack_bot, initial_stack_top, stack_words);
            i = 0;
            do {
                p = sp + static_cast<md::uint32>(i * static_cast<int>(sizeof(md::uint32)));
                v = skl::read(p, false, sizeof(md::uint32));

                O3::decode_pc(v, decoded_pc);

                if (p == next_sfp) {
                    dialog::cpu("  %0xH [SP+%03.3xH] : (SFP) %s\n",
                                p, i * static_cast<int>(sizeof(md::uint32)),
                                decoded_pc);
                    next_sfp = v;
                } else {
                    dialog::cpu("  %0xH [SP+%03.3xH] :       %s\n",
                                p, i * static_cast<int>(sizeof(md::uint32)),
                                decoded_pc);
                }
                ++i;
            } while (i < stack_words);
        } else {
            dialog::cpu("Stack [stack empty]\n");
        }
        dialog::cpu("\n");
    }

    static void
    dump_control_registers(cpu_t *cpu)
    {
        if (false) {
            dialog::cpu("CR0: %8.8xH [exception address]\n", cpu->_CR[0]);
            dialog::cpu("CR1: %8.8xH [hardware exception handler]\n", cpu->_CR[1]);
            dialog::cpu("CR2: %8.8xH [exception status]\n", cpu->_CR[2]);
            dialog::cpu("CR5: %8.8xH [Software exception handler]\n", cpu->_CR[5]);
            dialog::cpu("\n");
        }
    }


    void
    dump_cpu__(cpu_t *cpu)
    {
        bool            dump_float_registers = true;
        int              i;
        O3::decode_pc_t decoded_pc;

        if (config::options & config::opt_trace_cpu) {
            O3::decode_pc(cpu->pc, decoded_pc);
            dialog::cpu("pc : %s  (%xH)\n", decoded_pc, cpu->pc);
            dump_control_registers(cpu);

            i = 0;
            while (i < static_cast<int>(sizeof(cpu->_R) /
                                        sizeof(cpu->_R[0]))) {
                dialog::cpu("R%-2u: %8.8xH", i, cpu->_R[i]);
                ++i;
                if ((i % 4) == 0) {
                    dialog::cpu("\n");
                } else {
                    dialog::cpu("  ");
                }
            }

            if (dump_float_registers) {
                dialog::cpu("\n");
                i = 0;
                while (i < static_cast<int>(sizeof(cpu->_F) /
                                            sizeof(cpu->_F[0]))) {
                    dialog::cpu("F%-2u: %e", i, cpu->_F[i]);
                    ++i;
                    if ((i % 3) == 0) {
                        dialog::cpu("\n");
                    } else {
                        dialog::cpu("  ");
                    }
                }
            }
            dialog::cpu("\n");
            dump_cpu_stack(cpu);
        }
    }


    void
    software_trap(cpu_t *cpu, int trap)
    {
        write_integer_register(cpu, 1,
                               static_cast<md::uint32>(trap)); // Trap code.
        write_integer_register(cpu, 31, cpu->pc);  // Return address.
        cpu->pc = read_control_register(cpu, CR5); // Kernel.SysTrap
        cpu->exception_raised = true;
    }


    void
    hardware_trap(cpu_t *cpu, control_register_2_t trap)
    {
        md::uint32 cr2;
        write_control_register(cpu, CR0, cpu->pc); // Exception address.
        cr2 = static_cast<md::uint32>(trap |
                                      0    | // Interrupt enable setting (not supported).
                                      1);    // Processor, not external.
        write_control_register(cpu, CR2, cr2);
        cpu->pc = read_control_register(cpu, CR1); // Kernel.HardwareTrap
        cpu->exception_raised = true;
    }


    static inline opcode_class_t
    classof(md::OINST inst)
    {
        int v = field(inst, 31, 26);
        if (v > N_OPCODE_CLASSES) {
            v = N_OPCODE_CLASSES; // Invalid opcode.
        }
        return static_cast<opcode_class_t>(v);
    }


    void
    write(md::OADDR addr, md::uint32 val, int size)
    {
        if (LIKELY(address_valid(addr, size))) {
            md::HADDR p = heap::heap_to_host(addr);

            switch (size) {
            case 1: {
                md::uint8 v = static_cast<md::uint8>(val);
                *reinterpret_cast<md::uint8 *>(p) = v;
                break;
            }

            case 2: {
                md::uint16 v = static_cast<md::uint16>(val);
                *reinterpret_cast<md::uint16 *>(p) = v;
                break;
            }

            case 4:
                *reinterpret_cast<md::uint32 *>(p) = val;
                break;

            default:
                dialog::internal_error("%s: invalid write size '%d'",
                                       __func__, size);
            }
        } else {
            hardware_trap(&cpu, CR2_OUT_OF_BOUNDS_WRITE);
        }
    }


    static md::uint32
    fetch_instruction(void)
    {
        md::uint32 inst;

        if (LIKELY(aligned(cpu.pc, static_cast<int>(sizeof(md::uint32))))) {
            inst = skl::read(cpu.pc, false, sizeof(md::uint32));
        } else {
            hardware_trap(&cpu, CR2_BAD_ALIGNMENT);
        }
        return inst;
    }

    static skl::instruction_t *
    fetch_and_cache_instruction(skl::cpu_t *cpu)
    {
        md::OINST           inst;
        opcode_class_t      cls;
        skl::instruction_t *cinst = NULL;

        dump_cpu(cpu);
        cpu->exception_raised = false;
        inst = skl::fetch_instruction();
        cls  = classof(inst);

        switch (cls) {
        case OC_GEN_REG:
            cinst = op_gen_reg(cpu, inst);
            break;

        case OC_INT_REG:
            cinst = op_int_reg(cpu, inst);
            break;

        case OC_SIGN_EXT:
            dialog::not_implemented("%s: OC_SIGN_EXT", __func__);
            break;

        case OC_CTL_REG:
            cinst = op_ctrl_reg(cpu, inst);
            break;

        case OC_SYS_REG:
            cinst = op_sys_reg(cpu, inst);
            break;

        case OC_MISC:
            cinst = op_misc(cpu, inst);
            break;

        case OC_JRAL:
            cinst = op_jral(cpu, inst);
            break;

        case OC_JUMP:
            cinst = op_jump(cpu, inst);
            break;

        case OC_REG_MEM:
            cinst = op_reg_mem(cpu, inst);
            break;

        case OC_BIT_TEST:
            cinst = op_bit_test(cpu, inst);
            break;

        case OC_STACK:
            cinst = op_stack(cpu, inst);
            break;

        case OC_CONDITIONAL_SET:
            cinst = op_conditional_set(cpu, inst);
            break;

        case OC_SYSTRAP:
            cinst = op_systrap(cpu, inst);
            break;

        default: {
            hardware_trap(cpu, CR2_INVALID_OPCODE);
            break;
        }
        }
        if (cinst != NULL) {
            skl::cache_instruction(cinst);
            return cinst;
        }
        return NULL;
    }


    static skl::instruction_t *
    fetch_cached_instruction(skl::cpu_t *cpu)
    {
        skl::instruction_t *cinst = skl::lookup_instruction(cpu->pc);
        return cinst;
    }


    void
    execute(cpu_t *cpu, md::OADDR addr)
    {
        cpu->pc = addr;

        while (1) {
            skl::instruction_t *cinst = fetch_cached_instruction(cpu);

            write_integer_register(cpu, 0, 0); // Reset R0 to zero.

            cpu->_instruction_count++;
            if (cinst == NULL) {
                cinst = fetch_and_cache_instruction(cpu);
            }
            assert(cinst != NULL);
            cinst->interpret();
        }
    }


    register_bank_t
    compute_using(register_bank_t R0,
                  register_bank_t R1)
    {
        if (R0 == RB_DOUBLE || R1 == RB_DOUBLE) {
            return RB_DOUBLE;
        }
        return RB_INTEGER;
    }


    md::uint32
    register_as_integer(cpu_t           *cpu,
                        int              regno,
                        register_bank_t  bank)
    {
        if (bank == RB_INTEGER) {
            return read_integer_register(cpu, regno);
        } else {
            assert(bank == RB_DOUBLE);
            return static_cast<md::uint32>(cpu->_F[regno]);
        }
    }

    double
    register_as_double(cpu_t           *cpu,
                       int              regno,
                       register_bank_t  bank)
    {
        if (bank == RB_INTEGER) {
            return read_integer_register(cpu, regno);
        } else {
            assert(bank == RB_DOUBLE);
            return cpu->_F[regno];
        }
    }

    void
    initialize_stack(void)
    {
        /* Since module initialization functions have a normal
         * signature that expects the stack frame to be configured
         * correctly, initialize SP for Oberon.  Note that the valid stack addresses are:
         *
         *   MEMORY[heap::oberon_heap, heap::oberon_heap + stack_top)
         *
         * SP is initially beyond the end of the stack.  This is ok
         * because 'push' is pre-decrement.
         *
         * SFP is initialized to within the stack, as it is used
         * without decrement or increment.
         */
        md::OADDR stack_top = (heap::heap_address(heap::oberon_stack) +
                               static_cast<md::OADDR>(heap::oberon_stack_size_in_bytes));
        /* Stack is predecrement.  To use the last element of the
         * stack, the stack pointer must be positioned one word past
         * the end of the stack; it does at the end of heap
         * initialization.
         */
        skl::initial_stack_top = stack_top;
        skl::initial_stack_bot = heap::heap_address(heap::oberon_stack);

        /* It's important to give { SP, SFP } the same value so that
         * the stack dumping logic can terminate easily in
         * skl::dump_cpu_stack().
         */
        write_integer_register(&skl::cpu, SP, stack_top);
        write_integer_register(&skl::cpu, SFP, stack_top);
    }
}
