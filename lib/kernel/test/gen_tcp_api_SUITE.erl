%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 1998-2020. All Rights Reserved.
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
-module(gen_tcp_api_SUITE).

%% Tests the documented API for the gen_tcp functions.  The "normal" cases
%% are not tested here, because they are tested indirectly in this and
%% and other test suites.

-include_lib("common_test/include/ct.hrl").
-include_lib("kernel/include/inet.hrl").
-include("kernel_test_lib.hrl").

-export([
	 all/0, suite/0, groups/0,
	 init_per_suite/1, end_per_suite/1, 
	 init_per_group/2,end_per_group/2, 
	 init_per_testcase/2, end_per_testcase/2,

	 t_connect_timeout/1, t_accept_timeout/1,
	 t_connect_bad/1,
	 t_recv_timeout/1, t_recv_eof/1, t_recv_delim/1,
	 t_shutdown_write/1, t_shutdown_both/1, t_shutdown_error/1,
	 t_shutdown_async/1,
	 t_fdopen/1, t_fdconnect/1, t_implicit_inet6/1,
	 t_local_basic/1, t_local_unbound/1, t_local_fdopen/1,
	 t_local_fdopen_listen/1, t_local_fdopen_listen_unbound/1,
	 t_local_fdopen_connect/1, t_local_fdopen_connect_unbound/1,
	 t_local_abstract/1, t_accept_inet6_tclass/1,
	 s_accept_with_explicit_socket_backend/1
	]).

-export([getsockfd/0, closesockfd/1]).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

suite() ->
    [
     {ct_hooks,[ts_install_cth]},
     {timetrap,{minutes,1}}
    ].

all() ->
    %% This is a temporary messure to ensure that we can 
    %% test the socket backend without effecting *all*
    %% applications on *all* machines.
    %% This flag is set only for *one* host.
    case ?TEST_INET_BACKENDS() of
        true ->
            [
             {group, inet_backend_default},
             {group, inet_backend_inet},
             {group, inet_backend_socket},
             {group, s_misc}
            ];
        _ ->
            [
             {group, inet_backend_default},
             {group, s_misc}
            ]
    end.

groups() -> 
    [
     {inet_backend_default, [], inet_backend_default_cases()},
     {inet_backend_inet,    [], inet_backend_inet_cases()},
     {inet_backend_socket,  [], inet_backend_socket_cases()},
     {t_accept,             [], t_accept_cases()},
     {t_connect,            [], t_connect_cases()},
     {t_recv,               [], t_recv_cases()},
     {t_shutdown,           [], t_shutdown_cases()},
     {t_misc,               [], t_misc_cases()},
     {t_local,              [], t_local_cases()},
     {s_misc,               [], s_misc_cases()}
    ].

inet_backend_default_cases() ->
    [
     {group, t_accept},
     {group, t_connect},
     {group, t_recv},
     {group, t_shutdown},
     {group, t_misc},
     {group, t_local}
    ].

inet_backend_inet_cases() ->
    inet_backend_default_cases().

inet_backend_socket_cases() ->
    inet_backend_default_cases().

t_accept_cases() ->
    [
     t_accept_timeout
    ].

t_connect_cases() ->
    [
     t_connect_timeout,
     t_connect_bad
    ].

t_recv_cases() ->
    [
     t_recv_timeout,
     t_recv_eof,
     t_recv_delim
    ].

t_shutdown_cases() ->
    [
     t_shutdown_write,
     t_shutdown_both,
     t_shutdown_error,
     t_shutdown_async
    ].

t_misc_cases() ->
    [
     t_fdopen,
     t_fdconnect,
     t_implicit_inet6,
     t_accept_inet6_tclass
    ].

t_local_cases() ->
    [
     t_local_basic,
     t_local_unbound,
     t_local_fdopen,
     t_local_fdopen_listen,
     t_local_fdopen_listen_unbound,
     t_local_fdopen_connect,
     t_local_fdopen_connect_unbound,
     t_local_abstract
    ].

s_misc_cases() ->
    [
     s_accept_with_explicit_socket_backend
    ].

init_per_suite(Config0) ->

    ?P("init_per_suite -> entry with"
       "~n      Config: ~p"
       "~n      Nodes:  ~p", [Config0, erlang:nodes()]),

    case ?LIB:init_per_suite(Config0) of
        {skip, _} = SKIP ->
            SKIP;

        Config1 when is_list(Config1) ->

            ?P("init_per_suite -> end when "
               "~n      Config: ~p", [Config1]),
            
            Config1
    end.


end_per_suite(Config0) ->

    ?P("end_per_suite -> entry with"
       "~n      Config: ~p"
       "~n      Nodes:  ~p", [Config0, erlang:nodes()]),

    Config1 = ?LIB:end_per_suite(Config0),

    ?P("end_per_suite -> "
            "~n      Nodes: ~p", [erlang:nodes()]),

    Config1.


init_per_group(inet_backend_default = _GroupName, Config) ->
    [{socket_create_opts, []} | Config];
