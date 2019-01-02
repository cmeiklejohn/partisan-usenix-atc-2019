
#!/bin/bash

sudo tc qdisc del dev lo root netem

# 1ms RTT
sudo tc qdisc add dev lo root netem delay 0.5ms

LATENCY=1 SIZE=8192 CONCURRENCY=2 make partisan-perf
LATENCY=1 SIZE=8192 CONCURRENCY=4 make partisan-perf
LATENCY=1 SIZE=8192 CONCURRENCY=8 make partisan-perf
LATENCY=1 SIZE=8192 CONCURRENCY=16 make partisan-perf
LATENCY=1 SIZE=8192 CONCURRENCY=24 make partisan-perf
LATENCY=1 SIZE=8192 CONCURRENCY=32 make partisan-perf
LATENCY=1 SIZE=8192 CONCURRENCY=64 make partisan-perf

sudo tc qdisc del dev lo root netem