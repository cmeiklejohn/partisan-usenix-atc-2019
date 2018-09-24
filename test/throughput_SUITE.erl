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

-module(throughput_SUITE).
-author("Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>").

%% common_test callbacks
-export([suite/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2,
         all/0,
         groups/0,
         init_per_group/2]).

%% tests
-compile([export_all]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/inet.hrl").

-define(SUPPORT, support).

%% ===================================================================
%% common_test callbacks
%% ===================================================================

suite() ->
    [{timetrap, {hours, 10}}].

init_per_suite(_Config) ->
    _Config.

end_per_suite(_Config) ->
    _Config.

init_per_testcase(Case, Config) ->
    ct:pal("Beginning test case ~p", [Case]),
    [{hash, erlang:phash2({Case, Config})}|Config].

end_per_testcase(Case, Config) ->
    ct:pal("Ending test case ~p", [Case]),
    Config.

init_per_group(disterl, Config) ->
    Config;

init_per_group(partisan, Config) ->
    [{pid_encoding, false}, {partisan_dispatch, true}] ++ Config;

init_per_group(partisan_with_parallelism, Config) ->
    parallelism() ++ init_per_group(partisan, Config);
init_per_group(partisan_with_channels, Config) ->
    channels() ++ init_per_group(partisan, Config);
init_per_group(partisan_with_monotonic_channels, Config) ->
    monotonic_channels() ++ init_per_group(partisan, Config);
init_per_group(partisan_with_partitioned_parallelism, Config) ->
    parallelism() ++ [{vnode_partitioning, true}] ++ init_per_group(partisan, Config);
init_per_group(partisan_with_partitioned_parallelism_and_channels, Config) ->
    channels() ++ parallelism() ++ [{vnode_partitioning, true}] ++ init_per_group(partisan, Config);
init_per_group(partisan_with_partitioned_parallelism_and_channels_and_monotonic_channels, Config) ->
    monotonic_channels() ++ parallelism() ++ [{vnode_partitioning, true}] ++ init_per_group(partisan, Config);
init_per_group(partisan_with_binary_padding, Config) ->
    [{binary_padding, true}] ++ init_per_group(partisan, Config);
init_per_group(partisan_with_vnode_partitioning, Config) ->
    [{vnode_partitioning, true}] ++ init_per_group(partisan, Config);

init_per_group(bench, Config) ->
    ?SUPPORT:bench_config() ++ Config;

init_per_group(_, Config) ->
    Config.

end_per_group(_, _Config) ->
    ok.

all() ->
    [
     {group, default, []}
    ].

groups() ->
    [
     {bench, [],
      [%% bench_test,
       fsm_performance_test,
       partisan_performance_test,
       echo_performance_test]},

     {default, [],
      [{group, bench}] },

     {disterl, [],
      [{group, bench}] },
     
     {partisan, [],
      [{group, bench}]},

     {partisan_with_parallelism, [],
      [{group, bench}]},

     {partisan_with_channels, [],
      [{group, bench}]},

     {partisan_with_monotonic_channels, [],
      [{group, bench}]},

     {partisan_with_partitioned_parallelism, [],
      [{group, bench}]},

     {partisan_with_partitioned_parallelism_and_channels, [],
      [{group, bench}]},

     {partisan_with_partitioned_parallelism_and_channels_and_monotonic_channels, [],
      [{group, bench}]},

     {partisan_with_binary_padding, [],
      [{group, bench}]},

     {partisan_with_vnode_partitioning, [],
      [{group, bench}]}
    ].

%% ===================================================================
%% Tests.
%% ===================================================================

partisan_performance_test(Config) ->
    Manager = partisan_default_peer_service_manager,

    Nodes = case os:getenv("PARTISAN_INIT", false) of
        "true" ->
            %% Specify servers.
            Servers = partisan_support:node_list(1, "server", Config),

            %% Specify clients.
            Clients = partisan_support:node_list(1, "client", Config),

            %% Start nodes.
            partisan_support:start(partisan_performance_test, Config,
                                   [{partisan_peer_service_manager, Manager},
                                   {servers, Servers},
                                   {clients, Clients}]);
        _ ->
            ?SUPPORT:start(partisan_performance_test,
                           Config,
                           [{num_nodes, 3},
                           {partisan_peer_service_manager, Manager}])
    end,

    App = case os:getenv("PARTISAN_INIT", false) of
        "true" ->
            partisan;
        _ ->
            riak_core
    end,

    ct:pal("Configuration: ~p", [Config]),

    %% Pause for clustering.
    timer:sleep(1000),

    [{_, Node1}, {_, Node2}|_] = Nodes,

    Profile = case os:getenv("PROFILE", false) of
        "true" ->
            ct:pal("Enabling profiling!"),
            true;
        _ ->
            ct:pal("Disabling profiling!"),
            false
    end,
    
    case Profile of
        true ->
            rpc:call(Node1, eprof, start, []);
        _ ->
            ok
    end,

    %% One process per connection.
    Concurrency = case os:getenv("CONCURRENCY", "1") of
        undefined ->
            1;
        C ->
            list_to_integer(C)
    end,

    %% Latency.
    Latency = case os:getenv("LATENCY", "0") of
        undefined ->
            0;
        L ->
            list_to_integer(L)
    end,

    %% Size.
    Size = case os:getenv("SIZE", "1024") of
        undefined ->
            0;
        S ->
            list_to_integer(S)
    end,

    %% Parallelism.
    Parallelism = case rpc:call(Node1, partisan_config, get, [parallelism]) of
        undefined ->
            1;
        P ->
            P
    end,
        
    NumMessages = 1000,
    BenchPid = self(),
    BytesSize = Size * 1024,

    %% Prime a binary at each node.
    ct:pal("Generating binaries!"),
    EchoBinary = rand_bits(BytesSize * 8),

    %% Spawn processes to send receive messages on node 1.
    ct:pal("Spawning processes."),
    SenderPids = lists:map(fun(SenderNum) ->
        ReceiverFun = fun() ->
            receiver(Manager, BenchPid, NumMessages)
        end,
        ReceiverPid = rpc:call(Node2, erlang, spawn, [ReceiverFun]),

        SenderFun = fun() ->
            init_sender(EchoBinary, Manager, Node2, ReceiverPid, SenderNum, NumMessages)
        end,
        SenderPid = rpc:call(Node1, erlang, spawn, [SenderFun]),
        SenderPid
    end, lists:seq(1, Concurrency)),

    %% Start bench.
    ProfileFun = fun() ->
        %% Start sending.
        lists:foreach(fun(SenderPid) ->
            SenderPid ! start
        end, SenderPids),

        %% Wait for them all.
        bench_receiver(Concurrency)
    end,
    {Time, _Value} = timer:tc(ProfileFun),

    %% Write results.
    RootDir = root_dir(Config),
    ResultsFile = RootDir ++ "results.csv",
    ct:pal("Writing results to: ~p", [ResultsFile]),
    {ok, FileHandle} = file:open(ResultsFile, [append]),
    Backend = case ?config(partisan_dispatch, Config) of
        true ->
            partisan;
        _ ->
            disterl
    end,
    NumChannels = case ?config(channels, Config) of
        undefined ->
            1;
        [] ->
            1;
        List ->
            length(List)
    end,
    Partitioned = case ?config(vnode_partitioning, Config) of
        undefined ->
            false;
        VP ->
            VP
    end,
    io:format(FileHandle, "~p,~p,~p,~p,~p,~p,~p,~p,~p,~p,~p~n", [App, Backend, Concurrency, NumChannels, false, Parallelism, Partitioned, BytesSize, NumMessages, Latency, Time]),
    file:close(FileHandle),

    case Profile of
        true ->
            ProfileFile = RootDir ++ "eprof/" ++ atom_to_list(App) ++ "-" ++ atom_to_list(Backend) ++ "-" ++ integer_to_list(Parallelism),
            ct:pal("Outputting profile results to file: ~p", [ProfileFile]),
            rpc:call(Node1, eprof, stop_profiling, []),
            rpc:call(Node1, eprof, log, [ProfileFile]),
            rpc:call(Node1, eprof, analyze, []);
        _ ->
            ok
    end,

    ct:pal("Time: ~p", [Time]),

    %% Stop nodes.
    ?SUPPORT:stop(Nodes),

    ok.

echo_performance_test(Config) ->
    Manager = partisan_default_peer_service_manager,

    Nodes = ?SUPPORT:start(echo_performance_test,
                           Config,
                           [{num_nodes, 3},
                           {partisan_peer_service_manager, Manager}]),

    ct:pal("Configuration: ~p", [Config]),

    %% Pause for clustering.
    timer:sleep(1000),

    [{_, Node1}|_] = Nodes,

    %% One process per connection.
    Concurrency = case os:getenv("CONCURRENCY", "1") of
        undefined ->
            1;
        C ->
            list_to_integer(C)
    end,

    %% Latency.
    Latency = case os:getenv("LATENCY", "0") of
        undefined ->
            0;
        L ->
            list_to_integer(L)
    end,

    %% Size.
    Size = case os:getenv("SIZE", "1024") of
        undefined ->
            0;
        S ->
            list_to_integer(S)
    end,

    %% Parallelism.
    Parallelism = case rpc:call(Node1, partisan_config, get, [parallelism]) of
        undefined ->
            1;
        P ->
            P
    end,
        
    NumMessages = 1000,
    BenchPid = self(),
    BytesSize = Size * 1024,

    %% Prime a binary at each node.
    ct:pal("Generating binaries!"),
    EchoBinary = rand_bits(BytesSize * 8),

    %% Spawn processes to send receive messages on node 1.
    ct:pal("Spawning processes."),
    SenderPids = lists:flatmap(fun({_, Node}) -> 
            lists:map(fun(SenderNum) ->
                SenderFun = fun() ->
                    init_echo_sender(BenchPid, SenderNum, EchoBinary, NumMessages)
                end,
                rpc:call(Node, erlang, spawn, [SenderFun])
            end, lists:seq(1, Concurrency))
        end, Nodes),

    %% Start bench.
    ProfileFun = fun() ->
        %% Start sending.
        lists:foreach(fun(SenderPid) ->
            SenderPid ! start
        end, SenderPids),

        %% Wait for them all.
        bench_receiver(length(SenderPids))
    end,
    {Time, _Value} = timer:tc(ProfileFun),

    %% Write results.
    RootDir = root_dir(Config),
    ResultsFile = RootDir ++ "results.csv",
    ct:pal("Writing results to: ~p", [ResultsFile]),
    {ok, FileHandle} = file:open(ResultsFile, [append]),
    Backend = case ?config(partisan_dispatch, Config) of
        true ->
            partisan;
        _ ->
            disterl
    end,
    NumChannels = case ?config(channels, Config) of
        undefined ->
            1;
        [] ->
            1;
        List ->
            length(List)
    end,
    Partitioned = case ?config(vnode_partitioning, Config) of
        undefined ->
            false;
        VP ->
            VP
    end,
    MonotonicChannels = case ?config(monotonic_channels, Config) of
        undefined ->
            false;
        MC ->
            MC
    end,
    io:format(FileHandle, "~p,~p,~p,~p,~p,~p,~p,~p,~p,~p,~p~n", [echo, Backend, Concurrency, NumChannels, MonotonicChannels, Parallelism, Partitioned, BytesSize, NumMessages, Latency, Time]),
    file:close(FileHandle),

    ct:pal("Time: ~p", [Time]),

    %% Stop nodes.
    ?SUPPORT:stop(Nodes),

    ok.

fsm_performance_test(Config) ->
    Manager = partisan_default_peer_service_manager,

    Nodes = ?SUPPORT:start(fsm_performance_test,
                           Config,
                           [{num_nodes, 3},
                           {partisan_peer_service_manager, Manager}]),

    ct:pal("Configuration: ~p", [Config]),

    %% Pause for clustering.
    timer:sleep(1000),

    [{_, Node1}|_] = Nodes,

    %% One process per connection.
    Concurrency = case os:getenv("CONCURRENCY", "1") of
        undefined ->
            1;
        C ->
            list_to_integer(C)
    end,

    %% Latency.
    Latency = case os:getenv("LATENCY", "0") of
        undefined ->
            0;
        L ->
            list_to_integer(L)
    end,

    %% Size.
    Size = case os:getenv("SIZE", "1024") of
        undefined ->
            0;
        S ->
            list_to_integer(S)
    end,

    %% Parallelism.
    Parallelism = case rpc:call(Node1, partisan_config, get, [parallelism]) of
        undefined ->
            1;
        P ->
            P
    end,
        
    NumMessages = 1000,
    BenchPid = self(),
    BytesSize = Size * 1024,

    %% Prime a binary at each node.
    ct:pal("Generating binaries!"),
    EchoBinary = rand_bits(BytesSize * 8),

    %% Spawn processes to send receive messages on node 1.
    ct:pal("Spawning processes."),
    SenderPids = lists:flatmap(fun({_, Node}) -> 
            lists:map(fun(SenderNum) ->
                SenderFun = fun() ->
                    init_fsm_sender(BenchPid, SenderNum, EchoBinary, NumMessages)
                end,
                rpc:call(Node, erlang, spawn, [SenderFun])
            end, lists:seq(1, Concurrency))
        end, Nodes),

    %% Start bench.
    ProfileFun = fun() ->
        %% Start sending.
        lists:foreach(fun(SenderPid) ->
            SenderPid ! start
        end, SenderPids),

        %% Wait for them all.
        bench_receiver(length(SenderPids))
    end,
    {Time, Value} = timer:tc(ProfileFun),

    %% Write results.
    RootDir = root_dir(Config),
    ResultsFile = RootDir ++ "results.csv",
    ct:pal("Writing results to: ~p", [ResultsFile]),
    {ok, FileHandle} = file:open(ResultsFile, [append]),
    Backend = case ?config(partisan_dispatch, Config) of
        true ->
            partisan;
        _ ->
            disterl
    end,
    NumChannels = case ?config(channels, Config) of
        undefined ->
            1;
        [] ->
            1;
        List ->
            length(List)
    end,
    MonotonicChannels = case ?config(monotonic_channels, Config) of
        undefined ->
            false;
        MC ->
            MC
    end,
    Partitioned = case ?config(vnode_partitioning, Config) of
        undefined ->
            false;
        VP ->
            VP
    end,
    io:format(FileHandle, "~p,~p,~p,~p,~p,~p,~p,~p,~p,~p,~p~n", [kvs, Backend, Concurrency, NumChannels, MonotonicChannels, Parallelism, Partitioned, BytesSize, NumMessages, Latency, Time]),
    file:close(FileHandle),

    ct:pal("Value: ~p, Time: ~p", [Value, Time]),

    %% Stop nodes.
    ?SUPPORT:stop(Nodes),

    ok.

bench_test(Config0) ->
    RootDir = ?SUPPORT:root_dir(Config0),

    ct:pal("Configuration was: ~p", [Config0]),

    Config = case file:consult(RootDir ++ "config/test.config") of
        {ok, Terms} ->
            ct:pal("Read terms configuration: ~p", [Terms]),
            Terms ++ Config0;
        {error, Reason} ->
            ct:fail("Could not open the terms configuration: ~p", [Reason]),
            ok
    end,

    ct:pal("Configuration is now: ~p", [Config]),

    Nodes = ?SUPPORT:start(bench_test,
                           Config,
                           [{num_nodes, 3},
                           {partisan_peer_service_manager,
                               partisan_default_peer_service_manager}]),

    ct:pal("Configuration: ~p", [Config]),

    RootDir = ?SUPPORT:root_dir(Config),

    %% Configure parameters.
    ResultsParameters = case proplists:get_value(partisan_dispatch, Config, false) of
        true ->
            BinaryPadding = case proplists:get_value(binary_padding, Config, false) of
                true ->
                    "binary-padding";
                false ->
                    "no-binary-padding"
            end,

            VnodePartitioning = case proplists:get_value(vnode_partitioning, Config, true) of
                true ->
                    "vnode-partitioning";
                false ->
                    "no-vnode-partitioning"
            end,

            Parallelism = case proplists:get_value(parallelism, Config, 1) of
                1 ->
                    "parallelism-" ++ integer_to_list(1);
                P ->
                    "parallelism-" ++ integer_to_list(P)
            end,

            "partisan-" ++ BinaryPadding ++ "-" ++ VnodePartitioning ++ "-" ++ Parallelism;
        false ->
            "disterl"
    end,

    %% Get benchmark configuration.
    BenchConfig = ?config(bench_config, Config),

    %% Consult the benchmark file for benchmark terms.
    BenchConfigTerms = case file:consult(RootDir ++ "examples/" ++ BenchConfig) of
        {ok, BenchTerms} ->
            ct:pal("Read bench terms configuration: ~p", [BenchTerms]),
            BenchTerms;
        {error, BenchErrorReason} ->
            ct:fail("Could not open the bench terms configuration: ~p", [BenchErrorReason]),
            ok
    end,
    {fixed_bin, Size} = proplists:get_value(value_generator, BenchConfigTerms, undefined),
    TestType = proplists:get_value(type, BenchConfigTerms, undefined),

    %% Configure the echo terms.
    ConfigureFun = fun({_, N}) ->
        %% Store the echo binary.
        ct:pal("Storing ~p byte object in the echo binary storage.", [Size]),
        EchoBinary = rand_bits(Size * 8),
        ok = rpc:call(N, partisan_config, set, [echo_binary, EchoBinary])
    end,
    lists:foreach(ConfigureFun, Nodes),

    %% Select the node configuration.
    SortedNodes = lists:usort([Node || {_Name, Node} <- Nodes]),

    %% Verify partisan connection is configured with the correct
    %% membership information.
    ct:pal("Waiting for partisan membership..."),
    ?assertEqual(ok, ?SUPPORT:wait_until_partisan_membership(SortedNodes)),

    %% Ensure we have the right number of connections.
    %% Verify appropriate number of connections.
    ct:pal("Waiting for partisan connections..."),
    ?assertEqual(ok, ?SUPPORT:wait_until_all_connections(SortedNodes)),

    %% Configure bench paths.
    BenchDir = RootDir ++ "_build/default/lib/lasp_bench/",

    %% Build bench.
    ct:pal("Building benchmarking suite..."),
    BuildCommand = "cd " ++ BenchDir ++ "; make all",
    _BuildOutput = os:cmd(BuildCommand),
    % ct:pal("~p => ~p", [BuildCommand, BuildOutput]),

    %% Register our process.
    yes = global:register_name(runner, self()),

    %% Run bench.
    SortedNodesString = lists:flatten(lists:join(",", lists:map(fun(N) -> atom_to_list(N) end, SortedNodes))),
    RunnerString = atom_to_list(node()),
    BenchCommand = "cd " ++ BenchDir ++ "; RUNNER=\"" ++ RunnerString ++ "\" NODES=\"" ++ SortedNodesString ++ "\" _build/default/bin/lasp_bench " ++ RootDir ++ "examples/" ++ BenchConfig,
    ct:pal("Executing benchmark: ~p", [BenchCommand]),
    BenchOutput = os:cmd(BenchCommand),
    ct:pal("Benchmark output: ~p => ~p", [BenchCommand, BenchOutput]),

    %% Generate results.
    ct:pal("Generating results..."),
    ResultsCommand = "cd " ++ BenchDir ++ "; make results",
    _ResultsOutput = os:cmd(ResultsCommand),
    % ct:pal("~p => ~p", [ResultsCommand, ResultsOutput]),

    %% Get priv dir.
    PrivDir = ?config(priv_dir, Config),

    case os:getenv("TRAVIS") of
        false ->
            %% Make results dir.
            ct:pal("Making results output directory..."),
            DirCommand = "mkdir " ++ RootDir ++ "results/",
            _DirOutput = os:cmd(DirCommand),
            % ct:pal("~p => ~p", [DirCommand, DirOutput]),

            %% Get full path to the results.
            ReadLinkCommand = "readlink " ++ BenchDir ++ "tests/current",
            ReadLinkOutput = os:cmd(ReadLinkCommand),
            FullResultsPath = string:substr(ReadLinkOutput, 1, length(ReadLinkOutput) - 1),
            ct:pal("~p => ~p", [ReadLinkCommand, ReadLinkOutput]),

            %% Get directory name.
            Directory = string:substr(FullResultsPath, string:rstr(FullResultsPath, "/") + 1, length(FullResultsPath)),
            ResultsDirectory = Directory ++ "-" ++ BenchConfig ++ "-" ++ ResultsParameters,

            %% Copy results.
            ct:pal("Copying results into output directory: ~p", [ResultsDirectory]),
            CopyCommand = "cp -rpv " ++ FullResultsPath ++ " " ++ RootDir ++ "results/" ++ ResultsDirectory,
            _CopyOutput = os:cmd(CopyCommand),
            % ct:pal("~p => ~p", [CopyCommand, CopyOutput]),

            %% Copy logs.
            ct:pal("Copying logs into output directory: ~p", [ResultsDirectory]),
            LogsCommand = "cp -rpv " ++ PrivDir ++ " " ++ RootDir ++ "results/" ++ ResultsDirectory,
            _LogOutput = os:cmd(LogsCommand),
            % ct:pal("~p => ~p", [CopyCommand, CopyOutput]),

            %% Receive results.
            %% TotalOpsMessages = receive_bench_operations(0),
            %% ct:pal("Total operations issued based on messages: ~p", [TotalOpsMessages]),

            TotalOpsSummary = get_total_ops(FullResultsPath),
            ct:pal("Total operations issued based on summary: ~p", [TotalOpsSummary]),

            %% Get busy errors.
            BusyErrorsRaw = os:cmd("grep -r busy_ " ++ PrivDir ++ " | wc -l"),
            BusyErrorsString = string:substr(BusyErrorsRaw, 1, length(BusyErrorsRaw) - 1),
            BusyErrors = list_to_integer(BusyErrorsString),
            ct:pal("Busy errors: ~p", [BusyErrors]),

            %% Write aggregate results.
            AggregateResultsFile = RootDir ++ "results/aggregate.csv",
            ct:pal("Writing aggregate results to: ~p", [AggregateResultsFile]),
            {ok, FileHandle} = file:open(AggregateResultsFile, [append]),
            Mode = case ?config(partisan_dispatch, Config) of
                true ->
                    case ?config(parallelism, Config) of
                        undefined ->
                            partisan;
                        Conns ->
                            list_to_atom("partisan_" ++ integer_to_list(Conns))
                    end;
                _ ->
                    disterl
            end,
            io:format(FileHandle, "~p,~p,~p,~p,~p~n", [TestType, Mode, Size, TotalOpsSummary, BusyErrors]),
            file:close(FileHandle);
        _ ->
            ok
    end,

    ?SUPPORT:stop(Nodes),

    ok.

receive_bench_operations(TotalOps) ->
    receive
        {bench_operations, Ops} ->
            receive_bench_operations(TotalOps + Ops)
    after 10000 ->
        TotalOps
    end.

get_total_ops(ResultsDir) ->
    {ok, Device} = file:open(ResultsDir ++ "/summary.csv", [read]),

    %% Dump header line.
    _ = io:get_line(Device, ""),

    try get_totals(Device, 0)
        after file:close(Device)
    end.

get_totals(Device, Total) ->
    case io:get_line(Device, "") of
        eof  -> 
            Total;
        Line -> 
            Tokens = string:tokens(Line, ","),
            RawOps = lists:nth(3, Tokens),
            TruncRawOps = string:sub_string(RawOps, 2),
            Ops = list_to_integer(TruncRawOps),
            get_totals(Device, Total + Ops)
    end.

%% @private
rand_bits(Bits) ->
        Bytes = (Bits + 7) div 8,
        <<Result:Bits/bits, _/bits>> = crypto:strong_rand_bytes(Bytes),
        Result.

%% @private
echo_sender(BenchPid, _SenderNum, _EchoBinary, 0) ->
    BenchPid ! done,
    ok;
echo_sender(BenchPid, SenderNum, EchoBinary, Count) ->
    unir:echo(EchoBinary),
    echo_sender(BenchPid, SenderNum, EchoBinary, Count - 1).

%% @private
init_echo_sender(BenchPid, SenderNum, EchoBinary, Count) ->
    receive
        start ->
            ok
    end,
    echo_sender(BenchPid, SenderNum, EchoBinary, Count).

%% @private
fsm_sender(BenchPid, _SenderNum, _EchoBinary, Success, Failure, 0) ->
    BenchPid ! {done, Success, Failure},
    ok;
fsm_sender(BenchPid, SenderNum, EchoBinary, Success, Failure, Count) ->
    %% Normal distribution over 10000 keys.
    RandomNumber = trunc((rand:normal() + 1) * 5000),

    %% Craft object name.
    ObjectName = list_to_binary("object" ++ integer_to_list(RandomNumber)),

    %% 50/50 read/write workload.
    case Count rem 2 == 0 of
        true ->
            case unir:fsm_put(ObjectName, EchoBinary) of
                {ok, _Val} ->
                    fsm_sender(BenchPid, SenderNum, EchoBinary, Success + 1, Failure, Count - 1);
                {error, timeout} ->
                    fsm_sender(BenchPid, SenderNum, EchoBinary, Success, Failure + 1, Count - 1)
            end;
        false ->
            case unir:fsm_get(ObjectName) of
                {ok, _Val} ->
                    fsm_sender(BenchPid, SenderNum, EchoBinary, Success + 1, Failure, Count - 1);
                {error, timeout} ->
                    fsm_sender(BenchPid, SenderNum, EchoBinary, Success, Failure + 1, Count - 1)
            end
    end.

%% @private
init_fsm_sender(BenchPid, SenderNum, EchoBinary, Count) ->
    receive
        start ->
            ok
    end,
    fsm_sender(BenchPid, SenderNum, EchoBinary, 0, 0, Count).

%% @private
root_path(Config) ->
    DataDir = proplists:get_value(data_dir, Config, ""),
    DataDir ++ "../../../../../../".

%% @private
root_dir(Config) ->
    RootCommand = "cd " ++ root_path(Config) ++ "; pwd",
    RootOutput = os:cmd(RootCommand),
    RootDir = string:substr(RootOutput, 1, length(RootOutput) - 1) ++ "/",
    ct:pal("RootDir: ~p", [RootDir]),
    RootDir.

%% @private
parallelism() ->
    case os:getenv("PARALLELISM", "1") of
        false ->
            [{parallelism, list_to_integer("1")}];
        "1" ->
            [{parallelism, list_to_integer("1")}];
        Config ->
            [{parallelism, list_to_integer(Config)}]
    end.

%% @private
channels() ->
    [{channels, [undefined, gossip, broadcast, vnode]}].

%% @private
monotonic_channels() ->
    [{monotonic_channels, true}, {channels, [undefined, {monotonic, gossip}, broadcast, vnode]}].

%% @private
bench_receiver(Count) ->
    bench_receiver(0, 0, Count).

%% @private
bench_receiver(Success, Failure, 0) ->
    ct:pal("Success: ~p, Failure: ~p", [Success, Failure]),
    ok;
bench_receiver(Success, Failure, Count) ->
    ct:pal("Waiting for ~p processes to finish...", [Count]),

    receive
        done ->
            ct:pal("Received, but still waiting for ~p", [Count -1]),
            bench_receiver(Success, Failure, Count - 1);
        {done, S, F} ->
            ct:pal("Received; success: ~p, failure: ~p; but still waiting for ~p", [S, F, Count -1]),
            bench_receiver(Success + S, Failure + F, Count - 1)
    end.

%% @private
receiver(_Manager, BenchPid, 0) ->
    BenchPid ! done,
    ok;
receiver(Manager, BenchPid, Count) ->
    receive
        {_Message, _SourceNode, _SourcePid} ->
            receiver(Manager, BenchPid, Count - 1)
    end.

%% @private
sender(_EchoBinary, _Manager, _DestinationNode, _DestinationPid, _PartitionKey, 0) ->
    ok;
sender(EchoBinary, Manager, DestinationNode, DestinationPid, PartitionKey, Count) ->
    Manager:forward_message(DestinationNode, undefined, DestinationPid, {EchoBinary, node(), self()}, [{partition_key, PartitionKey}]),
    sender(EchoBinary, Manager, DestinationNode, DestinationPid, PartitionKey, Count - 1).

%% @private
init_sender(EchoBinary, Manager, DestinationNode, DestinationPid, PartitionKey, Count) ->
    receive
        start ->
            ok
    end,
    sender(EchoBinary, Manager, DestinationNode, DestinationPid, PartitionKey, Count).
