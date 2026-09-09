# Copyright (c) 2026 Logic Magicians Software

export SKL_CC_linux_WARNINGS	:=		\
	-fdiagnostics-color=never		\
	-fno-diagnostics-show-caret

export SKL_CC_macos_WARNINGS	:=		\
	-Wno-unused-const-variable

export SKL_LD_linux_OPTS	:=		\
	-fdiagnostics-color=never		\
	-fno-diagnostics-show-caret

export SKL_LD_macos_OPTS	:=		\
	-Wno-unused-const-variable		\
	-Wl,-pagezero_size=0x4000
