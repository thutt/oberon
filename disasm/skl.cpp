/* Copyright (c) 2000, 2021-2023 Logic Magicians Software */
#include <assert.h>
#include <math.h>
#include <stdio.h>

#include "global.h"
#include "buildenv.h"
#include "objio.h"
#include "skl.h"

namespace skl
{
    const unsigned mnemonic_width = 10;
    typedef unsigned char byte_t;
    typedef unsigned int  word_t;

    typedef enum _instruction_class_t {
        ic_general_register         = 0,
        ic_integer_register         = 1,
        ic_sign_extension           = 2,
        ic_control_register         = 3,
        ic_system_register          = 4,
        ic_misc                     = 5,
        ic_jump_register_and_link   = 6,
        ic_branch                   = 7,
        ic_reg_mem                  = 8,
        ic_bt                       = 9,
        ic_stack                    = 10,
        ic_conditional_set          = 11,
        ic_systrap                  = 12,
        ic_floating_point_reg       = 13,

        NUM_INSTRUCTION_CLASS
    } instruction_class_t;

    typedef struct output_t {
        char        address[4     + 1]; // '0000'
        char        data[3][8     + 1]; // Upto 3 8-character opcode words, + spaces.
        char        operand[3][32 + 1]; // Upto three operands' data.
        const char *mne;
    } output_t;

    typedef void (*decode_instruction_t)(word_t inst);

    static void decode_general_register(word_t inst);
    static void decode_integer_register(word_t inst);
    static void decode_floating_point_register(word_t inst);
    static void decode_sign_extension(word_t inst);
    static void decode_control_register(word_t inst);
    static void decode_system_register(word_t inst);
    static void decode_misc(word_t inst);
    static void decode_jump_register_and_link(word_t inst);
    static void decode_branch(word_t inst);
    static void decode_reg_mem(word_t inst);
    static void decode_bt(word_t inst);
    static void decode_stack(word_t inst);
    static void decode_conditional_set(word_t inst);
    static void decode_systrap(word_t inst);
    static void decode_invalid_opcode(word_t inst);

    static char const * const register_bank[] = {
        "R",                    // SHORTINT, INTEGER, LONGINT, SET, POINTER
        "F",                    // REAL (float), LONGREAL (double)
    };


    static decode_instruction_t decoder[NUM_INSTRUCTION_CLASS + 1] = {
        /* [ic_general_register] */       decode_general_register,
        /* [ic_integer_register] */       decode_integer_register,
        /* [ic_sign_extension] */         decode_sign_extension,
        /* [ic_control_register] */       decode_control_register,
        /* [ic_system_register] */        decode_system_register,
        /* [ic_misc] */                   decode_misc,
        /* [ic_jump_register_and_link] */ decode_jump_register_and_link,
        /* [ic_branch] */                 decode_branch,
        /* [ic_reg_mem] */                decode_reg_mem,
        /* [ic_bt] */                     decode_bt,
        /* [ic_stack] */                  decode_stack,
        /* [ic_conditional_set] */        decode_conditional_set,
        /* [ic_systrap] */                decode_systrap,
        /* [ic_floating_point_reg] */     decode_floating_point_register,
        /* [NUM_INSTRUCTION_CLASS] */     decode_invalid_opcode,
    };


    static int     pc;
    static byte_t *code_base;

    static inline void
    pc_init(byte_t *code, int p)
    {
        code_base = code;
        assert(p % static_cast<int>(sizeof(word_t)) == 0);
        pc = p;
    }


    static const char *
    format_hex(int v)
    {
        static char buf[16];
        char sprintf_buf[16];   // Avoids gcc error that says buffer is ALWAYS overrun.

        snprintf(sprintf_buf, sizeof(sprintf_buf) / sizeof(sprintf_buf[0]),
                 "%XH", v);
        buf[0] = '0';
        strcpy(&buf[1], sprintf_buf);
        if (buf[1] >= 'A') {
            return buf;
        } else {
            return &buf[1];
        }
    }


    static const char *
    _format_hex(int v)
    {
        if (!::show_dashes) {
            return format_hex(v);
        } else {
            return "-----";
        }
    }


