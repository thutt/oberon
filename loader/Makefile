# Copyright (c) 2000-2026 Logic Magicians Software
MAKEFILE	:= $(lastword $(MAKEFILE_LIST))
SRC_DIR		:= $(dir $(MAKEFILE))
include $(SKL_DIR)/make/config.mk

ARCHITECTURE_DIR	:=					\
	$(strip $(if $(filter $(SKL_ARCHITECTURE),Intel-x86-64),x86)	\
	$(if $(filter $(SKL_ARCHITECTURE),Arm64),arm64))

INCLUDE	:=					\
	$(SKL_DIR)/include			\
	$(SRC_DIR)				\
	$(SRC_DIR)$(ARCHITECTURE_DIR)


SOURCE :=					\
		bootstrap.cpp			\
		config.cpp			\
		dialog.cpp			\
		dump.cpp			\
		fileutils.cpp			\
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
		skl_fp_reg.cpp			\
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
		skl_vmsvc_directory.cpp		\
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

oberon:	$(OBJ) test_flags
	$(PROLOG);				\
	$(CC)					\
	    $(addprefix -Xlinker,$(CC_LD_$(SKL_HOST_OS)_OPTS))		\
	    -g $(PROFILE)			\
	    $(OBJ)				\
	    $(LIBS)				\
	    -o oberon;


loader__:	oberon
	$(PROLOG);

test_flags:	CXXFLAGS +=			\
	-Wno-narrowing				\
	-Wno-sign-conversion			\
	-Wno-error=sign-conversion

test_flags:	test_flags.cpp
	$(PROLOG);				\
	$(CC) $(CXXFLAGS) -o $@ $^;

-include $(SOURCE:.cpp=.d)
