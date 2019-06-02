
#!/bin/bash

sudo tc qdisc del dev lo root netem

# 1ms RTT
sudo tc qdisc add dev lo root netem delay 0.5ms

LATENCY=1 SIZE=512 CONCURRENCY=128 make microbenchmarks-queueoverhead

sudo tc qdisc del dev lo root netem

mv results.csv microbenchmarks-queueoverhead.csv