    static inline word_t
    get_next_word(void)
    {
        word_t result;

        assert(pc % static_cast<int>(sizeof(word_t)) == 0);
        result = *reinterpret_cast<word_t *>(&code_base[pc]);
        pc     += 4;
        return result;
    }


    static unsigned field(word_t inst, unsigned hi, unsigned lo)
    {
        unsigned r    = (inst >> lo); // Shift field to bit 0.
        unsigned mask = ((1U << (hi - lo + 1)) - 1);
        return r & mask;
    }

    static void print_header(int pc, word_t inst)
    {
        /* pc is incremented with each instruction fetch; adjust for
         * display */
        if (!::show_dashes) {
            printf("%4.4x:  %8.8x %8s %8s   ", pc - 4, inst, " ", " ");
        } else {
            printf("%4s   %8s %8s %8s   ", " ", " ", " ", " ");
        }
    }


    static void print_header_2(int pc, word_t i0, word_t i1)
    {
        /* pc is incremented with each instruction fetch; adjust for
         * display */
        if (!::show_dashes) {
            printf("%4.4x:  %8.8x %8.8x %8s   ", pc - 4, i0, i1, " ");
        } else {
            printf("%4s   %8s %8s %8s   ", " ", " ", " ", " ");
        }
    }


    static void print_header_3(int pc, word_t i0, word_t i1, word_t i2)
    {
        /* pc is incremented with each instruction fetch; adjust for
         * display */
        if (!::show_dashes) {
            printf("%4.4x:  %8.8x %8.8x %8.8x   ", pc - 4, i0, i1, i2);
        } else {
            printf("%4s   %8s %8s %8s   ", " ", " ", " ", " ");
        }
    }


    const char *decode_mem_ref(unsigned Rbase,
                               unsigned Rindex,
                               unsigned S,
                               unsigned offset)
    {
        char const * const scale[] = { // Indexed by 2 bits.
            "1",
            "2",
            "4",
            "8",
        };
        char        sign = '+';
        static char buffer[200];
        int offs = static_cast<int>(offset);

        if (offs < 0) {
            offs = abs(offs);
            sign   = '-';
        }
        if (Rbase != 0 && Rindex != 0) { /* Base.  Index. */
            snprintf(buffer, sizeof(buffer) / sizeof(buffer[0]),
                     "(R%d + R%d:%s %c %s)",
                     Rbase, Rindex, scale[S], sign, format_hex(offs));
        } else if (Rbase != 0 && Rindex == 0) { /* Base.  No index. */
            snprintf(buffer, sizeof(buffer) / sizeof(buffer[0]),
                     "(R%d %c %s)", Rbase, sign, format_hex(offs));
        } else if (Rbase == 0 && Rindex != 0) { /* No base.  Index */
            snprintf(buffer, sizeof(buffer) / sizeof(buffer[0]),
                     "(R%d:%s %c %XH)",
                     Rindex, scale[S], sign, offs);
        } else {                         /* No base.  No index. */
            assert(Rbase == 0 && Rindex == 0);
            snprintf(buffer, sizeof(buffer) / sizeof(buffer[0]),
                     "(%c%s)", sign, format_hex(offs));
        }

        return buffer;
    }


