/* Copyright (c) 2000, 2020, 2021, 2022 Logic Magicians Software */
#if !defined(_SKL_H)
#define _SKL_H
#include <assert.h>

#include "config.h"
#include "md.h"
#include "heap.h"

namespace skl
{
    const int SFP    = 29; /* (LMCGL.Mod) Stack Frame Pointer. */
    const int SP     = 30; /* (LMCGL.Mod) Stack Pointer. */
    const int RETADR = 31; /* Hardware-defined.  Return address. */

    typedef enum memory_access_t {
        MA_BYTE,
        MA_HALF_WORD,
        MA_WORD,
        MA_DOUBLE_WORD
    } memory_access_t;

    typedef enum control_registers_t {
        CR0,                    // Exception return address.
        CR1,                    // Exception handler address.
        CR2,                    // CPU Status.
        CR3_RESVERVED,
        CR4_RESVERVED,
        CR5,                    // Kernel.SysTrap address (set by Kernel.Mod)
        N_CONTROL_REGISTERS
    } control_registers_t;

    typedef enum control_register_2_t {
        CR2_CAUSE                = (1 << 0),

        CR2_RESERVED_2           = (1 << 1), /* Reserved for interrupts. */

        CR2_INVALID_OPCODE       = (0 << 2),
        CR2_BREAK                = (1 << 2),
        CR2_BAD_ALIGNMENT        = (2 << 2),
        CR2_OUT_OF_BOUNDS_READ   = (3 << 2),
        CR2_OUT_OF_BOUNDS_WRITE  = (4 << 2),
        CR2_DIVIDE_BY_ZERO       = (5 << 2),
        CR2_RESERVED_0           = (6 << 2),
        CR2_RESERVED_1           = (7 << 2)
    } control_register_2_t;

    typedef enum register_bank_t {
        RB_INTEGER,
        RB_DOUBLE
    } register_bank_t;


    typedef struct cpu_t {
        md::OADDR    pc_;
        md::uint32   instruction_count_;
        md::uint32   CR_[N_CONTROL_REGISTERS]; // Control registers.
        md::uint32   R_[32];                   // 32 integer registers.
        double       F_[32];                   // 32 IEEE 754 double registers.


        /* exception_raised:
         *
         *   When true, indicates the current instruction raised an
         *   exception.  The side effects of the instruction (such as
         *   storing to the destination register) cannot occur.
         *
         *   It's reset to false at the beginning of instruction fetch.
         */
        bool         exception_raised_;
    } cpu_t;

    typedef enum cpuid_t {
        BOOT_CPU = 0,
        CPU_0    = 0,
        N_CPUS
    } cpuid_t;

    typedef struct memory_t {   // Memory: [beg, end)
        md::OADDR beg;
        md::OADDR end;
        int       n_bytes;
    } memory_t;


    typedef enum effective_address_kind_t {
        EA_LOAD,
        EA_STORE,
        EA_COMPUTE,
        N_EA_KIND
    } effective_address_kind_t;


    extern memory_t    memory;
    extern const char *reg_bank[2];

    /* The bootstrap loader sets the stack information here.  It is
     * used bound stack dumping when printing the CPU state.
     */
    extern memory_t    initial_stack;


    void initialize_memory(md::OADDR membeg, int n_bytes);
    void initialize_stack(void);

    register_bank_t compute_using(register_bank_t R0, register_bank_t R1);

    void execute(skl::cpuid_t cpu, md::OADDR addr);

    md::uint32 register_as_integer(cpuid_t         cpu,
                                   int             regno,
                                   register_bank_t bank);

    double register_as_double(cpuid_t         cpu,
                              int             regno,
                              register_bank_t bank);

    void software_trap(skl::cpuid_t cpu, int trap);
    void hardware_trap(skl::cpuid_t cpu, control_register_2_t trap);

    void dump_cpu__(skl::cpuid_t cpu);
    static inline void
    dump_cpu(skl::cpuid_t cpu)
    {
        if (UNLIKELY(skl_trace)) {
            dump_cpu__(cpu);
        }
    }


    static inline int
    mask_shift_bits(int b)
    {
        return b & 31;          // Shift no more than 5 bits.
    }


    /* left_shift: Logical shift left. */
    static inline unsigned
    left_shift(md::uint32 v, int bits)
    {
        return v << mask_shift_bits(bits);
    }


    /* right_shift: Logical shift right. */
    static inline unsigned
    right_shift(md::uint32 v, int bits)
    {
        return v >> mask_shift_bits(bits);
    }


