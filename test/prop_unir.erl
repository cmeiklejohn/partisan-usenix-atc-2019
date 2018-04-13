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

-define(NUM_NODES, 4).
-define(COMMAND_MULTIPLE, 1).

-export([command/1, 
         initial_state/0, 
         next_state/3,
         precondition/2, 
         postcondition/3]).

prop_test() ->
    ?FORALL(Cmds, more_commands(?COMMAND_MULTIPLE, commands(?MODULE)), 
        begin
            start_nodes(),
            {History, State, Result} = run_commands(?MODULE, Cmds), 
            stop_nodes(),
            ?WHENFAIL(io:format("History: ~p\nState: ~p\nResult: ~p\n",
                                [History,State,Result]),
                      aggregate(command_names(Cmds), Result =:= ok))
        end).

-record(state, {joined_nodes, nodes, store}).

%% Initial model value at system start. Should be deterministic.
initial_state() -> 
    %% Initialize empty dictionary for process state.
    Store = dict:new(),

    %% Get the list of nodes.
    Nodes = names(),

    %% Assume first is joined -- node_1 will be the join point.
    JoinedNodes = [hd(Nodes)],

    %% Debug message.
    debug("initial_state: nodes ~p joined_nodes ~p", [Nodes, JoinedNodes]),

    #state{joined_nodes=JoinedNodes, nodes=Nodes, store=Store}.

command(#state{joined_nodes=JoinedNodes}) -> 
    oneof([
        {call, ?MODULE, write_object, [node_name(), key(), value()]},
        {call, ?MODULE, read_object, [node_name(), key()]},
        {call, ?MODULE, join_cluster, [node_name(), JoinedNodes]},
        {call, ?MODULE, leave_cluster, [node_name(), JoinedNodes]}
    ]).

%% Picks whether a command should be valid under the current state.
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
            true
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
            true
    end;
precondition(#state{joined_nodes=JoinedNodes}, {call, _Mod, read_object, [Node, _Key]}) -> 
    enough_nodes_connected(JoinedNodes) andalso is_joined(Node, JoinedNodes);
precondition(#state{joined_nodes=JoinedNodes}, {call, _Mod, write_object, [Node, _Key, _Value]}) -> 
    enough_nodes_connected(JoinedNodes) andalso is_joined(Node, JoinedNodes);
precondition(#state{}, {call, _Mod, _Fun, _Args}) -> 
    debug("general precondition fired", []),
    false.

%% Given the state `State' *prior* to the call `{call, Mod, Fun, Args}',
%% determine whether the result `Res' (coming from the actual system)
%% makes sense.
postcondition(#state{store=Store}, {call, ?MODULE, read_object, [_Node, Key]}, {ok, Value}) -> 
    debug("read_object: returned key ~p value ~p", [Key, Value]),
    %% Only pass acknowledged reads.
    case dict:find(Key, Store) of
        {ok, Value} ->
            debug("read_object: value read was written, OK", []),
            true;
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
postcondition(_State, {call, ?MODULE, join_cluster, [_Node, _JoinedNodes]}, ok) ->
    debug("postcondition join_cluster: succeeded", []),
    %% Accept joins that succeed.
    true;
postcondition(_State, {call, ?MODULE, leave_cluster, [_Node, _JoinedNodes]}, ok) ->
    debug("postcondition leave_cluster: succeeded", []),
    %% Accept leaves that succeed.
    true;
postcondition(_State, {call, ?MODULE, read_object, [_Node, _Key]}, {error, _}) -> 
    %% Fail timed out reads.
    false;
postcondition(_State, {call, ?MODULE, write_object, [_Node, _Key, _Value]}, {ok, _Value}) -> 
    %% Only pass acknowledged writes.
    true;
postcondition(_State, {call, ?MODULE, write_object, [_Node, _Key, _Value]}, {error, _}) -> 
    %% Consider timeouts as failures for now.
    false;
postcondition(_State, {call, _Mod, _Fun, _Args}, Res) -> 
    debug("general postcondition fired with response ~p", [Res]),
    %% All other commands pass.
    false.

%% Assuming the postcondition for a call was true, update the model
%% accordingly for the test to proceed.
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
next_state(State, _Res, {call, ?MODULE, read_object, [_Node, _Key]}) -> 
    State;
next_state(#state{store=Store0}=State, _Res, {call, ?MODULE, write_object, [_Node, Key, Value]}) -> 
    Store = dict:store(Key, Value, Store0),
    State#state{store=Store};
next_state(State, _Res, {call, _Mod, _Fun, _Args}) -> 
    debug("general next_state fired", []),
    NewState = State,
    NewState.

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
              {vnode_partitioning, false}],

    %% Initialize a cluster.
    Nodes = ?SUPPORT:start(scale_test,
                           Config,
                           [{partisan_peer_service_manager,
                               partisan_default_peer_service_manager},
                           {num_nodes, ?NUM_NODES},
                           {cluster_nodes, false}]),

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
    ct:pal(Line, Args).

is_joined(Node, Cluster) ->
    lists:member(Node, Cluster).