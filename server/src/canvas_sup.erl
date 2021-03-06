%% @author Nick Ewing <nick@nickewing.net>
%% @copyright 2009 Nick Ewing.

%% @doc Supervisor for the canvas server application.

-module(canvas_sup).
-author('Nicholas E. Ewing <nick@nickewing.net>').

-behaviour(supervisor).

-export([
  %% External exports
  start_link/0, upgrade/0,
  %% supervisor callbacks
  init/1
]).

-include("canvas.hrl").

%% @spec start_link() -> ServerRet
%% @doc API for starting the supervisor.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @spec upgrade() -> ok
%% @doc Add processes if necessary.
upgrade() ->
    {ok, {_, Specs}} = init([]),

    Old = sets:from_list(
            [Name || {Name, _, _, _} <- supervisor:which_children(?MODULE)]),
    New = sets:from_list([Name || {Name, _, _, _, _, _} <- Specs]),
    Kill = sets:subtract(Old, New),

    sets:fold(fun (Id, ok) ->
                supervisor:terminate_child(?MODULE, Id),
                supervisor:delete_child(?MODULE, Id),
                ok
              end, ok, Kill),

    [supervisor:start_child(?MODULE, Spec) || Spec <- Specs],
    ok.

%% @spec init([]) -> SupervisorTree
%% @doc supervisor callback.
init([]) ->
    Ip = case os:getenv("MOCHIWEB_IP") of false -> "0.0.0.0"; Any -> Any end,   
    WebConfig = [
      {ip, Ip},
      {port, ?server_port},
      {docroot, canvas_deps:local_path(["priv", "www"])}
    ],
    Web = {canvas_web,
           {canvas_web, start, [WebConfig]},
           permanent, 5000, worker, dynamic},

    Processes = [Web],
    {ok, {{one_for_one, 10, 10}, Processes}}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Tests
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Module was autogenerated by mochiweb framework.  Tests are provided in the
%% framework