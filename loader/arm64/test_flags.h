/* Copyright (c) 2026 Logic Magicians Software
 *
 */
#if !defined(_TEST_EFLAGS_H)
#define _TEST_EFLAGS_H

namespace test_flags {
    typedef struct flags_t {
        unsigned Z;
        unsigned C;
        unsigned S;
        unsigned O;
    } flags_t;


    static inline void
    hardware_flags(md::int32 l, md::int32 r, test_flags::flags_t *flags)
    {
        unsigned long nzcv;

        __asm__ __volatile__("cmp %w[left], %w[right]\n\t"
                             "mrs %[nzcv], s3_3_c4_c2_0"
                             : [nzcv] "=r" (nzcv)
                             : [left] "r" (l),
                               [right] "r" (r)
                             : "cc");

        /* ARM's carry means "no borrow".
         * It is inverted to match x86 CF ("borrow") semantic.
         */
        flags->S = static_cast<unsigned>((nzcv >> 31) & 1);        // N
        flags->Z = static_cast<unsigned>((nzcv >> 30) & 1);        // Z
        flags->C = static_cast<unsigned>(((nzcv >> 29) & 1) ^ 1);  // C
        flags->O = static_cast<unsigned>((nzcv >> 28) & 1);        // V
    }
}
#endif
