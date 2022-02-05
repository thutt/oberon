# Copyright (c) 2000, 2020-2022 Logic Magicians Software
include $(SKL_DIR)/make/config.mk

SOURCE	:=					\
	disasm.cpp				\
	dump.cpp				\
	objio.cpp				\
	skl.cpp					\
	x86.cpp

OBJ	= $(SOURCE:.cpp=.o)


fail:
	$(PROLOG);							\
	echo "This Makefile must be used via $(SKL_DIR)/Makefile";	\
	false;

disasm__:	$(OBJ)
	$(PROLOG);					\
	$(CC) -g $(PROFILE) $(OBJ) -o disasm;


-include $(SOURCE:.cpp=.d)
