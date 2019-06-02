
#!/bin/bash

sudo tc qdisc del dev lo root netem

# 1ms RTT
sudo tc qdisc add dev lo root netem delay 0.5ms

LATENCY=1 SIZE=8192 CONCURRENCY=16 make microbenchmarks-largepayload
LATENCY=1 SIZE=8192 CONCURRENCY=32 make microbenchmarks-largepayload
LATENCY=1 SIZE=8192 CONCURRENCY=64 make microbenchmarks-largepayload
LATENCY=1 SIZE=8192 CONCURRENCY=128 make microbenchmarks-largepayload

sudo tc qdisc del dev lo root netem

mv results.csv microbenchmarks-largepayload.csv
