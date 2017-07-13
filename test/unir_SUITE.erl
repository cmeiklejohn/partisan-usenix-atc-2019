%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Christopher S. Meiklejohn.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
%%

-module(unir_SUITE).
-author("Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>").

%% common_test callbacks
-export([%% suite/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2,
         all/0,
         %% groups/0,
         init_per_group/2]).

%% tests
-compile([export_all]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/inet.hrl").

-define(APP, partisan).
-define(CLIENT_NUMBER, 3).
-define(PEER_PORT, 9000).

%% ===================================================================
%% common_test callbacks
%% ===================================================================

init_per_suite(_Config) ->
    _Config.

end_per_suite(_Config) ->
    _Config.

init_per_testcase(Case, Config) ->
    ct:pal("Beginning test case ~p", [Case]),
    [{hash, erlang:phash2({Case, Config})}|Config].

end_per_testcase(Case, _Config) ->
    ct:pal("Ending test case ~p", [Case]),
    _Config.

init_per_group(_, Config) ->
    Config.

end_per_group(_, _Config) ->
    ok.

all() ->
    [build_cluster_test].

%% ===================================================================
%% Tests.
%% ===================================================================

build_cluster_test(Config) ->
    Nodes = start(build_cluster_test,
                  Config,
                  [{partisan_peer_service_manager,
                    partisan_default_peer_service_manager}]),

    stop(Nodes),

    ct:fail(fail),

    ok.

%% ===================================================================
%% Internal functions.
%% ===================================================================

%% @private
stop(Nodes) ->
    StopFun = fun({Name, _Node}) ->
        case ct_slave:stop(Name) of
            {ok, _} ->
                ok;
            Error ->
                ct:fail(Error)
        end
    end,
    lists:map(StopFun, Nodes),
    ok.

%% @private
codepath() ->
    lists:filter(fun filelib:is_dir/1, code:get_path()).

%% @private
start(_Case, Config, Options) ->
    %% Launch distribution for the test runner.
    ct:pal("Launching Erlang distribution..."),

    os:cmd(os:find_executable("epmd") ++ " -daemon"),
    {ok, Hostname} = inet:gethostname(),
    case net_kernel:start([list_to_atom("runner@" ++ Hostname), shortnames]) of
        {ok, _} ->
            ok;
        {error, {already_started, _}} ->
            ok
    end,

    %% Load sasl.
    application:load(sasl),
    ok = application:set_env(sasl, sasl_error_logger, false),
    application:start(sasl),

    %% Load lager.
    {ok, _} = application:ensure_all_started(lager),

    %% Generate node names.
    NodeNames = node_list(5, "unir", Config),

    %% Start all nodes.
    InitializerFun = fun(Name) ->
                            ct:pal("Starting node: ~p", [Name]),

                            NodeConfig = [{monitor_master, true},
                                          {startup_functions,
                                           [{code, set_path, [codepath()]}]}],

                            case ct_slave:start(Name, NodeConfig) of
                                {ok, Node} ->
                                    {Name, Node};
                                Error ->
                                    ct:fail(Error)
                            end
                     end,
    Nodes = lists:map(InitializerFun, NodeNames),

    %% Load applications on all of the nodes.
    LoaderFun = fun({Name, Node}) ->
                            ct:pal("Loading applications on node: ~p", [Node]),

                            PrivDir = proplists:get_value(priv_dir, Config),
                            NodeDir = filename:join([PrivDir, Node]),

                            %% Manually force sasl loading, and disable the logger.
                            ok = rpc:call(Node, application, load, [sasl]),
                            ok = rpc:call(Node, application, set_env, [sasl, sasl_error_logger, false]),
                            ok = rpc:call(Node, application, start, [sasl]),

                            ok = rpc:call(Node, application, load, [partisan]),
                            ok = rpc:call(Node, application, load, [lager]),
                            ok = rpc:call(Node, application, load, [riak_core]),
                            ok = rpc:call(Node, application, set_env, [lager, log_root, NodeDir]),

                            ct:print("Node dir: ~p", [NodeDir]),

                            PlatformDir = NodeDir ++ "/data/",
                            RingDir = PlatformDir ++ "/ring/",
                            NumberOfVNodes = 4,
                            filelib:ensure_dir(PlatformDir),
                            filelib:ensure_dir(RingDir),

                            ok = rpc:call(Node, application, set_env, [riak_core, riak_state_dir, RingDir]),
                            ok = rpc:call(Node, application, set_env, [riak_core, ring_creation_size, NumberOfVNodes]),

                            ok = rpc:call(Node, application, set_env, [riak_core, platform_data_dir, PlatformDir]),
                            ok = rpc:call(Node, application, set_env, [riak_core, handoff_port, web_ports(Name) + 3]),

                            ok = rpc:call(Node, application, set_env,
                                          [riak_core, schema_dirs,
                                           ["../../../../_build/default/rel/unir/share/schema/"]]),

                            ok = rpc:call(Node, application, set_env, [riak_api, pb_port, web_ports(Name) + 2]),
                            ok = rpc:call(Node, application, set_env, [riak_api, pb_ip, "127.0.0.1"])
                     end,
    lists:map(LoaderFun, Nodes),

    %% Configure settings.
    ConfigureFun = fun({_Name, Node}) ->
            %% Configure the peer service.
            PeerService = proplists:get_value(partisan_peer_service_manager, Options),
            ok = rpc:call(Node, partisan_config, set,
                          [partisan_peer_service_manager, PeerService]),

            MaxActiveSize = proplists:get_value(max_active_size, Options, 5),
            ok = rpc:call(Node, partisan_config, set,
                          [max_active_size, MaxActiveSize]),

            ok = rpc:call(Node, partisan_config, set, [tls, ?config(tls, Config)]),
            ok = rpc:call(Node, partisan_config, set, [parallelism, ?config(parallelism, Config)])
    end,
    lists:foreach(ConfigureFun, Nodes),

    ct:pal("Starting nodes."),

    StartFun = fun({_Name, Node}) ->
                        %% Start partisan.
                        {ok, _} = rpc:call(Node,
                                           application, ensure_all_started,
                                           [partisan]),

                        %% Start riak_core.
                        CoreResult = rpc:call(Node,
                                              application, ensure_all_started,
                                              [riak_core]),
                        case CoreResult of
                            {ok, _} ->
                                ok;
                            Error ->
                                ct:pal("Riak Core failed to start: ~p",
                                       [Error]),
                                ct:fail(riak_core_failure)
                        end
               end,
    lists:foreach(StartFun, Nodes),

    ct:pal("Clustering nodes."),
    join_cluster([Node || {_Name, Node} <- Nodes]),

    ct:pal("Nodes fully initialized: ~p", [Nodes]),

    Nodes.

%% @private
node_list(0, _Name, _Config) -> [];
node_list(N, Name, _Config) ->
    [ list_to_atom(string:join([Name,
                                integer_to_list(X)],
                               "_")) ||
        X <- lists:seq(1, N) ].

%% @private
web_ports(unir_1) ->
    10015;
web_ports(unir_2) ->
    10025;
web_ports(unir_3) ->
    10035;
web_ports(unir_4) ->
    10045;
web_ports(unir_5) ->
    10055;
web_ports(Other) ->
    ct:fail(Other).

%% @private
join_cluster(Nodes) ->
    %% Ensure each node owns 100% of it's own ring
    [ct:pal("Owners: ~p", [owners_according_to(Node)]) || Node <- Nodes],
    [?assertEqual([Node], owners_according_to(Node)) || Node <- Nodes],
    %% Join nodes
    [Node1|OtherNodes] = Nodes,
    case OtherNodes of
        [] ->
            %% no other nodes, nothing to join/plan/commit
            ok;
        _ ->
            %% ok do a staged join and then commit it, this eliminates the
            %% large amount of redundant handoff done in a sequential join
            [staged_join(Node, Node1) || Node <- OtherNodes],
            plan_and_commit(Node1),
            try_nodes_ready(Nodes, 3, 500)
    end,

    ?assertEqual(ok, wait_until_nodes_ready(Nodes)),

    %% Ensure each node owns a portion of the ring
    wait_until_nodes_agree_about_ownership(Nodes),
    ?assertEqual(ok, wait_until_no_pending_changes(Nodes)),
    wait_until_ring_converged(Nodes),
    wait_until(hd(Nodes), fun wait_init:check_ready/1),
    ok.

%% @private
owners_according_to(Node) ->
    case rpc:call(Node, riak_core_ring_manager, get_raw_ring, []) of
        {ok, Ring} ->
            lager:info("Ring ~p", [Ring]),
            Owners = [Owner || {_Idx, Owner} <- riak_core_ring:all_owners(Ring)],
            lager:info("Owners ~p", [lists:usort(Owners)]),
            lists:usort(Owners);
        {badrpc, _}=BadRpc ->
            lager:info("Badrpc"),
            BadRpc
    end.

%% @private
staged_join(Node, PNode) ->
    timer:sleep(5000),
    R = rpc:call(Node, riak_core, staged_join, [PNode]),
    lager:info("[join] ~p to (~p): ~p", [Node, PNode, R]),
    ?assertEqual(ok, R),
    ok.

%% @private
plan_and_commit(Node) ->
    timer:sleep(5000),
    lager:info("planning and committing cluster join"),
    case rpc:call(Node, riak_core_claimant, plan, []) of
        {error, ring_not_ready} ->
            lager:info("plan: ring not ready"),
            timer:sleep(5000),
            maybe_wait_for_changes(Node),
            plan_and_commit(Node);
        {ok, _, _} ->
            do_commit(Node)
    end.

%% @private
do_commit(Node) ->
    lager:info("Committing"),
    case rpc:call(Node, riak_core_claimant, commit, []) of
        {error, plan_changed} ->
            lager:info("commit: plan changed"),
            timer:sleep(100),
            maybe_wait_for_changes(Node),
            plan_and_commit(Node);
        {error, ring_not_ready} ->
            lager:info("commit: ring not ready"),
            timer:sleep(100),
            maybe_wait_for_changes(Node),
            do_commit(Node);
        {error, nothing_planned} ->
            %% Assume plan actually committed somehow
            ok;
        ok ->
            ok
    end.

%% @private
try_nodes_ready([Node1 | _Nodes], 0, _SleepMs) ->
      lager:info("Nodes not ready after initial plan/commit, retrying"),
      plan_and_commit(Node1);
  try_nodes_ready(Nodes, N, SleepMs) ->
      ReadyNodes = [Node || Node <- Nodes, is_ready(Node) =:= true],
      case ReadyNodes of
          Nodes ->
              ok;
          _ ->
              timer:sleep(SleepMs),
              try_nodes_ready(Nodes, N-1, SleepMs)
      end.

%% @private
maybe_wait_for_changes(Node) ->
    wait_until_no_pending_changes([Node]).

%% @private
wait_until_no_pending_changes(Nodes) ->
    lager:info("Wait until no pending changes on ~p", [Nodes]),
    F = fun() ->
                rpc:multicall(Nodes, riak_core_vnode_manager, force_handoffs, []),
                {Rings, BadNodes} = rpc:multicall(Nodes, riak_core_ring_manager, get_raw_ring, []),
                Changes = [ riak_core_ring:pending_changes(Ring) =:= [] || {ok, Ring} <- Rings ],
                BadNodes =:= [] andalso length(Changes) =:= length(Nodes) andalso lists:all(fun(T) -> T end, Changes)
        end,
    ?assertEqual(ok, wait_until(F)),
    ok.

%% @private
wait_until(Fun) when is_function(Fun) ->
    MaxTime = 600000, %% @TODO use config,
        Delay = 1000, %% @TODO use config,
        Retry = MaxTime div Delay,
    wait_until(Fun, Retry, Delay).

%% @private
wait_until_nodes_ready(Nodes) ->
    lager:info("Wait until nodes are ready : ~p", [Nodes]),
    [?assertEqual(ok, wait_until(Node, fun is_ready/1)) || Node <- Nodes],
    ok.

%% @private
is_ready(Node) ->
    case rpc:call(Node, riak_core_ring_manager, get_raw_ring, []) of
        {ok, Ring} ->
            case lists:member(Node, riak_core_ring:ready_members(Ring)) of
                true -> true;
                false -> {not_ready, Node}
            end;
        Other ->
            Other
    end.

%% @private
wait_until_nodes_agree_about_ownership(Nodes) ->
    lager:info("Wait until nodes agree about ownership ~p", [Nodes]),
    Results = [ wait_until_owners_according_to(Node, Nodes) || Node <- Nodes ],
    ?assert(lists:all(fun(X) -> ok =:= X end, Results)).

%% @private
wait_until(Node, Fun) when is_atom(Node), is_function(Fun) ->
    wait_until(fun() -> Fun(Node) end).

%% @private
wait_until_owners_according_to(Node, Nodes) ->
  SortedNodes = lists:usort(Nodes),
  F = fun(N) ->
      ct:pal("Owners: ~p, SortedNodes: ~p", [owners_according_to(N), SortedNodes]),
      owners_according_to(N) =:= SortedNodes
  end,
  ?assertEqual(ok, wait_until(Node, F)),
  ok.

%% @private
is_ring_ready(Node) ->
    case rpc:call(Node, riak_core_ring_manager, get_raw_ring, []) of
        {ok, Ring} ->
            riak_core_ring:ring_ready(Ring);
        _ ->
            false
    end.

%% @private
wait_until_ring_converged(Nodes) ->
    lager:info("Wait until ring converged on ~p", [Nodes]),
    [?assertEqual(ok, wait_until(Node, fun is_ring_ready/1)) || Node <- Nodes],
    ok.

%% @private
wait_until(Fun, Retry, Delay) when Retry > 0 ->
    wait_until_result(Fun, true, Retry, Delay).

%% @private
wait_until_result(Fun, Result, Retry, Delay) when Retry > 0 ->
    Res = Fun(),
    case Res of
        Result ->
            ok;
        _ when Retry == 1 ->
            {fail, Res};
        _ ->
            timer:sleep(Delay),
            wait_until_result(Fun, Result, Retry-1, Delay)
    end.