init_per_group(inet_backend_inet = _GroupName, Config) ->
    case ?EXPLICIT_INET_BACKEND() of
        true ->
            %% The environment trumps us,
            %% so only the default group should be run!
            {skip, "explicit inet backend"};
        false ->
            [{socket_create_opts, [{inet_backend, inet}]} | Config]
    end;
init_per_group(inet_backend_socket = _GroupName, Config) ->
    case ?EXPLICIT_INET_BACKEND() of
        true ->
            %% The environment trumps us,
            %% so only the default group should be run!
            {skip, "explicit inet backend"};
        false ->
            [{socket_create_opts, [{inet_backend, socket}]} | Config]
    end;
init_per_group(t_local = _GroupName, Config) ->
    %% A specific inet-backend can be enabled by the environment
    case lists:keysearch(socket_create_opts, 1, Config) of
        {value, {socket_create_opts, []}} ->
            %% Default
            %% Currently, default is inet, so unless the user has set
            %% the environment variable ERL_FLAGS to use socket, we
            %% use inet.
            case application:get_all_env(kernel) of
                Env when is_list(Env) ->
                    case lists:keysearch(inet_backend, 1, Env) of
                        {value, {inet_backend, socket}} ->
                            try is_local_socket_supported() of
                                true ->
                                    Config;
                                false ->
                                    {skip, "AF_LOCAL not supported"}
                            catch
                                _:_:_ ->
                                    {skip, "AF_LOCAL not supported"}
                            end;
                        _ ->
                            try is_local_inet_supported() of
                                true ->
                                    Config;
                                false ->
                                    {skip, "AF_LOCAL not supported"}
                            catch
                                _:_:_ ->
                                    {skip, "AF_LOCAL not supported"}
                            end
                    end;
                _ ->
                    try is_local_inet_supported() of
                        true ->
                            Config;
                        false ->
                            {skip, "AF_LOCAL not supported"}
                    catch
                        _:_:_ ->
                            {skip, "AF_LOCAL not supported"}
                    end
            end;

         {value, {socket_create_opts, [{inet_backend, inet}]}} ->
            try is_local_inet_supported() of
                true ->
                    Config;
                false ->
                    {skip, "AF_LOCAL not supported"}
            catch
                _:_:_ ->
                    {skip, "AF_LOCAL not supported"}
            end;

         {value, {socket_create_opts, [{inet_backend, socket}]}} ->
            try is_local_socket_supported() of
                true ->
                    Config;
                false ->
                    {skip, "AF_LOCAL not supported"}
            catch
                _:_:_ ->
                    {skip, "AF_LOCAL not supported"}
            end
    end;
init_per_group(_GroupName, Config) ->
    Config.


is_local_socket_supported() ->
    socket:is_supported(local).

is_local_inet_supported() ->
    case gen_tcp:connect({local,<<"/">>}, 0, []) of
	{error, eafnosupport} ->
	    false;
	{error,_} ->
	    true
    end.
    
end_per_group(t_local, _Config) ->
    delete_local_filenames();
end_per_group(_, _Config) ->
    ok.


init_per_testcase(Func, Config)
  when Func =:= undefined -> % Insert your testcase name here
    dbg:tracer(),
    dbg:p(self(), c),
    dbg:tpl(prim_inet, cx),
    dbg:tpl(local_tcp, cx),
    dbg:tpl(inet, cx),
    dbg:tpl(gen_tcp, cx),
    Config;
init_per_testcase(_Func, Config) ->
    Config.

end_per_testcase(_Func, _Config) ->
    dbg:stop().

%%% gen_tcp:accept/1,2


%% Test that gen_tcp:accept/2 (with timeout) works.
t_accept_timeout(Config) when is_list(Config) ->
    {ok, L} = gen_tcp:listen(0, ?INET_BACKEND_OPTS(Config)),
    timeout({gen_tcp, accept, [L, 200]}, 0.2, 1.0).

%%% gen_tcp:connect/X


%% Test that gen_tcp:connect/4 (with timeout) works.
t_connect_timeout(Config) when is_list(Config) ->
    %%BadAddr = {134,138,177,16},
    %%TcpPort = 80,
    {ok, BadAddr} =  unused_ip(),
    TcpPort = 45638,
    ok = ?P("Connecting to ~p, port ~p", [BadAddr, TcpPort]),
    connect_timeout({gen_tcp,connect,[BadAddr,TcpPort,?INET_BACKEND_OPTS(Config),200]}, 0.2, 5.0).

%% Test that gen_tcp:connect/3 handles non-existings hosts, and other
%% invalid things.
t_connect_bad(Config) when is_list(Config) ->
    NonExistingPort = 45638,		% Not in use, I hope.
    {error, Reason1} = gen_tcp:connect(localhost, NonExistingPort, 
                                       ?INET_BACKEND_OPTS(Config)),
    io:format("Error for connection attempt to port not in use: ~p",
	      [Reason1]),

    {error, Reason2} = gen_tcp:connect("non-existing-host-xxx", 7,
                                       ?INET_BACKEND_OPTS(Config)),
    io:format("Error for connection attempt to non-existing host: ~p",
	      [Reason2]),
    ok.


