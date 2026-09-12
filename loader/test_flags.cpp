/* Copyright (c) 2021-2026 Logic Magicians Software */

/* This progrem tests synthesis of flags.
 *
 * It does not test interpretation of those flags.
 *
 * It uses x86 inline assembly to get actual hardware flags produced
 * by the CPU to compare with the software-synthesized values.
 */

#include <assert.h>
#include <stdio.h>
#include "md.h"
#include "skl_flags_alu.h"
#include "test_flags.h"

#define MinInt -0x80000000
#define MaxInt  0x7fffffff

namespace test_flags {
    typedef struct value_t {
        md::int32 l;
        md::int32 r;
        flags_t   expected;
    } value_t;

   /* values: Test values to exercise flag synthesis.
    *
    *  Refer to: https://en.wikipedia.org/wiki/Overflow_flag
    *
    *    The overflow flag can be set when subtracting numbers with
    *    differing sign bits.
    *
    *  Also note that only subtraction is needed to synthesize the
    *  overflow flag for the comparison instructions.
    */
    value_t values[] = {
        { 6, MinInt,
          {
              0,                    // ZF
              1,                    // CF
              1,                    // SF
              1                     // OF
          }
        },
        { MaxInt, MaxInt,
          {
              1,                    // ZF
              0,                    // CF
              0,                    // SF
              0                     // OF
          }
        },
        { -3, -3,
          {
              1,                    // ZF
              0,                    // CF
              0,                    // SF
              0                     // OF
          }
        },
        { -3, 3,
          {
              0,                    // ZF
              0,                    // CF
              1,                    // SF
              0                     // OF
          }
        },
        { 3, -3,
          {
              0,                    // ZF
              1,                    // CF
              0,                    // SF
              0                     // OF
          }
        },
        { -68, 0,
          {
              0,                    // ZF
              0,                    // CF
              1,                    // SF
              0                     // OF
          }
        },
        { 0, 0,
          {
              1,                    // ZF
              0,                    // CF
              0,                    // SF
              0                     // OF
          }
        },
        { 100000, MinInt,
          {
              0,                    // ZF
              1,                    // CF
              1,                    // SF
              1                     // OF
          }
        },
    };

    md::uint32 global;               // Used to silence compiler errors.

    static void
    display(const value_t *v,
            const flags_t *s,
            const flags_t *h)
    {
        printf("\n");
        printf("%8.8xH  %8.8xH  "
               "E : { Z:%u  S:%u  C:%u  O:%u }\n"
               "%9.9s  %9.9s  "
               "SW: { Z:%u  S:%u  C:%u  O:%u }  "
               "HW: { Z:%u  S:%u  C:%u  O:%u }\n",
               v->l, v->r,
               v->expected.Z, v->expected.S, v->expected.C, v->expected.O,
               " ", " ",
               s->Z, s->S, s->C, s->O,
               h->Z, h->S, h->C, h->O);
        printf("\n");
    }

    static void
    map_software_eflags(md::uint32 swf, flags_t *flags)
    {
        flags->Z = !!(swf & 1);
        flags->S = !!(swf & 2);
        flags->C = !!(swf & 4);
        flags->O = !!(swf & 8);
    }


    static void
    test(const value_t *v)
    {
        flags_t sflags;
        flags_t hflags;
        md::uint32 flags;

        assert(sizeof(md::int32) == 4);
        assert(sizeof(int) == 4);

        flags = skl::synthesize_flags_int32(v->l, v->r);
        map_software_eflags(flags, &sflags);
        hardware_flags(v->l, v->r, &hflags);

        display(v, &sflags, &hflags);

        if (v->expected.Z != sflags.Z || sflags.Z != hflags.Z) {
            printf("%9s  %9s  fail[ZF]:  { exp: %u  synth: %u  hwd: %u }\n",
                   "", "", v->expected.Z, sflags.Z, hflags.Z);
        }

        if (v->expected.S != sflags.S || sflags.S != hflags.S) {
            printf("%9s  %9s  fail[SF]:  { exp: %u  synth: %u  hwd: %u }\n",
                   "", "", v->expected.S, sflags.S, hflags.S);
        }

        if (v->expected.O != sflags.O || sflags.O != hflags.O) {
            printf("%9s  %9s  fail[OF]:  { exp: %u  synth: %u  hwd: %u }\n",
                   "", "", v->expected.O, sflags.O, hflags.O);
        }

        if (v->expected.C != sflags.C || sflags.C != hflags.C) {
            printf("%9s  %9s  fail[CF]:  { exp: %u  synth: %u  hwd: %u }\n",
                   "", "", v->expected.C, sflags.C, hflags.C);
        }
    }
}

int main(void)
{

    unsigned   i;

    /* The compiler's optimization phases do not work well with this
     * test program.  For example, the code in hardware_flags() is
     * rearranged, making the inline assembly produce wrong values.
     * As a consequence, this can only be used when the build type is
     * alpha.
     */
    assert(skl_alpha);

    i = 0;
    while (i < sizeof(test_flags::values) / sizeof(test_flags::values[0])) {
        test_flags::test(&test_flags::values[i]);
        ++i;
    }
    return 0;
}
