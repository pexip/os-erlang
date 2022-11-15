%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1997-2021. All Rights Reserved.
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
-module(win32reg_SUITE).

-export([all/0, suite/0,groups/0,init_per_suite/1, end_per_suite/1, 
	 init_per_group/2,end_per_group/2,long/1,evil_write/1,
         read_write_default_1/1,read_write_default_2/1,
         delete_key/1, up_and_away/1]).

-include_lib("common_test/include/ct.hrl").

suite() ->
    [{ct_hooks,[ts_install_cth]},
     {timetrap,{seconds,10}}].

all() -> 
    [long,
     evil_write,
     read_write_default_1,
     read_write_default_2,
     delete_key,
     up_and_away].

groups() -> 
    [].

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, Config) ->
    Config.


init_per_suite(Config) when is_list(Config) ->
    case os:type() of
	{win32, _} ->
	    Config;
	_ ->
	    {skip,"Doesn't run on UNIX."}
    end.
end_per_suite(Config) when is_list(Config) ->
    Config.

%% Test long keys and entries (OTP-3446).
long(Config) when is_list(Config) ->
    LongKey = "software\\" ++
	lists:flatten(lists:duplicate(10, "..\\software\\")) ++
	"Ericsson\\Erlang",
    {ok,Read} = win32reg:open([read]),
    ok = win32reg:change_key(Read, "\\hklm"),

    case os:getenv("WSLENV") of
        false ->
            ok = win32reg:change_key(Read, LongKey),
            {ok,ErlangKey} = win32reg:current_key(Read),
            io:format("Erlang key: ~s~n", [ErlangKey]),
            ok = win32reg:close(Read),

            {ok,Reg} = win32reg:open([read, write]),
            %% Write a long value and read it back.
            TestKey = "test_key",
            LongValue = lists:concat(["This is a long value generated by the test case ",?MODULE,":long/1. "|lists:duplicate(128, "a")]),
            ok = win32reg:set_value(Reg, TestKey, LongValue),
            {ok,LongValue} = win32reg:value(Reg, TestKey),

            io:format("Where ~p Key ~s Value ~s ~n", [win32reg:current_key(Reg), TestKey, LongValue]),
            %% Done.
            ok = win32reg:close(Reg);
        _ ->
            %% We have installed erlang when testing on win10 and newer
            ok
    end.

evil_write(Config) when is_list(Config) ->
    Key = "Software\\Ericsson\\Erlang",
    {ok,Reg} = win32reg:open([read,write]),
    ok = win32reg:change_key(Reg, "\\hkcu"),
    ok = win32reg:change_key_create(Reg, Key),
    {ok,ErlangKey} = win32reg:current_key(Reg),
    io:format("Erlang key: ~s", [ErlangKey]),

    %% Write keys with different length and read it back.
    TestKey = "test_key " ++ lists:duplicate(128, $a),
    evil_write_1(Reg, TestKey),

    %% Done.
    ok = win32reg:close(Reg),
    ok.

evil_write_1(Reg, [_|[_|_]=Key]=Key0) ->
    io:format("Key = ~p\n", [Key0]),
    ok = win32reg:set_value(Reg, Key0, "A good value for me"),
    {ok,_Val} = win32reg:value(Reg, Key0),
    ok = win32reg:delete_value(Reg, Key0),
    evil_write_1(Reg, Key);
evil_write_1(_, [_]) -> ok.

read_write_default_1(Config) when is_list(Config) ->
    Key = "Software\\Ericsson\\Erlang",
    Value = "The default value 1",
    {ok,Reg} = win32reg:open([read,write]),
    ok = win32reg:change_key(Reg, "\\hkcu"),
    ok = win32reg:change_key_create(Reg, Key),
    ok = win32reg:set_value(Reg, default, Value),
    {ok,Value} = win32reg:value(Reg, default),
    ok = win32reg:delete_value(Reg, default),
    {error,enoent} = win32reg:value(Reg, default),
    ok = win32reg:close(Reg),
    ok.

read_write_default_2(Config) when is_list(Config) ->
    Key = "Software\\Ericsson\\Erlang",
    Value = "The default value 2",
    {ok,Reg} = win32reg:open([read,write]),
    ok = win32reg:change_key(Reg, "\\hkcu"),
    ok = win32reg:change_key_create(Reg, Key),
    ok = win32reg:set_value(Reg, "", Value),
    {ok,Value} = win32reg:value(Reg, ""),
    ok = win32reg:delete_value(Reg, ""),
    {error,enoent} = win32reg:value(Reg, ""),
    ok = win32reg:close(Reg),
    ok.

delete_key(Config) when is_list(Config) ->
    Key = "Software\\Ericsson\\Erlang\\new-test-key",
    {ok,Reg} = win32reg:open([read,write]),
    ok = win32reg:change_key(Reg, "\\hkcu"),
    ok = win32reg:change_key_create(Reg, Key),
    {ok, []} = win32reg:sub_keys(Reg),
    ok = win32reg:delete_key(Reg),
    ok = win32reg:close(Reg),
    ok.

up_and_away(Config) when is_list(Config) ->
    {ok,Reg} = win32reg:open([read]),
    {ok, "\\hkey_classes_root"} = win32reg:current_key(Reg),
    {error,enoent} = win32reg:change_key(Reg, ".."),
    ok = win32reg:close(Reg),
    ok.