%%% gen_tcp:recv/X


%% Test that gen_tcp:recv/3 (with timeout works).
t_recv_timeout(Config) when is_list(Config) ->
    {ok, L} = gen_tcp:listen(0, ?INET_BACKEND_OPTS(Config)),
    {ok, Port} = inet:port(L),
    {ok, Client} = gen_tcp:connect(localhost, Port,
                                   ?INET_BACKEND_OPTS(Config) ++
                                       [{active, false}]),
    {ok, _A} = gen_tcp:accept(L),
    timeout({gen_tcp, recv, [Client, 0, 200]}, 0.2, 5.0).

%% Test that end of file on a socket is reported correctly.
t_recv_eof(Config) when is_list(Config) ->
    {ok, L} = gen_tcp:listen(0, ?INET_BACKEND_OPTS(Config)),
    {ok, Port} = inet:port(L),
    {ok, Client} = gen_tcp:connect(localhost, Port,
                                   ?INET_BACKEND_OPTS(Config) ++
                                       [{active, false}]),
    {ok, A} = gen_tcp:accept(L),
    ok = gen_tcp:close(A),
    {error, closed} = gen_tcp:recv(Client, 0),
    ok.

%% Test using message delimiter $X.
t_recv_delim(Config) when is_list(Config) ->
    {ok, L} = gen_tcp:listen(0, ?INET_BACKEND_OPTS(Config)),
    {ok, Port} = inet:port(L),
    Opts = ?INET_BACKEND_OPTS(Config) ++
        [{active,false}, {packet,line}, {line_delimiter,$X}],
    {ok, Client} = gen_tcp:connect(localhost, Port, Opts),
    {ok, A} = gen_tcp:accept(L),
    ok = gen_tcp:send(A, "abcXefgX"),
    {ok, "abcX"} = gen_tcp:recv(Client, 0, 200),
    {ok, "efgX"} = gen_tcp:recv(Client, 0, 200),
    ok = gen_tcp:close(Client),
    ok = gen_tcp:close(A),
    ok.

%%% gen_tcp:shutdown/2

t_shutdown_write(Config) when is_list(Config) ->
    {ok, L} = gen_tcp:listen(0, ?INET_BACKEND_OPTS(Config)),
    {ok, Port} = inet:port(L),
    {ok, Client} = gen_tcp:connect(localhost, Port,
                                   ?INET_BACKEND_OPTS(Config) ++
                                       [{active, false}]),
    {ok, A} = gen_tcp:accept(L),
    ok = gen_tcp:shutdown(A, write),
    {error, closed} = gen_tcp:recv(Client, 0),
    ok.

t_shutdown_both(Config) when is_list(Config) ->
    {ok, L} = gen_tcp:listen(0, ?INET_BACKEND_OPTS(Config)),
    {ok, Port} = inet:port(L),
    {ok, Client} = gen_tcp:connect(localhost, Port,
                                   ?INET_BACKEND_OPTS(Config) ++
                                       [{active, false}]),
    {ok, A} = gen_tcp:accept(L),
    ok = gen_tcp:shutdown(A, read_write),
    {error, closed} = gen_tcp:recv(Client, 0),
    ok.

t_shutdown_error(Config) when is_list(Config) ->
    {ok, L} = gen_tcp:listen(0, ?INET_BACKEND_OPTS(Config)),
    {error, enotconn} = gen_tcp:shutdown(L, read_write),
    ok = gen_tcp:close(L),
    {error, closed} = gen_tcp:shutdown(L, read_write),
    ok.

t_shutdown_async(Config) when is_list(Config) ->
    {OS, _} = os:type(),
    {ok, L} = gen_tcp:listen(0, ?INET_BACKEND_OPTS(Config) ++ [{sndbuf, 4096}]),
    {ok, Port} = inet:port(L),
    {ok, Client} = gen_tcp:connect(localhost, Port,
				   ?INET_BACKEND_OPTS(Config) ++
                                       [{recbuf, 4096},
                                        {active, false}]),
    {ok, S} = gen_tcp:accept(L),
    PayloadSize = 1024 * 1024,
    Payload = lists:duplicate(PayloadSize, $.),
    ok = gen_tcp:send(S, Payload),
    case erlang:port_info(S, queue_size) of
	{queue_size, N} when N > 0 -> ok;
	{queue_size, 0} when OS =:= win32 -> ok;
	{queue_size, 0} = T -> ct:fail({unexpected, T})
    end,

    ok = gen_tcp:shutdown(S, write),
    {ok, Buf} = gen_tcp:recv(Client, PayloadSize),
    {error, closed} = gen_tcp:recv(Client, 0),
    case length(Buf) of
	PayloadSize -> ok;
	Sz -> ct:fail({payload_size,
		       {expected, PayloadSize},
		       {received, Sz}})
    end.


%%% gen_tcp:fdopen/2

