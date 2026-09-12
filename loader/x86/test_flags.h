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

    extern md::uint32 global;


    static inline void
    map_x86_eflags(unsigned long eflags, test_flags::flags_t *flags)
    {
        flags->C = (eflags >> 0) & 1;
        flags->Z = (eflags >> 6) & 1;
        flags->S = (eflags >> 7) & 1;
        flags->O = (eflags >> 11) & 1;
    }


    static inline void
    hardware_flags(md::int32 l, md::int32 r, test_flags::flags_t *flags)
    {
        md::uint32    ll = static_cast<md::uint32>(l);
        md::uint32    rr = static_cast<md::uint32>(r);
        md::uint32    x;
        unsigned long eflags;

        x = ll - rr;
        __asm__ __volatile__("pushf\n"
                             "popq %[reg]"
                             : [reg] "=r" (eflags));

        map_x86_eflags(eflags, flags);
        global = x;             /* Silence gcc unused warning. */
    }
}
#endif
