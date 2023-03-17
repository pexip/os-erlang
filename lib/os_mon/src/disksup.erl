%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 1996-2022. All Rights Reserved.
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
-module(disksup).
-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([get_disk_data/0,
	 get_check_interval/0, set_check_interval/1,
	 get_almost_full_threshold/0, set_almost_full_threshold/1]).
-export([dummy_reply/1, param_type/2, param_default/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2]).

%% Other exports
-export([format_status/2, parse_df/2]).

-record(state, {threshold, timeout, os, diskdata = [],port}).

%%----------------------------------------------------------------------
%% API
%%----------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, disksup}, disksup, [], []).

get_disk_data() ->
    os_mon:call(disksup, get_disk_data, infinity).

get_check_interval() ->
    os_mon:call(disksup, get_check_interval, infinity).
set_check_interval(Value) ->
    case param_type(disk_space_check_interval, Value) of
        true ->
            os_mon:call(disksup, {set_check_interval, Value}, infinity);
        false ->
            erlang:error(badarg)
    end.

get_almost_full_threshold() ->
    os_mon:call(disksup, get_almost_full_threshold, infinity).
set_almost_full_threshold(Float) ->
    case param_type(disk_almost_full_threshold, Float) of
	true ->
	    os_mon:call(disksup, {set_almost_full_threshold, Float}, infinity);
	false ->
	    erlang:error(badarg)
    end.

dummy_reply(get_disk_data) ->
    [{"none", 0, 0}];
dummy_reply(get_check_interval) ->
    case os_mon:get_env(disksup, disk_space_check_interval) of
        {TimeUnit, Time} ->
            erlang:convert_time_unit(Time, TimeUnit, millisecond);
        Minute ->
            minutes_to_ms(Minute)
    end;
dummy_reply({set_check_interval, _}) ->
    ok;
dummy_reply(get_almost_full_threshold) ->
    round(os_mon:get_env(disksup, disk_almost_full_threshold) * 100);
dummy_reply({set_almost_full_threshold, _}) ->
    ok.

param_type(disk_space_check_interval, {TimeUnit, Time}) ->
    try erlang:convert_time_unit(Time, TimeUnit, millisecond) of
        MsTime when MsTime > 0 -> true;
        _ -> false
    catch
        _:_ -> false
    end;
param_type(disk_space_check_interval, Val) when is_integer(Val),
						Val>=1 -> true;
param_type(disk_almost_full_threshold, Val) when is_number(Val),
						 0=<Val,
						 Val=<1 -> true;
param_type(disksup_posix_only, Val) when Val==true; Val==false -> true;
param_type(_Param, _Val) -> false.

param_default(disk_space_check_interval) -> 30;
param_default(disk_almost_full_threshold) -> 0.80;
param_default(disksup_posix_only) -> false.

%%----------------------------------------------------------------------
%% gen_server callbacks
%%----------------------------------------------------------------------

init([]) ->  
    process_flag(trap_exit, true),
    process_flag(priority, low),

    PosixOnly = os_mon:get_env(disksup, disksup_posix_only),
    OS = get_os(PosixOnly),
    Port = case OS of
		{unix, Flavor} when Flavor==sunos4;
				    Flavor==solaris;
				    Flavor==freebsd;
				    Flavor==dragonfly;
				    Flavor==darwin;
				    Flavor==linux;
				    Flavor==posix;
				    Flavor==openbsd;
				    Flavor==netbsd;
				    Flavor==irix64;
				    Flavor==irix ->
		   start_portprogram();
	       {win32, _OSname} ->
		   not_used;
	       _ ->
		   exit({unsupported_os, OS})
	   end,

    %% Read the values of some configuration parameters
    Threshold = os_mon:get_env(disksup, disk_almost_full_threshold),
    Timeout = case os_mon:get_env(disksup, disk_space_check_interval) of
                  {TimeUnit, Time} ->
                      erlang:convert_time_unit(Time, TimeUnit, millisecond);
                  Minutes ->
                      minutes_to_ms(Minutes)
              end,

    %% Initiation first disk check
    self() ! timeout,

    {ok, #state{port=Port, os=OS,
		threshold=round(Threshold*100),
		timeout=Timeout}}.

