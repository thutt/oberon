# Copyright (c) 2000, 2020-2022 Logic Magicians Software
MAKEFILE	:= $(lastword $(MAKEFILE_LIST))
include $(SKL_DIR)/make/config.mk

SOURCE	:=					\
	disasm.cpp				\
	dump.cpp				\
	objio.cpp				\
	skl.cpp

OBJ	= $(SOURCE:.cpp=.o)

INCLUDE	:=							\
	$(SKL_DIR)/include


$(OBJ):	$(SKL_DIR)/make/config.mk $(MAKEFILE)


fail:
	$(PROLOG);							\
	echo "This Makefile must be used via $(SKL_DIR)/Makefile";	\
	false;


disasm__:	$(OBJ)
	$(PROLOG);					\
	$(CC) -g $(PROFILE) $(OBJ) -o disasm;


-include $(SOURCE:.cpp=.d)
