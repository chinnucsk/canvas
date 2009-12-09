-module(request_controller).
-author('Nicholas E. Ewing <nick@nickewing.net>').

-export([route_request/1, join/1, update/1, send_line/1, send_line_worker/2]).

-include("canvas.hrl").
-include("spatial.hrl").
-include_lib("eunit/include/eunit.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% External API
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

route_request(Req) ->
  "/" ++ Path = Req:get(path),
  case list_to_atom(Path) of
    Action when Action == join;
                Action == update;
                Action == send_line ->
      try ?MODULE:Action(Req) of
        Result ->
          io:format("Action ~w ~w~n", [Action, self()]),
          Req:ok({"text/plain", [], [Result]})
      catch
        Class:Exception ->
          error_logger:error_report([
            {Class, Exception},
            erlang:get_stacktrace()
          ]),
          Req:ok({"text/plain", [], ["ERROR Invalid request"]})
      end;
    _ ->
      no_route
  end.

%% Distribute lines to mailboxes and line store
send_line_worker(#line{points = P} = Line, SenderSID) ->
  %io:format("Got new line: ~p from ~s~n", [Line, SenderSID]),
  Box = spatial:points_box(P),
  To  = lists:keydelete(SenderSID, 1, client_manager:filter_by_box(Box)),
  %io:format("Sending to: ~p~n", [To]),
  % TODO: send line to linestore
  send_line_to_mailboxes(To, Line).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Internal API
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Actions

join(_Req) ->
  {sid, SID} = client_manager:join(),
  resp_ok(SID).

update(Req) ->
  {SID, QS} = parse_qs_sid(Req),
  Tiles     = parse_tiles(proplists:get_value("t", QS)),
  case fetch_updates(Tiles, SID) of
    Lines when is_list(Lines) ->
      resp_ok(lines_to_resp_str(Lines));
    cancel ->
      io:format("Responded with cancelled~n"),
      resp_ok();
    timeout ->
      resp_timeout()
  end.

send_line(Req) ->
  {SID, QS} = parse_qs_sid(Req),
  Line = add_line_user(Req, parse_line(proplists:get_value("l", QS))),
  spawn(?MODULE, send_line_worker, [Line, SID]),
  resp_ok().

fetch_updates(Tiles, SID) ->
  Box = box_tiles(Tiles),
  {CBox, Mailbox} = client_manager:fetch_sid(SID),
  case (Box == CBox) of
    true ->
      client_mailbox:subscribe(Mailbox),
      wait_for_lines(?line_wait_timeout);
    false ->
      io:format("Update sid ~s: ~p ~w~n", [SID, Box, Mailbox]),
      client_manager:update_sid(SID, Box, Mailbox),
      client_mailbox:empty_lines(Mailbox),
      client_mailbox:subscribe(Mailbox),
      %% TODO: fetch lines from linestore
      %% Lines = line_store:fecth_lines...
      wait_for_lines(?line_wait_timeout)
  end.

wait_for_lines(Timeout) ->
  receive
    {lines, Lines, FromMailbox} ->
      client_mailbox:empty_lines(FromMailbox),
      Lines;
    cancel ->
      cancel
  after Timeout ->
    timeout
  end.

%% Set user for line from request data
add_line_user(Req, L) ->
  L#line{user = Req:get(peer)}.

% Send a line to a list of mailboxes
send_line_to_mailboxes([], _Line) ->
  ok;
send_line_to_mailboxes([{_SID, Mailbox}|T], Line) ->
  %io:format("Sending ~p to ~w~n", [Line, Mailbox]),
  client_mailbox:send_line(Mailbox, Line),
  send_line_to_mailboxes(T, Line).


tiles_boxes(Tiles) ->
  lists:map(fun(#tile{box = B}) -> B end, Tiles).

box_tiles(Tiles) ->
  spatial:boxes_box(tiles_boxes(Tiles)).



%% Responses

resp_ok() ->
  io:format("Result ~w OK~n", [self()]),
  <<"OK">>.

resp_ok(Str) ->
  io:format("Result ~w OK ~s ~n", [self(), Str]),
  list_to_binary("OK " ++ Str).

resp_timeout() ->
  io:format("Result ~w TIMEOUT~n", [self()]),
  <<"TIMEOUT">>.



%% Request Parsing

parse_qs_sid(Req) ->
  QS  = Req:parse_qs(),
  SID = proplists:get_value("sid", QS),
  {SID, QS}.

%% parse tiles from tile request string.  Example tile str:
%% 123,1234,3341,3412/123423334;4244,452,4523,45234/123412333
parse_tiles(Str) ->
  lists:map(fun parse_tile/1, string:tokens(Str, ";")).

%% parse a #tile from a string
parse_tile(Str) ->
  [PointStr, TimeStr] = string:tokens(Str, "/"),
  [X, Y, X1, Y1]      = parse_points(PointStr),
  Time                = util:str_to_num(TimeStr),
  #tile{box = #box{x = X, y = Y, x1 = X1, y1 = Y1}, time = Time}.

%% parse points from string in the form of "132,412,34123,413"
parse_points(Str) ->
  PointStrs = string:tokens(Str, ","),
  Points = lists:map(fun util:str_to_num/1, PointStrs),
  if
    length(Points) rem 2 == 0 ->
      Points;
    true ->
      erlang:error(badarg)
  end.

%% parse a #line from a string in the format of "24,543,3242,545/DF992A/3"
parse_line(Str) ->
  [PointStr, ColorStr, SizeStr] = string:tokens(Str, "/"),
  Color   = util:str_to_num(ColorStr),
  Size    = util:str_to_num(SizeStr),
  Points  = parse_points(PointStr),
  #line{points = Points, color = Color, size = Size}.


%% Response Building

lines_to_resp_str(Lines) ->
  string:join(lists:map(fun line_to_resp_str/1, Lines), ";").

line_to_resp_str(#line{points = P, size = S, color = C}) ->
  string:join([
    points_to_resp_str(P),
    util:num_to_str(C),
    util:num_to_str(S)
  ], "/").

points_to_resp_str(Points)
    when (length(Points) > 0) and (length(Points) rem 2 == 0) ->
  string:join(lists:map(fun util:num_to_str/1, Points), ",").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Tests
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% FIXME: Incomplete tests


parse_points_test() ->
  [
    ?assertError(badarg, parse_points("abc")),
    ?assertError(badarg, parse_points("234,abc,23")),
    ?assertError(badarg, parse_points("132,412,34123")),
    ?assertEqual([132,412,34123,413], parse_points("132,412,34123,413")),
    ?assertEqual([23.4,234.5,453.4,34.3], parse_points("23.4,234.5,453.4,34.3"))
  ].

parse_line_test() ->
  [
    ?assertEqual(
      #line{points = [24,543,3242,545], size = 3, color = 14653738},
      parse_points("24,543,3242,545/14653738/3")
    )
  ].

line_to_resp_str_test() ->
  [
    ?assertError(function_clause,
      line_to_resp_str(
        #line{points = [24,543,3242], size = 3, color = 14653738}
      )
    ),
    ?assertEqual(
      "24,543,3242,545/14653738/3",
      line_to_resp_str(
        #line{points = [24,543,3242,545], size = 3, color = 14653738}
      )
    )
  ].

points_to_resp_str_test() ->
  [
    ?assertError(function_clause, points_to_resp_str([1,2,3])),
    ?assertEqual("1,2,3,4", points_to_resp_str([1,2,3,4])),
    ?assertEqual("1.2,2.43,3.9,4", points_to_resp_str([1.2,2.43,3.9,4]))
  ].