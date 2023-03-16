%% 
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2014-2022. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%% 

%% 
%% The reason for this (test) counter server is that the 
%% agent test suite is implemented in such a way that the 
%% agent is started once and then used for several test cases.
%% Each request is given a request id which *was* generated using 
%% random! It is therefore possible, although unlikely, that a 
%% request may get a request id that has recently been used, 
%% which will cause the agent to silently reject the request.
%% For this reason, we start this server at the start of the
%% agent suite and stop it at the end and all request ids are 
%% generated by this server.
%% 

-module(snmp_test_mgr_counter_server).

-export([start/0, stop/0, increment/4]).

-define(SERVER, ?MODULE).
-define(TAB,    snmp_test_mgr_counter_tab).


%%%-------------------------------------------------------------------
%%% API
%%%-------------------------------------------------------------------

-spec start() -> ok.
    
start() ->
    Parent      = self(),
    ReqIdServer = spawn(fun() -> init(Parent) end),
    receive
	{ReqIdServer, ok} ->
	    ok;
	{ReqIdServer, {error, Reason}} ->
	    exit({failed_starting_counter_server, Reason})
    after 5000 ->
	    exit(ReqIdServer, kill), % Cleanup, just in case
	    exit({failed_starting_counter_server, timeout})
    end.

-spec stop() -> {ok, Counters :: list()} | {error, Reason :: term()}.
    
stop() ->
    request(stop).


-spec increment(Counter  :: atom(), 
	       Initial   :: non_neg_integer(), 
	       Increment :: pos_integer(), 
	       Max       :: pos_integer()) -> 
    Next :: pos_integer().

increment(Counter, Initial, Increment, Max) ->
    Request = {increment, Counter, Initial, Increment, Max}, 
    case request(Request) of
	{ok, ReqId} ->
	    ReqId;
	{error, Reason} ->
	    exit(Reason)
    end.


request(Request) ->
    Id  = make_ref(),
    Msg = {self(), Id, Request}, 
    try
	begin
	    global:send(?SERVER, Msg),
	    receive
		{reply, Id, Reply} ->
		    {ok, Reply}
	    end
	end
    catch
	T:E ->
	    {error, {T, E}}
    end.
		
    
%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

init(Parent) ->
    p("starting"),
    case global:register_name(?SERVER, self()) of
	yes ->
	    p("name registration ok"),
	    Parent ! {self(), ok};
	no ->
	    p("name registration failed"),
	    Parent ! {self(), registration_failed},
	    exit(registration_failed)
    end,
    ets:new(?TAB, [set, named_table, {keypos, 1}]),
    loop().

loop() ->
    receive
	{From, Id, {increment, Counter, Initial, Increment, Max}} ->
	    Position  = 2,
	    Threshold = Max,
	    SetValue  = Initial,
	    UpdateOp  = {Position, Increment, Threshold, SetValue},
	    NextVal = 
		try ets:update_counter(?TAB, Counter, UpdateOp) of
		    Next when is_integer(Next) ->
			p("increment ~w: (next) ~w", [Counter, Next]),
			Next
		catch
		    error:badarg ->
			%% Oups, first time
			p("increment ~w: (initial) ~w", [Counter, Initial]),
			ets:insert(?TAB, {Counter, Initial}),
			Initial
		end,
	    From ! {reply, Id, NextVal},
	    loop();

	{From, Id, stop} ->
	    p("stop"),
	    Counters = ets:tab2list(?TAB), 
	    From ! {reply, Id, Counters}, 
	    exit(normal)
    end.


p(F) ->
    p(F, []).

p(F, A) ->
    io:format("*** [~s] COUNTER-SERVER [~w] " ++ F ++ "~n", 
	      [snmp_test_lib:formated_timestamp(), self() | A]).
