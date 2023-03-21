/* Copyright (c) 2021, 2022, 2023 Logic Magicians Software */
#include <assert.h>

#include "config.h"
#include "heap.h"
#include "o3.h"
#include "md.h"
#include "skl.h"
#include "skl_bit_test.h"
#include "skl_cond.h"
#include "skl_ctrl_reg.h"
#include "skl_fp_reg.h"
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

    memory_t initial_stack;

    const char *reg_bank[2] = {
        "R",
        "F"
    };

    cpu_t    cpu_;
    memory_t memory;


    void
    initialize_memory(md::OADDR membeg, int n_bytes)
    {
        memory.beg     = membeg;
        memory.end     = membeg + static_cast<md::OADDR>(n_bytes);
        memory.n_bytes = n_bytes;
    }


    static void
    dump_cpu_stack(skl::cpuid_t cpu)
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

        if (sp >= initial_stack.end - sizeof(md::uint32)) {
            /* At startup, with an empty stack, SP will be one word
             * above the topmost stack element, because the SP is
             * predecrement.
             */
            stack_words = 0;
        } else {
            stack_words = static_cast<int>((initial_stack.end - sp) /
                                           static_cast<int>(sizeof(md::uint32)));
        }

        if (stack_words > 0) {
            dialog::cpu("Stack [%xH..%xH) [%xH words]\n",
                        initial_stack.beg, initial_stack.end, /* [beg..end) */
                        stack_words);
            i = 0;
            do {
                p = sp + static_cast<md::uint32>(i * static_cast<int>(sizeof(md::uint32)));
                v = skl::read(cpu, p, false, sizeof(md::uint32));

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
    dump_control_registers(skl::cpuid_t cpuid)
    {
        if (false) {
            skl::cpu_t *cpu = skl::cpuid_to_cpu(cpuid);
            dialog::cpu("CR0: %8.8xH [exception address]\n", cpu->CR_[0]);
            dialog::cpu("CR1: %8.8xH [hardware exception handler]\n", cpu->CR_[1]);
            dialog::cpu("CR2: %8.8xH [exception status]\n", cpu->CR_[2]);
            dialog::cpu("CR5: %8.8xH [Software exception handler]\n", cpu->CR_[5]);
            dialog::cpu("\n");
        }
    }


    void
    dump_cpu__(skl::cpuid_t cpuid)
    {
        skl::cpu_t      *cpu                  = skl::cpuid_to_cpu(cpuid);
        bool             dump_float_registers = true;
        int              i;
        O3::decode_pc_t  decoded_pc;

        if (config::options & config::opt_trace_cpu) {
            O3::decode_pc(skl::program_counter(cpuid), decoded_pc);
            dialog::cpu("pc : %s  (%xH)\n", decoded_pc,
                        skl::program_counter(cpuid));
            dump_control_registers(cpuid);

            i = 0;
            while (i < static_cast<int>(sizeof(cpu->R_) /
                                        sizeof(cpu->R_[0]))) {
                dialog::cpu("R%-2u: %8.8xH", i, cpu->R_[i]);
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
                while (i < static_cast<int>(sizeof(cpu->F_) /
                                            sizeof(cpu->F_[0]))) {
                    dialog::cpu("F%-2u: %e", i, cpu->F_[i]);
                    ++i;
                    if ((i % 3) == 0) {
                        dialog::cpu("\n");
                    } else {
                        dialog::cpu("  ");
                    }
                }
            }
            dialog::cpu("\n");
            dump_cpu_stack(cpuid);
        }
    }

    void
    software_trap(skl::cpuid_t cpuid, int trap)
    {
        write_integer_register(cpuid, 1,
                               static_cast<md::uint32>(trap)); // Trap code.
        write_integer_register(cpuid, 31, skl::program_counter(cpuid));  // Return address.
        set_program_counter(cpuid, read_control_register(cpuid, CR5)); // Kernel.SysTrap
        set_exception_raised(cpuid, true);
    }


    static int
    process_cr2_active(skl::cpuid_t cpuid)
    {
        int        active;      // CR2 Active field, bits 6..5.
        md::uint32 cr2 = skl::read_control_register(cpuid, CR2);

        active = static_cast<int>(((cr2 >> 5) & 3)) + 1;
        if (active < 2) {
            return active << 5;
        } else {
            dialog::fatal("Hardware trap raised while processing "
                          "hardware trap.");
            return 0;
        }
    }

    void
    hardware_trap(skl::cpuid_t cpuid, control_register_2_t trap)
    {
        md::uint32 cr2;
        int        active = process_cr2_active(cpuid);

        write_control_register(cpuid, CR0,
                               skl::program_counter(cpuid)); // Exception address.
        cr2 = static_cast<md::uint32>(active   | /* Bits 6..5.  Pre-shifted. */
                                      trap     | /* Bits 4..2.  Pre-shifted. */
                                      (0 << 1) | /* Bit 1: interrupt enable
                                                  *        (unsupported). */
                                      (1 << 0)); /* Bit 0: Processor trap. */
        write_control_register(cpuid, CR2, cr2);
        set_program_counter(cpuid,
                            read_control_register(cpuid, CR1)); // Kernel.HardwareTrap
        set_exception_raised(cpuid, true);
    }


    static inline opcode_class_t
    classof(md::OINST inst)
    {
        int v = field(inst, 31, 26);
        if (UNLIKELY(v > N_OPCODE_CLASSES)) {
            v = N_OPCODE_CLASSES; // Invalid opcode.
        }
        return static_cast<opcode_class_t>(v);
    }


    static md::uint32
    fetch_instruction(cpuid_t cpu, md::OADDR pc)
    {
        md::uint32 inst;

        if (LIKELY(aligned(pc, static_cast<int>(sizeof(md::uint32))))) {
            inst = skl::read(cpu, pc, false, sizeof(md::uint32));
            return inst;
        } else {
            hardware_trap(cpu, CR2_BAD_ALIGNMENT);
            return ~0U;         // Causes classof() to return invalid.
        }
    }

    static skl::instruction_t *
    fetch_and_cache_instruction(skl::cpuid_t cpuid)
    {
        md::OINST           inst;
        opcode_class_t      cls;
        skl::instruction_t *cinst = NULL;
        md::OADDR           pc    = skl::program_counter(cpuid);

        dump_cpu(cpuid);
        set_exception_raised(cpuid, false);
        inst = skl::fetch_instruction(cpuid, pc);
        cls  = classof(inst);

        switch (cls) {
        case OC_GEN_REG:
            cinst = op_gen_reg(pc, inst);
            break;

        case OC_INT_REG:
            cinst = op_int_reg(pc, inst);
            break;

        case OC_SIGN_EXT:
            dialog::not_implemented("%s: OC_SIGN_EXT", __func__);
            break;

        case OC_CTL_REG:
            cinst = op_ctrl_reg(pc, inst);
            break;

        case OC_SYS_REG:
            cinst = op_sys_reg(pc, inst);
            break;

        case OC_MISC:
            cinst = op_misc(pc, inst);
            break;

        case OC_JRAL:
            cinst = op_jral(pc, inst);
            break;

        case OC_JUMP:
            cinst = op_jump(cpuid, pc, inst);
            break;

        case OC_REG_MEM:
            cinst = op_reg_mem(cpuid, pc, inst);
            break;

        case OC_BIT_TEST:
            cinst = op_bit_test(pc, inst);
            break;

        case OC_STACK:
            cinst = op_stack(pc, inst);
            break;

        case OC_CONDITIONAL_SET:
            cinst = op_conditional_set(pc, inst);
            break;

        case OC_SYSTRAP:
            cinst = op_systrap(pc, inst);
            break;

        case OC_FP_REG:
            cinst = op_fp_reg(pc, inst);
            break;

        default:
            hardware_trap(cpuid, CR2_INVALID_OPCODE);
            return NULL;
        }
        assert(cinst != NULL);
        skl::cache_instruction(cinst);
        return cinst;
    }


    static skl::instruction_t *
    fetch_cached_instruction(skl::cpuid_t cpu)
    {
        skl::instruction_t *cinst = skl::lookup_instruction(skl::program_counter(cpu));
        return cinst;
    }


    void
    execute(skl::cpuid_t cpuid, md::OADDR addr)
    {
        skl::instruction_t *next;
        skl::instruction_t *cinst;

        skl::set_program_counter(cpuid, addr);
        next    = fetch_cached_instruction(cpuid);
        while (1) {
            cinst = next;
            if (UNLIKELY(read_integer_register(cpuid, 0) != 0)) {
                write_integer_register(cpuid, 0, 0); // Reset R0 to zero.
            }

            if (UNLIKELY(cinst == NULL)) {
                cinst = fetch_and_cache_instruction(cpuid);
            }

            /* cinst == NIL --> Invalid opcode. */
            if (LIKELY(cinst != NULL)) {
                cinst->interpret(cpuid);
                skl::increment_instruction_count(cpuid);
                next = cinst->next;
                if (UNLIKELY(next == NULL ||
                             next->pc != skl::program_counter(cpuid))) {
                    next = fetch_cached_instruction(cpuid);
                    cinst->next = next;
                }
            } else {
                /* Verify hardware trap raised. */
                assert(skl::program_counter(cpuid) ==
                       read_control_register(cpuid, CR1));
            }
        }
    }


    register_bank_t
    compute_using(register_bank_t R0,
                  register_bank_t R1)
    {
        bool dbl = R0 == RB_DOUBLE || R1 == RB_DOUBLE;
        if (UNLIKELY(dbl)) {
            return RB_DOUBLE;
        }
        return RB_INTEGER;
    }


    md::uint32
    register_as_integer(skl::cpuid_t    cpuid,
                        int             regno,
                        register_bank_t bank)
    {
        if (LIKELY(bank == RB_INTEGER)) {
            return read_integer_register(cpuid, regno);
        } else {
            assert(bank == RB_DOUBLE);
            return static_cast<md::uint32>(read_real_register(cpuid, regno));
        }
    }

    double
    register_as_double(cpuid_t         cpuid,
                       int             regno,
                       register_bank_t bank)
    {
        if (LIKELY(bank == RB_INTEGER)) {
            return read_integer_register(cpuid, regno);
        } else {
            assert(bank == RB_DOUBLE);
            return read_real_register(cpuid, regno);
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
        skl::initial_stack.end = stack_top;
        skl::initial_stack.beg = heap::heap_address(heap::oberon_stack);

        /* It's important to give { SP, SFP } the same value so that
         * the stack dumping logic can terminate easily in
         * skl::dump_cpu_stack().
         */
        write_integer_register(skl::BOOT_CPU, SP, stack_top);
        write_integer_register(skl::BOOT_CPU, SFP, stack_top);
    }
}
