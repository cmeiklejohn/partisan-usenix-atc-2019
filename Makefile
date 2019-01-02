BASEDIR = $(shell pwd)
REBAR = ./rebar3
RELPATH = _build/default/rel/unir
PRODRELPATH = _build/prod/rel/unir
APPNAME = unir
SHELL = /bin/bash
CONCURRENCY 	 ?= 4
LATENCY 		 ?= 0
SIZE 			 ?= 1024
PROJECT_ID 		 ?= partisan-203021

compile:
	$(REBAR) compile

test-workflow: kill
	./rebar3 proper -m prop_unir -p prop_sequential --noshrink

gcloud-build:
	docker build --no-cache -t gcr.io/$(PROJECT_ID)/unir:v1 .
	gcloud docker -- push gcr.io/$(PROJECT_ID)/unir:v1

gcloud-deploy:
	@read -s -p "Please make sure you've run gcloud-build and then hit enter to continue..."
	@echo
	yes | gcloud container clusters delete unir; exit 0
	gcloud container clusters create unir --machine-type n1-highcpu-16	
	gcloud container clusters get-credentials unir
	sleep 60
	bin/kube

gcloud-redeploy:
	@read -s -p "Please make sure you've run gcloud-build and then hit enter to continue..."
	@echo
	kubectl delete -f /tmp/unir.yaml
	bin/kube

kube-deploy:
	bin/kube

gcloud-delete:
	yes | gcloud container clusters delete unir; exit 0

release: compile
	$(REBAR) release
	mkdir -p $(RELPATH)/../unir_config
	[ -f $(RELPATH)/../unir_config/unir.conf ] || cp $(RELPATH)/etc/unir.conf  $(RELPATH)/../unir_config/unir.conf
	[ -f $(RELPATH)/../unir_config/advanced.config ] || cp $(RELPATH)/etc/advanced.config  $(RELPATH)/../unir_config/advanced.config

proper: release kill
	$(REBAR) proper -m prop_unir -p prop_sequential

kill:
	pkill -9 beam.smp; pkill -9 epmd; exit 0

console:
	cd $(RELPATH) && ./bin/unir console

clear-logs:
	rm -rf _build/test/logs

proper-logs:
	find . -name console.log | grep `ls -d ./undefined* | tail -1` | xargs cat

tail-proper-logs:
	find . -name console.log | grep `ls -d ./undefined* | tail -1` | xargs tail -F

logs:
	find . -name console.log | grep `ls -d ./_build/test/logs/ct_run* | tail -1` | xargs cat

tail-logs:
	find . -name console.log | grep `ls -d ./_build/test/logs/ct_run* | tail -1` | xargs tail -F

echo-bench:
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=echo.config $(REBAR) ct --suite=throughput_SUITE --group=disterl --case=bench_test --readable=false -v
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=echo.config $(REBAR) ct --suite=throughput_SUITE --group=partisan --case=bench_test --readable=false -v
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=echo.config $(REBAR) ct --suite=throughput_SUITE --group=partisan_with_parallelism --case=bench_test --readable=false -v

kvs-latency: release
	pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=fsm_performance_test --group=disterl
	pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=fsm_performance_test --group=partisan
	pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=fsm_performance_test --group=partisan_with_partitioned_parallelism_and_channels_and_monotonic_channels

fsm-perf: release
	pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=fsm_performance_test --group=disterl
	# pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=fsm_performance_test --group=partisan
	# pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=fsm_performance_test --group=partisan_with_channels
	# pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=fsm_performance_test --group=partisan_with_parallelism
	# pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=fsm_performance_test --group=partisan_with_monotonic_channels
	# pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=fsm_performance_test --group=partisan_with_partitioned_parallelism
	# pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=fsm_performance_test --group=partisan_with_partitioned_parallelism_and_channels
	pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=fsm_performance_test --group=partisan_with_partitioned_parallelism_and_channels_and_monotonic_channels

echo-perf: release
	pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=echo_performance_test --group=disterl
	# pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=echo_performance_test --group=partisan
	# pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=echo_performance_test --group=partisan_with_channels
	# pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=echo_performance_test --group=partisan_with_monotonic_channels
	# pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=echo_performance_test --group=partisan_with_parallelism
	# pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=echo_performance_test --group=partisan_with_partitioned_parallelism
	# pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=echo_performance_test --group=partisan_with_partitioned_parallelism_and_channels
	pkill -9 beam.smp; pkill -9 epmd; SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=echo_performance_test --group=partisan_with_partitioned_parallelism_and_channels_and_monotonic_channels