    static inline int
    field(md::uint32 inst, int hi, int lo)
    {
        // Extract bits [hi, lo] from inst.
        unsigned r    = (inst >> lo); // Shift field to bit 0.
        unsigned mask = ((1U << (hi - lo + 1)) - 1);

        assert(hi >= lo);
        return static_cast<int>(r & mask);
    }


    static inline skl::cpu_t *
    cpuid_to_cpu(skl::cpuid_t cpuid)
    {
        extern skl::cpu_t cpu_;
        return &cpu_;
    }


    static inline md::uint32
    increment_words(int n_words)
    {
        return static_cast<md::uint32>(n_words *
                                       static_cast<int>(sizeof(md::uint32)));
    }


    static inline void
    increment_instruction_count(skl::cpuid_t cpuid)
    {
        skl::cpu_t *cpu = skl::cpuid_to_cpu(cpuid);
        cpu->instruction_count_++;
    }


    static inline md::uint32
    instruction_count(skl::cpuid_t cpuid)
    {
        skl::cpu_t *cpu = skl::cpuid_to_cpu(cpuid);
        return cpu->instruction_count_;
    }


    static inline bool
    exception_raised(skl::cpuid_t cpuid)
    {
        skl::cpu_t *cpu = skl::cpuid_to_cpu(cpuid);
        return cpu->exception_raised_;
    }


    static inline void
    set_exception_raised(skl::cpuid_t cpuid, bool value)
    {
        skl::cpu_t *cpu = skl::cpuid_to_cpu(cpuid);
        cpu->exception_raised_ = value;
    }


    static inline md::uint32
    program_counter(skl::cpuid_t cpuid)
    {
        skl::cpu_t *cpu = skl::cpuid_to_cpu(cpuid);
        return cpu->pc_;
    }


    static inline void
    set_program_counter(skl::cpuid_t cpuid, md::uint32 pc)
    {
        skl::cpu_t *cpu = skl::cpuid_to_cpu(cpuid);
        cpu->pc_ = pc;
    }


    static inline void
    increment_pc(skl::cpuid_t cpuid, int n_words)
    {
        set_program_counter(cpuid, (program_counter(cpuid) +
                                    increment_words(n_words)));
    }


    static inline md::uint32
    read_integer_register(skl::cpuid_t cpuid, int regno)
    {
        skl::cpu_t *cpu = skl::cpuid_to_cpu(cpuid);
        assert(regno < static_cast<int>(sizeof(cpu->R_) / sizeof(cpu->R_[0])));
        return cpu->R_[regno];
    }


    static inline void
    write_integer_register(skl::cpuid_t cpuid, int regno, md::uint32 value)
    {
        skl::cpu_t *cpu = skl::cpuid_to_cpu(cpuid);
        assert(regno < static_cast<int>(sizeof(cpu->R_) / sizeof(cpu->R_[0])));
        cpu->R_[regno] = value;
    }


    static inline void
    write_real_register(skl::cpuid_t cpuid, int regno, double value)
    {
        skl::cpu_t *cpu = skl::cpuid_to_cpu(cpuid);
        assert(regno < static_cast<int>(sizeof(cpu->F_) / sizeof(cpu->F_[0])));
        cpu->F_[regno] = value;
    }


    static inline double
    read_real_register(skl::cpuid_t cpuid, int regno)
    {
        skl::cpu_t *cpu = skl::cpuid_to_cpu(cpuid);
        assert(regno < static_cast<int>(sizeof(cpu->F_) / sizeof(cpu->F_[0])));
        return cpu->F_[regno];
    }


    static inline void
    write_control_register(cpuid_t             cpuid,
                           control_registers_t regno,
                           md::uint32          value)
    {
        skl::cpu_t *cpu = skl::cpuid_to_cpu(cpuid);
        assert(regno < sizeof(cpu->CR_) / sizeof(cpu->CR_[0]));
        cpu->CR_[regno] = value;
    }


    static inline md::uint32
    read_control_register(skl::cpuid_t cpuid, control_registers_t regno)
    {
        skl::cpu_t *cpu = skl::cpuid_to_cpu(cpuid);
        assert(regno < sizeof(cpu->CR_) / sizeof(cpu->CR_[0]));
        return cpu->CR_[regno];
    }

    static inline bool
    aligned(md::OADDR addr, int size)
    {
        assert((size & (size - 1)) == 0); // inv: power-of-2.

        /* NOTE:
         *
         *   Enabling memory alignment is not possible unless all
         *   variable allocation is done differently.
         *
         *   This is because copying a string to the stack (for a
         *   non-var array) uses 'push'.  The string being put onto
         *   the stack may not be aligned to a word boundary for the
         *   push.  If every variable is aligned, then memory
         *   alignment can be turned on.  But, really, why?  There is
         *   no hardware penalty for not having it misaligned.
         */
        return true || (addr & (size - 1)) == 0;
    }


