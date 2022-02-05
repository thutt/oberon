#include <stdlib.h>
#include <stdio.h>
#include <getopt.h>
#include "objio.h"
#include "dump.h"

int main(int argc, char *argv[])
{
    static struct option opt[] =
    {
	{ "help",       0,       NULL,   'h' },
    };
    int opt_index = 1;
    int c;
    objio::file_mode_t mode;
    
    while (1)
    {
	c = getopt_long(argc, argv, "h", opt, &opt_index);
	if (c == EOF)
	    break;

	switch (c)
	{
	case 'h':
	    printf("Logic Magicians Oberon-3 Disassembler\n");
	    exit(0);
	    break;
	    
        case '?':
	default:
            break;
	}
    }
    mode = objio::open(argv[opt_index]);
    objio::read();
    objio::close();
    dump::file(mode);
    exit(0);
}
