#!/bin/sh

# Get experimental data.
scp root@142.93.203.167:unir/results.csv fsm-perf.csv; 
scp root@142.93.57.239:unir/results.csv echo-perf.csv; 
scp root@104.248.228.80:unir/results.csv fixed-perf.csv; 

# Remove duplicates.
cat echo-perf.csv | grep -v 'echo,partisan,4' > echo-perf-final.csv

# Remove duplicates.
cat fsm-perf.csv | grep -v 'kvs,partisan,4' > fsm-perf-final.csv

# Add new.
cat fixed-perf.csv | grep 'echo,partisan' >> echo-perf-final.csv
cat fixed-perf.csv | grep 'kvs,partisan' >> fsm-perf-final.csv

# Generate lossy plot.
rm -f echo-perf-lossy-final.csv
cat echo-perf.csv | grep 'echo,' | sed -e 's/partisan/partisan-N/g' >> echo-perf-lossy-final.csv
cat fixed-perf.csv | grep 'echo,' | sed -e 's/partisan/partisan-4/g' >> echo-perf-lossy-final.csv


