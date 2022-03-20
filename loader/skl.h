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

    typedef enum exception_t {
        E_STACK_UNDERFLOW,
        E_STACK_OVERFLOW
    } exception_t;

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
        CR5,                    // Kernel.SysTrap address (set by SKLKernel.Mod)
        N_CONTROL_REGISTERS
    } control_registers_t;

    typedef enum control_register_2_t {
        CR2_CAUSE                = (1 << 0),

        CR2_INTERRUPT            = (1 << 1),

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
        md::OADDR    ea;                       // Computed effective address.
        md::OADDR    pc;
        md::uint32   _instruction_count;
        md::uint32   _CR[N_CONTROL_REGISTERS]; // Control registers.
        md::uint32   _R[32];                   // 32 integer registers.
        double       _F[32];                   // 32 IEEE 754 double registers.


        /* exception_raised:
         *
         *   When true, indicates the current instruction raised an
         *   exception.  The side effects of the instruction (such as
         *   storing to the destination register) cannot occur.
         *
         *   It's reset to false at the beginning of instruction fetch.
         */
        bool         exception_raised;
    } cpu_t;

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


    extern cpu_t       cpu;
    extern memory_t    memory;
    extern const char *reg_bank[2];

    /* The bootstrap loader sets the stack information here.  It is
     * used bound stack dumping when printing the CPU state.
     */
    extern md::OADDR initial_stack_bot;
    extern md::OADDR initial_stack_top;

    void initialize_memory(md::OADDR membeg, int n_bytes);
    void initialize_stack(void);

    register_bank_t compute_using(register_bank_t R0, register_bank_t R1);

    void execute(cpu_t *cpu, md::OADDR addr);

    void write(md::OADDR addr, md::uint32 val, int size);

    md::uint32 register_as_integer(cpu_t           *cpu,
                                   int              regno,
                                   register_bank_t  bank);

    double register_as_double(cpu_t           *cpu,
                              int              regno,
                              register_bank_t  bank);

    void software_trap(cpu_t *cpu, int trap);
    void hardware_trap(cpu_t *cpu, control_register_2_t trap);

    void dump_cpu__(cpu_t *cpu);
    static inline void
    dump_cpu(cpu_t *cpu)
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
        unsigned r    = (inst >> lo); // Shift field to bit 0.
        unsigned mask = ((1U << (hi - lo + 1)) - 1);
        return static_cast<int>(r & mask);
    }


    static inline md::uint32
    increment_words(int n_words)
    {
        return static_cast<md::uint32>(n_words *
                                       static_cast<int>(sizeof(md::uint32)));
    }

    static inline void
    increment_pc(cpu_t *cpu, int n_words)
    {
        cpu->pc += increment_words(n_words);
    }


    static inline md::uint32
    read_integer_register(cpu_t *cpu, int regno)
    {
        assert(regno < static_cast<int>(sizeof(cpu->_R) / sizeof(cpu->_R[0])));
        assert(regno != 0 || cpu->_R[regno] == 0);
        return cpu->_R[regno];
    }


    static inline void
    write_integer_register(cpu_t *cpu, int regno, md::uint32 value)
    {
        assert(regno < static_cast<int>(sizeof(cpu->_R) / sizeof(cpu->_R[0])));
        cpu->_R[regno] = value;
    }


    static inline void
    write_real_register(cpu_t *cpu, int regno, double value)
    {
        assert(regno < static_cast<int>(sizeof(cpu->_F) / sizeof(cpu->_F[0])));
        cpu->_F[regno] = value;
    }


    static inline double
    read_real_register(cpu_t *cpu, int regno)
    {
        assert(regno < static_cast<int>(sizeof(cpu->_F) / sizeof(cpu->_F[0])));
        return cpu->_F[regno];
    }


    static inline void
    write_control_register(cpu_t               *cpu,
                           control_registers_t  regno,
                           md::uint32           value)
    {
        assert(regno < sizeof(cpu->_CR) / sizeof(cpu->_CR[0]));
        cpu->_CR[regno] = value;
    }


    static inline md::uint32
    read_control_register(cpu_t *cpu, control_registers_t regno)
    {
        assert(regno < sizeof(cpu->_CR) / sizeof(cpu->_CR[0]));
        return cpu->_CR[regno];
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

    /* Returns true if:
     *
     *   [acc_beg, acc_beg + n_bytes)
     *
     * is in
     *
     *   [mem_beg, mem_end).
     */
    static inline bool
    memory_access_ok(const memory_t *memory,
                     md::OADDR       acc_beg,
                     int             n_bytes)
    {
        /* [acc_beg, acc_beg + n_bytes) IN [memory->beg, memory->end) */
        md::uint32 acc_end = acc_beg + static_cast<md::uint32>(n_bytes);
        return (memory->beg <= acc_beg &&
                acc_end < memory->end);
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
        return (aligned(ea, size) &&
                memory_access_ok(&memory, ea, size));
    }


    static inline void
    compute_effective_address(cpu_t      *cpu,
                              md::uint32  base,
                              md::uint32  index,
                              int         scale,
                              int         offset)
    {
        md::uint32 scaled_index = index * static_cast<md::uint32>(scale);

        assert(scale == 1 || scale == 2 || scale == 4 || scale == 8);
        cpu->ea = base + scaled_index  + static_cast<md::uint32>(offset);
    }


    static inline md::uint32
    read_1(md::OADDR addr, bool sign_extend)
    {
        md::HADDR p = heap::heap_to_host(addr);
        if (sign_extend) {
            md::int8  i8  = *reinterpret_cast<md::int8 *>(p);
            md::int32 i32 = static_cast<md::int32>(i8);
            return static_cast<md::uint32>(i32);
        } else {
            return *reinterpret_cast<md::uint8 *>(p);
        }
    }


    static inline md::uint32
    read_2(md::OADDR addr, bool sign_extend)
    {
        md::HADDR p = heap::heap_to_host(addr);

        if (sign_extend) {
            md::int16 i16 = *reinterpret_cast<md::int16 *>(p);
            md::int32 i32 = static_cast<md::int32>(i16);
            return static_cast<md::uint32>(i32);
        } else {
            return *reinterpret_cast<md::uint16 *>(p);
        }
    }


    static inline md::uint32
    read_4(md::OADDR addr, bool sign_extend)
    {
        md::HADDR p = heap::heap_to_host(addr);
        if (sign_extend) {
            /* This sign-extension only makes sense if the VM
             * supports memory access more than 32-bits. */
            md::int32 i32 = *reinterpret_cast<md::int32 *>(p);
            return static_cast<md::uint32>(i32);
        } else {
            return *reinterpret_cast<md::uint32 *>(p);
        }
    }


    static inline md::uint32
    read(md::OADDR addr, bool sign_extend, int size)
    {
        if (LIKELY(address_valid(addr, size))) {
            if (size == 1) {
                return read_1(addr, sign_extend);
            } else if (size == 2) {
                return read_2(addr, sign_extend);
            } else {
                assert(size == 4);
                return read_4(addr, sign_extend);
            }
        } else {
            hardware_trap(&cpu, CR2_OUT_OF_BOUNDS_READ);
            return ~0U; // Value ignored, because CPU does not return.
        }
    }
}
#endif