    static void decode_reg_mem(word_t inst)
    {
        static char const * const mne[] = {
            "lb",
            "lbu",
            "ld",
            "ldi",
            "lf",
            "lfi",
            "lh",
            "lhu",
            "lw",
            "lwi",
            "sb",
            "sd",
            "sf",
            "sh",
            "sw",
            "la",
        };
        unsigned    Rd     = field(inst, 25, 21);
        unsigned    Rbase  = field(inst, 20, 16);
        unsigned    Rindex = field(inst, 15, 11);
        unsigned    S      = field(inst,  7,  6);
        unsigned    opc    = field(inst,  4,  0);

        switch (opc) {
        case 0:                 // lb
        case 1:                 // lbu
        case 2:                 // ld
        case 4:                 // lf
        case 6:                 // lh
        case 7:                 // lhu
        case 8:                 // lw
        case 15:                // la
        {
            const char *mem_ref;
            unsigned    bank   = 0; // Integer registers.
            word_t      offset = get_next_word();

            if (opc == 2 || opc == 4) {
                bank = 1;       // REAL / LONGREAL registers.
            }

            mem_ref = decode_mem_ref(Rbase, Rindex, S, offset);
            print_header_2(pc - 4, inst, offset);
            printf("%-*s  %s, %s%d\n",
                       mnemonic_width, mne[opc], mem_ref, register_bank[bank], Rd);
            break;
        }

        case 3:                 // ldi
        {
            union {
                struct {
                    word_t lo;
                    word_t hi;
                } halves;
                double d;
            } u;

            COMPILE_TIME_ASSERT(skl_endian_little);
            assert(sizeof(u.d) == sizeof(u.halves));
            u.halves.lo = get_next_word();
            u.halves.hi = get_next_word();
            print_header_3(pc - 8, inst, u.halves.lo, u.halves.hi);
            printf("%-*s  %E, F%d\n", mnemonic_width, mne[opc], u.d, Rd);
            break;
        }

        case 5:                 // lfi
        {
            union {
                word_t w;
                float  f;
            } v;
            COMPILE_TIME_ASSERT(skl_endian_little);
            v.w = get_next_word();
            print_header_2(pc - 4, inst, v.w);
            printf("%-*s  %E, F%d\n", mnemonic_width, mne[opc],
                   (double)v.f, Rd);
            break;
        }

        case 9:                 // lwi
        {
            word_t v = get_next_word();
            print_header_2(pc - 4, inst, v);
            printf("%-*s  %s, R%d\n",
                   mnemonic_width, mne[opc],
                   format_hex(static_cast<int>(v)), Rd);
            break;
        }

        case 10:                // sb
        case 11:                // sd
        case 12:                // sf
        case 13:                // sh
        case 14:                // sw
        {
            const char *mem_ref;
            unsigned bank = 0;  // Integer registers.
            word_t offset = get_next_word();
            if (opc == 11 || opc == 12) {
                bank = 1;       // REAL / LONGREAL registers.
            }

            mem_ref = decode_mem_ref(Rbase, Rindex, S, offset);

            print_header_2(pc - 4, inst, offset);
            printf("%-*s  %s%d, %s\n",
                   mnemonic_width, mne[opc], register_bank[bank], Rd, mem_ref);
            break;
        }

        default:
            print_header(pc, inst);
            printf("invalid encoding\n");
            break;

        }
    }


    static void decode_bt(word_t inst)
    {
        static char const * const mne[] = {
            "bt",
            "bti",
            "btm",
            "btmi",
            "btmc",             // bit test memory, clear
            "btmci",
            "btms",
            "btmsi",
        };
        const char *prefix = "";
        unsigned    Rd     = field(inst, 25, 21);
        unsigned    R0     = field(inst, 20, 16);
        unsigned    R1     = field(inst, 15, 11);
        unsigned    zero   = field(inst, 10, 5);
        unsigned    opc    = field(inst, 4, 0);
        const char *format;

        if (zero != 0) {
            prefix = "(invalid encoding)";
        }
        switch (opc) {
        case 0:
            format = "%s%-*s  R%d, R%d, R%d\n";
            break;

        case 1:
            format = "%s%-*s  %d, R%d, R%d\n";
            break;

        case 2:
            format = "%s%-*s  R%d, (R%d), R%d\n";
            break;

        case 3:
            format = "%s%-*s  %d, (R%d), R%d\n";
            break;

        case 4:                 // btmc
        case 6:                 // btms
            format = "%s%-*s  R%d, (R%d), R%d\n";
            break;

        case 5:                 // btmci
        case 7:                 // btmsi
            format = "%s%-*s  %d, (R%d), R%d\n";
            break;

        default:
            format = "";
            break;
        }
        print_header(pc, inst);
        printf(format, prefix, mnemonic_width, mne[opc], R0, R1, Rd);
    }


