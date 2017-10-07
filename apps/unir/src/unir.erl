-module(unir).
-include_lib("riak_core/include/riak_core_vnode.hrl").

-export([
         ping/0,
         sync_ping/0,
         sync_spawn_ping/0
        ]).

-ignore_xref([
              ping/0,
              sync_ping/0,
              sync_spawn_ping/0
             ]).

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