t_fdopen(Config) when is_list(Config) ->
    Question  = "Aaaa... Long time ago in a small town in Germany,",
    Question1 = list_to_binary(Question),
    Question2 = [<<"Aaaa">>, "... ", $L, <<>>, $o, "ng time ago ",
		 ["in ", [], <<"a small town">>, [" in Germany,", <<>>]]],
    Question1 = iolist_to_binary(Question2),
    Answer    = "there was a shoemaker, Schumacher was his name.",
    {ok, L}      = gen_tcp:listen(0, ?INET_BACKEND_OPTS(Config) ++ [{active, false}]),
    {ok, Port}   = inet:port(L),
    {ok, Client} = gen_tcp:connect(localhost, Port,
                                   ?INET_BACKEND_OPTS(Config) ++
                                       [{active, false}]),
    {A, FD} = case gen_tcp:accept(L) of
                  {ok, ASock} when is_port(ASock) ->
                      {ok, FileDesc} = prim_inet:getfd(ASock),
                      {ASock, FileDesc};
                  {ok, ASock} -> % socket
                      {ok, [{fd, FileDesc}]} =
                          gen_tcp_socket:getopts(ASock, [fd]),
                      {ASock, FileDesc}
              end,
    ?P("fdopen -> accepted: "
       "~n   A:  ~p"
       "~n   FD: ~p", [A, FD]),
    {ok, Server}    = gen_tcp:fdopen(FD, []),
    ok              = gen_tcp:send(Client, Question),
    {ok, Question}  = gen_tcp:recv(Server, length(Question), 2000),
    ok              = gen_tcp:send(Client, Question1),
    {ok, Question}  = gen_tcp:recv(Server, length(Question), 2000),
    ok              = gen_tcp:send(Client, Question2),
    {ok, Question}  = gen_tcp:recv(Server, length(Question), 2000),
    ok              = gen_tcp:send(Server, Answer),
    {ok, Answer}    = gen_tcp:recv(Client, length(Answer), 2000),
    ok              = gen_tcp:close(Client),
    {error, closed} = gen_tcp:recv(A, 1, 2000),
    ok              = gen_tcp:close(Server),
    ok              = gen_tcp:close(A),
    ok              = gen_tcp:close(L),
    ok.


t_fdconnect(Config) when is_list(Config) ->
    ?TC_TRY(t_fdconnect, fun() -> do_t_fdconnect(Config) end).

do_t_fdconnect(Config) ->
    Question = "Aaaa... Long time ago in a small town in Germany,",
    Question1 = list_to_binary(Question),
    Question2 = [<<"Aaaa">>, "... ", $L, <<>>, $o, "ng time ago ",
		 ["in ", [], <<"a small town">>, [" in Germany,", <<>>]]],
    Question1 = iolist_to_binary(Question2),
    Answer = "there was a shoemaker, Schumacher was his name.",
    Path = proplists:get_value(data_dir, Config),
    Lib = "gen_tcp_api_SUITE",
    ?P("try load util nif lib"),
    case erlang:load_nif(filename:join(Path,Lib), []) of
        ok ->
            ok;
        {error, Reason} ->
            ?P("UNEXPECTED - failed loading util nif lib: "
               "~n   ~p", [Reason]),
            ?SKIPT("failed loading util nif lib")
    end,
    ?P("try create listen socket"),
    L = case gen_tcp:listen(0, ?INET_BACKEND_OPTS(Config) ++ [{active, false}]) of
            {ok, LSock} ->
                LSock;
            {error, eaddrnotavail = LReason} ->
                ?SKIPT(listen_failed_str(LReason))
        end,            
    {ok, Port} = inet:port(L),
    ?P("try create file descriptor (fd)"),
    FD = gen_tcp_api_SUITE:getsockfd(),
    ?P("try connect to using file descriptor (~w)", [FD]),
    Client = case gen_tcp:connect(localhost, Port, ?INET_BACKEND_OPTS(Config) ++
                                      [{fd,     FD},
                                       {port,   20002},
                                       {active, false}]) of
                 {ok, CSock} ->
                     CSock;
                 {error, eaddrnotavail = CReason} ->
                     gen_tcp:close(L),
                     gen_tcp_api_SUITE:closesockfd(FD),
                     ?SKIPT(connect_failed_str(CReason))
             end,                             
    ?P("try accept connection"),
    Server = case gen_tcp:accept(L) of
                 {ok, ASock} ->
                     ASock;
                 {error, eaddrnotavail = AReason} ->
                     gen_tcp:close(Client),
                     gen_tcp:close(L),
                     gen_tcp_api_SUITE:closesockfd(FD),
                     ?SKIPT(accept_failed_str(AReason))
        end,                             
    ?P("begin validation"),
    ok = gen_tcp:send(Client, Question),
    {ok, Question} = gen_tcp:recv(Server, length(Question), 2000),
    ok = gen_tcp:send(Client, Question1),
    {ok, Question} = gen_tcp:recv(Server, length(Question), 2000),
    ok = gen_tcp:send(Client, Question2),
    {ok, Question} = gen_tcp:recv(Server, length(Question), 2000),
    ok = gen_tcp:send(Server, Answer),
    {ok, Answer} = gen_tcp:recv(Client, length(Answer), 2000),
    ok = gen_tcp:close(Client),
    FD = gen_tcp_api_SUITE:closesockfd(FD),
    {error,closed} = gen_tcp:recv(Server, 1, 2000),
    ok = gen_tcp:close(Server),
    ok = gen_tcp:close(L),
    ?P("done"),
    ok.


