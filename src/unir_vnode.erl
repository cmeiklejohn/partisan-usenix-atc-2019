-module(unir_vnode).
-author("Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>").

-behaviour(riak_core_vnode).

-export([start_vnode/1,
         init/1,
         ping/2,
         put/4,
         get/3,
         nuke/3,
         alter/4]).

-export([terminate/2,
         handle_command/3,
         is_empty/1,
         delete/1,
         handle_handoff_command/3,
         handoff_starting/2,
         handoff_cancelled/1,
         handoff_finished/2,
         handle_handoff_data/2,
         encode_handoff_item/2,
         handle_overload_command/3,
         handle_overload_info/2,
         handle_coverage/4,
         handle_exit/3]).

-ignore_xref([start_vnode/1]).

-record(state, {partition, store}).

-define(MASTER, unir_vnode_master).

%% API
start_vnode(I) ->
    riak_core_vnode_master:get_vnode_pid(I, ?MODULE).

init([Partition]) ->
    Store = dict:new(),
    {ok, #state {partition=Partition, store=Store}}.

put(Preflist, Identity, Key, Value) ->
    riak_core_vnode_master:command(Preflist,
                                   {put, Identity, Key, Value},
                                   {fsm, undefined, self()},
                                   ?MASTER).

get(Preflist, Identity, Key) ->
    riak_core_vnode_master:command(Preflist,
                                   {get, Identity, Key},
                                   {fsm, undefined, self()},
                                   ?MASTER).

nuke(Preflist, Identity, Key) ->
    riak_core_vnode_master:command(Preflist,
                                   {nuke, Identity, Key},
                                   {fsm, undefined, self()},
                                   ?MASTER).

alter(Preflist, Identity, Key, Value) ->
    riak_core_vnode_master:command(Preflist,
                                   {alter, Identity, Key, Value},
                                   {fsm, undefined, self()},
                                   ?MASTER).

ping(Preflist, Identity) ->
    riak_core_vnode_master:command(Preflist,
                                   {ping, Identity},
                                   {fsm, undefined, self()},
                                   ?MASTER).

handle_command({put, {ReqId, _}, Key, Value}, _Sender, #state{store=Store0}=State) ->
    %% Sleep for 10ms, read 1MB from disk.
    %% https://gist.github.com/jboner/2841832
    timer:sleep(10),
    Store = dict:store(Key, Value, Store0),
    {reply, {ok, ReqId, Value}, State#state{store=Store}};
handle_command({nuke, {ReqId, _}, Key}, _Sender, #state{store=Store0}=State) ->
    Store = dict:erase(Key, Store0),
    {reply, {ok, ReqId}, State#state{store=Store}};
handle_command({alter, {ReqId, _}, Key, Value}, _Sender, #state{store=Store0}=State) ->
    Store = case dict:find(Key, Store0) of
        {ok, Value} ->
            dict:store(Key, Value, Store0);
        error ->
            Store0
    end,
    {reply, {ok, ReqId}, State#state{store=Store}};
handle_command({get, {ReqId, _}, Key}, _Sender, #state{store=Store}=State) ->
    %% Sleep for 10ms, read 1MB from disk.
    %% https://gist.github.com/jboner/2841832
    timer:sleep(10),
    Value = case dict:find(Key, Store) of
        {ok, V} ->
            V;
        error ->
            not_found
    end,
    {reply, {ok, ReqId, Value}, State};
handle_command({ping, {ReqId, _}}, _Sender, State) ->
    {reply, {ok, ReqId}, State};
handle_command({echo, EchoBinary, FromNode, FromPid}, _Sender, State) ->
    riak_core_partisan_utils:forward(vnode, FromNode, FromPid, {echo, EchoBinary}),
    {reply, ok, State};
handle_command(ping, _Sender, State) ->
    {reply, {pong, State#state.partition}, State};
handle_command(Message, _Sender, State) ->
    lager:warning("unhandled_command ~p", [Message]),
    {noreply, State}.

handle_overload_command(_, _, _) ->
    ok.

handle_overload_info(_, _) ->
    ok.

handle_handoff_command(_Message, _Sender, State) ->
    {noreply, State}.

handoff_starting(_TargetNode, State) ->
    {true, State}.

handoff_cancelled(State) ->
    {ok, State}.

handoff_finished(_TargetNode, State) ->
    {ok, State}.

handle_handoff_data(_Data, State) ->
    {reply, ok, State}.

encode_handoff_item(_ObjectName, _ObjectValue) ->
    <<>>.

is_empty(State) ->
    {true, State}.

delete(State) ->
    {ok, State}.

handle_coverage(_Req, _KeySpaces, _Sender, State) ->
    {stop, not_implemented, State}.

handle_exit(_Pid, _Reason, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.