    /* address_valid
     *
     *  Returns 'true' iff the address is within the bounds of memory,
     *  and it is aligned to natural alignment to access 'size' bytes.
     *
     */
    static inline bool
    address_valid(md::OADDR ea, int size)
    {
        bool beg_ok = memory.beg <= ea;
        bool end_ok = ea + static_cast<md::uint32>(size) < memory.end;
        return beg_ok & end_ok;
    }


    static inline md::OADDR
    compute_effective_address(skl::cpuid_t cpu,
                              int          Rbase,
                              int          Rindex,
                              int          scale,
                              int          offset)
    {
        md::uint32 scaled_index;
        md::uint32 base  = read_integer_register(cpu, Rbase);
        md::uint32 index = read_integer_register(cpu, Rindex);

        assert(scale == 0 ||  /* index * 1 */
               scale == 1 ||  /* index * 2 */
               scale == 2 ||  /* index * 4 */
               scale == 3);   /* index * 8 */
        scaled_index = index << static_cast<md::uint32>(scale);
        return base + scaled_index + static_cast<md::uint32>(offset);
    }


    static inline md::uint32
    read_1_se(md::HADDR p)
    {
        md::int8  i8  = *reinterpret_cast<md::int8 *>(p);
        md::int32 i32 = static_cast<md::int32>(i8);
        return static_cast<md::uint32>(i32);
    }


    static inline md::uint32
    read_1_ze(md::HADDR p)
    {
        return *reinterpret_cast<md::uint8 *>(p);
    }


    static inline md::uint32
    read_2_se(md::HADDR p)
    {
        md::int16 i16 = *reinterpret_cast<md::int16 *>(p);
        md::int32 i32 = static_cast<md::int32>(i16);
        return static_cast<md::uint32>(i32);
    }


    static inline md::uint32
    read_2_ze(md::HADDR p)
    {
        return *reinterpret_cast<md::uint16 *>(p);
    }


    static inline md::uint32
    read_4_se(md::HADDR p)
    {
        md::int32 i32 = *reinterpret_cast<md::int32 *>(p);
        return static_cast<md::uint32>(i32);
    }


    static inline md::uint32
    read_4_ze(md::HADDR p)
    {
        return *reinterpret_cast<md::uint32 *>(p);
    }


    static inline md::uint32
    read(skl::cpuid_t cpu, md::OADDR addr, bool sign_extend, int size)
    {
        if (LIKELY(address_valid(addr, size))) {
            md::HADDR p = heap::heap_to_host(addr);
            if (size == 1) {
                if (sign_extend) {
                    return read_1_se(p);
                } else {
                    return read_1_ze(p);
                }
            } else if (size == 2) {
                if (sign_extend) {
                    return read_2_se(p);
                } else {
                    return read_2_ze(p);
                }
            } else {
                assert(size == 4);
                if (sign_extend) {
                    return read_4_se(p);
                } else {
                    return read_4_ze(p);
                }
            }
        } else {
            hardware_trap(cpu, CR2_OUT_OF_BOUNDS_READ);
            return ~0U; // Value ignored, because CPU does not return.
        }
    }


    static inline void
    write_1(skl::cpuid_t cpu, md::HADDR p, md::uint8 val)
    {
        md::uint8 v = static_cast<md::uint8>(val);
        *reinterpret_cast<md::uint8 *>(p) = v;
    }


    static inline void
    write_2(skl::cpuid_t cpu, md::HADDR p, md::uint16 val)
    {
        md::uint16 v = static_cast<md::uint16>(val);
        *reinterpret_cast<md::uint16 *>(p) = v;
    }


    static inline void
    write_4(skl::cpuid_t cpu, md::HADDR p, md::uint32 val)
    {
        *reinterpret_cast<md::uint32 *>(p) = val;
    }


    static inline void
    write(skl::cpuid_t cpu, md::OADDR addr, md::uint32 val, int size)
    {
        if (LIKELY(address_valid(addr, size))) {
            md::HADDR p = heap::heap_to_host(addr);
            if (size == 1) {
                write_1(cpu, p, static_cast<md::uint8>(val));
            } else if (size == 2) {
                write_2(cpu, p, static_cast<md::uint16>(val));
            } else {
                assert(size == 4);
                write_4(cpu, p, val);
            }
        } else {
            hardware_trap(cpu, CR2_OUT_OF_BOUNDS_WRITE);
        }
    }
}
#endif