partisan-perf: release
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=disterl
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan
	# pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_channels
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_parallelism
	# pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_partitioned_parallelism
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_partitioned_parallelism_and_channels

figure-1-3: release
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=disterl
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan
	# pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_channels
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_parallelism
	# pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_partitioned_parallelism
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=16 ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_partitioned_parallelism_and_channels
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_partitioned_parallelism_and_channels

figure-5: release
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=disterl
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan
	# pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_channels
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_parallelism
	# pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_partitioned_parallelism
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=16 ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_partitioned_parallelism_and_channels
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_partitioned_parallelism_and_channels

profile: release
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=false PROFILE=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=disterl
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=false PROFILE=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=false PROFILE=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_channels
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=false PROFILE=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_parallelism
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=false PROFILE=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_partitioned_parallelism
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=false PROFILE=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_partitioned_parallelism_and_channels
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true PROFILE=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=disterl
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true PROFILE=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true PROFILE=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_channels
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true PROFILE=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_parallelism
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true PROFILE=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_partitioned_parallelism
	pkill -9 beam.smp; pkill -9 epmd; PARTISAN_INIT=true PROFILE=true SIZE=${SIZE} LATENCY=${LATENCY} CONCURRENCY=${CONCURRENCY} PARALLELISM=${CONCURRENCY} ${REBAR} ct --readable=false -v --suite=throughput_SUITE --case=partisan_performance_test --group=partisan_with_partitioned_parallelism_and_channels

single-bench:
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=32kb_object.config $(REBAR) ct --readable=false -v --suite=throughput_SUITE --group=disterl --case=bench_test
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=32kb_object.config $(REBAR) ct --readable=false -v --suite=throughput_SUITE --group=partisan --case=bench_test
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=32kb_object.config $(REBAR) ct --readable=false -v --suite=throughput_SUITE --group=partisan_with_binary_padding --case=bench_test
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=64kb_object.config $(REBAR) ct --readable=false -v --suite=throughput_SUITE --group=disterl --case=bench_test
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=64kb_object.config $(REBAR) ct --readable=false -v --suite=throughput_SUITE --group=partisan --case=bench_test
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=64kb_object.config $(REBAR) ct --readable=false -v --suite=throughput_SUITE --group=partisan_with_binary_padding --case=bench_test
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=96kb_object.config $(REBAR) ct --readable=false -v --suite=throughput_SUITE --group=disterl --case=bench_test
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=96kb_object.config $(REBAR) ct --readable=false -v --suite=throughput_SUITE --group=partisan --case=bench_test
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=96kb_object.config $(REBAR) ct --readable=false -v --suite=throughput_SUITE --group=partisan_with_binary_padding --case=bench_test

busy-port-bench:
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=default.config $(REBAR) ct --suite=throughput_SUITE --group=disterl --case=bench_test --readable=false -v
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=32kb_object.config $(REBAR) ct --suite=throughput_SUITE --group=disterl --case=bench_test --readable=false -v
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=64kb_object.config $(REBAR) ct --suite=throughput_SUITE --group=disterl --case=bench_test --readable=false -v
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=96kb_object.config $(REBAR) ct --suite=throughput_SUITE --group=disterl --case=bench_test --readable=false -v
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=512kb_object.config $(REBAR) ct --suite=throughput_SUITE --group=disterl --case=bench_test --readable=false -v
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=1mb_object.config $(REBAR) ct --suite=throughput_SUITE --group=disterl --case=bench_test --readable=false -v
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=2mb_object.config $(REBAR) ct --suite=throughput_SUITE --group=disterl --case=bench_test --readable=false -v
	pkill -9 beam.smp; pkill -9 epmd; exit 0
	BENCH_CONFIG=4mb_object.config $(REBAR) ct --suite=throughput_SUITE --group=disterl --case=bench_test --readable=false -v

bench: kill
	@echo "Running Distributed Erlang benchmark with configuration $(BENCH_CONFIG)..."
	BENCH_CONFIG=$(BENCH_CONFIG) $(REBAR) ct --suite=throughput_SUITE --group=disterl --case=bench_test
	@echo "Running Partisan benchmark with configuration $(BENCH_CONFIG)..."
	BENCH_CONFIG=$(BENCH_CONFIG) $(REBAR) ct --suite=throughput_SUITE --group=partisan --case=bench_test