    static void decode_stack(word_t inst)
    {
        static char const * const mne[] = {
            "enter",            // 0
            "leave",            // 1
            "push",             // 2
            "pushf",            // 3
            "pushd",            // 4
            "pop",              // 5
            "popf",             // 6
            "popd",             // 7
        };
        unsigned    Rd     = field(inst, 25, 21);
        unsigned    size   = field(inst, 20, 5); // enter, leave
        unsigned    opc    = field(inst, 4, 0);
        unsigned    bd     = 0;

        if (opc == 3 || opc == 4 || opc == 6 || opc == 7) {
            bd = 1;
        }

        switch (opc) {
        case 0:
        case 1:
            print_header(pc, inst);
            printf("%-*s  R%d, %d\n", mnemonic_width, mne[opc], Rd, size);
            break;

        case 2:
        case 3:
        case 4:
        case 5:
        case 6:
        case 7:
            print_header(pc, inst);
            printf("%-*s  %s%d\n", mnemonic_width, mne[opc],
                   register_bank[bd], Rd);
            break;

        default:
            print_header(pc, inst);
            printf("invalid encoding\n");
            break;
        }
    }


    static void decode_integer_register(word_t inst)
    {
        static char const * const mne[] = {
            "and",
            "ash",
            "bitset",
            "cmps",
            "lsh",
            "nor",
            "or",
            "rot",
            "xor"
        };
        const char *prefix = "";
        unsigned    Rd     = field(inst, 25, 21);
        unsigned    R0     = field(inst, 20, 16);
        unsigned    R1     = field(inst, 15, 11);
        unsigned    zero   = field(inst, 10, 6);
        unsigned    code   = field(inst, 5, 0);

        if (zero != 0) {
            prefix = "(invalid encoding)";
        }
        print_header(pc, inst);
        printf("%s%-*s  R%d, R%d, R%d\n",
               prefix, mnemonic_width, mne[code], R0, R1, Rd);
    }


    static void decode_floating_point_register(word_t inst)
    {
        static char const * const mne[] = {
            "arctan",
            "cos",
            "exp",
            "ln",
            "sin",
            "sqrt",
            "tan",
        };
        const char *prefix = "";
        unsigned    Rd     = field(inst, 25, 21);
        unsigned    R0     = field(inst, 20, 16);
        unsigned    R1     = field(inst, 15, 11);
        unsigned    zero   = field(inst, 10, 6);
        unsigned    code   = field(inst, 5, 0);

        if (zero != 0 || R1 != 0) {
            prefix = "(invalid encoding)";
        }
        print_header(pc, inst);
        printf("%s%-*s  F%d, F%d\n",
               prefix, mnemonic_width, mne[code], R0, Rd);
    }

    static void decode_sign_extension(word_t inst)
    {
        static char const * const mne[] = {
            "seb",
            "seh",
        };
        const char *prefix = "";
        unsigned    Rd     = field(inst, 25, 21);
        unsigned    R0     = field(inst, 20, 16);
        unsigned    zero   = field(inst, 15, 6);
        unsigned    code   = field(inst, 5, 0);

        if (zero != 0) {
            prefix = "(invalid encoding)";
        }
        print_header(pc, inst);
        printf("%s%-*s  R%d, R%d\n",
               prefix, mnemonic_width, mne[code], R0, Rd);
    }


    static void decode_system_register(word_t inst)
    {
        static char const * const mne[] = {
            "di",               // 0
            "ei",               // 1
            "lcc",              // 2
        };
        const char *prefix = "";
        unsigned    Rd     = field(inst, 25, 21);
        unsigned    zero   = field(inst, 20, 5);
        unsigned    opc    = field(inst, 4, 0);

        assert(opc <= 2);
        if (zero != 0) {
            prefix = "(invalid encoding)";
        }
        print_header(pc, inst);
        printf("%s%-*s  R%d\n",
               prefix, mnemonic_width, mne[opc], Rd);
    }


