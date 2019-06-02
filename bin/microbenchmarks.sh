
#!/bin/bash

sudo tc qdisc del dev lo root netem

# 1ms RTT
sudo tc qdisc add dev lo root netem delay 0.5ms

LATENCY=1 SIZE=512 CONCURRENCY=16 make microbenchmarks
LATENCY=1 SIZE=512 CONCURRENCY=32 make microbenchmarks
LATENCY=1 SIZE=512 CONCURRENCY=64 make microbenchmarks
LATENCY=1 SIZE=512 CONCURRENCY=128 make microbenchmarks

sudo tc qdisc del dev lo root netem

mv results.csv microbenchmarks.csv
