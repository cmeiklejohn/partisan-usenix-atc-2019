%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Christopher Meiklejohn.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(unir_get_fsm).
-author('Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>').

-behaviour(gen_fsm).

%% API
-export([start_link/3,
         get/1]).

%% Callbacks
-export([init/1,
         code_change/4,
         handle_event/3,
         handle_info/3,
         handle_sync_event/4,
         terminate/3]).

%% States
-export([prepare/2,
         execute/2,
         waiting/2]).

-record(state, {preflist,
                req_id,
                coordinator,
                from,
                key,
                responses}).

-define(N, 3).
-define(W, 2).

%%%===================================================================
%%% API
%%%===================================================================

start_link(ReqId, From, Key) ->
    gen_fsm:start_link(?MODULE, [ReqId, From, Key], []).

%% @doc Join a pid to a group.
get(Key) ->
    ReqId = unir:mk_reqid(),
    _ = unir_get_fsm_sup:start_child([ReqId, self(), Key]),
    {ok, ReqId}.

%%%===================================================================
%%% Callbacks
%%%===================================================================

handle_info(_Info, _StateName, StateData) ->
    {stop, badmsg, StateData}.

handle_event(_Event, _StateName, StateData) ->
    {stop, badmsg, StateData}.

handle_sync_event(_Event, _From, _StateName, StateData) ->
    {stop, badmsg, StateData}.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

terminate(_Reason, _SN, _SD) ->
    ok.

%%%===================================================================
%%% States
%%%===================================================================

%% @doc Initialize the request.
init([ReqId, From, Key]) ->
    State = #state{preflist=undefined,
                   req_id=ReqId,
                   key=Key,
                   coordinator=node(),
                   from=From,
                   responses=0},
    {ok, prepare, State, 0}.

prepare(timeout, #state{key=Key}=State) ->
    DocIdx = riak_core_util:chash_key({<<"objects">>, term_to_binary(Key)}),
    Preflist = riak_core_apl:get_primary_apl(DocIdx, ?N, unir),
    Preflist2 = [{Index, Node} || {{Index, Node}, _Type} <- Preflist],
    {next_state, execute, State#state{preflist=Preflist2}, 0}.

execute(timeout, #state{preflist=Preflist,
                        req_id=ReqId,
                        key=Key,
                        coordinator=Coordinator}=State) ->
    unir_vnode:get(Preflist, {ReqId, Coordinator}, Key),
    {next_state, waiting, State}.

waiting({ok, ReqId, Value}, #state{responses=Responses0, from=From}=State0) ->
    Responses = Responses0 + 1,
    State = State0#state{responses=Responses},
    case Responses =:= ?W of
        true ->
            From ! {ReqId, ok, Value},
            {stop, normal, State};
        false ->
            {next_state, waiting, State}
    end.

%%%===================================================================
%%% Internal Functions
%%%===================================================================