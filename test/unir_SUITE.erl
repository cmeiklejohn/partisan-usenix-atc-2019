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
    LoaderFun = fun({_Name, Node}) ->
                            ct:pal("Loading applications on node: ~p", [Node]),

                            PrivDir = code:priv_dir(?APP),
                            NodeDir = filename:join([PrivDir, "lager", Node]),

                            %% Manually force sasl loading, and disable the logger.
                            ok = rpc:call(Node, application, load, [sasl]),
                            ok = rpc:call(Node, application, set_env,
                                          [sasl, sasl_error_logger, false]),
                            ok = rpc:call(Node, application, start, [sasl]),

                            ok = rpc:call(Node, application, load, [partisan]),
                            ok = rpc:call(Node, application, load, [lager]),
                            ok = rpc:call(Node, application, set_env, [sasl,
                                                                       sasl_error_logger,
                                                                       false]),
                            ok = rpc:call(Node, application, set_env, [lager,
                                                                       log_root,
                                                                       NodeDir]),
                            ok = rpc:call(Node, application, set_env,
                                          [riak_core,
                                           platform_data_dir,
                                           string:join([atom_to_list(Node), "data"], "_")])
                     end,
    lists:map(LoaderFun, Nodes),

    %% Configure settings.
    ConfigureFun = fun({_Name, Node}) ->
            %% Configure the peer service.
            PeerService = proplists:get_value(partisan_peer_service_manager, Options),
            ct:pal("Setting peer service maanger on node ~p to ~p", [Node, PeerService]),
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

    % ct:pal("Clustering nodes."),
    % lists:foreach(fun(Node) -> cluster(Node, Nodes, Options) end, Nodes),

    ct:pal("Nodes fully initialized: ~p", [Nodes]),

    Nodes.

%% @private
node_list(0, _Name, _Config) -> [];
node_list(N, Name, Config) ->
    [ list_to_atom(string:join([Name,
                                integer_to_list(?config(hash, Config)),
                                integer_to_list(X)],
                               "_")) ||
        X <- lists:seq(1, N) ].
