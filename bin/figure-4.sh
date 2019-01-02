
#!/bin/bash

sudo tc qdisc del dev lo root netem

# 1ms RTT
sudo tc qdisc add dev lo root netem delay 10ms

LATENCY=20 SIZE=512 CONCURRENCY=2 make figure-4
LATENCY=20 SIZE=512 CONCURRENCY=4 make figure-4
LATENCY=20 SIZE=512 CONCURRENCY=8 make figure-4
LATENCY=20 SIZE=512 CONCURRENCY=16 make figure-4
LATENCY=20 SIZE=512 CONCURRENCY=32 make figure-4
LATENCY=20 SIZE=512 CONCURRENCY=64 make figure-4
LATENCY=20 SIZE=512 CONCURRENCY=128 make figure-4

sudo tc qdisc del dev lo root netem