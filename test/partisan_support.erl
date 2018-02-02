-module(partisan_support).

-export([start/3, node_list/3]).

-define(APP, unir).
-define(GOSSIP_INTERVAL, 1000).
-define(PEER_IP, {127, 0, 0, 1}).
-define(PEER_PORT, 9000).
-define(PEER_SERVICE_SERVER, partisan_peer_service_server).
-define(FANOUT, 5).
-define(CACHE, partisan_connection_cache).
-define(PARALLELISM, 1).
-define(DEFAULT_CHANNEL, undefined).
-define(DEFAULT_PARTITION_KEY, undefined).
-define(CHANNELS, [?DEFAULT_CHANNEL]).
-define(CONNECTION_JITTER, 1000).
-define(DEFAULT_PEER_SERVICE_MANAGER, partisan_default_peer_service_manager).

-define(UTIL, partisan_plumtree_util).
-define(DEFAULT_LAZY_TICK_PERIOD, 1000).
-define(DEFAULT_EXCHANGE_TICK_PERIOD, 10000).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/inet.hrl").

%% @private
start(_Case, Config, Options) ->
    %% Launch distribution for the test runner.
    ct:pal("Launching Erlang distribution..."),

    {ok, Hostname} = inet:gethostname(), 
    os:cmd(os:find_executable("epmd") ++ " -daemon"),
    case net_kernel:start([list_to_atom("runner@" ++ Hostname), shortnames]) of
        {ok, _} ->
            ok;
        {error, {already_started, _}} ->
            ok
    end,

    %% Load sasl.
    application:load(sasl),
    ok = application:set_env(sasl,
                             sasl_error_logger,
                             false),
    application:start(sasl),

    %% Load lager.
    {ok, _} = application:ensure_all_started(lager),

    Servers = proplists:get_value(servers, Options, []),
    Clients = proplists:get_value(clients, Options, []),

    NodeNames = lists:flatten(Servers ++ Clients),

    %% Start all nodes.
    InitializerFun = fun(Name) ->
                            ct:pal("Starting node: ~p", [Name]),

                            NodeConfig = [{monitor_master, true},
                                          {startup_functions, [{code, set_path, [codepath()]}]}],

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
                                                                       NodeDir])
                     end,
    lists:map(LoaderFun, Nodes),

    %% Configure settings.
    ConfigureFun = fun({Name, Node}) ->
            %% Configure the peer service.
            PeerService = proplists:get_value(partisan_peer_service_manager, Options),
            ct:pal("Setting peer service manager on node ~p to ~p", [Node, PeerService]),
            ok = rpc:call(Node, partisan_config, set,
                          [partisan_peer_service_manager, PeerService]),

            MaxActiveSize = proplists:get_value(max_active_size, Options, 5),
            ok = rpc:call(Node, partisan_config, set,
                          [max_active_size, MaxActiveSize]),
                          
            ok = rpc:call(Node, partisan_config, set,
                          [gossip_interval, ?GOSSIP_INTERVAL]),

            ok = rpc:call(Node, application, set_env, [partisan, peer_ip, ?PEER_IP]),

            ForwardOptions = case ?config(forward_options, Config) of
                              undefined ->
                                  [];
                              FO ->
                                  FO
                          end,
            ct:pal("Setting forward_options to: ~p", [ForwardOptions]),
            ok = rpc:call(Node, partisan_config, set, [forward_options, ForwardOptions]),

            %% If users call partisan directly, and you want to ensure you dispatch
            %% using partisan and not riak core, please toggle this option.
            Disterl = case ?config(partisan_dispatch, Config) of
                              true ->
                                  false;
                              _ ->
                                  false
                          end,
            ct:pal("Setting disterl to: ~p", [Disterl]),
            ok = rpc:call(Node, partisan_config, set, [disterl, Disterl]),

            BinaryPadding = case ?config(binary_padding, Config) of
                              undefined ->
                                  false;
                              BP ->
                                  BP
                          end,
            ct:pal("Setting binary_padding to: ~p", [BinaryPadding]),
            ok = rpc:call(Node, partisan_config, set, [binary_padding, BinaryPadding]),

            Broadcast = case ?config(broadcast, Config) of
                              undefined ->
                                  false;
                              B ->
                                  B
                          end,
            ct:pal("Setting broadcast to: ~p", [Broadcast]),
            ok = rpc:call(Node, partisan_config, set, [broadcast, Broadcast]),

            Channels = case ?config(channels, Config) of
                              undefined ->
                                  ?CHANNELS;
                              C ->
                                  C
                          end,
            ct:pal("Setting channels to: ~p", [Channels]),
            ok = rpc:call(Node, partisan_config, set, [channels, Channels]),

            ok = rpc:call(Node, partisan_config, set, [tls, ?config(tls, Config)]),
            Parallelism = case ?config(parallelism, Config) of
                              undefined ->
                                  ?PARALLELISM;
                              P ->
                                  P
                          end,
            ct:pal("Setting parallelism to: ~p", [Parallelism]),
            ok = rpc:call(Node, partisan_config, set, [parallelism, Parallelism]),

            Servers = proplists:get_value(servers, Options, []),
            Clients = proplists:get_value(clients, Options, []),

            %% Configure servers.
            case lists:member(Name, Servers) of
                true ->
                    ok = rpc:call(Node, partisan_config, set, [tag, server]),
                    ok = rpc:call(Node, partisan_config, set, [tls_options, ?config(tls_server_opts, Config)]);
                false ->
                    ok
            end,

            %% Configure clients.
            case lists:member(Name, Clients) of
                true ->
                    ok = rpc:call(Node, partisan_config, set, [tag, client]),
                    ok = rpc:call(Node, partisan_config, set, [tls_options, ?config(tls_client_opts, Config)]);
                false ->
                    ok
            end
    end,
    lists:foreach(ConfigureFun, Nodes),

    ct:pal("Starting nodes."),

    StartFun = fun({_Name, Node}) ->
                        %% Start partisan.
                        {ok, _} = rpc:call(Node, application, ensure_all_started, [partisan]),
                        %% Start a dummy registered process that saves in the environment
                        %% whatever message it gets, it will only do this *x* amount of times
                        %% *x* being the number of nodes present in the cluster
                        Pid = rpc:call(Node, erlang, spawn,
                                       [fun() ->
                                            lists:foreach(fun(_) ->
                                                receive
                                                    {store, N} ->
                                                        %% save the number in the environment
                                                        application:set_env(partisan, forward_message_test, N)
                                                end
                                            end, lists:seq(1, length(NodeNames)))
                                        end]),
                        true = rpc:call(Node, erlang, register, [store_proc, Pid]),
                        ct:pal("registered store_proc on pid ~p, node ~p",
                               [Pid, Node])
               end,
    lists:foreach(StartFun, Nodes),

    ct:pal("Clustering nodes."),
    lists:foreach(fun(Node) -> cluster(Node, Nodes, Options, Config) end, Nodes),

    ct:pal("Partisan fully initialized."),

    Nodes.