    static void decode_jump_register_and_link(word_t inst)
    {
        static char const * const mne[] = {
            "jral",
        };
        const char *prefix = "";
        unsigned    opc    = field(inst, 31, 26);
        unsigned    Rd     = field(inst, 25, 21);
        unsigned    R0     = field(inst, 20, 16);
        unsigned    zero   = field(inst, 15, 0);

        assert(opc == ic_jump_register_and_link);

        if (zero != 0) {
            prefix = "(invalid encoding)";
        }
        print_header(pc, inst);
        printf("%s%-*s  R%d, R%d\n",
               prefix, mnemonic_width, mne[opc - ic_jump_register_and_link],
               R0, Rd);
    }


    static void decode_misc(word_t inst)
    {
        static char const * const mne[] = {
            "break",            // 0
            "wait",             // 1
            "eret",             // 2
            "vmsvc",            // 3
        };
        const char *prefix = "";
        unsigned    opc    = field(inst,  4, 0);

        assert(opc <= 3);

        print_header(pc, inst);

        switch (opc) {
        case 0:
        case 1:
        case 2: {
            unsigned zero = field(inst, 25, 5);

            if (zero != 0) {
                prefix = "(invalid encoding)";
            }

            printf("%s%-*s\n", prefix, mnemonic_width, mne[opc]);
            break;
        }

        case 3: {
            unsigned r0 = field(inst, 20, 16);

            printf("%s%-*s  R%u\n", prefix, mnemonic_width, mne[opc], r0);
            break;
        }

        }
    }


    static void decode_branch(word_t inst)
    {
        static char const * const mne[] = {
            "jeq",
            "jne",
            "jlt",
            "jge",
            "jle",
            "jgt",
            "jltu",
            "jgeu",
            "jleu",
            "jgtu",
            "j",
            "jal",
        };
        unsigned opc  = field(inst, 4, 0);
        word_t   dest = get_next_word();

        switch (opc) {
        case 0:
        case 1:
        case 2:
        case 3:
        case 4:
        case 5:
        case 6:
        case 7:
        case 8:
        case 9: {
            unsigned R0 = field(inst, 20, 16);

            print_header_2(pc - 4, inst, dest);
            printf("%-*s  R%u, %s\n", mnemonic_width, mne[opc], R0,
                   _format_hex(pc + static_cast<int>(dest)));
            break;
        }

        case 10:                 // j
        case 11: {               // jal
            print_header_2(pc - 4, inst, dest);
            printf("%-*s  %s\n",
                   mnemonic_width, mne[opc],
                   _format_hex(pc + static_cast<int>(dest)));
            break;
        }

        default:
            print_header(pc, inst);
            printf("invalid encoding\n");
            break;
        }
    }

    static void decode_control_register(word_t inst)
    {
        static char const * const mne[] = {
            "lcr",              // 0
            "scr",              // 1
        };
        const char *prefix = "";
        unsigned    zero   = field(inst, 15,  5);
        unsigned    opc    = field(inst,  4,  0);

        if (zero != 0) {
            prefix = "(invalid encoding)";
        }
        assert(opc <= 1);


        print_header(pc, inst);
        if (opc == 0) {         // Load control register to register.
            unsigned R0 = field(inst, 25, 21);
            unsigned CR = field(inst, 20, 16);
            printf("%s%-*s  C%d, R%d\n", prefix, mnemonic_width, mne[opc], CR, R0);
        } else {                // Store register to control register.
            unsigned CR = field(inst, 25, 21);
            unsigned R0 = field(inst, 20, 16);
            assert(opc == 1);
            printf("%s%-*s  R%d, C%d\n", prefix, mnemonic_width, mne[opc], R0, CR);
        }
    }


