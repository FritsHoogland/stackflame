stapflame - a process stack profiling tool using systemtap, perf and flamegraphs.

Author: frits.hoogland@gmail.com
Created: Januari 2016

The purpose of this tool is to investigate where time is spent when running an Oracle database foreground process. 
This tool uses perf to sample full stacktraces, and systemtap to profile the time.

It uses two files from Brendan Gregg's flamegraph visualisation scripts (https://github.com/brendangregg/FlameGraph):
stackcollapse-perf.pl
flamegraph.pl

And a script from Luca Canali's stack profiling project (https://github.com/LucaCanali/Stack_Profiling):
eventsname.sql

For systemtap to understand the linux scheduler, the kernel debuginfo packages need to be installed: kernel-euk-debuginfo and kernel-uek-debuginfo-common, available via https://oss.oracle.com/ol6/debuginfo/.

The output of eventsname.sql (eventsname.sed) needs to be in the same directory as the run_stapflame.sh script. Also, the stackcollapse-perf.pl and flamegraph.pl scripts need to be in that directory too.

To run it, execute, as root:
./run_stapflame.sh 123
(where 123 is the pid of an Oracle foreground process)
The systemtap kernel module is compiled, and once systemtap and perf are setup, it will display:

profiling started, press enter to stop

Then execute the things you want to profile in the Oracle session you are profiling. Press enter once you want to stop profiling.
The script will then process the data, and output multiple svg files:
- stapflame_ora_cpu_wait_sequence.svg
  This shows a flamegraph of stacktraces per Oracle cpu and wait state.
- stapflame_no_ora_state.svg
  This shows a flamegraph of stacktraces per CPU state, without Oracle state.
- stapflame_os_cpu_state.svg
  This shows a flamegraph of stacktraces per CPU state, with Oracle state.
- stapflame_ora_state_perf.collapsed.noseq.oracle__ON_CPU.svg
  This shows a flamegraph of stacktraces of all time spend in Oracle on cpu state.
- stapflame_ora_state_perf.collapsed.noseq.oracle__<waiteventname>.svg
  This shows a flamegraph of stacktraces of all time spend in a waitevent (a flamegraph is created for every waitevent encountered). 

WARNING!
This is EXPERIMENTAL proof-of-concept code. Use at your own risk.
