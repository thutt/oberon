This repository implements an Oberon compiler and runtime system
targeting a virtual CPU.

The self-hosting compiler is written in Oberon, and works within the
rest of the native Oberon runtime system.  The interpreter for the
virtual CPU is written in simple C++.

The repository does not support the full Oberon operating environment
at this point in time, but doing so remains a project goal.

One primary goal is to have a platform for writing Oberon source that
can be used outside of the Oberon system.

If you are interested in learning a small, well defined, modern
programming language, or compilers or how garbage collection works,
this project may be useful to you.  It provides a good introductory
platform for these topics, without being too large to understand.

The system is known to work on Linux, Raspberry Pi, and the Ubuntu
distribution of WSL 2.

It should not be terribly difficult to port to other operating
systems, but it will be easier to port to POSIX-style hosts than
non-POSIX style.