%%% implicit inet6 option to api functions

t_implicit_inet6(Config) when is_list(Config) ->
    ?TC_TRY(t_implicit_inet6, fun() -> do_t_implicit_inet6(Config) end).

do_t_implicit_inet6(Config) ->
    ?P("try get hostname"),
    Host = ok(inet:gethostname()),
    ?P("try get address for host ~p", [Host]),
    case inet:getaddr(Host, inet6) of
	{ok, Addr} ->
            ?P("address: ~p", [Addr]),
	    t_implicit_inet6(Config, Host, Addr);
	{error, Reason} ->
	    {skip,
	     "Can not look up IPv6 address: "
	     ++atom_to_list(Reason)}
    end.

t_implicit_inet6(Config, Host, Addr) ->
    Loopback = {0,0,0,0,0,0,0,1},
    InetBackendOpts = ?INET_BACKEND_OPTS(Config),
    case gen_tcp:listen(0, InetBackendOpts ++ [inet6, {ip,Loopback}]) of
	{ok, S1} ->
	    ?P("try ~s ~p", ["::1", Loopback]),
	    implicit_inet6(Config, S1, Loopback),
	    ok = gen_tcp:close(S1),
	    %%
	    LocalAddr = ok(get_localaddr()),
	    S2 = case gen_tcp:listen(0, InetBackendOpts ++ [{ip, LocalAddr}]) of
                     {ok, LSock2} ->
                         LSock2;
                     {error, Reason2} ->
                         ?P("Listen failed (ip):"
                            "~n   Reason2: ~p", [Reason2]),
                         ?SKIPT(listen_failed_str(Reason2))
                 end,
	    implicit_inet6(Config, S2, LocalAddr),
	    ok = gen_tcp:close(S2),
	    %%
	    ?P("try ~s ~p", [Host, Addr]),
	    S3 = case gen_tcp:listen(0, InetBackendOpts ++ [{ifaddr,Addr}]) of
                     {ok, LSock3} ->
                         LSock3;
                     {error, Reason3} ->
                         ?P("Listen failed (ifaddr):"
                            "~n   Reason3: ~p", [Reason3]),
                         ?SKIPT(listen_failed_str(Reason3))
                 end,
	    implicit_inet6(Config, S3, Addr),
	    ok = gen_tcp:close(S3),
	    ?P("done"),
            ok;
        {error, Reason1} ->
            ?SKIPT(listen_failed_str(Reason1))
    end.

implicit_inet6(Config, S, Addr) ->
    P = ok(inet:port(S)),
    S2 = case gen_tcp:connect(Addr, P, ?INET_BACKEND_OPTS(Config)) of
             {ok, CSock} ->
                 CSock;
             {error, CReason} ->
                 ?SKIPT(connect_failed_str(CReason))
         end,
    P2 = ok(inet:port(S2)),
    S1 = case gen_tcp:accept(S) of
             {ok, ASock} ->
                 ASock;
             {error, AReason} ->
                 ?SKIPT(accept_failed_str(AReason))
         end,
    P1 = P = ok(inet:port(S1)),
    {Addr,P2} = ok(inet:peername(S1)),
    {Addr,P1} = ok(inet:peername(S2)),
    {Addr,P1} = ok(inet:sockname(S1)),
    {Addr,P2} = ok(inet:sockname(S2)),
    ok = gen_tcp:close(S2),
    ok = gen_tcp:close(S1).


t_local_basic(Config) ->
    SFile = local_filename(server),
    SAddr = {local, bin_filename(SFile)},
    CFile = local_filename(client),
    CAddr = {local,bin_filename(CFile)},
    _ = file:delete(SFile),
    _ = file:delete(CFile),
    %%
    ?P("try create listen socket"),
    InetBackendOpts = ?INET_BACKEND_OPTS(Config),
    L =
	ok(
	  gen_tcp:listen(0, InetBackendOpts ++ 
                             [{ifaddr,{local,SFile}},{active,false}])),
    ?P("try connect"),
    C =
	ok(
	  gen_tcp:connect(
	    {local,SFile}, 0, InetBackendOpts ++
                [{ifaddr,{local,CFile}},{active,false}])),
    ?P("try accept connection"),
    S = ok(gen_tcp:accept(L)),
    ?P("try get sockname for listen socket"),
    %% SAddr = ok(inet:sockname(L)),
    case inet:sockname(L) of
        {ok, SAddr} ->
            ok;
        {ok, SAddr2} ->
            ?P("Invalid sockname: "
               "~n   Expected: ~p"
               "~n   Actual:   ~p", [SAddr, SAddr2]),
            exit({sockename, SAddr, SAddr2});
        {error, Reason} ->
            exit({sockname, Reason})
    end,
    ?P("try get peername for listen socket"),
    {error, enotconn} = inet:peername(L),
    ?P("try handshake"),
    local_handshake(S, SAddr, C, CAddr),
    ?P("try close listen socket"),
    ok = gen_tcp:close(L),
    ?P("try close accept socket"),
    ok = gen_tcp:close(S),
    ?P("try close connect socket"),
    ok = gen_tcp:close(C),
    %%
    ?P("try 'local' files"),
    ok = file:delete(SFile),
    ok = file:delete(CFile),
    ?P("done"),
    ok.


