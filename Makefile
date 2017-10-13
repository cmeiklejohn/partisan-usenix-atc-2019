BASEDIR = $(shell pwd)
REBAR = ./rebar3
RELPATH = _build/default/rel/unir
PRODRELPATH = _build/prod/rel/unir
APPNAME = unir
SHELL = /bin/bash

compile:
	$(REBAR) compile

release:
	$(REBAR) release
	mkdir -p $(RELPATH)/../unir_config
	[ -f $(RELPATH)/../unir_config/unir.conf ] || cp $(RELPATH)/etc/unir.conf  $(RELPATH)/../unir_config/unir.conf
	[ -f $(RELPATH)/../unir_config/advanced.config ] || cp $(RELPATH)/etc/advanced.config  $(RELPATH)/../unir_config/advanced.config

kill: 
	pkill -9 beam.smp; exit 0

console:
	cd $(RELPATH) && ./bin/unir console

logs:
	find . -name console.log | grep `ls -d ./_build/test/logs/ct_run* | tail -1` | xargs cat

tail-logs:
	find . -name console.log | grep `ls -d ./_build/test/logs/ct_run* | tail -1` | xargs tail -F

scale-up-test:
	$(REBAR) ct --readable=false -v --suite=unir_SUITE --case=scale_up_test

prod-release:
	$(REBAR) as prod release
	mkdir -p $(PRODRELPATH)/../unir_config
	[ -f $(PRODRELPATH)/../unir_config/unir.conf ] || cp $(PRODRELPATH)/etc/unir.conf  $(PRODRELPATH)/../unir_config/unir.conf
	[ -f $(PRODRELPATH)/../unir_config/advanced.config ] || cp $(PRODRELPATH)/etc/advanced.config  $(PRODRELPATH)/../unir_config/advanced.config

prod-console:
	cd $(PRODRELPATH) && ./bin/unir console

clean:
	$(REBAR) clean

test: kill release
	$(REBAR) ct

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

