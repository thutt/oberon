#include <assert.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "config.h"
#include "dialog.h"
#include "dump.h"

namespace dump
{
    void hex(const unsigned char *lab, const unsigned char *buf, int len, int address_offset)
    {
        int i, j, k;

        if (len != 0)
        {
            dialog::print("%s\n", lab);
            k = 0;
            while (len > 0)
            {
                dialog::print("%#4x: ", k + address_offset);

                /* print hex part */
                for (i = 0, j = (len < 16) ? len : 16; i < j; ++i)
                    dialog::print("%2x ", buf[k + i]);

                /* print char part */
                dialog::print("  ");
                for (i = 0, j = (len < 16) ? len : 16; i < j; ++i)
                {
                    if ((buf[k + i] < ' ') || (buf[k + i] > 0x7f))
                        dialog::print(".");
                    else
                        dialog::print("%c", buf[k + i]);
                }
                k += j;
                len -= j;
                dialog::print("\n");
            }
        }
    }
}
