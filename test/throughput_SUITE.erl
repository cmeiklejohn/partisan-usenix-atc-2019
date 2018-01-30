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
    [{partisan_dispatch, true}] ++ Config;

init_per_group(partisan_with_parallelism, Config) ->
    [{parallelism, 5}] ++ init_per_group(partisan, Config);
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
      [bench_test]},

     {default, [],
      [{group, bench}] },

     {disterl, [],
      [{group, bench}] },
     
     {partisan, [],
      [{group, bench}]},

     {partisan_with_parallelism, [],
      [{group, bench}]},

     {partisan_with_binary_padding, [],
      [{group, bench}]},

     {partisan_with_vnode_partitioning, [],
      [{group, bench}]}
    ].

%% ===================================================================
%% Tests.
%% ===================================================================

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

            VnodePartitioning = case proplists:get_value(vnode_partitioning, Config, false) of
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

    %% Get benchmark configuration.
    BenchConfig = ?config(bench_config, Config),

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
                    case ?config(binary_padding, Config) of
                        true ->
                            partisan_padded;
                        _ ->
                            partisan
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