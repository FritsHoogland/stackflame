#!/bin/bash
PROFILE_PID=$1

stap -x $PROFILE_PID cpu-wait-profile.stap -o profile.txt &
until grep -q Begin. profile.txt; do sleep 0.01; done
perf record -g -T -p $PROFILE_PID &
read -p "profiling started, press enter to stop" a
kill -s SIGTERM %1 
kill -s SIGINT %2

# remove first line
sed -i '1d' profile.txt
# get wait event names in
if [ ! -f eventsname.sed ]; then 
	echo "need eventsname.sed"
	exit 1
fi
sed -i -f eventsname.sed profile.txt
perf script -i perf.data > perf.data.script

PROCESS_NAME="$(cat perf.data.script | grep -v ^# | grep -v -P '^\t' | grep -v ^$ | awk '{ print $1 }' | sort | uniq)"
if [ $(echo "$PROCESS_NAME" | wc -l) -gt 1 ]; then
	echo "WARNING! Multiple processes found in perf.data; using the first one found."
	PROCESS_NAME=$(echo "$PROCESS_NAME" | head -1)
fi

cat profile.txt | while read PROFILE_LINE; do
        export START_TIME=$(echo $PROFILE_LINE | awk -F\; '{ print "scale=6; "$11"/1000000" }' | bc)
        export END_TIME=$(echo $PROFILE_LINE | awk -F\; '{ print "scale=6; "$12"/1000000" }' | bc)
	export NUMBER=$(echo $PROFILE_LINE | awk -F\; '{ print $1 }')
	export TYPE=$(echo $PROFILE_LINE | awk -F\; '{ print $2 }')
	export WAIT_EVENT=$(echo $PROFILE_LINE | awk -F\; '{ print $3 }')
	export TOT_TIME=$(echo $PROFILE_LINE | awk -F\; '{ print $4 }')
	export ON_CPU_TIME=$(echo $PROFILE_LINE | awk -F\; '{ print $5 }')
	export OFF_CPU_TIME=$(echo $PROFILE_LINE | awk -F\; '{ print $6 }')
	export RUNQUEUE_TIME=$(echo $PROFILE_LINE | awk -F\; '{ print $7 }')
	export TASKINTERRUPTIBLE_TIME=$(echo $PROFILE_LINE | awk -F\; '{ print $8 }')
	export TASKUNINTERRUPTIBLE_TIME=$(echo $PROFILE_LINE | awk -F\; '{ print $9 }')
	> perf.data.script.$NUMBER
	cat perf.data.script | grep -v ^# | grep -v -P '^\t' | grep -v ^$ | sed 's/://g' | awk '$3 > ENVIRON["START_TIME"] && $3 < ENVIRON["END_TIME"] { print $3 }' | while read PERF_TIME; do
		sed -n "/$PERF_TIME/,/^$/p" perf.data.script >> perf.data.script.$NUMBER
	done
	./stackcollapse-perf.pl perf.data.script.$NUMBER > perf.data.collapsed.$NUMBER
	rm -f perf.data.script.$NUMBER

	export NUMBER_OF_SAMPLES=$(cat perf.data.collapsed.$NUMBER | awk 'BEGIN {sum=0} { sum+=$2 } END { print sum }')
	> perf.data.collapsed.scaled.$NUMBER
	if [ $TYPE = "c" ]; then
		INCLUDE="oracle: ON CPU"
	else
		INCLUDE="oracle: $WAIT_EVENT"
	fi
	cat perf.data.collapsed.$NUMBER | while read PERF_COLLAPSED_LINE; do
		SCALED=$( echo $PERF_COLLAPSED_LINE | awk '{ printf "%.0f", $2/ENVIRON["NUMBER_OF_SAMPLES"]*ENVIRON["ON_CPU_TIME"] }' )
		NONSCALED=$( echo $PERF_COLLAPSED_LINE | awk '{ printf $2 }' )
		echo $PERF_COLLAPSED_LINE | sed "s/$NONSCALED$/$SCALED/" | sed "s/^$PROCESS_NAME/$PROCESS_NAME;$NUMBER;TASK_RUNNING;$INCLUDE/" >> perf.data.collapsed.scaled.$NUMBER
	done
	if [ ! -s perf.data.collapsed.scaled.$NUMBER ]; then
		echo "$PROCESS_NAME;$NUMBER;TASK_RUNNING;$INCLUDE $ON_CPU_TIME" >> perf.data.collapsed.scaled.$NUMBER
	fi
	echo "$PROCESS_NAME;$NUMBER;RUNQUEUE;$INCLUDE $RUNQUEUE_TIME" >> perf.data.collapsed.scaled.$NUMBER
	echo "$PROCESS_NAME;$NUMBER;TASK_INTERRUPTIBLE;$INCLUDE $TASKINTERRUPTIBLE_TIME" >> perf.data.collapsed.scaled.$NUMBER
	echo "$PROCESS_NAME;$NUMBER;TASK_UNINTERRUPTIBLE;$INCLUDE $TASKUNINTERRUPTIBLE_TIME" >> perf.data.collapsed.scaled.$NUMBER
	TIME_FOUND=$(echo "$ON_CPU_TIME+$RUNQUEUE_TIME+$TASKINTERRUPTIBLE_TIME+$TASKUNINTERRUPTIBLE_TIME" | bc)
	if [ $TIME_FOUND -lt $TOT_TIME ]; then
		echo "$PROCESS_NAME;$NUMBER;OFF_CPU;$INCLUDE $(echo "$TOT_TIME-$TIME_FOUND" | bc)" >> perf.data.collapsed.scaled.$NUMBER
	fi
	rm -f perf.data.collapsed.$NUMBER
done
cat perf.data.collapsed.scaled.* > perf.data.collapsed.all
rm -f perf.data.collapsed.scaled.*
cat perf.data.collapsed.all | grep -v \ 0$ > perf.collapsed.all
rm -f perf.data.collapsed.all
./flamegraph.pl --countname "microseconds" perf.collapsed.all > stapflame_ora_cpu_wait_sequence.svg
cat perf.collapsed.all | sed "s/$PROCESS_NAME;[0-9]*/$PROCESS_NAME/" > perf.collapsed.noseq.all
./flamegraph.pl --countname "microseconds" perf.collapsed.noseq.all > stapflame_os_cpu_state.svg
cat perf.collapsed.noseq.all | awk -F\; '{ print $3 }' | sed 's/\ [0-9]*$//' | sort | uniq | while read ORA_STATE; do
	ORA_STATE="$(echo $ORA_STATE | sed 's/*/./')"
	grep "$ORA_STATE" perf.collapsed.noseq.all > perf.collapsed.noseq.$(echo $ORA_STATE | sed 's/[^a-zA-Z0-9]/_/g')
	./flamegraph.pl --countname "microseconds" perf.collapsed.noseq.$(echo $ORA_STATE | sed 's/[^a-zA-Z0-9]/_/g') > stapflame_ora_state_perf.collapsed.noseq.$(echo $ORA_STATE | sed 's/[^a-zA-Z0-9]/_/g').svg
done
cat perf.collapsed.noseq.all | sed 's/\ \([0-9]*\)$/;\1/' | cut -d\; -f3 --complement | sed 's/;\([0-9]*\)$/ \1/' > perf.collapsed.no_ora_state
./flamegraph.pl --countname "microseconds" perf.collapsed.no_ora_state > stapflame_no_ora_state.svg
