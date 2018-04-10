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

-export([command/1, 
         initial_state/0, 
         next_state/3,
         precondition/2, 
         postcondition/3]).

prop_test() ->
    ?FORALL(Cmds, more_commands(10, commands(?MODULE)), 
        begin
            start_nodes(),
            {History, State, Result} = run_commands(?MODULE, Cmds), 
            stop_nodes(),
            ?WHENFAIL(io:format("History: ~p\nState: ~p\nResult: ~p\n",
                                [History,State,Result]),
                      aggregate(command_names(Cmds), Result =:= ok))
        end).

-record(state, {joined_nodes, nodes, store}).

-define(NUM_NODES, 5).

%% Initial model value at system start. Should be deterministic.
initial_state() -> 
    %% Initialize empty dictionary for process state.
    Store = dict:new(),

    %% Get the list of nodes.
    Nodes = names(),

    %% All nodes are assumed as joined.
    JoinedNodes = Nodes,

    #state{joined_nodes=JoinedNodes, nodes=Nodes, store=Store}.

command(#state{joined_nodes=_JoinedNodes}) -> 
    oneof([
        {call, ?MODULE, write_object, [node_name(), key(), value()]},
        {call, ?MODULE, read_object, [node_name(), key()]}
        %% {call, ?MODULE, leave_cluster, [node_name()]}
        %% {call, ?MODULE, join_cluster, [node_name(), JoinedNodes]}
    ]).

%% Picks whether a command should be valid under the current state.
precondition(#state{joined_nodes=JoinedNodes}, {call, _Mod, join_cluster, [Node]}) -> 
    enough_nodes_connected(JoinedNodes) andalso not lists:member(Node, JoinedNodes);
precondition(#state{joined_nodes=JoinedNodes}, {call, _Mod, leave_cluster, [Node]}) -> 
    enough_nodes_connected(JoinedNodes) andalso lists:member(Node, JoinedNodes);
precondition(#state{joined_nodes=JoinedNodes}, {call, _Mod, read_object, [Node, _Key]}) -> 
    enough_nodes_connected(JoinedNodes) andalso lists:member(Node, JoinedNodes);
precondition(#state{joined_nodes=JoinedNodes}, {call, _Mod, write_object, [Node, _Key, _Value]}) -> 
    enough_nodes_connected(JoinedNodes) andalso lists:member(Node, JoinedNodes);
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
    %% Accept leaves that succeed.
    true;
postcondition(_State, {call, ?MODULE, leave_cluster, [_Node]}, ok) ->
    %% Accept leaves that succeed.
    true;
postcondition(_State, {call, ?MODULE, leave_cluster, [_Node]}, error) ->
    %% Fail leaves that fail.
    false;
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
    State#state{joined_nodes=JoinedNodes ++ [Node]};
next_state(#state{joined_nodes=JoinedNodes}=State, _Res, {call, ?MODULE, leave_cluster, [Node]}) -> 
    State#state{joined_nodes=JoinedNodes -- [Node]};
next_state(#state{store=Store0}=State, _Res, {call, ?MODULE, write_object, [_Node, Key, Value]}) -> 
    Store = dict:store(Key, Value, Store0),
    State#state{store=Store};
next_state(State, _Res, {call, _Mod, _Fun, _Args}) -> 
    NewState = State,
    NewState.

%%%===================================================================
%%% Generators
%%%===================================================================

node_name() ->
    ?LET(Names, names(), oneof(Names)).

names() ->
    lists:map(fun(N) -> list_to_atom("node_" ++ integer_to_list(N)) end, lists:seq(1, ?NUM_NODES)).

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
                           {cluster_nodes, true}]),

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

leave_cluster(Node) ->
    debug("leave_cluster: leaving node from cluster.", [Node]),
    rpc:call(name_to_nodename(Node), riak_core, leave, []).

join_cluster(Node, JoinedNodes) ->
    ?SUPPORT:join_cluster(JoinedNodes ++ [Node]).

name_to_nodename(Name) ->
    [{_, NodeName}] = ets:lookup(?MODULE, Name),
    NodeName.

enough_nodes_connected(Nodes) ->
    length(Nodes) >= 3.

debug(Line, Args) ->
    ct:pal(Line, Args).