t_local_unbound(Config) ->
    SFile = local_filename(server),
    SAddr = {local,bin_filename(SFile)},
    _ = file:delete(SFile),
    %%
    InetBackendOpts = ?INET_BACKEND_OPTS(Config),
    L = ok(gen_tcp:listen(0, InetBackendOpts ++
                              [{ifaddr,SAddr},{active,false}])),
    C = ok(gen_tcp:connect(SAddr, 0,
                           InetBackendOpts ++ [{active,false}])),
    S = ok(gen_tcp:accept(L)),
    SAddr = ok(inet:sockname(L)),
    {error,enotconn} = inet:peername(L),
    local_handshake(S, SAddr, C, {local,<<>>}),
    ok = gen_tcp:close(L),
    ok = gen_tcp:close(S),
    ok = gen_tcp:close(C),
    ok = file:delete(SFile),
    ok.


t_local_fdopen(Config) ->
    SFile = local_filename(server),
    SAddr = {local,bin_filename(SFile)},
    _ = file:delete(SFile),
    %%
    InetBackendOpts = ?INET_BACKEND_OPTS(Config),
    L = ok(gen_tcp:listen(0, InetBackendOpts ++ [{ifaddr,SAddr},{active,false}])),
    C0 = ok(gen_tcp:connect(SAddr, 0, InetBackendOpts ++ [{active,false}])),
    Fd = ok(prim_inet:getfd(C0)),
    ok = prim_inet:ignorefd(C0, true),
    C = ok(gen_tcp:fdopen(Fd, [local])),
    S = ok(gen_tcp:accept(L)),
    SAddr = ok(inet:sockname(L)),
    {error,enotconn} = inet:peername(L),
    local_handshake(S, SAddr, C, {local,<<>>}),
    ok = gen_tcp:close(L),
    ok = gen_tcp:close(S),
    ok = gen_tcp:close(C),
    ok = gen_tcp:close(C0),
    ok = file:delete(SFile),
    ok.

t_local_fdopen_listen(Config) ->
    SFile = local_filename(server),
    SAddr = {local,bin_filename(SFile)},
    _ = file:delete(SFile),
    InetBackendOpts = ?INET_BACKEND_OPTS(Config),
    L0 = ok(gen_tcp:listen(0, InetBackendOpts ++ [{ifaddr,SAddr},{active,false}])),
    Fd = ok(prim_inet:getfd(L0)),
    L = ok(gen_tcp:listen(0, InetBackendOpts ++ [{fd,Fd},local,{active,false}])),
    C = ok(gen_tcp:connect(SAddr, 0, InetBackendOpts ++ [{active,false}])),
    S = ok(gen_tcp:accept(L)),
    SAddr = ok(inet:sockname(L)),
    {error,enotconn} = inet:peername(L),
    local_handshake(S, SAddr, C, {local,<<>>}),
    ok = gen_tcp:close(L),
    ok = gen_tcp:close(L0),
    ok = gen_tcp:close(S),
    ok = gen_tcp:close(C),
    ok = file:delete(SFile),
    ok.

t_local_fdopen_listen_unbound(Config) ->
    SFile = local_filename(server),
    SAddr = {local,bin_filename(SFile)},
    _ = file:delete(SFile),
    P = ok(prim_inet:open(tcp, local, stream)),
    Fd = ok(prim_inet:getfd(P)),
    InetBackendOpts = ?INET_BACKEND_OPTS(Config),
    L =
	ok(gen_tcp:listen(
	     0, InetBackendOpts ++ [{fd,Fd},{ifaddr,SAddr},{active,false}])),
    C = ok(gen_tcp:connect(SAddr, 0, InetBackendOpts ++ [{active,false}])),
    S = ok(gen_tcp:accept(L)),
    SAddr = ok(inet:sockname(L)),
    {error,enotconn} = inet:peername(L),
    local_handshake(S, SAddr, C, {local,<<>>}),
    ok = gen_tcp:close(L),
    ok = gen_tcp:close(P),
    ok = gen_tcp:close(S),
    ok = gen_tcp:close(C),
    ok = file:delete(SFile),
    ok.

