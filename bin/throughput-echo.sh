#!/bin/bash

rm results.csv

for N in 1 2 3 4 5
do
	sudo tc qdisc del dev lo root netem

	# 1ms RTT
	sudo tc qdisc add dev lo root netem delay 0.5ms

	LATENCY=1 SIZE=1 CONCURRENCY=16 make echo-perf
	LATENCY=1 SIZE=1 CONCURRENCY=32 make echo-perf
	LATENCY=1 SIZE=1 CONCURRENCY=64 make echo-perf
	LATENCY=1 SIZE=1 CONCURRENCY=128 make echo-perf

	LATENCY=1 SIZE=512 CONCURRENCY=16 make echo-perf
	LATENCY=1 SIZE=512 CONCURRENCY=32 make echo-perf
	LATENCY=1 SIZE=512 CONCURRENCY=64 make echo-perf
	LATENCY=1 SIZE=512 CONCURRENCY=128 make echo-perf

	LATENCY=1 SIZE=8192 CONCURRENCY=16 make echo-perf
	LATENCY=1 SIZE=8192 CONCURRENCY=32 make echo-perf
	LATENCY=1 SIZE=8192 CONCURRENCY=64 make echo-perf
	LATENCY=1 SIZE=8192 CONCURRENCY=128 make echo-perf

	sudo tc qdisc del dev lo root netem

	mv results.csv throughput-echo-${N}-1ms.csv
done

for N in 1 2 3 4 5
do
	sudo tc qdisc del dev lo root netem

	# 20ms RTT
	sudo tc qdisc add dev lo root netem delay 10ms

	LATENCY=20 SIZE=1 CONCURRENCY=16 make echo-perf
	LATENCY=20 SIZE=1 CONCURRENCY=32 make echo-perf
	LATENCY=20 SIZE=1 CONCURRENCY=64 make echo-perf
	LATENCY=20 SIZE=1 CONCURRENCY=128 make echo-perf

	LATENCY=20 SIZE=512 CONCURRENCY=16 make echo-perf
	LATENCY=20 SIZE=512 CONCURRENCY=32 make echo-perf
	LATENCY=20 SIZE=512 CONCURRENCY=64 make echo-perf
	LATENCY=20 SIZE=512 CONCURRENCY=128 make echo-perf

	LATENCY=20 SIZE=8192 CONCURRENCY=16 make echo-perf
	LATENCY=20 SIZE=8192 CONCURRENCY=32 make echo-perf
	LATENCY=20 SIZE=8192 CONCURRENCY=64 make echo-perf
	LATENCY=20 SIZE=8192 CONCURRENCY=128 make echo-perf

	sudo tc qdisc del dev lo root netem

	mv results.csv throughput-echo-${N}-20ms.csv
done