    static void decode_general_register(word_t inst)
    {
        static char const * const mne[] = {
            "add",              // 0
            "sub",              // 1
            "mul",              // 2
            "div",              // 3
            "mod",              // 4
            "cmp",              // 5
            "abs",              // 6
        };
        unsigned    Rd      = field(inst, 25, 21);
        unsigned    R0      = field(inst, 20, 16);
        unsigned    R1      = field(inst, 15, 11);
        unsigned    Rd_bank = field(inst, 10, 10);
        unsigned    R0_bank = field(inst,  9,  9);
        unsigned    R1_bank = field(inst,  8,  8);
        unsigned    zero    = field(inst,  7,  5);
        unsigned    opc     = field(inst,  4,  0);
        const char *prefix  = "";

        assert(opc <= sizeof(mne) / sizeof(mne[0]));
        if (zero != 0) {
            prefix = "(invalid encoding)";
        }

        // ABS requires special encoding.
        if (opc == 6 && (R0 != 0 || R0_bank != 0)) {
            prefix = "(invalid encoding)";
        }

        print_header(pc, inst);
        printf("%s%-*s  %s%d, %s%d, %s%d\n",
               prefix, mnemonic_width, mne[opc],
               register_bank[R0_bank], R0,
               register_bank[R1_bank], R1,
               register_bank[Rd_bank], Rd);
    }


    static void decode_systrap(word_t inst)
    {
        const char *mne;
        const char *prefix = "";
        unsigned    Rd     = field(inst, 25, 21);
        unsigned    R0     = field(inst, 20, 16);
        unsigned    opc    = field(inst, 15,  8);
        unsigned    subcl  = field(inst,  7,  0);

        if (opc == 19 /* nil guard */ || opc == 20 /* nil pointer */) {
            mne = "trapnil";
        } else if (opc == 12) {
            mne = "traprange";
        } else if (opc == 13) {
            mne = "traparray";
        } else {
            mne = "<UNSUPPORTED>";
        }

        print_header(pc, inst);
        if (opc == 19 || opc == 20) {
            printf("%s%-*s  R%d\n",
                   prefix, mnemonic_width, mne, R0);
        } else if (opc == 13) {
            printf("%s%-*s  R%u, R%u\n",
                   prefix, mnemonic_width, mne, R0, Rd);

        } else {
            assert(opc == 12);
            printf("%s%-*s  R%u, %u\n",
                   prefix, mnemonic_width, mne, R0, subcl);
        }
    }


    static void decode_invalid_opcode(word_t inst)
    {
        const char *mne    = "<invalid opcode>";
        const char *prefix = "";

        print_header(pc, inst);
        printf("%s%-*s\n", prefix, mnemonic_width, mne);
    }


    static void decode_conditional_set(word_t inst)
    {
        static char const * const mne[] = {
            "seq",              // 0
            "sne",              // 1
            "slt",              // 2
            "sge",              // 3
            "sle",              // 4
            "sgt",              // 5
            "sltu",             // 6
            "sgeu",             // 7
            "sleu",             // 8
            "sgtu",             // 9
        };
        const char *prefix = "";
        unsigned Rd       = field(inst, 25, 21);
        unsigned R0       = field(inst, 20, 16);
        unsigned zero     = field(inst, 15,  5);
        unsigned opc      = field(inst,  4,  0);

        if (zero != 0) {
            prefix = "(invalid encoding)";
        }

        assert(opc <= sizeof(mne) / sizeof(mne[0]));

        print_header(pc, inst);
        printf("%s%-*s  R%d, R%d\n",
               prefix, mnemonic_width, mne[opc],
               R0,
               Rd);
    }


    static inline instruction_class_t
    get_instruction_class(word_t inst)
    {
        /* Instruction class is in bits 31..26 */
        instruction_class_t r = static_cast<instruction_class_t>(field(inst, 31, 26));
        if (r >= NUM_INSTRUCTION_CLASS) {
            fprintf(stderr, "invalid instruction class: %#x -> opclass %d\n", inst, r);
            r = NUM_INSTRUCTION_CLASS;
        }
        return r;
    }


    void
    disassemble(FILE *fp, unsigned char *code, int offs, int len)
    {
        assert(sizeof(byte_t) == 1);
        assert(sizeof(word_t) == 4);
        assert(len >= static_cast<int>(sizeof(word_t)));

        pc_init(code, offs);

        while (pc < offs + len) {
            word_t inst = get_next_word();
            instruction_class_t cls = get_instruction_class(inst);
            decoder[cls](inst);
        }
    }
}
