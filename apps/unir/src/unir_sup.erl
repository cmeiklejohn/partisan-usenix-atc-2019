-module(unir_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init(_Args) ->
    VMaster = {unir_vnode_master,
               {riak_core_vnode_master, start_link, [unir_vnode]},
                permanent, 5000, worker, [riak_core_vnode_master]},

    PingFSM = {unir_ping_fsm_sup,
               {unir_ping_fsm_sup, start_link, []},
                permanent, infinity, supervisor, [unir_ping_fsm_sup]},

    {ok, {{one_for_one, 5, 10}, [VMaster, PingFSM]}}.