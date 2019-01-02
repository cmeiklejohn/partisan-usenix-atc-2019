
#!/bin/bash

sudo tc qdisc del dev lo root netem

# 1ms RTT
sudo tc qdisc add dev lo root netem delay 0.5ms

LATENCY=1 SIZE=512 CONCURRENCY=2 make figure-1-3
LATENCY=1 SIZE=512 CONCURRENCY=4 make figure-1-3
LATENCY=1 SIZE=512 CONCURRENCY=8 make figure-1-3
LATENCY=1 SIZE=512 CONCURRENCY=16 make figure-1-3
LATENCY=1 SIZE=512 CONCURRENCY=32 make figure-1-3
LATENCY=1 SIZE=512 CONCURRENCY=64 make figure-1-3
LATENCY=1 SIZE=512 CONCURRENCY=128 make figure-1-3

sudo tc qdisc del dev lo root netem