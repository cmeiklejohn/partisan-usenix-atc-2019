#!/bin/bash

# Other options: make partisan-perf fsm-perf

sudo tc qdisc del dev lo root netem

# 1ms RTT
sudo tc qdisc add dev lo root netem delay 0.5ms

LATENCY=1 SIZE=1024 CONCURRENCY=8 make kvs-latency

sudo tc qdisc del dev lo root netem

# 10 RTT
sudo tc qdisc add dev lo root netem delay 5ms

LATENCY=10 SIZE=1024 CONCURRENCY=8 make kvs-latency

sudo tc qdisc del dev lo root netem

# 20 RTT
sudo tc qdisc add dev lo root netem delay 10

LATENCY=20 SIZE=1024 CONCURRENCY=8 make kvs-latency

sudo tc qdisc del dev lo root netem

# 40 RTT
sudo tc qdisc add dev lo root netem delay 20

LATENCY=40 SIZE=1024 CONCURRENCY=8 make kvs-latency

sudo tc qdisc del dev lo root netem

# 80 RTT
sudo tc qdisc add dev lo root netem delay 40

LATENCY=80 SIZE=1024 CONCURRENCY=8 make kvs-latency

sudo tc qdisc del dev lo root netem

# 120 RTT
sudo tc qdisc add dev lo root netem delay 60

LATENCY=120 SIZE=1024 CONCURRENCY=8 make kvs-latency

sudo tc qdisc del dev lo root netem

sudo tc qdisc del dev lo root netem