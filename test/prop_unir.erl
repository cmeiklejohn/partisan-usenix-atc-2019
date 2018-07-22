%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Christopher S. Meiklejohn.  All Rights Reserved.
%%
%% -------------------------------------------------------------------

-module(prop_unir).
-author("Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>").

-include_lib("proper/include/proper.hrl").

-compile([export_all]).

-define(SUPPORT, support).

-define(NUM_NODES, 3).
-define(COMMAND_MULTIPLE, 10).
-define(CLUSTER_NODES, true).
-define(MANAGER, partisan_default_peer_service_manager).
-define(DEBUG, true).

%% Application under test.
-define(APP, unir).                                 %% The name of the top-level application that requests
                                                    %% should be issued to using the RPC mechanism.

%% TODO: Fix message corruption fault.
%% TODO: Fix bit flip bugs.

%% Partisan connection and forwarding settings.
-define(EGRESS_DELAY, 0).                           %% How many milliseconds to delay outgoing messages?
-define(INGRESS_DELAY, 0).                          %% How many milliseconds to delay incoming messages?
-define(VNODE_PARTITIONING, false).                 %% Should communication be partitioned by vnode identifier?
-define(PARALLELISM, 1).                            %% How many connections should exist between nodes?
-define(CHANNELS, 
        [broadcast, vnode, {monotonic, gossip}]).   %% What channels should be established?
-define(CAUSAL_LABELS, []).                         %% What causal channels should be established?

%% Only one of the modes below should be selected for efficient, proper shriking.
-define(PERFORM_LEAVES_AND_JOINS, false).           %% Do we allow cluster transitions during test execution:
                                                    %% EXTREMELY slow, given a single join can take ~30 seconds.
-define(PERFORM_CLUSTER_PARTITIONS, false).         %% Whether or not we should partition at the cluster level 
                                                    %% ie. groups of nodes at a time.
-define(PERFORM_ASYNC_PARTITIONS, false).           %% Whether or not we should partition using asymmetric partitions
                                                    %% ie. nodes can send but not receive from other nodes
-define(PERFORM_SYNC_PARTITIONS, true).             %% Whether or not we should use symmetric partitions: most common.
                                                    %% ie. two-way communication prohibited between different nodes.
-define(PERFORM_BYZANTINE_MESSAGE_FAULTS, false).   %% Whether or not we should use cluster byzantine faults:
                                                    %% ie. message corruption, etc.
-define(PERFORM_BYZANTINE_NODE_FAULTS, true).       %% Whether or not we should use cluster-specific byzantine faults.
                                                    %% ie. data loss bugs, bit flips, etc.

%% Other options to exercise pathological cases.
-define(BIAS_MINORITY, false).                      %% Bias requests to minority partitions.
-define(MONOTONIC_READS, false).                    %% Do we assume the system provides monotonic read?

-export([command/1, 
         initial_state/0, 
         next_state/3,
         precondition/2, 
         postcondition/3]).

prop_sequential() ->
    ?FORALL(Cmds, more_commands(?COMMAND_MULTIPLE, commands(?MODULE)), 
        begin
            start_nodes(),
            {History, State, Result} = run_commands(?MODULE, Cmds), 
            stop_nodes(),
            ?WHENFAIL(io:format("History: ~p\nState: ~p\nResult: ~p\n",
                                [History,State,Result]),
                      aggregate(command_names(Cmds), Result =:= ok))
        end).

prop_parallel() ->
    ?FORALL(Cmds, more_commands(?COMMAND_MULTIPLE, parallel_commands(?MODULE)), 
        begin
            start_nodes(),
            {History, State, Result} = run_parallel_commands(?MODULE, Cmds), 
            stop_nodes(),
            ?WHENFAIL(io:format("History: ~p\nState: ~p\nResult: ~p\n",
                                [History,State,Result]),
                      aggregate(command_names(Cmds), Result =:= ok))
        end).

-record(state, {
                joined_nodes :: [node()],
                nodes :: [node()],
                node_state :: {dict:dict(), dict:dict()}, 
                partition_filters :: dict:dict(),
                minority_nodes :: [node()], 
                majority_nodes :: [node()], 
                byzantine_faults :: dict:dict()
            }).

%%%===================================================================
%%% Generators
%%%===================================================================

%% Initial model value at system start. Should be deterministic.
initial_state() -> 
    %% Initialize empty dictionary for process state.
    NodeState = node_initial_state(),

    %% Get the list of nodes.
    Nodes = names(),

    %% Assume first is joined -- node_1 will be the join point.
    JoinedNodes = case ?CLUSTER_NODES of
        false ->
            [hd(Nodes)];
        true ->
            Nodes
    end,

    %% Fault state management.
    PartitionFilters = dict:new(),
    ByzantineFaults = dict:new(),
    MinorityNodes = [],
    MajorityNodes = [],

    %% Debug message.
    debug("initial_state: nodes ~p joined_nodes ~p", [Nodes, JoinedNodes]),

    #state{joined_nodes=JoinedNodes, 
           nodes=Nodes,
           minority_nodes=MinorityNodes,
           majority_nodes=MajorityNodes, 
           node_state=NodeState, 
           byzantine_faults=ByzantineFaults,
           partition_filters=PartitionFilters}.

