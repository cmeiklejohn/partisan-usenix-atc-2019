# ATC'19 Results for Partisan

Here you can find the test harness used for generating all of our results.
Obviously, your results will differ from ours if you do not use the same
experimental configuration as we do.

Preliminary results are available [here.](https://partisan.cloud)

This repository includes a microbenchmark suite for Partisan itself, and a
port of Riak Core (from Basho) ported to Partisan for running experiments
with a simulated key-value store using three vnodes, and a echo service using
a single vnode.

Our port of Riak Core is available [here](https://github.com/lasp-lang/riak_core) with a compatibility library available [here](https://github.com/lasp-lang/riak_core_partisan_utils).

## Data Collection Targets

* `bin/microbenchmarks.sh`: Run the microbenchmark suite, Figure 1.

* `bin/microbenchmarks-queueoverhead.sh`: Run the microbenchmark suite for identifying queue overhead introduced by additional connections/queues, Figure 2.

* `bin/microbenchmarks-highlatency.sh`: Run the high-latency microbenchmark suite, Figure 3.

* `bin/microbenchmarks-largepayload.sh`: Run the large-payload microbenchmark suite, Figure 4.

* `bin/throughput-echo.sh`: Run the Echo workload, Figures 5 & 6.

* `bin/throughput-kvs.sh`: Run the KVS workload, Figures 7 & 8.

## Plots

Available in the ```Rscripts``` folder are a number of scripts used to generate the plots included in our final paper.