# Copyright (c) 2000, 2020-2022 Logic Magicians Software
MAKEFILE	:= $(lastword $(MAKEFILE_LIST))
include $(SKL_DIR)/make/config.mk

TEST-FLAGS	:= test-flags-$(SKL_ARCHITECTURE)

INCLUDE	:=					\
	$(SKL_DIR)/include

SOURCE :=					\
		bootstrap.cpp			\
		config.cpp			\
		dialog.cpp			\
		dump.cpp			\
		heap.cpp			\
		kernintf.cpp			\
		loader.cpp			\
		md.cpp				\
		o3.cpp				\
		objinfo.cpp			\
		skl.cpp				\
		skl_bit_test.cpp		\
		skl_cond.cpp			\
		skl_ctrl_reg.cpp		\
		skl_flags.cpp			\
		skl_gen_reg.cpp			\
		skl_instruction.cpp		\
		skl_int_reg.cpp			\
		skl_jral.cpp			\
		skl_jump.cpp			\
		skl_misc.cpp			\
		skl_reg_mem.cpp			\
		skl_stack.cpp			\
		skl_sys_reg.cpp			\
		skl_systrap.cpp			\
		skl_vmsvc.cpp			\
		skl_vmsvc_bootstrap.cpp		\
		skl_vmsvc_console.cpp		\
		skl_vmsvc_debug_log.cpp		\
		skl_vmsvc_early_hwdtrap.cpp	\
		skl_vmsvc_early_systrap.cpp	\
		skl_vmsvc_environment.cpp	\
		skl_vmsvc_file.cpp		\
		skl_vmsvc_fill_memory.cpp	\
		skl_vmsvc_terminate.cpp		\
		skl_vmsvc_trace_control.cpp

OBJ 	:= $(SOURCE:.cpp=.o)

$(OBJ):	$(SKL_DIR)/make/config.mk $(MAKEFILE)

fail:
	$(PROLOG);							\
	echo "This Makefile must be used via $(SKL_DIR)/Makefile";	\
	false;

oberon:	$(OBJ) $(TEST-FLAGS)
	$(PROLOG);				\
	$(CC)					\
	    -Xlinker --gc-sections		\
	    -g $(PROFILE)			\
	    $(OBJ)				\
	    $(LIBS)				\
	    -o oberon;


loader__:	oberon
	$(PROLOG);

$(TEST-FLAGS):
test_flags:	CXXFLAGS +=			\
	-Wno-narrowing				\
	-Wno-sign-conversion			\
	-Wno-error=sign-conversion

test_flags:	test_flags.cpp
	$(PROLOG);				\
	$(CC) $(CXXFLAGS) -o $@ $^;


test-flags-Intel-x86-64:	test_flags
test-flags-Arm64:
	$(PROLOG);							\
	echo "test_flags uses x86 inline assembly." ;			\
	echo "It is a test program and does not compile on Arm64.";


-include $(SOURCE:.cpp=.d)
