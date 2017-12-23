-module(unir).
-include_lib("riak_core/include/riak_core_vnode.hrl").

-export([
         ping/0,
         sync_ping/0,
         sync_spawn_ping/0,
         fsm_ping/0
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

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @doc Generate a request id.
mk_reqid() ->
    erlang:phash2(erlang:now()).

%% @doc Wait for a response.
wait_for_reqid(ReqID, Timeout) ->
    receive
        {ReqID, ok} ->
            ok;
        {ReqID, ok, Val} ->
            {ok, Val}
    after Timeout ->
        {error, timeout}
    end.