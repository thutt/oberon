# Copyright (c) 2022 Logic Magicians Software
SHELL	:=	\
	bash

SPACE	:=
SPACE	:= $(SPACE) $(SPACE)

CC	:=	\
	g++

HOSTOS	:=	\
	LINUX

ATSIGN	:=	\
	$(if $(VERBOSE),,@)

PROLOG	:=					\
	$(ATSIGN)set -o errexit;		\
	set -o pipefail;			\
	set -o nounset

# Build Directory
#
#   Allow any build option change to have a unique build directory
#   reduces the burden on the developer to know when to perform a
#   clean build.  The build directory is created from the build type
#   and the build options.
#
#   This construction must be matched by 'skl-oberon-path' in
#   ${SKL_DIR}/system/scripts/functions.
#
_OPTS		:= $(if $(SKL_BUILD_OPTIONS),/$(subst $(SPACE),/,$(SKL_BUILD_OPTIONS)))
_BUILD_DIR	:= $(SKL_BUILD_DIR)/$(SKL_BUILD_TYPE)$(_OPTS)

# Compiler Code Generation options.
#
PROFILE	:=							\
	$(if $(filter profile,$(SKL_BUILD_OPTIONS)),-pg)

DEBUG	:=							\
	$(if $(filter alpha beta,$(SKL_BUILD_TYPE)),-g)

OPT	:=							\
	$(if $(filter release,$(SKL_BUILD_TYPE)),-O2,-Og)


INCLUDE	:=					\
	$(SKL_DIR)/include

WARNINGS	:=				\
	--pedantic				\
	-Wall					\
	-Wconversion				\
	-Werror					\
	-Wno-switch				\
	-Wsign-conversion			\
	-fdata-sections				\
	-fdiagnostics-color=never		\
	-ffunction-sections			\
	-fno-diagnostics-show-caret


# Compiler Source code control
TRACE	:=	\
	$(if $(filter trace,$(SKL_BUILD_OPTIONS)),-DENABLE_TRACE)


CXXFLAGS	:=				\
	-D$(HOSTOS)				\
	-DBUILD_TYPE_$(SKL_BUILD_TYPE)		\
	$(addprefix -I,$(INCLUDE))		\
	$(TRACE)				\
	$(OPT)					\
	$(PROFILE)				\
	$(DEBUG)				\
	-MMD					\
	$(WARNINGS)

LIBS =		-ldl
