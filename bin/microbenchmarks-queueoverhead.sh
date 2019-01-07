
#!/bin/bash

sudo tc qdisc del dev lo root netem

# 1ms RTT
sudo tc qdisc add dev lo root netem delay 10ms

LATENCY=20 SIZE=8192 CONCURRENCY=2 make microbenchmarks-queueoverhead
LATENCY=20 SIZE=8192 CONCURRENCY=4 make microbenchmarks-queueoverhead
LATENCY=20 SIZE=8192 CONCURRENCY=8 make microbenchmarks-queueoverhead
LATENCY=20 SIZE=8192 CONCURRENCY=16 make microbenchmarks-largepayload
LATENCY=20 SIZE=8192 CONCURRENCY=32 make microbenchmarks-queueoverhead
LATENCY=20 SIZE=8192 CONCURRENCY=64 make microbenchmarks-queueoverhead
LATENCY=20 SIZE=8192 CONCURRENCY=128 make microbenchmarks-queueoverhead

sudo tc qdisc del dev lo root netem