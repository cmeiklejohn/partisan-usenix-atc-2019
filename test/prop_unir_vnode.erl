%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Christopher S. Meiklejohn.  All Rights Reserved.
%%
%% -------------------------------------------------------------------

-module(prop_unir_vnode).
-author("Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>").

-include_lib("proper/include/proper.hrl").

-compile([export_all]).

%% Application under test.
-define(APP, unir).                                 %% The name of the top-level application that requests
                                                    %% should be issued to using the RPC mechanism.

%% Configuration parameters.
-define(PERFORM_BYZANTINE_NODE_FAULTS, false).      %% Whether or not we should use cluster-specific byzantine faults.
                                                    %% ie. data loss bugs, bit flips, etc.
-define(MONOTONIC_READS, false).                    %% Do we assume the system provides monotonic read?
-define(NUM_NODES, 3).
-define(NODE_DEBUG, true).                          %% Should we print out debugging information?

%% Helpers.
-define(ETS, prop_unir).
-define(NAME, fun(Name) -> [{_, NodeName}] = ets:lookup(?ETS, Name), NodeName end).

%%%===================================================================
%%% Generators
%%%===================================================================

key() ->
    oneof([<<"key">>]).

value() ->
    ?LET(Binary, binary(), 
        {erlang:timestamp(), Binary}).

node_name() ->
    ?LET(Names, names(), oneof(Names)).

names() ->
    NameFun = fun(N) -> 
        list_to_atom("node_" ++ integer_to_list(N)) 
    end,
    lists:map(NameFun, lists:seq(1, ?NUM_NODES)).

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
    node_debug("read_object: returned key ~p value ~p", [Key, Value]),
    %% Only pass acknowledged reads.
    StartingValues = [not_found],

    case dict:find(Key, DatabaseState) of
        {ok, KeyValues} ->
            ValueList = StartingValues ++ KeyValues,
            node_debug("read_object: looking for ~p in ~p", [Value, ValueList]),
            ItWasWritten = lists:member(Value, ValueList),
            node_debug("read_object: value read in write history: ~p", [ItWasWritten]),
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
                    node_debug("read_object: object wasn't written yet, not_found might be OK", []),
                    is_monotonic_read(Key, Value, ClientState);
                _ ->
                    node_debug("read_object: consistency violation, object was not written but was read", []),
                    false
            end
    end;
node_postcondition({_DatabaseState, _ClientState}, {call, ?MODULE, read_object, [Node, Key]}, {error, timeout}) -> 
    node_debug("read_object ~p ~p timeout", [Node, Key]),
    %% Consider timeouts as failures for now.
    false;
node_postcondition({_DatabaseState, _ClientState}, {call, ?MODULE, induce_byzantine_bit_flip_fault, [Node, Key, Value]}, ok) -> 
    node_debug("induce_byzantine_bit_flip_fault: ~p ~p ~p", [Node, Key, Value]),
    true;
node_postcondition({_DatabaseState, _ClientState}, {call, ?MODULE, induce_byzantine_disk_loss_fault, [Node, Key]}, ok) -> 
    node_debug("induce_byzantine_disk_loss_fault: ~p ~p", [Node, Key]),
    true;
node_postcondition({_DatabaseState, _ClientState}, {call, ?MODULE, write_object, [_Node, _Key, _Value]}, {ok, _Value}) -> 
    node_debug("write_object returned ok", []),
    %% Only pass acknowledged writes.
    true;
node_postcondition({_DatabaseState, _ClientState}, {call, ?MODULE, write_object, [Node, Key, _Value]}, {error, timeout}) -> 
    node_debug("write_object ~p ~p timeout", [Node, Key]),
    %% Consider timeouts as failures for now.
    false.


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

%% Precondition.
node_precondition({_DatabaseState, _ClientState}, {call, _Mod, induce_byzantine_disk_loss_fault, [_Node, _Key]}) -> 
    true;
node_precondition({_DatabaseState, _ClientState}, {call, _Mod, induce_byzantine_bit_flip_fault, [_Node, _Key, _Value]}) -> 
    true;
node_precondition({_DatabaseState, _ClientState}, {call, _Mod, read_object, [_Node, _Key]}) -> 
    true;
node_precondition({_DatabaseState, _ClientState}, {call, _Mod, write_object, [_Node, _Key, _Value]}) -> 
    true.

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% Should we do node debugging?
node_debug(Line, Args) ->
    case ?NODE_DEBUG of
        true ->
            lager:info(Line, Args);
        false ->
            ok
    end.

%% Determine if a read is monotonic or not?
is_monotonic_read(Key, not_found, ClientState) ->
    case dict:find(Key, ClientState) of
        {ok, {_LastReadTimestamp, _LastReadBinary} = LastReadValue} ->
            node_debug("got not_found, should have read ~p", [LastReadValue]),
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
            node_debug("last read ~p now read ~p, result ~p", [LastReadValue, ReadValue, Result]),
            Result;
        _ ->
            true
    end.

induce_byzantine_disk_loss_fault(Node, Key) ->
    rpc:call(?NAME(Node), ?APP, inject_failure, [Key, undefined]).

induce_byzantine_bit_flip_fault(Node, Key, Value) ->
    rpc:call(?NAME(Node), ?APP, inject_failure, [Key, Value]).

write_object(Node, Key, Value) ->
    node_debug("write_object: node ~p key ~p value ~p", [Node, Key, Value]),
    rpc:call(?NAME(Node), ?APP, fsm_put, [Key, Value]).

read_object(Node, Key) ->
    node_debug("read_object: node ~p key ~p", [Node, Key]),
    rpc:call(?NAME(Node), ?APP, fsm_get, [Key]).