handle_call(get_disk_data, _From, State) ->
    {reply, State#state.diskdata, State};

handle_call(get_check_interval, _From, State) ->
    {reply, State#state.timeout, State};
handle_call({set_check_interval, {TimeUnit, Time}}, _From, State) ->
    Timeout = erlang:convert_time_unit(Time, TimeUnit, millisecond),
    {reply, ok, State#state{timeout=Timeout}};
handle_call({set_check_interval, Minutes}, _From, State) ->
    Timeout = minutes_to_ms(Minutes),
    {reply, ok, State#state{timeout=Timeout}};

handle_call(get_almost_full_threshold, _From, State) ->
    {reply, State#state.threshold, State};
handle_call({set_almost_full_threshold, Float}, _From, State) ->
    Threshold = round(Float * 100),
    {reply, ok, State#state{threshold=Threshold}};

handle_call({set_threshold, Threshold}, _From, State) -> % test only
    {reply, ok, State#state{threshold=Threshold}}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(timeout, State) ->
    NewDiskData = check_disk_space(State#state.os, State#state.port,
				   State#state.threshold),
    {ok, _Tref} = timer:send_after(State#state.timeout, timeout),
    {noreply, State#state{diskdata = NewDiskData}};
handle_info({'EXIT', _Port, Reason}, State) ->
    {stop, {port_died, Reason}, State#state{port=not_used}};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    clear_alarms(),
    case State#state.port of
	not_used ->
	    ok;
	Port ->
	    port_close(Port)
    end,
    ok.

%%----------------------------------------------------------------------
%% Other exports
%%----------------------------------------------------------------------

format_status(_Opt, [_PDict, #state{os = OS, threshold = Threshold,
				    timeout = Timeout,
				    diskdata = DiskData}]) ->
    [{data, [{"OS", OS},
	     {"Timeout", Timeout},
	     {"Threshold", Threshold},
	     {"DiskData", DiskData}]}].

%%----------------------------------------------------------------------
%% Internal functions
%%----------------------------------------------------------------------

get_os(PosixOnly) ->
    case os:type() of
	{unix, sunos} ->
            case os:version() of
		{5,_,_} -> {unix, solaris};
		{4,_,_} -> {unix, sunos4};
		V -> exit({unknown_os_version, V})
            end;
	{unix, _} when PosixOnly ->
	    {unix, posix};
        {unix, irix64} -> {unix, irix};
	OS ->
	    OS
    end.

%%--Port handling functions---------------------------------------------

start_portprogram() -> 
    open_port({spawn, "sh -s disksup 2>&1"}, [stream]).

my_cmd(Cmd0, Port) ->
    %% Insert a new line after the command, in case the command
    %% contains a comment character
    Cmd = io_lib:format("(~s\n) </dev/null; echo  \"\^M\"\n", [Cmd0]),
    Port ! {self(), {command, [Cmd, 10]}},
    get_reply(Port, []).

get_reply(Port, O) ->
    receive 
        {Port, {data, N}} -> 
            case newline(N, O) of
                {ok, Str} -> Str;
                {more, Acc} -> get_reply(Port, Acc)
            end;
        {'EXIT', Port, Reason} ->
	    exit({port_died, Reason})
    end.

newline([13|_], B) -> {ok, lists:reverse(B)};
newline([H|T], B) -> newline(T, [H|B]);
newline([], B) -> {more, B}.

%%-- Looking for Cmd location ------------------------------------------
find_cmd(Cmd) ->
    os:find_executable(Cmd).

find_cmd(Cmd, Path) ->
    %% try to find it at the specific location
    case os:find_executable(Cmd, Path) of
        false ->
            find_cmd(Cmd);
        Found ->
            Found
    end.

%%--Check disk space----------------------------------------------------

%% We use as many absolute paths as possible below as there may be stale
%% NFS handles in the PATH which cause these commands to hang.
check_disk_space({win32,_}, not_used, Threshold) ->
    Result = os_mon_sysinfo:get_disk_info(),
    check_disks_win32(Result, Threshold);
check_disk_space({unix, solaris}, Port, Threshold) ->
    Result = my_cmd("/usr/bin/df -lk", Port),
    check_disks_solaris(skip_to_eol(Result), Threshold);
check_disk_space({unix, irix}, Port, Threshold) ->
    Result = my_cmd("/usr/sbin/df -lk",Port),
    check_disks_irix(skip_to_eol(Result), Threshold);
check_disk_space({unix, linux}, Port, Threshold) ->
    Df = find_cmd("df", "/bin"),
    Result = my_cmd(Df ++ " -lk -x squashfs", Port),
    check_disks_solaris(skip_to_eol(Result), Threshold);
check_disk_space({unix, posix}, Port, Threshold) ->
    Result = my_cmd("df -k -P", Port),
    check_disks_solaris(skip_to_eol(Result), Threshold);
check_disk_space({unix, dragonfly}, Port, Threshold) ->
    Result = my_cmd("/bin/df -k -t ufs,hammer", Port),
    check_disks_solaris(skip_to_eol(Result), Threshold);
check_disk_space({unix, freebsd}, Port, Threshold) ->
    Result = my_cmd("/bin/df -k -l", Port),
    check_disks_solaris(skip_to_eol(Result), Threshold);
check_disk_space({unix, openbsd}, Port, Threshold) ->
    Result = my_cmd("/bin/df -k -l", Port),
    check_disks_solaris(skip_to_eol(Result), Threshold);
check_disk_space({unix, netbsd}, Port, Threshold) ->
    Result = my_cmd("/bin/df -k -t ffs", Port),
    check_disks_solaris(skip_to_eol(Result), Threshold);
check_disk_space({unix, sunos4}, Port, Threshold) ->
    Result = my_cmd("df", Port),
    check_disks_solaris(skip_to_eol(Result), Threshold);
check_disk_space({unix, darwin}, Port, Threshold) ->
    Result = my_cmd("/bin/df -i -k -t ufs,hfs,apfs", Port),
    check_disks_susv3(skip_to_eol(Result), Threshold).

% This code works for Linux and FreeBSD as well
check_disks_solaris("", _Threshold) ->
    [];
check_disks_solaris("\n", _Threshold) ->
    [];
check_disks_solaris(Str, Threshold) ->
    case parse_df(Str, posix) of
	{ok, {KB, Cap, MntOn}, RestStr} ->
	    if
		Cap >= Threshold ->
		    set_alarm({disk_almost_full, MntOn}, []);
		true ->
		    clear_alarm({disk_almost_full, MntOn})
	    end,
	    [{MntOn, KB, Cap} |
	     check_disks_solaris(RestStr, Threshold)];
	_Other ->
	    check_disks_solaris(skip_to_eol(Str),Threshold)
    end.

%% @private
%% @doc Predicate to take a word from the input string until a space or
%% a percent '%' sign (the Capacity field is followed by a %)
parse_df_is_not_space($ ) -> false;
parse_df_is_not_space($%) -> false;
parse_df_is_not_space(_) -> true.

%% @private
%% @doc Predicate to take spaces away from string. Stops on a non-space
parse_df_is_space($ ) -> true;
parse_df_is_space(_) -> false.

%% @private
%% @doc Predicate to consume remaining characters until end of line.
parse_df_is_not_eol($\r) -> false;
parse_df_is_not_eol($\n) -> false;
parse_df_is_not_eol(_)   -> true.

%% @private
%% @doc Trims leading non-spaces (the word) from the string then trims spaces.
parse_df_skip_word(Input) ->
    Remaining = lists:dropwhile(fun parse_df_is_not_space/1, Input),
    lists:dropwhile(fun parse_df_is_space/1, Remaining).

%% @private
%% @doc Takes all non-spaces and then drops following spaces.
parse_df_take_word(Input) ->
    {Word, Remaining0} = lists:splitwith(fun parse_df_is_not_space/1, Input),
    Remaining1 = lists:dropwhile(fun parse_df_is_space/1, Remaining0),
    {Word, Remaining1}.

%% @private
%% @doc Takes all non-spaces and then drops the % after it and the spaces.
parse_df_take_word_percent(Input) ->
    {Word, Remaining0} = lists:splitwith(fun parse_df_is_not_space/1, Input),
    %% Drop the leading % or do nothing
    Remaining1 = case Remaining0 of
                     [$% | R1] -> R1;
                     _ -> Remaining0 % Might be no % or empty list even
                 end,
    Remaining2 = lists:dropwhile(fun parse_df_is_space/1, Remaining1),
    {Word, Remaining2}.

%% @private
%% @doc Given a line of 'df' POSIX/SUSv3 output split it into fields:
%% a string (mounted device), 4 integers (kilobytes, used, available
%% and capacity), skip % sign, (optionally for susv3 can also skip IUsed, IFree
%% and ICap% fields) then take remaining characters as the mount path
-spec parse_df(string(), posix | susv3) ->
    {error, parse_df} | {ok, {integer(), integer(), list()}, string()}.
parse_df(Input0, Flavor) ->
    %% Format of Posix/Linux df output looks like Header + Lines
    %% Filesystem     1024-blocks     Used Available Capacity Mounted on
    %% udev               2467108        0   2467108       0% /dev
    Input1 = parse_df_skip_word(Input0), % skip device path field
    {KbStr, Input2} = parse_df_take_word(Input1), % take Kb field
    Input3 = parse_df_skip_word(Input2), % skip Used field
    Input4 = parse_df_skip_word(Input3), % skip Avail field

    % take Capacity% field; drop a % sign following the capacity
    {CapacityStr, Input5} = parse_df_take_word_percent(Input4),

    %% Format of OS X/SUSv3 df looks similar to POSIX but has 3 extra columns
    %% Filesystem 1024-blocks Used Available Capacity iused ifree %iused Mounted
    %% /dev/disk1   243949060 2380  86690680    65% 2029724 37555    0%  /
    Input6 = case Flavor of
                 posix -> Input5;
                 susv3 -> % there are 3 extra integers we want to skip
                     Input5a = parse_df_skip_word(Input5), % skip IUsed field
                     Input5b = parse_df_skip_word(Input5a), % skip IFree field
                     %% skip the value of ICap + '%' field
                     {_, Input5c} = parse_df_take_word_percent(Input5b),
                     Input5c
             end,

    % path is the remaining string till end of line
    {MountPath, Input7} = lists:splitwith(fun parse_df_is_not_eol/1, Input6),
    % Trim the newlines
    Remaining = lists:dropwhile(fun(X) -> not parse_df_is_not_eol(X) end,
                                Input7),
    try
        Kb = erlang:list_to_integer(KbStr),
        Capacity = erlang:list_to_integer(CapacityStr),
        {ok, {Kb, Capacity, MountPath}, Remaining}
    catch error:badarg ->
        {error, parse_df}
    end.

% Parse per SUSv3 specification, notably recent OS X
check_disks_susv3("", _Threshold) ->
    [];
check_disks_susv3("\n", _Threshold) ->
    [];
check_disks_susv3(Str, Threshold) ->
    case parse_df(Str, susv3) of
    {ok, {KB, Cap, MntOn}, RestStr} ->
	    if
		Cap >= Threshold ->
		    set_alarm({disk_almost_full, MntOn}, []);
		true ->
		    clear_alarm({disk_almost_full, MntOn})
	    end,
	    [{MntOn, KB, Cap} |
	     check_disks_susv3(RestStr, Threshold)];
	_Other ->
	    check_disks_susv3(skip_to_eol(Str),Threshold)
    end.

%% Irix: like Linux with an extra FS type column and no '%'.
check_disks_irix("", _Threshold) -> [];
check_disks_irix("\n", _Threshold) -> [];
check_disks_irix(Str, Threshold) ->
    case io_lib:fread("~s~s~d~d~d~d~s", Str) of
	{ok, [_FS, _FSType, KB, _Used, _Avail, Cap, MntOn], RestStr} ->
	    if Cap >= Threshold -> set_alarm({disk_almost_full, MntOn}, []);
	       true             -> clear_alarm({disk_almost_full, MntOn}) end,
	    [{MntOn, KB, Cap} | check_disks_irix(RestStr, Threshold)];
	_Other ->
	    check_disks_irix(skip_to_eol(Str),Threshold)
    end.

check_disks_win32([], _Threshold) ->
    [];
check_disks_win32([H|T], Threshold) ->
    case io_lib:fread("~s~s~d~d~d", H) of
	{ok, [Drive,"DRIVE_FIXED",BAvail,BTot,_TotFree], _RestStr} ->
	    Cap = trunc((BTot-BAvail) / BTot * 100),
	    if
		 Cap >= Threshold ->
		    set_alarm({disk_almost_full, Drive}, []);
		true ->
		    clear_alarm({disk_almost_full, Drive})
	    end,
	    [{Drive, BTot div 1024, Cap} |
	     check_disks_win32(T, Threshold)]; % Return Total Capacity in Kbytes
	{ok,_,_RestStr} ->
	    check_disks_win32(T,Threshold);
	_Other ->
	    []
    end.

%%--Alarm handling------------------------------------------------------

set_alarm(AlarmId, AlarmDescr) ->
    case get(AlarmId) of
	set ->
	    ok;
	undefined ->
	    alarm_handler:set_alarm({AlarmId, AlarmDescr}),
	    put(AlarmId, set)
    end.

clear_alarm(AlarmId) ->
    case get(AlarmId) of
	set ->
	    alarm_handler:clear_alarm(AlarmId),
	    erase(AlarmId);
	undefined ->
	    ok
    end.

clear_alarms() ->
    lists:foreach(fun({{disk_almost_full, _MntOn} = AlarmId, set}) ->
			  alarm_handler:clear_alarm(AlarmId);
		     (_Other) ->
			  ignore
		  end,
		  get()).

%%--Auxiliary-----------------------------------------------------------

%% Type conversion
minutes_to_ms(Minutes) ->
    trunc(60000*Minutes).

skip_to_eol([]) ->
    [];
skip_to_eol([$\n | T]) ->
    T;
skip_to_eol([_ | T]) ->
    skip_to_eol(T).