extended-bench: kill bench
	@echo "Running Partisan (parallel) benchmark with configuration $(BENCH_CONFIG)..."
	BENCH_CONFIG=$(BENCH_CONFIG) $(REBAR) ct --suite=throughput_SUITE --group=partisan_with_parallelism --case=bench_test
	@echo "Running Partisan (binary padding) benchmark with configuration $(BENCH_CONFIG)..."
	BENCH_CONFIG=$(BENCH_CONFIG) $(REBAR) ct --suite=throughput_SUITE --group=partisan_with_binary_padding --case=bench_test
	@echo "Running Partisan (vnode partitioning) benchmark with configuration $(BENCH_CONFIG)..."
	BENCH_CONFIG=$(BENCH_CONFIG) $(REBAR) ct --suite=throughput_SUITE --group=partisan_with_vnode_partitioning --case=bench_test

without-partisan-test: kill release
	$(REBAR) ct -v --readable=false --suite=functionality_SUITE --group=disterl

with-partisan-test: kill release
	$(REBAR) ct -v --readable=false --suite=functionality_SUITE --group=partisan

scale-test: clear-logs kill release
	$(REBAR) ct -v --readable=false --suite=functionality_SUITE --group=scale

large-scale-test: kill release
	$(REBAR) ct -v --readable=false --suite=functionality_SUITE --group=large_scale

partisan-scale-test: clear-logs kill release
	$(REBAR) ct -v --readable=false --suite=functionality_SUITE --group=partisan_scale

partisan-large-scale-test: kill release
	$(REBAR) ct -v --readable=false --suite=functionality_SUITE --group=partisan_large_scale

partisan-with-binary-padding-test: kill release
	$(REBAR) ct -v --readable=false --suite=functionality_SUITE --group=partisan_with_binary_padding

partisan-with-parallelism-test: kill release
	$(REBAR) ct -v --readable=false --suite=functionality_SUITE --group=partisan_with_parallelism

prod-release:
	$(REBAR) as prod release
	mkdir -p $(PRODRELPATH)/../unir_config
	[ -f $(PRODRELPATH)/../unir_config/unir.conf ] || cp $(PRODRELPATH)/etc/unir.conf  $(PRODRELPATH)/../unir_config/unir.conf
	[ -f $(PRODRELPATH)/../unir_config/advanced.config ] || cp $(PRODRELPATH)/etc/advanced.config  $(PRODRELPATH)/../unir_config/advanced.config

prod-console:
	cd $(PRODRELPATH) && ./bin/unir console

clean:
	$(REBAR) clean

dialyzer:
	$(REBAR) dialyzer

functionality-test: kill release
	$(REBAR) ct --readable=false -v --suite=functionality_SUITE --case=vnode_test

test: kill release
	$(REBAR) ct --readable=false -v

devrel1:
	$(REBAR) as dev1 release

devrel2:
	$(REBAR) as dev2 release

devrel3:
	$(REBAR) as dev3 release

devrel: devrel1 devrel2 devrel3

dev1-console:
	$(BASEDIR)/_build/dev1/rel/unir/bin/$(APPNAME) console

dev2-console:
	$(BASEDIR)/_build/dev2/rel/unir/bin/$(APPNAME) console

dev3-console:
	$(BASEDIR)/_build/dev3/rel/unir/bin/$(APPNAME) console

devrel-start:
	for d in $(BASEDIR)/_build/dev*; do $$d/rel/unir/bin/$(APPNAME) start; done

devrel-join:
	for d in $(BASEDIR)/_build/dev{2,3}; do $$d/rel/unir/bin/$(APPNAME)-admin cluster join unir1@127.0.0.1; done

devrel-cluster-plan:
	$(BASEDIR)/_build/dev1/rel/unir/bin/$(APPNAME)-admin cluster plan

devrel-cluster-commit:
	$(BASEDIR)/_build/dev1/rel/unir/bin/$(APPNAME)-admin cluster commit

devrel-status:
	$(BASEDIR)/_build/dev1/rel/unir/bin/$(APPNAME)-admin member-status

devrel-ping:
	for d in $(BASEDIR)/_build/dev*; do $$d/rel/unir/bin/$(APPNAME) ping; done

devrel-stop:
	for d in $(BASEDIR)/_build/dev*; do $$d/rel/unir/bin/$(APPNAME) stop; done

start:
	$(BASEDIR)/$(RELPATH)/bin/$(APPNAME) start

stop:
	$(BASEDIR)/$(RELPATH)/bin/$(APPNAME) stop

attach:
	$(BASEDIR)/$(RELPATH)/bin/$(APPNAME) attach