t_local_fdopen_connect(Config) ->
    SFile = local_filename(server),
    SAddr = {local,bin_filename(SFile)},
    CFile = local_filename(client),
    CAddr = {local,bin_filename(CFile)},
    _ = file:delete(SFile),
    _ = file:delete(CFile),
    InetBackendOpts = ?INET_BACKEND_OPTS(Config),
    L = ok(gen_tcp:listen(0, InetBackendOpts ++ [{ifaddr,SAddr},{active,false}])),
    P = ok(prim_inet:open(tcp, local, stream)),
    Fd = ok(prim_inet:getfd(P)),
    C =
	ok(gen_tcp:connect(
	     SAddr, 0, InetBackendOpts ++
                 [{fd,Fd},{ifaddr,CAddr},{active,false}])),
    S = ok(gen_tcp:accept(L)),
    SAddr = ok(inet:sockname(L)),
    {error,enotconn} = inet:peername(L),
    local_handshake(S, SAddr, C, CAddr),
    ok = gen_tcp:close(L),
    ok = gen_tcp:close(S),
    ok = gen_tcp:close(C),
    ok = gen_tcp:close(P),
    ok = file:delete(SFile),
    ok.

t_local_fdopen_connect_unbound(Config) ->
    SFile = local_filename(server),
    SAddr = {local,bin_filename(SFile)},
    _ = file:delete(SFile),
    InetBackendOpts = ?INET_BACKEND_OPTS(Config),
    L = ok(gen_tcp:listen(0, InetBackendOpts ++ [{ifaddr,SAddr},{active,false}])),
    P = ok(prim_inet:open(tcp, local, stream)),
    Fd = ok(prim_inet:getfd(P)),
    C =	ok(gen_tcp:connect(SAddr, 0, InetBackendOpts ++ [{fd,Fd},{active,false}])),
    S = ok(gen_tcp:accept(L)),
    SAddr = ok(inet:sockname(L)),
    {error,enotconn} = inet:peername(L),
    local_handshake(S, SAddr, C, {local,<<>>}),
    ok = gen_tcp:close(L),
    ok = gen_tcp:close(S),
    ok = gen_tcp:close(C),
    ok = gen_tcp:close(P),
    ok = file:delete(SFile),
    ok.

t_local_abstract(Config) ->
    case os:type() of
	{unix,linux} ->
	    AbstAddr = {local,<<>>},
            InetBackendOpts = ?INET_BACKEND_OPTS(Config),
	    L =
		ok(gen_tcp:listen(
		     0, InetBackendOpts ++ [{ifaddr,AbstAddr},{active,false}])),
	    {local,_} = SAddr = ok(inet:sockname(L)),
	    C =
		ok(gen_tcp:connect(
		     SAddr, 0,
                     InetBackendOpts ++ [{ifaddr,AbstAddr},{active,false}])),
	    {local,_} = CAddr = ok(inet:sockname(C)),
	    S = ok(gen_tcp:accept(L)),
	    {error,enotconn} = inet:peername(L),
	    local_handshake(S, SAddr, C, CAddr),
	    ok = gen_tcp:close(L),
	    ok = gen_tcp:close(S),
	    ok = gen_tcp:close(C),
	    ok;
	_ ->
	    {skip,"AF_LOCAL Abstract Addresses only supported on Linux"}
    end.


local_handshake(S, SAddr, C, CAddr) ->
    SData = "9876543210",
    CData = "0123456789",
    SAddr = ok(inet:sockname(S)),
    CAddr = ok(inet:sockname(C)),
    CAddr = ok(inet:peername(S)),
    SAddr = ok(inet:peername(C)),
    ok = gen_tcp:send(C, CData),
    ok = gen_tcp:send(S, SData),
    CData = ok(gen_tcp:recv(S, length(CData))),
    SData = ok(gen_tcp:recv(C, length(SData))),
    ok.

