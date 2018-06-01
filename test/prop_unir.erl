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
-define(PERFORM_LEAVES_AND_JOINS, false).

%% Only one of the modes below should be selected for proper shriking.
-define(PERFORM_CLUSTER_PARTITIONS, false).
-define(PERFORM_ASYNC_PARTITIONS, false).
-define(PERFORM_SYNC_PARTITIONS, true).

%% Other options to exercise pathological cases.
-define(BIAS_MINORITY, false).

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

-record(state, {joined_nodes, nodes, node_state, message_filters, minority_nodes, majority_nodes}).

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

    %% Message filters.
    MessageFilters = dict:new(),
    MinorityNodes = [],
    MajorityNodes = [],

    %% Debug message.
    debug("initial_state: nodes ~p joined_nodes ~p", [Nodes, JoinedNodes]),

    #state{joined_nodes=JoinedNodes, 
           nodes=Nodes,
           minority_nodes=MinorityNodes,
           majority_nodes=MajorityNodes, 
           node_state=NodeState, 
           message_filters=MessageFilters}.

command(State) -> 
    ?LET(Commands, cluster_commands(State) ++ node_commands(), oneof(Commands)).

%% Picks whether a command should be valid under the current state.
precondition(#state{message_filters=MessageFilters}, {call, _Mod, induce_async_partition, [SourceNode, DestinationNode]}) -> 
    not is_involved_in_partition(SourceNode, DestinationNode, MessageFilters);
precondition(#state{message_filters=MessageFilters}, {call, _Mod, resolve_async_partition, [SourceNode, DestinationNode]}) -> 
    is_involved_in_partition(SourceNode, DestinationNode, MessageFilters);
precondition(#state{message_filters=MessageFilters}, {call, _Mod, induce_sync_partition, [SourceNode, DestinationNode]}) -> 
    not is_involved_in_partition(SourceNode, DestinationNode, MessageFilters);
precondition(#state{message_filters=MessageFilters}, {call, _Mod, resolve_sync_partition, [SourceNode, DestinationNode]}) -> 
    is_involved_in_partition(SourceNode, DestinationNode, MessageFilters);
precondition(#state{message_filters=MessageFilters}, {call, _Mod, induce_cluster_partition, [MajorityNodes, AllNodes]}) -> 
    MinorityNodes = AllNodes -- MajorityNodes,

    lists:all(fun(SourceNode) -> 
        lists:all(fun(DestinationNode) ->
            not is_involved_in_partition(SourceNode, DestinationNode, MessageFilters)
        end, MinorityNodes)
    end, MajorityNodes);
precondition(#state{message_filters=MessageFilters}, {call, _Mod, resolve_cluster_partition, [MajorityNodes, AllNodes]}) -> 
    MinorityNodes = AllNodes -- MajorityNodes,

    lists:all(fun(SourceNode) -> 
        lists:all(fun(DestinationNode) ->
            is_involved_in_partition(SourceNode, DestinationNode, MessageFilters)
        end, MinorityNodes)
    end, MajorityNodes);
precondition(#state{nodes=Nodes, joined_nodes=JoinedNodes}, {call, _Mod, join_cluster, [Node, JoinedNodes]}) -> 
    %% Only allow dropping of the first unjoined node in the nodes list, for ease of debugging.
    %% debug("precondition join_cluster: invoked for node ~p joined_nodes ~p", [Node, JoinedNodes]),

    ToBeJoinedNodes = Nodes -- JoinedNodes,
    %% debug("precondition join_cluster: remaining nodes to be joined are: ~p", [ToBeJoinedNodes]),

    case length(ToBeJoinedNodes) > 0 of
        true ->
            ToBeJoinedNode = hd(ToBeJoinedNodes),
            %% debug("precondition join_cluster: attempting to join ~p", [ToBeJoinedNode]),
            case ToBeJoinedNode of
                Node ->
                    %% debug("precondition join_cluster: YES attempting to join ~p is ~p", [ToBeJoinedNode, Node]),
                    true;
                _OtherNode ->
                    %% debug("precondition join_cluster: NO attempting to join ~p not ~p", [ToBeJoinedNode, OtherNode]),
                    false
            end;
        false ->
            %% debug("precondition join_cluster: no nodes left to join.", []),
            false %% Might need to be changed when there's no read/write operations.
    end;
precondition(#state{joined_nodes=JoinedNodes}, {call, _Mod, leave_cluster, [Node, JoinedNodes]}) -> 
    %% Only allow dropping of the last node in the join list, for ease of debugging.
    %% debug("precondition leave_cluster: invoked for node ~p joined_nodes ~p", [Node, JoinedNodes]),

    ToBeRemovedNodes = JoinedNodes,
    %% debug("precondition leave_cluster: remaining nodes to be removed are: ~p", [ToBeRemovedNodes]),

    case length(ToBeRemovedNodes) > 3 of
        true ->
            ToBeRemovedNode = lists:last(ToBeRemovedNodes),
            %% debug("precondition leave_cluster: attempting to leave ~p", [ToBeRemovedNode]),
            case ToBeRemovedNode of
                Node ->
                    %% debug("precondition leave_cluster: YES attempting to leave ~p is ~p", [ToBeRemovedNode, Node]),
                    true;
                _OtherNode ->
                    %% debug("precondition leave_cluster: NO attempting to leave ~p not ~p", [ToBeRemovedNode, OtherNode]),
                    false
            end;
        false ->
            %% debug("precondition leave_cluster: no nodes left to remove.", []),
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
                            %% debug("=> bias towards minority, write is going to node ~p in minority", [Node]),
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
postcondition(#state{minority_nodes=MinorityNodes, message_filters=MessageFilters, node_state=NodeState}, {call, Mod, Fun, [Node|_]=_Args}=Call, Res) -> 
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
                    %% One partitioned node makes a quorum of 2 fail.
                    case is_involved_in_x_partitions(Node, 1, MessageFilters) of
                        true ->
                            case Res of
                                {error, _} ->
                                    true;
                                _ ->
                                    false
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
next_state(#state{message_filters=MessageFilters0}=State, _Res, {call, ?MODULE, induce_async_partition, [SourceNode, DestinationNode]}) -> 
    MessageFilters = add_async_partition(SourceNode, DestinationNode, MessageFilters0),
    State#state{message_filters=MessageFilters};
next_state(#state{message_filters=MessageFilters0}=State, _Res, {call, ?MODULE, resolve_async_partition, [SourceNode, DestinationNode]}) -> 
    MessageFilters = delete_async_partition(SourceNode, DestinationNode, MessageFilters0),
    State#state{message_filters=MessageFilters};
next_state(#state{message_filters=MessageFilters0}=State, _Res, {call, ?MODULE, induce_sync_partition, [SourceNode, DestinationNode]}) -> 
    MessageFilters = add_sync_partition(SourceNode, DestinationNode, MessageFilters0),
    State#state{message_filters=MessageFilters};
next_state(#state{message_filters=MessageFilters0}=State, _Res, {call, ?MODULE, resolve_sync_partition, [SourceNode, DestinationNode]}) -> 
    MessageFilters = delete_sync_partition(SourceNode, DestinationNode, MessageFilters0),
    State#state{message_filters=MessageFilters};
next_state(#state{message_filters=MessageFilters0}=State, _Res, {call, ?MODULE, induce_cluster_partition, [MajorityNodes, AllNodes]}) -> 
    MinorityNodes = AllNodes -- MajorityNodes,
    MessageFilters = add_cluster_partition(MajorityNodes, MinorityNodes, MessageFilters0),
    State#state{message_filters=MessageFilters, majority_nodes=MajorityNodes, minority_nodes=MinorityNodes};
next_state(#state{message_filters=MessageFilters0}=State, _Res, {call, ?MODULE, resolve_cluster_partition, [MajorityNodes, AllNodes]}) -> 
    MinorityNodes = AllNodes -- MajorityNodes,
    MessageFilters = delete_cluster_partition(MajorityNodes, MinorityNodes, MessageFilters0),
    State#state{message_filters=MessageFilters, majority_nodes=[], minority_nodes=[]};
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
    binary().

%%%===================================================================
%%% Helper Functions
%%%===================================================================

start_nodes() ->
    %% Create an ets table for test configuration.
    ?MODULE = ets:new(?MODULE, [named_table]),

    %% Special configuration for the cluster.
    Config = [{partisan_dispatch, true},
              {parallelism, 1},
              {tls, false},
              {binary_padding, false},
              {vnode_partitioning, false},
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

write_object(Node, Key, Value) ->
    debug("write_object: node ~p key ~p value ~p", [Node, Key, Value]),
    rpc:call(name_to_nodename(Node), unir, fsm_put, [Key, Value]).

read_object(Node, Key) ->
    debug("read_object: node ~p key ~p", [Node, Key]),
    rpc:call(name_to_nodename(Node), unir, fsm_get, [Key]).

induce_async_partition(SourceNode, DestinationNode0) ->
    debug("induce_async_partition: source_node ~p destination_node ~p", [SourceNode, DestinationNode0]),

    %% Convert to real node name and not symbolic name.
    DestinationNode = name_to_nodename(DestinationNode0),

    MessageFilterFun = fun({N, _}) ->
        case N of
            DestinationNode ->
                lager:info("Dropping packet from ~p to ~p due to filter.", [SourceNode, DestinationNode]),
                false;
            OtherNode ->
                lager:info("Allowing message, doesn't match filter as destination is ~p and not ~p", [OtherNode, DestinationNode]),
                true
        end
    end,
    rpc:call(name_to_nodename(SourceNode), ?MANAGER, add_message_filter, [{async, DestinationNode}, MessageFilterFun]).

resolve_async_partition(SourceNode, DestinationNode0) ->
    debug("resolve_async_partition: source_node ~p destination_node ~p", [SourceNode, DestinationNode0]),

    %% Convert to real node name and not symbolic name.
    DestinationNode = name_to_nodename(DestinationNode0),

    rpc:call(name_to_nodename(SourceNode), ?MANAGER, remove_message_filter, [{async, DestinationNode}]).

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
    lager:info(Line, Args).

is_joined(Node, Cluster) ->
    lists:member(Node, Cluster).

cluster_commands(#state{joined_nodes=JoinedNodes}) ->
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

    MemberCommands ++ AsyncPartitionCommands ++ SyncPartitionCommands ++ ClusterPartitionCommands.

%%%===================================================================
%%% Node Functions
%%%===================================================================

%% What node-specific operations should be called.
node_commands() ->
    [
     {call, ?MODULE, read_object, [node_name(), key()]},
     {call, ?MODULE, write_object, [node_name(), key(), value()]}
    ].

%% What should the initial node state be.
node_initial_state() ->
    dict:new().

%% Names of the node functions so we kow when we can dispatch to the node
%% pre- and postconditions.
node_functions() ->
    lists:map(fun({call, _Mod, Fun, _Args}) -> Fun end, node_commands()).

%% Postconditions for node commands.
node_postcondition(NodeState, {call, ?MODULE, read_object, [_Node, Key]}, {ok, Value}) -> 
    debug("read_object: returned key ~p value ~p", [Key, Value]),
    %% Only pass acknowledged reads.
    case dict:find(Key, NodeState) of
        {ok, KeyValues} ->
            ItWasWritten = lists:member(Value, KeyValues),
            debug("read_object: value read in write history: ~p", [ItWasWritten]),
            ItWasWritten;
        _ ->
            case Value of
                not_found ->
                    debug("read_object: object wasn't written yet, not_found OK", []),
                    true;
                _ ->
                    debug("read_object: consistency violation, object was not written but was read", []),
                    false
            end
    end;
node_postcondition(_NodeState, {call, ?MODULE, read_object, [Node, Key]}, {error, timeout}) -> 
    debug("read_object ~p ~p timeout", [Node, Key]),
    %% Fail timed out reads.
    false;
node_postcondition(_NodeState, {call, ?MODULE, write_object, [_Node, _Key, _Value]}, {ok, _Value}) -> 
    debug("write_object returned ok", []),
    %% Only pass acknowledged writes.
    true;
node_postcondition(_NodeState, {call, ?MODULE, write_object, [Node, Key, _Value]}, {error, timeout}) -> 
    debug("write_object ~p ~p timeout", [Node, Key]),
    %% Consider timeouts as failures for now.
    false.

%% Precondition.
node_precondition(_NodeState, {call, _Mod, read_object, [_Node, _Key]}) -> 
    true;
node_precondition(_NodeState, {call, _Mod, write_object, [_Node, _Key, _Value]}) -> 
    true.

%% Next state.

%% Reads don't modify state.
node_next_state(NodeState, _Res, {call, ?MODULE, read_object, [_Node, _Key]}) -> 
    NodeState;

%% All we know is that the write was acknowledged at *some* of the nodes.
node_next_state(NodeState, _Res, {call, ?MODULE, write_object, [_Node, Key, Value]}) -> 
    dict:append_list(Key, [Value], NodeState).

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

%% Is a node involved in an sync partition?
is_involved_in_partition(SourceNode, DestinationNode, MessageFilters) ->
    Source = case dict:find({SourceNode, DestinationNode}, MessageFilters) of
        error ->
            false;
        _ ->
            true
    end,

    Destination = case dict:find({DestinationNode, SourceNode}, MessageFilters) of
        error ->
            false;
        _ ->
            true
    end,

    Source orelse Destination.

delete_sync_partition(SourceNode, DestinationNode, MessageFilters) ->
    delete_async_partition(DestinationNode, SourceNode, 
        delete_async_partition(SourceNode, DestinationNode, MessageFilters)).

delete_async_partition(SourceNode, DestinationNode, MessageFilters) ->
    dict:erase({SourceNode, DestinationNode}, MessageFilters).

add_sync_partition(SourceNode, DestinationNode, MessageFilters) ->
    add_async_partition(SourceNode, DestinationNode,
        add_async_partition(DestinationNode, SourceNode, MessageFilters)).

add_async_partition(SourceNode, DestinationNode, MessageFilters) ->
    dict:store({SourceNode, DestinationNode}, true, MessageFilters).

add_cluster_partition(MajorityNodes, AllNodes, MessageFilters) ->
    MinorityNodes = AllNodes -- MajorityNodes,

    lists:foldl(fun(SourceNode, Filters) ->
        lists:foldl(fun(DestinationNode, Filters2) ->
            add_sync_partition(SourceNode, DestinationNode, Filters2)
            end, Filters, MinorityNodes)
        end, MessageFilters, MajorityNodes).

delete_cluster_partition(MajorityNodes, AllNodes, MessageFilters) ->
    MinorityNodes = AllNodes -- MajorityNodes,

    lists:foldl(fun(SourceNode, Filters) ->
        lists:foldl(fun(DestinationNode, Filters2) ->
            delete_sync_partition(SourceNode, DestinationNode, Filters2)
            end, Filters, MinorityNodes)
        end, MessageFilters, MajorityNodes).

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

is_involved_in_x_partitions(Node, X, MessageFilters) ->
    Count = dict:fold(fun(Key, Value, AccIn) ->
            case Key of
                {Node, _} ->
                    AccIn + 1;
                _ ->
                    AccIn
            end
        end, 0, MessageFilters),
    debug("is_involved_in_x_partitions is ~p and should be ~p", [Count, X]),
    Count >= X.