command(State) -> 
    ?LET(Commands, cluster_commands(State) ++ node_commands(), oneof(Commands)).

%% Picks whether a command should be valid under the current state.
precondition(#state{byzantine_faults=ByzantineFaults}, {call, _Mod, induce_byzantine_message_corruption_fault, [SourceNode, DestinationNode, _Value]}) -> 
    not is_involved_in_byzantine_fault(SourceNode, DestinationNode, ByzantineFaults);
precondition(#state{byzantine_faults=ByzantineFaults}, {call, _Mod, resolve_byzantine_message_corruption_fault, [SourceNode, DestinationNode]}) -> 
    is_involved_in_byzantine_fault(SourceNode, DestinationNode, ByzantineFaults);
precondition(#state{partition_filters=PartitionFilters}, {call, _Mod, induce_async_partition, [SourceNode, DestinationNode]}) -> 
    not is_involved_in_partition(SourceNode, DestinationNode, PartitionFilters);
precondition(#state{partition_filters=PartitionFilters}, {call, _Mod, resolve_async_partition, [SourceNode, DestinationNode]}) -> 
    is_involved_in_partition(SourceNode, DestinationNode, PartitionFilters);
precondition(#state{partition_filters=PartitionFilters}, {call, _Mod, induce_sync_partition, [SourceNode, DestinationNode]}) -> 
    not is_involved_in_partition(SourceNode, DestinationNode, PartitionFilters) andalso is_valid_partition(SourceNode, DestinationNode);
precondition(#state{partition_filters=PartitionFilters}, {call, _Mod, resolve_sync_partition, [SourceNode, DestinationNode]}) -> 
    is_involved_in_partition(SourceNode, DestinationNode, PartitionFilters);
precondition(#state{partition_filters=PartitionFilters}, {call, _Mod, induce_cluster_partition, [MajorityNodes, AllNodes]}) -> 
    MinorityNodes = AllNodes -- MajorityNodes,

    lists:all(fun(SourceNode) -> 
        lists:all(fun(DestinationNode) ->
            not is_involved_in_partition(SourceNode, DestinationNode, PartitionFilters)
        end, MinorityNodes)
    end, MajorityNodes);
precondition(#state{partition_filters=PartitionFilters}, {call, _Mod, resolve_cluster_partition, [MajorityNodes, AllNodes]}) -> 
    MinorityNodes = AllNodes -- MajorityNodes,

    lists:all(fun(SourceNode) -> 
        lists:all(fun(DestinationNode) ->
            is_involved_in_partition(SourceNode, DestinationNode, PartitionFilters)
        end, MinorityNodes)
    end, MajorityNodes);
precondition(#state{nodes=Nodes, joined_nodes=JoinedNodes}, {call, _Mod, join_cluster, [Node, JoinedNodes]}) -> 
    %% Only allow dropping of the first unjoined node in the nodes list, for ease of debugging.
    debug("precondition join_cluster: invoked for node ~p joined_nodes ~p", [Node, JoinedNodes]),

    ToBeJoinedNodes = Nodes -- JoinedNodes,
    debug("precondition join_cluster: remaining nodes to be joined are: ~p", [ToBeJoinedNodes]),

    case length(ToBeJoinedNodes) > 0 of
        true ->
            ToBeJoinedNode = hd(ToBeJoinedNodes),
            debug("precondition join_cluster: attempting to join ~p", [ToBeJoinedNode]),
            case ToBeJoinedNode of
                Node ->
                    debug("precondition join_cluster: YES attempting to join ~p is ~p", [ToBeJoinedNode, Node]),
                    true;
                OtherNode ->
                    debug("precondition join_cluster: NO attempting to join ~p not ~p", [ToBeJoinedNode, OtherNode]),
                    false
            end;
        false ->
            debug("precondition join_cluster: no nodes left to join.", []),
            false %% Might need to be changed when there's no read/write operations.
    end;
precondition(#state{joined_nodes=JoinedNodes}, {call, _Mod, leave_cluster, [Node, JoinedNodes]}) -> 
    %% Only allow dropping of the last node in the join list, for ease of debugging.
    debug("precondition leave_cluster: invoked for node ~p joined_nodes ~p", [Node, JoinedNodes]),

    ToBeRemovedNodes = JoinedNodes,
    debug("precondition leave_cluster: remaining nodes to be removed are: ~p", [ToBeRemovedNodes]),

    case length(ToBeRemovedNodes) > 3 of
        true ->
            ToBeRemovedNode = lists:last(ToBeRemovedNodes),
            debug("precondition leave_cluster: attempting to leave ~p", [ToBeRemovedNode]),
            case ToBeRemovedNode of
                Node ->
                    debug("precondition leave_cluster: YES attempting to leave ~p is ~p", [ToBeRemovedNode, Node]),
                    true;
                OtherNode ->
                    debug("precondition leave_cluster: NO attempting to leave ~p not ~p", [ToBeRemovedNode, OtherNode]),
                    false
            end;
        false ->
            debug("precondition leave_cluster: no nodes left to remove.", []),
            false %% Might need to be changed when there's no read/write operations.
    end;
precondition(#state{majority_nodes=MajorityNodes, minority_nodes=MinorityNodes, node_state=NodeState, joined_nodes=JoinedNodes}, {call, Mod, Fun, [Node|_]=Args}=Call) -> 
    debug("precondition fired for node function: ~p, majority_nodes: ~p, minority_nodes ~p", [Fun, MajorityNodes, MinorityNodes]),
    case lists:member(Fun, node_functions()) of
        true ->
            case ?BIAS_MINORITY andalso length(MinorityNodes) > 0 of
                true ->
                    debug("precondition fired for node function where minority is biased: ~p, bias_minority: ~p, checking whether node ~p is in minority", [Fun, ?BIAS_MINORITY, Node]),
                    case lists:member(Node, MinorityNodes) of
                        true ->
                            debug("=> bias towards minority, write is going to node ~p in minority", [Node]),
                            ClusterCondition = enough_nodes_connected(JoinedNodes) andalso is_joined(Node, JoinedNodes),
                            NodePrecondition = node_precondition(NodeState, Call),
                            ClusterCondition andalso NodePrecondition;
                        false ->
                            false
                    end;
                false ->
                    ClusterCondition = enough_nodes_connected(JoinedNodes) andalso is_joined(Node, JoinedNodes),
                    NodePrecondition = node_precondition(NodeState, Call),
                    ClusterCondition andalso NodePrecondition
            end;
        false ->
            debug("general precondition fired for mod ~p and fun ~p and args ~p", [Mod, Fun, Args]),
            false
    end.

%% Given the state `State' *prior* to the call `{call, Mod, Fun, Args}',
%% determine whether the result `Res' (coming from the actual system)
%% makes sense.
postcondition(_State, {call, ?MODULE, induce_byzantine_message_corruption_fault, [_SourceNode, _DestinationNode, _Value]}, ok) ->
    debug("postcondition induce_byzantine_message_corruption_fault: succeeded", []),
    %% Added message filter.
    true;
postcondition(_State, {call, ?MODULE, resolve_byzantine_message_corruption_fault, [_SourceNode, _DestinationNode]}, ok) ->
    debug("postcondition resolve_byzantine_message_corruption_fault: succeeded", []),
    %% Remove message filter.
    true;
postcondition(_State, {call, ?MODULE, induce_async_partition, [_SourceNode, _DestinationNode]}, ok) ->
    debug("postcondition induce_async_partition: succeeded", []),
    %% Added message filter.
    true;
postcondition(_State, {call, ?MODULE, resolve_async_partition, [_SourceNode, _DestinationNode]}, ok) ->
    debug("postcondition resolve_async_partition: succeeded", []),
    %% Removed message filter.
    true;
postcondition(_State, {call, ?MODULE, induce_sync_partition, [_SourceNode, _DestinationNode]}, ok) ->
    debug("postcondition induce_sync_partition: succeeded", []),
    %% Added message filter.
    true;
postcondition(_State, {call, ?MODULE, resolve_sync_partition, [_SourceNode, _DestinationNode]}, ok) ->
    debug("postcondition resolve_sync_partition: succeeded", []),
    %% Removed message filter.
    true;
postcondition(_State, {call, ?MODULE, induce_cluster_partition, [_MajorityNodes, _MinorityNodes]}, ok) ->
    debug("postcondition induce_cluster_partition: succeeded", []),
    %% Added message filter.
    true;
postcondition(_State, {call, ?MODULE, resolve_cluster_partition, [_MajorityNodes, _MinorityNodes]}, ok) ->
    debug("postcondition resolve_cluster_partition: succeeded", []),
    %% Removed message filter.
    true;
postcondition(_State, {call, ?MODULE, join_cluster, [_Node, _JoinedNodes]}, ok) ->
    debug("postcondition join_cluster: succeeded", []),
    %% Accept joins that succeed.
    true;
postcondition(_State, {call, ?MODULE, leave_cluster, [_Node, _JoinedNodes]}, ok) ->
    debug("postcondition leave_cluster: succeeded", []),
    %% Accept leaves that succeed.
    true;
postcondition(#state{minority_nodes=MinorityNodes, partition_filters=PartitionFilters, node_state=NodeState}, {call, Mod, Fun, [Node|_]=_Args}=Call, Res) -> 
    case lists:member(Fun, node_functions()) of
        true ->
            case lists:member(Node, MinorityNodes) of
                true ->
                    case Res of
                        {error, _} ->
                            true;
                        _ ->
                            debug("node postcondition for ~p, operation succeeded, should have failed.", [Fun]),
                            false
                    end;
                false ->
                    debug("request went to majority node, node: ~p response: ~p", [Node, Res]),

                    %% One partitioned node may make a quorum of 2 fail.
                    case is_involved_in_x_partitions(Node, 1, PartitionFilters) of
                        true ->
                            case Res of
                                {error, _} ->
                                    true;
                                ok ->
                                    true;
                                {ok, _} ->
                                    true
                            end;
                        false ->
                            node_postcondition(NodeState, Call, Res)
                    end
        end;
    false ->
            debug("general postcondition fired for ~p:~p with response ~p", [Mod, Fun, Res]),
            %% All other commands pass.
            false
    end.

%% Assuming the postcondition for a call was true, update the model
%% accordingly for the test to proceed.
next_state(#state{byzantine_faults=ByzantineFaults0}=State, _Res, {call, ?MODULE, induce_byzantine_message_corruption_fault, [SourceNode, DestinationNode, Value]}) -> 
    ByzantineFaults = add_byzantine_fault(SourceNode, DestinationNode, Value, ByzantineFaults0),
    State#state{byzantine_faults=ByzantineFaults};
next_state(#state{byzantine_faults=ByzantineFaults0}=State, _Res, {call, ?MODULE, resolve_byzantine_message_corruption_fault, [SourceNode, DestinationNode]}) -> 
    ByzantineFaults = delete_byzantine_fault(SourceNode, DestinationNode, ByzantineFaults0),
    State#state{byzantine_faults=ByzantineFaults};
next_state(#state{partition_filters=PartitionFilters0}=State, _Res, {call, ?MODULE, induce_async_partition, [SourceNode, DestinationNode]}) -> 
    PartitionFilters = add_async_partition(SourceNode, DestinationNode, PartitionFilters0),
    State#state{partition_filters=PartitionFilters};
next_state(#state{partition_filters=PartitionFilters0}=State, _Res, {call, ?MODULE, resolve_async_partition, [SourceNode, DestinationNode]}) -> 
    PartitionFilters = delete_async_partition(SourceNode, DestinationNode, PartitionFilters0),
    State#state{partition_filters=PartitionFilters};
next_state(#state{partition_filters=PartitionFilters0}=State, _Res, {call, ?MODULE, induce_sync_partition, [SourceNode, DestinationNode]}) -> 
    PartitionFilters = add_sync_partition(SourceNode, DestinationNode, PartitionFilters0),
    State#state{partition_filters=PartitionFilters};
next_state(#state{partition_filters=PartitionFilters0}=State, _Res, {call, ?MODULE, resolve_sync_partition, [SourceNode, DestinationNode]}) -> 
    PartitionFilters = delete_sync_partition(SourceNode, DestinationNode, PartitionFilters0),
    State#state{partition_filters=PartitionFilters};
next_state(#state{partition_filters=PartitionFilters0}=State, _Res, {call, ?MODULE, induce_cluster_partition, [MajorityNodes, AllNodes]}) -> 
    MinorityNodes = AllNodes -- MajorityNodes,
    PartitionFilters = add_cluster_partition(MajorityNodes, MinorityNodes, PartitionFilters0),
    State#state{partition_filters=PartitionFilters, majority_nodes=MajorityNodes, minority_nodes=MinorityNodes};
next_state(#state{partition_filters=PartitionFilters0}=State, _Res, {call, ?MODULE, resolve_cluster_partition, [MajorityNodes, AllNodes]}) -> 
    MinorityNodes = AllNodes -- MajorityNodes,
    PartitionFilters = delete_cluster_partition(MajorityNodes, MinorityNodes, PartitionFilters0),
    State#state{partition_filters=PartitionFilters, majority_nodes=[], minority_nodes=[]};
next_state(State, _Res, {call, ?MODULE, join_cluster, [Node, JoinedNodes]}) -> 
    case is_joined(Node, JoinedNodes) of
        true ->
            %% no-op for the join
            State;
        false ->
            %% add to the joined list.
            State#state{joined_nodes=JoinedNodes ++ [Node]}
    end;
next_state(#state{joined_nodes=JoinedNodes}=State, _Res, {call, ?MODULE, leave_cluster, [Node, JoinedNodes]}) -> 
    case enough_nodes_connected_to_issue_remove(JoinedNodes) of
        true ->
            %% removed from the list.
            State#state{joined_nodes=JoinedNodes -- [Node]};
        false ->
            %% no-op for the leave
            State
    end;
next_state(#state{node_state=NodeState0}=State, Res, {call, _Mod, Fun, _Args}=Call) -> 
    case lists:member(Fun, node_functions()) of
        true ->
            NodeState = node_next_state(NodeState0, Res, Call),
            State#state{node_state=NodeState};
        false ->
            debug("general next_state fired", []),
            State
    end.

%%%===================================================================
%%% Generators
%%%===================================================================

node_name() ->
    ?LET(Names, names(), oneof(Names)).

names() ->
    NameFun = fun(N) -> 
        list_to_atom("node_" ++ integer_to_list(N)) 
    end,
    lists:map(NameFun, lists:seq(1, ?NUM_NODES)).

key() ->
    oneof([<<"key">>]).

value() ->
    ?LET(Binary, binary(), 
        {erlang:timestamp(), Binary}).

%%%===================================================================
%%% Cluster Functions
%%%===================================================================

start_nodes() ->
    %% Create an ets table for test configuration.
    ?MODULE = ets:new(?MODULE, [named_table]),

    %% Special configuration for the cluster.
    Config = [{partisan_dispatch, true},
              {parallelism, ?PARALLELISM},
              {tls, false},
              {binary_padding, false},
              {channels, ?CHANNELS},
              {vnode_partitioning, ?VNODE_PARTITIONING},
              {causal_labels, ?CAUSAL_LABELS},
              {egress_delay, ?EGRESS_DELAY},
              {ingress_delay, ?INGRESS_DELAY},
              {disable_fast_forward, true}],

    %% Initialize a cluster.
    Nodes = ?SUPPORT:start(scale_test,
                           Config,
                           [{partisan_peer_service_manager,
                               partisan_default_peer_service_manager},
                           {num_nodes, ?NUM_NODES},
                           {cluster_nodes, ?CLUSTER_NODES}]),

    %% Insert all nodes into group for all nodes.
    true = ets:insert(?MODULE, {nodes, Nodes}),

    %% Insert name to node mappings for lookup.
    %% Caveat, because sometimes we won't know ahead of time what FQDN the node will
    %% come online with when using partisan.
    lists:foreach(fun({Name, Node}) ->
        true = ets:insert(?MODULE, {Name, Node})
    end, Nodes),

    ok.

stop_nodes() ->
    %% Get list of nodes that were started at the start
    %% of the test.
    [{nodes, Nodes}] = ets:lookup(?MODULE, nodes),

    %% Stop nodes.
    ?SUPPORT:stop(Nodes),

    %% Delete the table.
    ets:delete(?MODULE),

    ok.

%% Determine if a bunch of operations succeeded or failed.
all_to_ok_or_error(List) ->
    case lists:all(fun(X) -> X =:= ok end, List) of
        true ->
            ok;
        false ->
            {error, some_opertions_failed}
    end.

%% Select a random grouping of nodes.
majority_nodes() ->
    ?LET(MajorityCount, ?NUM_NODES / 2 + 1,
        ?LET(Names, names(), 
            ?LET(Sublist, lists:sublist(Names, trunc(MajorityCount)), Sublist))).

%% Is a node involved in a byzantine fault?
is_involved_in_byzantine_fault(SourceNode, DestinationNode, ByzantineFaults) ->
    Source = case dict:find({SourceNode, DestinationNode}, ByzantineFaults) of
        error ->
            false;
        _ ->
            true
    end,

    Destination = case dict:find({DestinationNode, SourceNode}, ByzantineFaults) of
        error ->
            false;
        _ ->
            true
    end,

    Source orelse Destination.

%% Is a node involved in an sync partition?
is_involved_in_partition(SourceNode, DestinationNode, PartitionFilters) ->
    Source = case dict:find({SourceNode, DestinationNode}, PartitionFilters) of
        error ->
            false;
        _ ->
            true
    end,

    Destination = case dict:find({DestinationNode, SourceNode}, PartitionFilters) of
        error ->
            false;
        _ ->
            true
    end,

    Source orelse Destination.

delete_sync_partition(SourceNode, DestinationNode, PartitionFilters) ->
    delete_async_partition(DestinationNode, SourceNode, 
        delete_async_partition(SourceNode, DestinationNode, PartitionFilters)).

delete_async_partition(SourceNode, DestinationNode, PartitionFilters) ->
    dict:erase({SourceNode, DestinationNode}, PartitionFilters).

add_sync_partition(SourceNode, DestinationNode, PartitionFilters) ->
    add_async_partition(SourceNode, DestinationNode,
        add_async_partition(DestinationNode, SourceNode, PartitionFilters)).

add_async_partition(SourceNode, DestinationNode, PartitionFilters) ->
    dict:store({SourceNode, DestinationNode}, true, PartitionFilters).

add_byzantine_fault(SourceNode, DestinationNode, Value, ByzantineFaults) ->
    dict:store({SourceNode, DestinationNode}, Value, ByzantineFaults).

delete_byzantine_fault(SourceNode, DestinationNode, ByzantineFaults) ->
    dict:erase({SourceNode, DestinationNode}, ByzantineFaults).

add_cluster_partition(MajorityNodes, AllNodes, PartitionFilters) ->
    MinorityNodes = AllNodes -- MajorityNodes,

    lists:foldl(fun(SourceNode, Filters) ->
        lists:foldl(fun(DestinationNode, Filters2) ->
            add_sync_partition(SourceNode, DestinationNode, Filters2)
            end, Filters, MinorityNodes)
        end, PartitionFilters, MajorityNodes).

delete_cluster_partition(MajorityNodes, AllNodes, PartitionFilters) ->
    MinorityNodes = AllNodes -- MajorityNodes,

    lists:foldl(fun(SourceNode, Filters) ->
        lists:foldl(fun(DestinationNode, Filters2) ->
            delete_sync_partition(SourceNode, DestinationNode, Filters2)
            end, Filters, MinorityNodes)
        end, PartitionFilters, MajorityNodes).

induce_cluster_partition(MajorityNodes, AllNodes) ->
    MinorityNodes = AllNodes -- MajorityNodes,
    debug("induce_cluster_partition: majority_nodes ~p minority_nodes ~p", [MajorityNodes, MinorityNodes]),

    Results = lists:flatmap(fun(SourceNode) ->
        lists:flatmap(fun(DestinationNode) ->
            [
             induce_async_partition(SourceNode, DestinationNode),
             induce_async_partition(DestinationNode, SourceNode)
            ]
            end, MinorityNodes)
        end, MajorityNodes),
    all_to_ok_or_error(Results).

resolve_cluster_partition(MajorityNodes, AllNodes) ->
    MinorityNodes = AllNodes -- MajorityNodes,

    debug("resolve_cluster_partition: majority_nodes ~p minority_nodes ~p", [MajorityNodes, MinorityNodes]),
    Results = lists:flatmap(fun(SourceNode) ->
        lists:flatmap(fun(DestinationNode) ->
            [
             resolve_async_partition(SourceNode, DestinationNode),
             resolve_async_partition(DestinationNode, SourceNode)
            ]
            end, MinorityNodes)
        end, MajorityNodes),
    all_to_ok_or_error(Results).

is_involved_in_x_partitions(Node, X, PartitionFilters) ->
    Count = dict:fold(fun(Key, _Value, AccIn) ->
            case Key of
                {Node, _} ->
                    AccIn + 1;
                _ ->
                    AccIn
            end
        end, 0, PartitionFilters),
    debug("is_involved_in_x_partitions is ~p and should be ~p", [Count, X]),
    Count >= X.

is_valid_partition(SourceNode, DestinationNode) ->
    SourceNode =/= DestinationNode.

induce_byzantine_message_corruption_fault(SourceNode, DestinationNode0, Value) ->
    debug("induce_byzantine_message_corruption_fault: source_node ~p destination_node ~p value ~p", [SourceNode, DestinationNode0, Value]),

    %% Convert to real node name and not symbolic name.
    DestinationNode = name_to_nodename(DestinationNode0),

    InterpositionFun = fun({forward_message, N, Message}) ->
        case N of
            DestinationNode ->
                lager:info("Rewriting packet from ~p to ~p for message from ~p to ~p due to interposition.", [Message, Value, SourceNode, DestinationNode]),
                Value;
            OtherNode ->
                lager:info("Allowing message, doesn't match interposition as destination is ~p and not ~p", [OtherNode, DestinationNode]),
                Message
        end
    end,
    rpc:call(name_to_nodename(SourceNode), ?MANAGER, add_interposition_fun, [{corruption, DestinationNode}, InterpositionFun]).

resolve_byzantine_message_corruption_fault(SourceNode, DestinationNode0) ->
    debug("resolve_byzantine_message_corruption_fault: source_node ~p destination_node ~p", [SourceNode, DestinationNode0]),

    %% Convert to real node name and not symbolic name.
    DestinationNode = name_to_nodename(DestinationNode0),

    rpc:call(name_to_nodename(SourceNode), ?MANAGER, remove_interposition_fun, [{corruption, DestinationNode}]).

induce_async_partition(SourceNode, DestinationNode0) ->
    debug("induce_async_partition: source_node ~p destination_node ~p", [SourceNode, DestinationNode0]),

    %% Convert to real node name and not symbolic name.
    DestinationNode = name_to_nodename(DestinationNode0),

    InterpositionFun = fun({forward_message, N, Message}) ->
        case N of
            DestinationNode ->
                lager:info("Dropping packet from ~p to ~p due to interposition.", [SourceNode, DestinationNode]),
                undefined;
            OtherNode ->
                lager:info("Allowing message, doesn't match interposition as destination is ~p and not ~p", [OtherNode, DestinationNode]),
                Message
        end
    end,
    rpc:call(name_to_nodename(SourceNode), ?MANAGER, add_interposition_fun, [{async, DestinationNode}, InterpositionFun]).

resolve_async_partition(SourceNode, DestinationNode0) ->
    debug("resolve_async_partition: source_node ~p destination_node ~p", [SourceNode, DestinationNode0]),

    %% Convert to real node name and not symbolic name.
    DestinationNode = name_to_nodename(DestinationNode0),

    rpc:call(name_to_nodename(SourceNode), ?MANAGER, remove_interposition_fun, [{async, DestinationNode}]).

induce_sync_partition(SourceNode, DestinationNode) ->
    debug("induce_sync_partition: source_node ~p destination_node ~p", [SourceNode, DestinationNode]),
    SourceResult = induce_async_partition(SourceNode, DestinationNode),
    DestinationResult = induce_async_partition(DestinationNode, SourceNode),
    all_to_ok_or_error([SourceResult, DestinationResult]).

resolve_sync_partition(SourceNode, DestinationNode) ->
    debug("resolve_sync_partition: source_node ~p destination_node ~p", [SourceNode, DestinationNode]),
    SourceResult = resolve_async_partition(SourceNode, DestinationNode),
    DestinationResult = resolve_async_partition(DestinationNode, SourceNode),
    all_to_ok_or_error([SourceResult, DestinationResult]).

leave_cluster(Name, JoinedNames) ->
    Node = name_to_nodename(Name),
    debug("leave_cluster: leaving node ~p from cluster with members ~p", [Node, JoinedNames]),

    case enough_nodes_connected_to_issue_remove(JoinedNames) of
        false ->
            ok;
        true ->
            %% Issue remove.
            ok = ?SUPPORT:leave(Node),

            %% Verify appropriate number of connections.
            NewCluster = lists:map(fun name_to_nodename/1, JoinedNames -- [Name]),

            %% Ensure each node owns a portion of the ring
            ConvergeFun = fun() ->
                ok = ?SUPPORT:wait_until_all_connections(NewCluster),
                ok = ?SUPPORT:wait_until_nodes_agree_about_ownership(NewCluster),
                ok = ?SUPPORT:wait_until_no_pending_changes(NewCluster),
                ok = ?SUPPORT:wait_until_ring_converged(NewCluster)
            end,
            {ConvergeTime, _} = timer:tc(ConvergeFun),

            debug("leave_cluster: converged at ~p", [ConvergeTime]),
            ok
    end.

join_cluster(Name, [JoinedName|_]=JoinedNames) ->
    case is_joined(Name, JoinedNames) of
        true ->
            ok;
        false ->
            Node = name_to_nodename(Name),
            JoinedNode = name_to_nodename(JoinedName),
            debug("join_cluster: joining node ~p to node ~p", [Node, JoinedNode]),

            %% Stage join.
            ok = ?SUPPORT:staged_join(Node, JoinedNode),

            %% Plan will only succeed once the ring has been gossiped.
            ok = ?SUPPORT:plan_and_commit(JoinedNode),

            %% Verify appropriate number of connections.
            NewCluster = lists:map(fun name_to_nodename/1, JoinedNames ++ [Name]),

            %% Ensure each node owns a portion of the ring
            ConvergeFun = fun() ->
                ok = ?SUPPORT:wait_until_all_connections(NewCluster),
                ok = ?SUPPORT:wait_until_nodes_agree_about_ownership(NewCluster),
                ok = ?SUPPORT:wait_until_no_pending_changes(NewCluster),
                ok = ?SUPPORT:wait_until_ring_converged(NewCluster)
            end,
            {ConvergeTime, _} = timer:tc(ConvergeFun),

            debug("join_cluster: converged at ~p", [ConvergeTime]),
            ok
    end.

name_to_nodename(Name) ->
    [{_, NodeName}] = ets:lookup(?MODULE, Name),
    NodeName.

enough_nodes_connected(Nodes) ->
    length(Nodes) >= 3.

enough_nodes_connected_to_issue_remove(Nodes) ->
    length(Nodes) > 3.

debug(Line, Args) ->
    case ?DEBUG of
        true ->
            lager:info(Line, Args);
        false ->
            ok
    end.

is_joined(Node, Cluster) ->
    lists:member(Node, Cluster).

cluster_commands(#state{joined_nodes=JoinedNodes}) ->
    ByzantineCommands = case ?PERFORM_BYZANTINE_MESSAGE_FAULTS of
        true ->
            [
            {call, ?MODULE, induce_byzantine_message_corruption_fault, [node_name(), node_name(), value()]},
            {call, ?MODULE, resolve_byzantine_message_corruption_fault, [node_name(), node_name()]}
            ];
        false ->
            []
    end,

    MemberCommands = case ?PERFORM_LEAVES_AND_JOINS of
        true ->
            [
            {call, ?MODULE, join_cluster, [node_name(), JoinedNodes]},
            {call, ?MODULE, leave_cluster, [node_name(), JoinedNodes]}
            ];
        false ->
            []
    end,

    AsyncPartitionCommands = case ?PERFORM_ASYNC_PARTITIONS of
        true ->
            [
            {call, ?MODULE, induce_async_partition, [node_name(), node_name()]},
            {call, ?MODULE, resolve_async_partition, [node_name(), node_name()]}
            ];
        false ->
            []
    end,

    SyncPartitionCommands = case ?PERFORM_SYNC_PARTITIONS of
        true ->
            [
            {call, ?MODULE, induce_sync_partition, [node_name(), node_name()]},
            {call, ?MODULE, resolve_sync_partition, [node_name(), node_name()]}
            ];
        false ->
            []
    end,

    ClusterPartitionCommands = case ?PERFORM_CLUSTER_PARTITIONS of
        true ->
            [
             {call, ?MODULE, induce_cluster_partition, [majority_nodes(), names()]},
             {call, ?MODULE, resolve_cluster_partition, [majority_nodes(), names()]}
            ];
        false ->
            []
    end,

    MemberCommands ++ 
        AsyncPartitionCommands ++ 
        SyncPartitionCommands ++ 
        ClusterPartitionCommands ++
        ByzantineCommands.

%%%===================================================================
%%% Node Functions
%%%===================================================================

%% What node-specific operations should be called.
node_commands() ->
    ByzantineCommands = case ?PERFORM_BYZANTINE_NODE_FAULTS of
        true ->
            [
            {call, ?MODULE, induce_byzantine_disk_loss_fault, [node_name(), key()]},
            {call, ?MODULE, induce_byzantine_bit_flip_fault, [node_name(), key(), binary()]}
            ];
        false ->
            []
    end,

    [
     {call, ?MODULE, read_object, [node_name(), key()]},
     {call, ?MODULE, write_object, [node_name(), key(), value()]}
    ] ++

    ByzantineCommands.

%% What should the initial node state be.
node_initial_state() ->
    {dict:new(), dict:new()}.

%% Names of the node functions so we kow when we can dispatch to the node
%% pre- and postconditions.
node_functions() ->
    lists:map(fun({call, _Mod, Fun, _Args}) -> Fun end, node_commands()).

%% Postconditions for node commands.
node_postcondition({DatabaseState, ClientState}, {call, ?MODULE, read_object, [_Node, Key]}, {ok, Value}) -> 
    debug("read_object: returned key ~p value ~p", [Key, Value]),
    %% Only pass acknowledged reads.
    StartingValues = [not_found],

    case dict:find(Key, DatabaseState) of
        {ok, KeyValues} ->
            ValueList = StartingValues ++ KeyValues,
            debug("read_object: looking for ~p in ~p", [Value, ValueList]),
            ItWasWritten = lists:member(Value, ValueList),
            debug("read_object: value read in write history: ~p", [ItWasWritten]),
            case ItWasWritten of
                true ->
                    case ?MONOTONIC_READS of
                        true ->
                            is_monotonic_read(Key, Value, ClientState);
                        false ->
                            true
                    end;
                false ->
                    false
            end;
        _ ->
            case Value of
                not_found ->
                    debug("read_object: object wasn't written yet, not_found might be OK", []),
                    is_monotonic_read(Key, Value, ClientState);
                _ ->
                    debug("read_object: consistency violation, object was not written but was read", []),
                    false
            end
    end;
node_postcondition({_DatabaseState, _ClientState}, {call, ?MODULE, read_object, [Node, Key]}, {error, timeout}) -> 
    debug("read_object ~p ~p timeout", [Node, Key]),
    %% Consider timeouts as failures for now.
    false;
node_postcondition({_DatabaseState, _ClientState}, {call, ?MODULE, induce_byzantine_bit_flip_fault, [Node, Key, Value]}, ok) -> 
    debug("induce_byzantine_bit_flip_fault: ~p ~p ~p", [Node, Key, Value]),
    true;
node_postcondition({_DatabaseState, _ClientState}, {call, ?MODULE, induce_byzantine_disk_loss_fault, [Node, Key]}, ok) -> 
    debug("induce_byzantine_disk_loss_fault: ~p ~p", [Node, Key]),
    true;
node_postcondition({_DatabaseState, _ClientState}, {call, ?MODULE, write_object, [_Node, _Key, _Value]}, {ok, _Value}) -> 
    debug("write_object returned ok", []),
    %% Only pass acknowledged writes.
    true;
node_postcondition({_DatabaseState, _ClientState}, {call, ?MODULE, write_object, [Node, Key, _Value]}, {error, timeout}) -> 
    debug("write_object ~p ~p timeout", [Node, Key]),
    %% Consider timeouts as failures for now.
    false.

%% Precondition.
node_precondition({_DatabaseState, _ClientState}, {call, _Mod, induce_byzantine_disk_loss_fault, [_Node, _Key]}) -> 
    true;
node_precondition({_DatabaseState, _ClientState}, {call, _Mod, induce_byzantine_bit_flip_fault, [_Node, _Key, _Value]}) -> 
    true;
node_precondition({_DatabaseState, _ClientState}, {call, _Mod, read_object, [_Node, _Key]}) -> 
    true;
node_precondition({_DatabaseState, _ClientState}, {call, _Mod, write_object, [_Node, _Key, _Value]}) -> 
    true.

%% Next state.

%% Failures don't modify what the state should be.
node_next_state({DatabaseState, ClientState}, _Res, {call, ?MODULE, induce_byzantine_disk_loss_fault, [_Node, _Key]}) -> 
    {DatabaseState, ClientState};

node_next_state({DatabaseState, ClientState}, _Res, {call, ?MODULE, induce_byzantine_bit_flip_fault, [_Node, _Key, _Value]}) -> 
    {DatabaseState, ClientState};

%% Reads don't modify state.
%% TODO: Advance client state on read.
node_next_state({DatabaseState, ClientState}, _Res, {call, ?MODULE, read_object, [_Node, _Key]}) -> 
    {DatabaseState, ClientState};

%% All we know is that the write was potentially acknowledged at some of the nodes.
node_next_state({DatabaseState0, ClientState0}, {error, timeout}, {call, ?MODULE, write_object, [_Node, Key, Value]}) -> 
    DatabaseState = dict:append_list(Key, [Value], DatabaseState0),
    {DatabaseState, ClientState0};

%% Write succeeded at all nodes.
node_next_state({DatabaseState0, ClientState0}, _Res, {call, ?MODULE, write_object, [_Node, Key, Value]}) -> 
    DatabaseState = dict:append_list(Key, [Value], DatabaseState0),
    ClientState = dict:store(Key, Value, ClientState0),
    {DatabaseState, ClientState}.

is_monotonic_read(Key, not_found, ClientState) ->
    case dict:find(Key, ClientState) of
        {ok, {_LastReadTimestamp, _LastReadBinary} = LastReadValue} ->
            debug("got not_found, should have read ~p", [LastReadValue]),
            false;
        _ ->
            true
    end;
%% Old style tests.
is_monotonic_read(_Key, Binary, _ClientState) when is_binary(Binary) ->
    true;
is_monotonic_read(Key, {ReadTimestamp, _ReadBinary} = ReadValue, ClientState) ->
    case dict:find(Key, ClientState) of
        {ok, {LastReadTimestamp, _LastReadBinary} = LastReadValue} ->
            Result = timer:now_diff(ReadTimestamp, LastReadTimestamp) >= 0,
            debug("last read ~p now read ~p, result ~p", [LastReadValue, ReadValue, Result]),
            Result;
        _ ->
            true
    end.

induce_byzantine_disk_loss_fault(Node, Key) ->
    rpc:call(name_to_nodename(Node), ?APP, inject_failure, [Key, undefined]).

induce_byzantine_bit_flip_fault(Node, Key, Value) ->
    rpc:call(name_to_nodename(Node), ?APP, inject_failure, [Key, Value]).

write_object(Node, Key, Value) ->
    debug("write_object: node ~p key ~p value ~p", [Node, Key, Value]),
    rpc:call(name_to_nodename(Node), ?APP, fsm_put, [Key, Value]).

read_object(Node, Key) ->
    debug("read_object: node ~p key ~p", [Node, Key]),
    rpc:call(name_to_nodename(Node), ?APP, fsm_get, [Key]).