%% @private
codepath() ->
    lists:filter(fun filelib:is_dir/1, code:get_path()).

%% @private
%%
%% We have to cluster each node with all other nodes to compute the
%% correct overlay: for instance, sometimes you'll want to establish a
%% client/server topology, which requires all nodes talk to every other
%% node to correctly compute the overlay.
%%
cluster({Name, _Node} = Myself, Nodes, Options, Config) when is_list(Nodes) ->
    Manager = proplists:get_value(partisan_peer_service_manager, Options),

    Servers = proplists:get_value(servers, Options, []),
    Clients = proplists:get_value(clients, Options, []),

    AmIServer = lists:member(Name, Servers),
    AmIClient = lists:member(Name, Clients),

    OtherNodes = case Manager of
                     partisan_default_peer_service_manager ->
                         %% Omit just ourselves.
                         omit([Name], Nodes);
                     partisan_amqp_peer_service_manager ->
                         %% Omit just ourselves.
                         omit([Name], Nodes);
                     partisan_client_server_peer_service_manager ->
                         case {AmIServer, AmIClient} of
                             {true, false} ->
                                %% If I'm a server, I connect to both
                                %% clients and servers!
                                omit([Name], Nodes);
                             {false, true} ->
                                %% I'm a client, pick servers.
                                omit(Clients, Nodes);
                             {_, _} ->
                                omit([Name], Nodes)
                         end;
                     partisan_hyparview_peer_service_manager ->
                        case {AmIServer, AmIClient} of
                            {true, false} ->
                               %% If I'm a server, I connect to both
                               %% clients and servers!
                               omit([Name], Nodes);
                            {false, true} ->
                               %% I'm a client, pick servers.
                               omit(Clients, Nodes);
                            {_, _} ->
                               omit([Name], Nodes)
                        end
                 end,
    lists:map(fun(OtherNode) -> cluster(Myself, OtherNode, Config) end, OtherNodes).
cluster({_, Node}, {_, OtherNode}, Config) ->
    PeerPort = rpc:call(OtherNode,
                        partisan_config,
                        get,
                        [peer_port, ?PEER_PORT]),
    Parallelism = case ?config(parallelism, Config) of
                      undefined ->
                          1;
                      P ->
                          P
                  end,
    Channels = case ?config(channels, Config) of
                      undefined ->
                          [];
                      C ->
                          C
                  end,
    JoinMethod = case ?config(sync_join, Config) of
                  undefined ->
                      join;
                  true ->
                      sync_join
                  end,
    ct:pal("Joining node: ~p to ~p at port ~p", [Node, OtherNode, PeerPort]),
    ok = rpc:call(Node,
                  partisan_peer_service,
                  JoinMethod,
                  [#{name => OtherNode,
                     listen_addrs => [#{ip => {127, 0, 0, 1}, port => PeerPort}],
                     channels => Channels,
                     parallelism => Parallelism}]).

omit(OmitNameList, Nodes0) ->
    FoldFun = fun({Name, _Node} = N, Nodes) ->
                    case lists:member(Name, OmitNameList) of
                        true ->
                            Nodes;
                        false ->
                            Nodes ++ [N]
                    end
              end,
    lists:foldl(FoldFun, [], Nodes0).

%% @private
node_list(0, _Name, _Config) -> 
    [];
node_list(N, Name, Config) ->
    [ list_to_atom(string:join([Name,
                                integer_to_list(?config(hash, Config)),
                                integer_to_list(X)],
                               "_")) ||
        X <- lists:seq(1, N) ].