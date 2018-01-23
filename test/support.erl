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

-module(support).
-author("Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>").

-compile([export_all]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/inet.hrl").

-define(APP, unir).

-define(SLEEP, 30000).

-define(DEFAULT_PARALLELISM, 1).
-define(DEFAULT_CHANNELS, [broadcast, vnode, {monotonic, gossip}]).

-define(METADATA_PREFIX, {test, test}).
-define(METADATA_KEY, key).
-define(METADATA_VALUE, value).

%% ===================================================================
%% Internal functions.
%% ===================================================================

%% @private
stop(Nodes) ->
    StopFun = fun({Name, _Node}) ->
        ct:pal("Stopping node: ~p", [Name]),

        case ct_slave:stop(Name) of
            {ok, _} ->
                ok;
            {error, stop_timeout, _} ->
                ct:pal("Stop failed for node: ~p", [Name]),
                ok;
            {error, not_started, _} ->
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
    Hostname = "127.0.0.1",
    case net_kernel:start([list_to_atom("runner@" ++ Hostname), longnames]) of
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
    NumNodes = proplists:get_value(num_nodes, Options, 3),
    NodeNames = node_list(NumNodes, "node", Config),

    %% Start all nodes.
    InitializerFun = fun(Name) ->
                            ct:pal("Starting node: ~p", [Name]),

                            NodeConfig = [{monitor_master, true},
                                          {erl_flags, "-smp"}, %% smp for the eleveldb god
                                          {startup_functions,
                                           [{code, set_path, [codepath()]}]}],

                            case ct_slave:start(Name, NodeConfig) of
                                {ok, Node} ->
                                    ct:pal("Node started: ~p", [Node]),
                                    {Name, Node};
                                Error ->
                                    ct:fail(Error)
                            end
                     end,
    Nodes = lists:map(InitializerFun, NodeNames),

    %% Ping nodes to ensure we are connected via disterl.
    ConnectionFun = fun({_Name, Node}) ->
        case net_adm:ping(Node) of
            pong ->
                ok;
            pang ->
                ct:fail("Failed to connect to node ~p with distributed Erlang.", [Node]),
                ok
        end
    end, 
    lists:map(ConnectionFun, Nodes),

    %% Load applications on all of the nodes.
    LoaderFun = fun({Name, Node}) ->
                            % ct:pal("Loading applications on node: ~p", [Node]),

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

                            % ct:print("Node dir: ~p", [NodeDir]),

                            PlatformDir = NodeDir ++ "/data/",
                            RingDir = PlatformDir ++ "/ring/",
                            NumberOfVNodes = 1024,

                            %% Eagerly create incase it doesn't exist
                            %% and delete to remove any state that
                            %% remains between test executions.
                            filelib:ensure_dir(PlatformDir),
                            del_dir(PlatformDir),

                            %% Recreate directories before starting
                            %% Riak Core.
                            filelib:ensure_dir(PlatformDir),
                            filelib:ensure_dir(RingDir),

                            ok = rpc:call(Node, application, set_env, [riak_core, cluster_name, atom_to_list(default)]),
                            ok = rpc:call(Node, application, set_env, [riak_core, riak_state_dir, RingDir]),
                            ok = rpc:call(Node, application, set_env, [riak_core, ring_creation_size, NumberOfVNodes]),

                            ok = rpc:call(Node, application, set_env, [riak_core, platform_data_dir, PlatformDir]),
                            ok = rpc:call(Node, application, set_env, [riak_core, handoff_ip, "127.0.0.1"]),
                            ok = rpc:call(Node, application, set_env, [riak_core, handoff_port, web_ports(Name) + 3]),

                            ok = rpc:call(Node, application, set_env, [riak_core, schema_dirs, ["../../../../_build/default/rel/" ++ atom_to_list(?APP) ++ "/share/schema/"]]),

                            ok = rpc:call(Node, application, set_env, [riak_api, pb_port, web_ports(Name) + 2]),
                            ok = rpc:call(Node, application, set_env, [riak_api, pb_ip, "127.0.0.1"])
                     end,
    lists:map(LoaderFun, Nodes),

    %% Configure settings.
    ConfigureFun = fun({_Name, Node}) ->
            %% Configure the peer service.
            PeerService = proplists:get_value(partisan_peer_service_manager, Options),
            ok = rpc:call(Node, partisan_config, set, [partisan_peer_service_manager, PeerService]),

            %% Configure binary padding in Riak Core.
            BinaryPadding = ?config(binary_padding, Config),
            case BinaryPadding of
                true ->
                    ct:pal("Enabling binary padding."),
                    ok = rpc:call(Node, partisan_config, set, [binary_padding, BinaryPadding]);
                _ ->
                    ok
            end,

            %% Configure vnode partitioning in Riak Core.
            VnodePartitioning = ?config(vnode_partitioning, Config),
            case VnodePartitioning of
                true ->
                    ct:pal("Enabling vnode partitioning."),
                    ok = rpc:call(Node, partisan_config, set, [vnode_partitioning, VnodePartitioning]);
                _ ->
                    ok
            end,

            %% Get parallelism factor.
            Parallelism = ?config(parallelism, Config),
            case Parallelism of
                undefined -> 
                    ct:pal("Using default level of parallelism."),
                    ok = rpc:call(Node, partisan_config, set, [parallelism, ?DEFAULT_PARALLELISM]);
                _ ->
                    ct:pal("Using ~p level of parallelism.", [Parallelism]),
                    ok = rpc:call(Node, partisan_config, set, [parallelism, Parallelism])
            end,

            %% Configure partisan dispatch in Riak Core.
            PartisanDispatch = ?config(partisan_dispatch, Config),
            case PartisanDispatch of
                true ->
                    ct:pal("Enabling partisan dispatch on node ~p!", [Node]);
                _ ->
                    ok
            end,
            ok = rpc:call(Node, application, set_env, [riak_core, partisan_dispatch, PartisanDispatch]),

            MaxActiveSize = proplists:get_value(max_active_size, Options, 5),
            ok = rpc:call(Node, partisan_config, set, [persist_state, false]),
            ok = rpc:call(Node, partisan_config, set, [max_active_size, MaxActiveSize]),
            ok = rpc:call(Node, partisan_config, set, [tls, ?config(tls, Config)]),
            ok = rpc:call(Node, partisan_config, set, [channels, ?DEFAULT_CHANNELS]),
            ok = rpc:call(Node, partisan_config, set, [gossip, false])
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
                        end,

                        %% Start app.
                        {ok, _}  = rpc:call(Node,
                                            application, ensure_all_started,
                                            [?APP]),
                        ct:pal("Started node ~p", [Node])
               end,
    lists:foreach(StartFun, Nodes),

    %% Determine if we should cluster the nodes or not.
    ClusterNodes = proplists:get_value(cluster_nodes, Options, true),
    case ClusterNodes of
        true ->
            ct:pal("Clustering nodes."),
            ok = join_cluster([Node || {_Name, Node} <- Nodes]);
        false ->
            ct:pal("Skipping cluster formation.")
    end,

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
web_ports(Name) ->
    NameList = atom_to_list(Name),
    [_|[Number]] = string:tokens(NameList, "_"),
    10005 + (list_to_integer(Number) * 10).

%% @private
join_cluster(Nodes) ->
    %% Ensure each node owns 100% of it's own ring
    [?assertEqual([Node], owners_according_to(Node)) || Node <- Nodes],

    %% Join nodes
    [Node1|OtherNodes] = Nodes,
    case OtherNodes of
        [] ->
            %% no other nodes, nothing to join/plan/commit
            ok;
        _ ->
            case length(Nodes) > 2 of
                true ->
                    %% ok do a staged join and then commit it, this eliminates the
                    %% large amount of redundant handoff done in a sequential join
                    [staged_join(Node, Node1) || Node <- OtherNodes],

                    %% Sleep for partisan connections to be setup.
                    timer:sleep(?SLEEP),

                    plan_and_commit(Node1),

                    try_nodes_ready(Nodes, 3, 500);
                false ->
                    %% do the standard join.
                    [join(Node, Node1) || Node <- OtherNodes]
            end
    end,

    ?assertEqual(ok, wait_until_nodes_ready(Nodes)),

    %% Ensure each node owns a portion of the ring
    ?assertEqual(ok, wait_until_nodes_agree_about_ownership(Nodes)),
    ?assertEqual(ok, wait_until_no_pending_changes(Nodes)),
    ?assertEqual(ok, wait_until_ring_converged(Nodes)),

    ok.

%% @private
owners_according_to(Node) ->
    case rpc:call(Node, riak_core_ring_manager, get_raw_ring, []) of
        {ok, Ring} ->
            % lager:info("Ring ~p", [Ring]),
            Owners = [Owner || {_Idx, Owner} <- riak_core_ring:all_owners(Ring)],
            % lager:info("Owners according to ~p: ~p", [Node, lists:usort(Owners)]),
            lists:usort(Owners);
        {badrpc, _}=BadRpc ->
            lager:info("Badrpc"),
            BadRpc
    end.

%% @private
join(Node, PNode) ->
    timer:sleep(5000),
    R = rpc:call(Node, riak_core, join, [PNode]),
    lager:info("[join] ~p to (~p): ~p", [Node, PNode, R]),
    ?assertEqual(ok, R),
    ok.

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
    % lager:info("planning and committing cluster join"),
    case rpc:call(Node, riak_core_claimant, plan, []) of
        {error, ring_not_ready} ->
            ct:pal("plan: ring not ready"),
            timer:sleep(5000),
            maybe_wait_for_changes(Node),
            plan_and_commit(Node);
        {ok, _Actions, _RingTransitions} ->
            % ct:pal("Actions for ring transition: ~p", [Actions]),
            do_commit(Node);
        Other ->
            ct:fail("Claimant returned: ~p", [Other])
    end.

%% @private
do_commit(Node) ->
    % lager:info("Committing"),
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
            %% Keep waiting...
            % ct:pal("Nothing planned!"),
            plan_and_commit(Node);
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
    % lager:info("Wait until no pending changes on ~p", [Nodes]),
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
    % lager:info("Wait until nodes are ready : ~p", [Nodes]),
    [?assertEqual(ok, wait_until(Node, fun is_ready/1)) || Node <- Nodes],
    ok.

%% @private
is_ready(Node) ->
    case rpc:call(Node, riak_core_ring_manager, get_raw_ring, []) of
        {ok, Ring} ->
            case lists:member(Node, riak_core_ring:ready_members(Ring)) of
                true ->
                    true;
                false ->
                    {not_ready, Node}
            end;
        Other ->
            Other
    end.

%% @private
wait_until_nodes_agree_about_ownership(Nodes) ->
    ct:pal("Wait until nodes agree about ownership ~p", [Nodes]),
    Results = [ wait_until_owners_according_to(Node, Nodes) || Node <- Nodes ],
    ?assert(lists:all(fun(X) -> ok =:= X end, Results)).

%% @private
wait_until(Node, Fun) when is_atom(Node), is_function(Fun) ->
    wait_until(fun() -> Fun(Node) end).

%% @private
wait_until_owners_according_to(Node, Nodes) ->
    ct:pal("Waiting until node ~p agrees ownership on ~p", [Node, Nodes]),
  SortedNodes = lists:usort(Nodes),
  F = fun(N) ->
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
    % lager:info("Wait until ring converged on ~p", [Nodes]),
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

%% @private
del_dir(Dir) ->
   lists:foreach(fun(D) ->
                    ok = file:del_dir(D)
                 end, del_all_files([Dir], [])).

%% @private
del_all_files([], EmptyDirs) ->
   EmptyDirs;
del_all_files([Dir | T], EmptyDirs) ->
   {ok, FilesInDir} = file:list_dir(Dir),
   {Files, Dirs} = lists:foldl(fun(F, {Fs, Ds}) ->
                                  Path = Dir ++ "/" ++ F,
                                  case filelib:is_dir(Path) of
                                     true ->
                                          {Fs, [Path | Ds]};
                                     false ->
                                          {[Path | Fs], Ds}
                                  end
                               end, {[],[]}, FilesInDir),
   lists:foreach(fun(F) ->
                         ok = file:delete(F)
                 end, Files),
   del_all_files(T ++ Dirs, [Dir | EmptyDirs]).

%% @private
verify_open_connections(Me, Others, Connections) ->
    %% Verify we have connections to the peers we should have.
    R = lists:map(fun(Other) ->
                        Parallelism = rpc:call(Me, partisan_config, get, [parallelism, ?DEFAULT_PARALLELISM]),
                        OtherName = rpc:call(Other, partisan_peer_service_manager, myself, []),
                        DesiredConnections = Parallelism * (length(?DEFAULT_CHANNELS) + 1),
                        case dict:find(OtherName, Connections) of
                            {ok, Active} ->
                                case length(Active) of
                                    DesiredConnections ->
                                        true;
                                    _ ->
                                        false
                                end;
                            error ->
                                false
                        end
                  end, Others -- [Me]),

    OthersOpen = lists:all(fun(X) -> X =:= true end, R),

    %% Verify we don't have connetions to ourself.
    SelfOpen = case dict:find(Me, Connections) of
        {ok, _} ->
            false;
        error ->
            true
    end,

    SelfOpen andalso OthersOpen.

%% @private
verify_all_connections(Nodes) ->
    R = lists:map(fun(Node) ->
                        case rpc:call(Node, partisan_peer_service, connections, []) of
                            {ok, Connections} ->
                                verify_open_connections(Node, Nodes, Connections);
                            _ ->
                                false

                          end
                  end, Nodes),

    lists:all(fun(X) -> X =:= true end, R).

%% @private
wait_until_all_connections(Nodes) ->
    F = fun() ->
                verify_all_connections(Nodes)
        end,
    wait_until(F).

%% @private
verify_partisan_membership(Nodes) ->
    R = lists:map(fun(Node) ->
                          case rpc:call(Node, partisan_peer_service, members, []) of
                            {ok, JoinedNodes} ->
                                  case lists:usort(JoinedNodes) =:= Nodes of
                                      true ->
                                          true;
                                      false -> 
                                          ct:pal("Membership on node ~p is not right: ~p but should be ~p", [Node, JoinedNodes, Nodes]),
                                          false
                                  end;
                            Error ->
                                  ct:fail("Cannot retrieve membership: ~p", [Error])
                          end
                  end, Nodes),

    lists:all(fun(X) -> X =:= true end, R).

%% @private
wait_until_partisan_membership(Nodes) ->
    F = fun() ->
                verify_partisan_membership(Nodes)
        end,
    wait_until(F).

%% @private
wait_until_metadata_read(Nodes) ->
    F = fun() ->
                verify_metadata_read(Nodes)
        end,
    wait_until(F).

%% @private
verify_metadata_read(Nodes) ->
    %% Verify that we can read that value at all nodes.
    R = lists:map(fun(Node) ->
                          case rpc:call(Node, riak_core_metadata, get, [?METADATA_PREFIX, ?METADATA_KEY]) of
                              ?METADATA_VALUE ->
                                  true;
                              _ ->
                                  false
                          end
                  end,  Nodes),

    lists:all(fun(X) -> X =:= true end, R).

%% @private
perform_metadata_write(Node) ->
    case rpc:call(Node, riak_core_metadata, put, [?METADATA_PREFIX, ?METADATA_KEY, ?METADATA_VALUE]) of
        ok ->
            ok;
        _ ->
            error
    end.

%% @private
leave(Node) ->
    case rpc:call(Node, riak_core, leave, []) of
        ok ->
            ok;
        _ ->
            error
    end.

%% @private
scale(Nodes) ->
    [{_, Node1}, {_, Node2}|ToBeJoined] = Nodes,
    InitialCluster = [Node1, Node2],

    %% Cluster the first two ndoes.
    ct:pal("Building initial cluster: ~p", [InitialCluster]),
    ?assertEqual(ok, join_cluster(InitialCluster)),

    %% Verify appropriate number of connections.
    ct:pal("Verifying connections for initial cluster: ~p", [InitialCluster]),
    ?assertEqual(ok, wait_until_all_connections(InitialCluster)),

    lists:foldl(fun({_, Node}, CurrentCluster) ->
        %% Join another node.
        ct:pal("Joining ~p to ~p", [Node, Node1]),
        ?assertEqual(ok, staged_join(Node, Node1)),

        %% Plan will only succeed once the ring has been gossiped.
        ct:pal("Committing plan."),
        ?assertEqual(ok, plan_and_commit(Node1)),

        %% Verify appropriate number of connections.
        NewCluster = CurrentCluster ++ [Node],
        ct:pal("Verifying connections for expanded cluster: ~p", [NewCluster]),
        ?assertEqual(ok, wait_until_all_connections(NewCluster)),

        %% Ensure each node owns a portion of the ring
        ?assertEqual(ok, wait_until_nodes_agree_about_ownership(NewCluster)),
        ?assertEqual(ok, wait_until_no_pending_changes(NewCluster)),
        ?assertEqual(ok, wait_until_ring_converged(NewCluster)),

        NewCluster
    end, InitialCluster, ToBeJoined),

    %% Print final member status to the log.
    rpc:call(Node1, riak_core_console, member_status, [[]]),
    
    stop(Nodes),

    ok.

%% @private
rand_bits(Bits) ->
        Bytes = (Bits + 7) div 8,
        <<Result:Bits/bits, _/bits>> = crypto:strong_rand_bytes(Bytes),
        Result.

%% @private
default_bench_configuration() ->
    [{bench_config, "default.config"}].

%% @private
bench_config() ->
    case os:getenv("BENCH_CONFIG", "") of
        false ->
            ct:pal("Bench configuration not specified, using default."),
            default_bench_configuration();
        "" ->
            ct:pal("Bench configuration null, using default."),
            default_bench_configuration();
        Config ->
            ct:pal("Using alternative bench config: ~p", [Config]),
            [{bench_config, Config}]
    end.

%% @private
root_path(Config) ->
    DataDir = proplists:get_value(data_dir, Config, ""),
    DataDir ++ "../../../../../".

%% @private
root_dir(Config) ->
    RootCommand = "cd " ++ root_path(Config) ++ "; pwd",
    RootOutput = os:cmd(RootCommand),
    RootDir = string:substr(RootOutput, 1, length(RootOutput) - 1) ++ "/",
    ct:pal("RootDir: ~p", [RootDir]),
    RootDir.