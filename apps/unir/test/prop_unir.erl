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
    ?FORALL(Cmds, commands(?MODULE), 
        begin
            start_nodes(),
            {History, State, Result} = run_commands(?MODULE, Cmds), 
            stop_nodes(),
            ?WHENFAIL(io:format("History: ~p\nState: ~p\nResult: ~p\n",
                                [History,State,Result]),
                      aggregate(command_names(Cmds), Result =:= ok))
        end).

-record(state, {store}).

-define(NUM_NODES, 3).

%% Initial model value at system start. Should be deterministic.
initial_state() -> 
    %% Initialize empty dictionary for process state.
    Store = dict:new(),

    #state{store=Store}.

command(_State) -> 
    oneof([
        {call, ?MODULE, write_object, [node_name(), key(), value()]},
        {call, ?MODULE, read_object, [node_name(), key()]}
    ]).

%% Picks whether a command should be valid under the current state.
precondition(#state{}, {call, _Mod, _Fun, _Args}) -> 
    true.

%% Given the state `State' *prior* to the call `{call, Mod, Fun, Args}',
%% determine whether the result `Res' (coming from the actual system)
%% makes sense.
postcondition(#state{store=Store}, {call, ?MODULE, read_object, [_Node, Key]}, {ok, Value}) -> 
    %% Only pass acknowledged reads.
    case dict:find(Key, Store) of
        {ok, Value} ->
            true;
        _ ->
            false
    end;
postcondition(_State, {call, ?MODULE, read_object, [_Node, _Key]}, {error, _}) -> 
    %% Fail timed out reads.
    false;
postcondition(_State, {call, ?MODULE, write_object, [_Node, _Key, _Value]}, {ok, _Value}) -> 
    %% Only pass acknowledged writes.
    true;
postcondition(_State, {call, ?MODULE, write_object, [_Node, _Key, _Value]}, {error, _}) -> 
    %% Consider timeouts as failures for now.
    false;
postcondition(_State, {call, _Mod, _Fun, _Args}, _Res) -> 
    %% All other commands pass.
    false.

%% Assuming the postcondition for a call was true, update the model
%% accordingly for the test to proceed.
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
    lists:map(fun(N) -> "node_" ++ integer_to_list(N) end, lists:seq(1, ?NUM_NODES)).

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
    Config = [{partisan_dispatch, true}],

    %% Initialize a cluster.
    Nodes = ?SUPPORT:start(scale_test,
                           Config,
                           [{partisan_peer_service_manager,
                               partisan_default_peer_service_manager},
                           {num_nodes, ?NUM_NODES},
                           {cluster_nodes, true}]),

    true = ets:insert(?MODULE, {nodes, Nodes}),

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
    %% Perform write operation.
    rpc:call(Node, unir, fsm_put, [Key, Value]).

read_object(Node, Key) ->
    %% Perform write operation.
    rpc:call(Node, unir, fsm_get, [Key]).