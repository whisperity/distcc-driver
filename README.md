[DistCC](http://distcc.org) driver environment
==============================================

Helper script and wrapper environment to run [DistCC](http://distcc.org)-based distributed compilation of C and C++ projects without having to deal with manually configuring the otherwise necessary `DISTCC_HOSTS` variable.
This tool's goal is to prepare the necessary environment and configuration options in a smarter way, and do everything possible to prevent the automatic "local compilation fallback" from stalling your development environment.
