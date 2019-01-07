
#!/bin/bash

sudo tc qdisc del dev lo root netem

# 1ms RTT
sudo tc qdisc add dev lo root netem delay 10ms

LATENCY=20 SIZE=8192 CONCURRENCY=128 make microbenchmarks-queueoverhead

sudo tc qdisc del dev lo root netem