t_accept_inet6_tclass(Config) when is_list(Config) ->
    TClassOpt = {tclass,8#56 bsl 2}, % Expedited forwarding
    Loopback = {0,0,0,0,0,0,0,1},
    case gen_tcp:listen(0, ?INET_BACKEND_OPTS(Config) ++ [inet6, {ip, Loopback}, TClassOpt]) of
	{ok,L} ->
	    LPort = ok(inet:port(L)),
	    Sa = ok(gen_tcp:connect(Loopback, LPort, ?INET_BACKEND_OPTS(Config))),
	    Sb = ok(gen_tcp:accept(L)),
	    [TClassOpt] = ok(inet:getopts(Sb, [tclass])),
	    ok = gen_tcp:close(Sb),
	    ok = gen_tcp:close(Sa),
	    ok = gen_tcp:close(L),
	    ok;
	{error,_} ->
	    {skip,"IPv6 TCLASS not supported"}
    end.


%% On MacOS (maybe more), accepting a connection resulted in a crash.
%% Note that since 'socket' currently does not work on windows
%% we have to skip on that platform.
s_accept_with_explicit_socket_backend(Config) when is_list(Config) ->
    ?TC_TRY(s_accept_with_explicit_socket_backend,
            fun() -> is_not_windows() end,
            fun() -> do_s_accept_with_explicit_socket_backend() end).

do_s_accept_with_explicit_socket_backend() ->
    {ok, S}         = gen_tcp:listen(0, [{inet_backend, socket}]),
    {ok, {_, Port}} = inet:sockname(S),
    ClientF = fun() ->
		      {ok, _} = gen_tcp:connect("localhost", Port, []),
		      receive die -> exit(normal) after infinity -> ok end
	      end,
    Client = spawn_link(ClientF),
    {ok, _} = gen_tcp:accept(S),
    Client ! die,
    ok.


%%% Utilities

is_not_windows() ->
    case os:type() of
        {win32, _} ->
            {skip, "Windows not supported"};
        _ ->
            ok
    end.


%% Calls M:F/length(A), which should return a timeout error, and complete
%% within the given time.

timeout({M,F,A}, Lower, Upper) ->
    case test_server:timecall(M, F, A) of
	{Time, Result} when Time < Lower ->
	    ct:fail({too_short_time, Time, Result});
	{Time, Result} when Time > Upper ->
	    ct:fail({too_long_time, Time, Result});
	{_, {error, timeout}} ->
	    ok;
	{_, Result} ->
	    ct:fail({unexpected_result, Result})
    end.

connect_timeout({M,F,A}, Lower, Upper) ->
    case test_server:timecall(M, F, A) of
	{Time, Result} when Time < Lower ->
	    case Result of
		{error, econnrefused = E} ->
		    {skip, "Not tested -- got error " ++ atom_to_list(E)};
		{error, enetunreach = E} ->
		    {skip, "Not tested -- got error " ++ atom_to_list(E)};
		{ok, Socket} -> % What the...
		    Pinfo = erlang:port_info(Socket),
		    Db = inet_db:lookup_socket(Socket),
		    Peer = inet:peername(Socket),
		    ct:fail({too_short_time, Time,
			     [Result,Pinfo,Db,Peer]});
		_ ->
		    ct:fail({too_short_time, Time, Result})
	    end;
	{Time, Result} when Time > Upper ->
	    ct:fail({too_long_time, Time, Result});
	{_, {error, timeout}} ->
	    ok;
	{_, Result} ->
	    ct:fail({unexpected_result, Result})
    end.

%% Try to obtain an unused IP address in the local network.

unused_ip() ->
    {ok, Host} = inet:gethostname(),
    {ok, Hent} = inet:gethostbyname(Host),
    #hostent{h_addr_list=[{A, B, C, _D}|_]} = Hent,
    %% Note: In our net, addresses below 16 are reserved for routers and
    %% other strange creatures.
    IP = unused_ip(A, B, C, 16),
    if
        (IP =:= error) ->
            %% This is not supported on all platforms (yet), so...
            try net:getifaddrs() of
                {ok, IfAddrs} ->
                    io:format("we        = ~p,"
                              "unused_ip = ~p"
                              "            ~p"
                              "~n", [Hent, IP, IfAddrs]);
                {error, _} ->
                    io:format("we = ~p, unused_ip = ~p~n", [Hent, IP])
            catch
                _:_:_ ->
                    io:format("we = ~p, unused_ip = ~p~n", [Hent, IP])
            end;
        true ->
            io:format("we = ~p, unused_ip = ~p~n", [Hent, IP])
    end,
    IP.

unused_ip(255, 255, 255, 255) -> error;
unused_ip(255, B, C, D) -> unused_ip(1, B + 1, C, D);
unused_ip(A, 255, C, D) -> unused_ip(A, 1, C + 1, D);
unused_ip(A, B, 255, D) -> unused_ip(A, B, 1, D + 1);
unused_ip(A, B, C, D) ->
    case inet:gethostbyaddr({A, B, C, D}) of
	{ok, _} -> unused_ip(A + 1, B, C, D);
	{error, _} -> {ok, {A, B, C, D}}
    end.

ok({ok,V}) -> V;
ok(NotOk) ->
    try throw(not_ok)
    catch
	throw:Thrown:Stacktrace ->
	    erlang:raise(
	      error, {Thrown, NotOk}, tl(Stacktrace))
    end.

get_localaddr() ->
    get_localaddr(["localhost", "localhost6", "ip6-localhost"]).

get_localaddr([]) ->
    {error, localaddr_not_found};
get_localaddr([Localhost|Ls]) ->
    case inet:getaddr(Localhost, inet6) of
       {ok, LocalAddr} ->
           ?P("~s ~p", [Localhost, LocalAddr]),
           {ok, LocalAddr};
       _ ->
           get_localaddr(Ls)
    end.

getsockfd() -> undefined.
closesockfd(_FD) -> undefined.

local_filename(Tag) ->
    "/tmp/" ?MODULE_STRING "_" ++ os:getpid() ++ "_" ++ atom_to_list(Tag).

bin_filename(String) ->
    unicode:characters_to_binary(String, file:native_name_encoding()).

delete_local_filenames() ->
    _ =
	[file:delete(F) ||
	    F <-
		filelib:wildcard(
		  "/tmp/" ?MODULE_STRING "_" ++ os:getpid() ++ "_*")],
    ok.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

connect_failed_str(Reason) ->
    ?F("Connect failed: ~w", [Reason]).

listen_failed_str(Reason) ->
    ?F("Listen failed: ~w", [Reason]).

accept_failed_str(Reason) ->
    ?F("Accept failed: ~w", [Reason]).


