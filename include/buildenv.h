/* Copyright (c) 2021, 2022 Logic Magicians Software */

/* This file exclusively contains symbols that define the build environment.
 *
 */
#if !defined(_BUILDENV_H)
#define _BUILDENV_H
#include <stdlib.h>

#if defined(__GNUC__)
  #if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    #define skl_endian_little (1)
    #define skl_endian_big    (0)
  #else
    #define skl_endian_little (0)
    #define skl_endian_big    (1)
  #endif


  /* LIKELY, UNLIKELY
   *
   *  These macros require the use of boolean values to properly work.
   *  For example:
   *
   *    if (LIKELY(x & 8)) {
   *    }
   *
   * will not work correctly.  Instead, always convert into a boolean,
   * like so:
   *
   *    if (LIKELY((x & 8) != 0)) {
   *    }
   */
  #define LIKELY(_e) __builtin_expect((_e), 1)
  #define UNLIKELY(_e) __builtin_expect(_e, 0)
  #define UNUSED __attribute__((unused))
  #define NORETURN __attribute__((noreturn))

#else
  #error Unable to build.  Unsupported compiler.
#endif

#if defined(BUILD_TYPE_alpha)
  #define skl_alpha    (1)
  #define skl_beta     (0)
  #define skl_release  (0)
#elif defined(BUILD_TYPE_beta)
  #define skl_alpha    (0)
  #define skl_beta     (1)
  #define skl_release  (0)
#elif defined(BUILD_TYPE_release)
  #define skl_alpha    (0)
  #define skl_beta     (0)
  #define skl_release  (1)
  #define NDEBUG                /* Disable C assert(). */
#else
  #error BUILD_TYPE: Unsupported value.
#endif

#if defined(ENABLE_TRACE)
  #define skl_trace (1)
#else
  #define skl_trace (0)
#endif

/* COMPILE_TIME_ASSERT
 *
 *  Compile-time assert.  Checks if _expr, which must be a
 *  compile-time constant, is 'true'.  If it evalues to 'false', a
 *  compiler error will result.
 */
#define COMPILE_TIME_ASSERT(_expr)              \
    do {                                        \
        char _cta[(_expr) ? 1 : -1];            \
        (void)_cta;                             \
    } while (0)


#define NOT_IMPLEMENTED()                                       \
    do {                                                        \
        fprintf(stderr, "%s: not implemented\n", __func__);     \
        exit(1);                                                \
    } while (0);


  /* INFINITE_LOOP:
   *
   *   Use in cases where the compiler complains that 'noreturn'
   *   functions actually can return.
   */
  #define INFINITE_LOOP()                       \
      do {                                      \
      } while (1)
#endif
