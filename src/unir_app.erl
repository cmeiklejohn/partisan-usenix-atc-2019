-module(unir_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    case unir_sup:start_link() of
        {ok, Pid} ->
            ok = riak_core:register([{vnode_module, unir_vnode}]),
            ok = riak_core_node_watcher:service_up(unir, self()),

            {ok, Pid};
        {error, Reason} ->
            {error, Reason}
    end.

stop(_State) ->
    ok.
