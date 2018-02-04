-module(unir).
-author("Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>").

-include_lib("riak_core/include/riak_core_vnode.hrl").

-export([
         ping/0,
         sync_ping/0,
         sync_spawn_ping/0,
         fsm_ping/0,
         fsm_get/1,
         fsm_put/2,
         echo/0,
         echo/1
        ]).

-ignore_xref([
              ping/0,
              sync_ping/0,
              sync_spawn_ping/0
             ]).

-export([mk_reqid/0,
         wait_for_reqid/2]).

-define(TIMEOUT, 10000).

%% Public API

%% @doc Pings a random vnode to make sure communication is functional
ping() ->
    DocIdx = riak_core_util:chash_key({<<"ping">>, term_to_binary(os:timestamp())}),
    PrefList = riak_core_apl:get_primary_apl(DocIdx, 1, unir),
    [{IndexNode, _Type}] = PrefList,
    riak_core_vnode_master:command(IndexNode, ping, unir_vnode_master).

%% @doc Pings a random vnode to make sure communication is functional
sync_ping() ->
    DocIdx = riak_core_util:chash_key({<<"ping">>, term_to_binary(os:timestamp())}),
    PrefList = riak_core_apl:get_primary_apl(DocIdx, 1, unir),
    [{IndexNode, _Type}] = PrefList,
    riak_core_vnode_master:sync_command(IndexNode, ping, unir_vnode_master).

%% @doc Perform an echo request.
echo() ->
    EchoBinary = partisan_config:get(echo_binary, undefined),
    echo(EchoBinary).

%% @doc Perform an echo request.
echo(EchoBinary) ->
    DocIdx = riak_core_util:chash_key({<<"echo">>, term_to_binary(rand:uniform(1024))}),
    PrefList = riak_core_apl:get_primary_apl(DocIdx, 1, unir),
    [{IndexNode, _Type}] = PrefList,
    ok = riak_core_vnode_master:command(IndexNode, {echo, EchoBinary, node(), self()}, unir_vnode_master),
    receive
        {echo, EchoBinary} ->
            ok
    end,
    ok.

%% @doc Pings a random vnode to make sure communication is functional
sync_spawn_ping() ->
    DocIdx = riak_core_util:chash_key({<<"ping">>, term_to_binary(os:timestamp())}),
    PrefList = riak_core_apl:get_primary_apl(DocIdx, 1, unir),
    [{IndexNode, _Type}] = PrefList,
    riak_core_vnode_master:sync_spawn_command(IndexNode, ping, unir_vnode_master).

%% @doc Pings a random vnode to make sure communication is functional
fsm_ping() ->
    {ok, ReqId} = unir_ping_fsm:ping(),
    wait_for_reqid(ReqId, ?TIMEOUT).

%% @doc Make a request through the put FSM.
fsm_put(Key, Value) ->
    {ok, ReqId} = unir_put_fsm:put(Key, Value),
    wait_for_reqid(ReqId, ?TIMEOUT).

%% @doc Make a request through the get FSM.
fsm_get(Key) ->
    {ok, ReqId} = unir_get_fsm:get(Key),
    wait_for_reqid(ReqId, ?TIMEOUT).

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @doc Generate a request id.
mk_reqid() ->
    erlang:phash2(erlang:now()).

%% @doc Wait for a response.
wait_for_reqid(ReqID, _Timeout) ->
    receive
        {ReqID, ok} ->
            ok;
        {ReqID, ok, Val} ->
            {ok, Val}
    end.