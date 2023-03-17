%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2007-2022. All Rights Reserved.
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

-module(ssl_dist_SUITE).

-behaviour(ct_suite).

-include_lib("kernel/include/net_address.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("public_key/include/public_key.hrl").
-include("ssl_dist_test_lib.hrl").

%% Common test
-export([all/0,
         init_per_suite/1,
         init_per_testcase/2,
         end_per_suite/1,
         end_per_testcase/2
        ]).

%% Test cases
-export([basic/0,
         basic/1,
         monitor_nodes/1,
         payload/0,
         payload/1,
         dist_port_overload/0,
         dist_port_overload/1,
         plain_options/0,
         plain_options/1,
         plain_verify_options/0,
         plain_verify_options/1,
         nodelay_option/0,
         nodelay_option/1,
         listen_port_options/0,
         listen_port_options/1,
         listen_options/0,
         listen_options/1,
         connect_options/0,
         connect_options/1,
         net_ticker_spawn_options/0,
         net_ticker_spawn_options/1,
         use_interface/0,
         use_interface/1,
         verify_fun_fail/0,
         verify_fun_fail/1,
         verify_fun_pass/0,
         verify_fun_pass/1,
         epmd_module/0,
         epmd_module/1
         ]).

%% Apply export
-export([basic_test/3,
         monitor_nodes_test/3,
         payload_test/3,
         plain_options_test/3,
         plain_verify_options_test/3,
         do_listen_options/2,
         listen_options_test/3,
         do_connect_options/2,
         connect_options_test/3,
         net_ticker_spawn_options_test/3,
         verify_fun_fail_test/3,
         verify_fun_pass_test/3,
         verify_pass_always/3,
         verify_fail_always/3]).

%% Epmd module export
-export([start_link/0,
         register_node/2,
         register_node/3,
         port_please/2,
         address_please/3]).

-define(DEFAULT_TIMETRAP_SECS, 240).
-define(AWAIT_SSL_NODE_UP_TIMEOUT, 30000).

-import(ssl_dist_test_lib,
        [tstsrvr_format/2, send_to_tstcntrl/1,
         apply_on_ssl_node/4, apply_on_ssl_node/2,
         stop_ssl_node/1]).

start_ssl_node_name(Name, Args) ->
    Pa = filename:dirname(code:which(?MODULE)),
    ssl_dist_test_lib:start_ssl_node(Name, "-pa " ++ Pa ++ " " ++ Args).

%%--------------------------------------------------------------------
%% Common Test interface functions -----------------------------------
%%--------------------------------------------------------------------
all() ->
    [basic,
     monitor_nodes,
     payload,
     dist_port_overload,
     plain_options,
     plain_verify_options,
     nodelay_option,
     listen_port_options,
     listen_options,
     connect_options,
     net_ticker_spawn_options,
     use_interface,
     verify_fun_fail,
     verify_fun_pass,
     epmd_module
    ].

init_per_suite(Config0) ->
    _ = end_per_suite(Config0),
    try crypto:start() of
	ok ->
	    %% Currently no ct function available for is_cover!
	    case test_server:is_cover() of
		false ->
		    Config = add_ssl_opts_config(Config0),
		    setup_certs(Config),
		    Config;
		true ->
		    {skip, "Can not be covered"}
	    end
    catch _:_ ->
	    {skip, "Crypto did not start"}
    end.

end_per_suite(_Config) ->
    application:stop(crypto).

init_per_testcase(plain_verify_options = Case, Config) when is_list(Config) ->
    SslFlags = setup_tls_opts(Config),
    Flags = case os:getenv("ERL_FLAGS") of
		false ->
		    os:putenv("ERL_FLAGS", SslFlags),
		    "";
		OldFlags ->
		    os:putenv("ERL_FLAGS", OldFlags ++ " " ++ SslFlags),
		    OldFlags
    end,
    common_init(Case, [{old_flags, Flags} | Config]);

init_per_testcase(Case, Config) when is_list(Config) ->
    common_init(Case, Config).

common_init(Case, Config) ->
    ct:timetrap({seconds, ?DEFAULT_TIMETRAP_SECS}),
    [{testcase, Case}|Config].

end_per_testcase(Case, Config) when is_list(Config) ->
    Flags = proplists:get_value(old_flags, Config),
    catch os:putenv("ERL_FLAGS", Flags),
    common_end(Case, Config).

common_end(_, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% Test Cases --------------------------------------------------------
%%--------------------------------------------------------------------

basic() ->
    [{doc,"Test that two nodes can connect via ssl distribution"}].
basic(Config) when is_list(Config) ->
    gen_dist_test(basic_test, Config).

%%--------------------------------------------------------------------
%% Test net_kernel:monitor_nodes with nodedown_reason (OTP-17838)
monitor_nodes(Config) when is_list(Config) ->
    gen_dist_test(monitor_nodes_test, Config).

%%--------------------------------------------------------------------
payload() ->
    [{doc,"Test that send a lot of data between the ssl distributed nodes"}].
payload(Config) when is_list(Config) ->
    gen_dist_test(payload_test, Config).

%%--------------------------------------------------------------------
dist_port_overload() ->
    [{doc, "Test that TLS distribution connections can be accepted concurrently"}].
dist_port_overload(Config) when is_list(Config) ->
    %% Start a node, and get the port number it's listening on.
    #node_handle{nodename = NodeName} = NH1 = start_ssl_node(Config),
    [Name, Host] = string:lexemes(atom_to_list(NodeName), "@"),
    {ok, NodesPorts} = apply_on_ssl_node(NH1, fun net_adm:names/0),
    {Name, Port} = lists:keyfind(Name, 1, NodesPorts),
    %% Run 4 connections concurrently. When TLS handshake is not concurrent,
    %%  and with default net_setuptime of 7 seconds, only one connection per 7
    %%  seconds is closed from server side. With concurrent accept, all 7 will
    %%  be dropped in 7 seconds
    RequiredConcurrency = 4,
    Started = [connect(self(), Host, Port) || _ <- lists:seq(1, RequiredConcurrency)],
    %% give 10 seconds (more than 7, less than 2x7 seconds)
    Responded = barrier(RequiredConcurrency, [], erlang:system_time(millisecond) + 10000),
    %% clean up
    stop_ssl_node(NH1),
    [R ! exit || R <- Responded],
    [exit(P, kill) || P <- Started -- Responded],
    %% Ensure some amount of concurrency was reached.
    (length(Responded) >= RequiredConcurrency) orelse
        ct:fail({actual, length(Responded), expected, RequiredConcurrency}),
    success(Config).

barrier(0, Responded, _Until) ->
    Responded;
barrier(RequiredConcurrency, Responded, Until) ->
    Timeout = Until - erlang:system_time(millisecond),
    receive
        {waiting, Pid} ->
            barrier(RequiredConcurrency - 1, [Pid | Responded], Until);
        {error, Error} ->
            ct:fail(Error)
    after
        Timeout -> Responded
    end.

connect(Control, Host, Port) ->
    spawn(
        fun () ->
            case gen_tcp:connect(Host, Port, [{active, true}]) of
                {ok, Sock} ->
                    receive
                        {tcp_closed, Sock} ->
                            Control ! {waiting, self()};
                        exit ->
                            gen_tcp:close(Sock)
                    end;
                Error ->
                    Control ! {error, Error}
            end
        end).

%%--------------------------------------------------------------------
plain_options() ->
    [{doc,"Test specifying tls options not related to certificate verification"}].
plain_options(Config) when is_list(Config) ->
    TLSOpts = "-ssl_dist_opt server_secure_renegotiate true "
	"client_secure_renegotiate true "
	"server_hibernate_after 500 client_hibernate_after 500",
    gen_dist_test(plain_options_test, [{tls_only_basic_opts, TLSOpts} | Config]).


%%--------------------------------------------------------------------
plain_verify_options() ->
    [{doc,"Test specifying tls options including certificate verification options"}].
plain_verify_options(Config) when is_list(Config) ->
    TLSOpts = "-ssl_dist_opt server_secure_renegotiate true "
	"client_secure_renegotiate true "
        "server_hibernate_after 500 client_hibernate_after 500"
	"server_reuse_sessions true client_reuse_sessions true  "
        "server_depth 1 client_depth 1 ",
    gen_dist_test(plain_verify_options_test, [{tls_verify_opts, TLSOpts} | Config]).

%%--------------------------------------------------------------------
nodelay_option() ->
    [{doc,"Test specifying dist_nodelay option"}].
nodelay_option(Config) ->
    try
	%% The default is 'true', so try setting it to 'false'.
	application:set_env(kernel, dist_nodelay, false),
	basic(Config)
    after
	application:unset_env(kernel, dist_nodelay)
    end.
%%--------------------------------------------------------------------

listen_port_options() ->
    [{doc, "Test specifying listening ports"}].
listen_port_options(Config) when is_list(Config) ->
    %% Set up the probably most supported scenario
    %% for {reuseaddr,true}, i.e, the listening socket
    %% is closed, but an accepted server side socket
    %% blocks the server port, unless {reuseaddr,true}
    %% is used.
    %%
    %% Set up a server socket and close the listening socket
    {ok, L}    = gen_tcp:listen(0, [{reuseaddr,true}]),
    {ok, Port} = inet:port(L),
    {ok, C}    = gen_tcp:connect({127,0,0,1}, Port, []),
    {ok, S}    = gen_tcp:accept(L),
    ok         = gen_tcp:close(L),
    ct:pal("Port: ~w", [Port]),
    %%
    %% Start a node on the server port, {reuseaddr,true}
    %% is used per default on the listening socket
    %% since it is a server - see inet_tcp_dist:gen_listen/3
    PortOpts =
        "-kernel"
        " inet_dist_listen_min " ++ integer_to_list(Port) ++
        " inet_dist_listen_max " ++ integer_to_list(Port),
    %% basic_test/3 connects NH1 -> NH2 so it is NH2 that should
    %% act as server to make use of PortOpts
    NH1 = start_ssl_node(Config),
    NH2 = start_ssl_node(Config, PortOpts),
    try
        basic_test(NH1, NH2, Config),
        Node2 = NH2#node_handle.nodename,
        {ok,NodeInfo2} =
            apply_on_ssl_node(NH1, net_kernel, node_info, [Node2]),
        {address,#net_address{address = {_,Port}, protocol = tls}} =
            lists:keyfind(address, 1, NodeInfo2),
        ok
    after
        gen_tcp:close(C),
        gen_tcp:close(S),
        stop_ssl_node(NH1),
        stop_ssl_node(NH2)
    end.

%%--------------------------------------------------------------------
listen_options() ->
    [{doc, "Test inet_dist_listen_options"}].
listen_options(Config) when is_list(Config) ->
    try_setting_priority(fun do_listen_options/2, Config).

%%--------------------------------------------------------------------
connect_options() ->
    [{doc, "Test inet_dist_connect_options"}].
connect_options(Config) when is_list(Config) ->
    try_setting_priority(fun do_connect_options/2, Config).

%%--------------------------------------------------------------------
net_ticker_spawn_options() ->
    [{doc, "Test net_ticker_spawn_options"}].
net_ticker_spawn_options(Config) when is_list(Config) ->
    FullsweepString = maybe_quote_tuple_list("[{fullsweep_after,0}]"),
    Options = "-kernel net_ticker_spawn_options "++FullsweepString,
    gen_dist_test(net_ticker_spawn_options_test, [{tls_only_basic_opts, Options} | Config]).


%%--------------------------------------------------------------------
use_interface() ->
    [{doc, "Test inet_dist_use_interface"}].
use_interface(Config) when is_list(Config) ->
    %% Force the node to listen only on the loopback interface.
    IpString = localhost_ipstr(inet_ver()),
    Options = "-kernel inet_dist_use_interface " ++ IpString,

    %% Start a node, and get the port number it's listening on.
    NH1 = start_ssl_node([{tls_verify_opts, Options} | Config]),
  
    try
	Node1 = NH1#node_handle.nodename,
	Name = lists:takewhile(fun(C) -> C =/= $@ end, atom_to_list(Node1)),
	{ok, NodesPorts} = apply_on_ssl_node(NH1, fun net_adm:names/0),
	{Name, Port} = lists:keyfind(Name, 1, NodesPorts),
	
	%% Now find the socket listening on that port, and check its sockname.
	Sockets = apply_on_ssl_node(
		    NH1,
		    fun() ->
			    [inet:sockname(P) ||
				P <- inet_ports(),
				{ok, Port} =:= (catch inet:port(P))]
		    end),
	%% And check that it's actually listening on localhost.
        IP = localhost_ip(inet_ver()),
        [{ok,{IP,Port}}] = Sockets
    catch 
	_:Reason ->
	    stop_ssl_node(NH1),
	    ct:fail(Reason)
    end,
    stop_ssl_node(NH1),
    success(Config).
%%--------------------------------------------------------------------
verify_fun_fail() ->
    [{doc,"Test specifying verify_fun with a function that always fails"}].
verify_fun_fail(Config) when is_list(Config) ->
      AddTLSVerifyOpts = "-ssl_dist_opt "
        "server_verify_fun "
	"\"{ssl_dist_SUITE,verify_fail_always,{}}\" "
        "client_verify_fun "
	"\"{ssl_dist_SUITE,verify_fail_always,{}}\" ",
    gen_dist_test(verify_fun_fail_test, [{tls_verify_opts, AddTLSVerifyOpts} | Config]).


%%--------------------------------------------------------------------
verify_fun_pass() ->
    [{doc,"Test specifying verify_fun with a function that always succeeds"}].
verify_fun_pass(Config) when is_list(Config) ->
    AddTLSVerifyOpts = "-ssl_dist_opt "
        "server_verify_fun "
	"\"{ssl_dist_SUITE,verify_pass_always,{}}\" "
        "client_verify_fun "
	"\"{ssl_dist_SUITE,verify_pass_always,{}}\" ",
    gen_dist_test(verify_fun_pass_test, [{tls_verify_opts, AddTLSVerifyOpts} | Config]).

%%--------------------------------------------------------------------
epmd_module() ->
    [{doc,"Test that custom epmd_modules work"}].
epmd_module(Config0) when is_list(Config0) ->
    Config = [{hostname, "dummy"} | Config0],
    NH1 = start_ssl_node(Config, "-epmd_module " ++ atom_to_list(?MODULE)),
    NH2 = start_ssl_node(Config, "-epmd_module " ++ atom_to_list(?MODULE)),

    {ok, Port1} = apply_on_ssl_node(NH1, fun() -> application:get_env(kernel, dist_listen_port) end),
    {ok, Port2} = apply_on_ssl_node(NH2, fun() -> application:get_env(kernel, dist_listen_port) end),
    apply_on_ssl_node(NH1, fun() -> application:set_env(kernel, dist_connect_port, Port2) end),
    apply_on_ssl_node(NH2, fun() -> application:set_env(kernel, dist_connect_port, Port1) end),

    try
        basic_test(NH1, NH2, Config)
    catch
	_:Reason ->
	    stop_ssl_node(NH1),
	    stop_ssl_node(NH2),
	    ct:fail(Reason)
    end,
    stop_ssl_node(NH1),
    stop_ssl_node(NH2),	
    success(Config).

start_link() ->
    ignore.

register_node(Name, Port) ->
    register_node(Name, Port, inet_tcp).
register_node(_Name, Port, _Driver) ->
    %% Save the port number we're listening on.
    application:set_env(kernel, dist_listen_port, Port),
    Creation = rand:uniform(3),
    {ok, Creation}.

port_please(_Name, _Ip) ->
    {ok, Port} = application:get_env(kernel, dist_connect_port),
    {port, Port, 5}.

address_please(_Name, "dummy", AddressFamily) ->
    %% Use localhost.
    {ok,Host} = inet:gethostname(),
    inet:getaddr(Host, AddressFamily);
address_please(_, _, _) ->
    {error, nxdomain}.

%%--------------------------------------------------------------------
%%% Internal functions -----------------------------------------------
%%--------------------------------------------------------------------
gen_dist_test(Test, Config) ->
    NH1 = start_ssl_node(Config),
    NH2 = start_ssl_node(Config),
    try 
	?MODULE:Test(NH1, NH2, Config)
    catch
	_:Reason ->
	    stop_ssl_node(NH1),
	    stop_ssl_node(NH2),
	    ct:fail(Reason)
    end,
    stop_ssl_node(NH1),
    stop_ssl_node(NH2),	
    success(Config).

%% ssl_node side api
%%

try_setting_priority(TestFun, Config) ->
    Prio = 1,
    case gen_udp:open(0, [{priority,Prio}]) of
	{ok,Socket} ->
	    case inet:getopts(Socket, [priority]) of
		{ok,[{priority,Prio}]} ->
		    ok = gen_udp:close(Socket),
		    TestFun(Prio, Config);
		_ ->
		    ok = gen_udp:close(Socket),
		    {skip,
		     "Can not set priority "++integer_to_list(Prio)++
			 " on socket"}
	    end;
	{error,_} ->
	    {skip, "Can not set priority on socket"}
    end.
basic_test(NH1, NH2, _) ->
    Node1 = NH1#node_handle.nodename,
    Node2 = NH2#node_handle.nodename,
    pong = apply_on_ssl_node(NH1, fun () -> net_adm:ping(Node2) end),
    [Node2] = apply_on_ssl_node(NH1, fun () -> nodes() end),
    [Node1] = apply_on_ssl_node(NH2, fun () -> nodes() end),

    %% The test_server node has the same cookie as the ssl nodes
    %% but it should not be able to communicate with the ssl nodes
    %% via the erlang distribution.
    pang = net_adm:ping(Node1),
    pang = net_adm:ping(Node2),

    %% SSL nodes should not be able to communicate with the test_server node
    %% either (and ping should return eventually).
    TestServer = node(),
    pang = apply_on_ssl_node(NH1, fun () -> net_adm:ping(TestServer) end),
    pang = apply_on_ssl_node(NH2, fun () -> net_adm:ping(TestServer) end),

    %%
    %% Check that we are able to communicate over the erlang
    %% distribution between the ssl nodes.
    %%
    Ref = make_ref(),
    spawn(fun () ->
		  apply_on_ssl_node(
		    NH1,
		    fun () ->
			    tstsrvr_format(
                              "Hi from ~p!~n", [node()]),
			    send_to_tstcntrl(
                              {Ref, self()}),
			    receive
				{From, ping} ->
				    tstsrvr_format(
                                      "Received ping ~p!~n", [node()]),
				    From ! {self(), pong}
			    end
		    end)
	  end),
     receive
	 {Ref, SslPid} ->
	     ok = apply_on_ssl_node(
		    NH2,
		    fun () ->
			    tstsrvr_format(
                              "Hi from ~p!~n", [node()]),
			    SslPid ! {self(), ping},
			    receive
				{SslPid, pong} ->
				    ok
			    end
		    end)
     end.

monitor_nodes_test(NH1, NH2, _) ->
    Node2 = NH2#node_handle.nodename,

    Ref = make_ref(),
    MonitorNodesFun =
        fun() ->
                tstsrvr_format("Hi from ~p!~n", [node()]),
                ok = net_kernel:monitor_nodes(true, [nodedown_reason]),
                send_to_tstcntrl({self(), ready, Ref}),
                NodeUp = receive_any(),
                send_to_tstcntrl({self(), got, NodeUp}),
                NodeDown = receive_any(),
                send_to_tstcntrl({self(), got, NodeDown}),
                ok = net_kernel:monitor_nodes(false, [nodedown_reason])
        end,
    spawn_link(fun () ->
                       ok = apply_on_ssl_node(NH1, MonitorNodesFun)
               end),
    {SslPid, ready, Ref} = receive_any(),

    %% Setup connection and expect 'nodeup'
    pong = apply_on_ssl_node(NH1, fun () -> net_adm:ping(Node2) end),
    {SslPid, got, {nodeup, Node2, []}} = receive_any(),

    %% Disconnect and expect 'nodedown' with correct reason
    true = apply_on_ssl_node(NH1, fun () ->
                                          net_kernel:disconnect(Node2)
                                  end),
    {SslPid, got, {nodedown, Node2, [{nodedown_reason, disconnect}]}} = receive_any(),
    ok.


receive_any() ->
    receive M -> M end.

payload_test(NH1, NH2, _) ->
    Node1 = NH1#node_handle.nodename,
    Node2 = NH2#node_handle.nodename,

    pong = apply_on_ssl_node(NH1, fun () -> net_adm:ping(Node2) end),

    [Node2] = apply_on_ssl_node(NH1, fun () -> nodes() end),
    [Node1] = apply_on_ssl_node(NH2, fun () -> nodes() end),

    Ref = make_ref(),
    spawn(fun () ->
		  apply_on_ssl_node(
		    NH1,
		    fun () ->
			    send_to_tstcntrl(
                              {Ref, self()}),
			    receive
				{From, Msg} ->
				    From ! {self(), Msg}
			    end
		    end)
	  end),
     receive
	 {Ref, SslPid} ->
	     ok = apply_on_ssl_node(
		    NH2,
		    fun () ->
			    Msg = crypto:strong_rand_bytes(100000),
			    SslPid ! {self(), Msg},
			    receive
				{SslPid, Msg} ->
				    ok
			    end
		    end)
     end.

plain_options_test(NH1, NH2, _) ->
    Node1 = NH1#node_handle.nodename,
    Node2 = NH2#node_handle.nodename,

    pong = apply_on_ssl_node(NH1, fun () -> net_adm:ping(Node2) end),

    [Node2] = apply_on_ssl_node(NH1, fun () -> nodes() end),
    [Node1] = apply_on_ssl_node(NH2, fun () -> nodes() end).

plain_verify_options_test(NH1, NH2, _) ->
    Node1 = NH1#node_handle.nodename,
    Node2 = NH2#node_handle.nodename,

    pong = apply_on_ssl_node(NH1, fun () -> net_adm:ping(Node2) end),

    [Node2] = apply_on_ssl_node(NH1, fun () -> nodes() end),
    [Node1] = apply_on_ssl_node(NH2, fun () -> nodes() end).

do_listen_options(Prio, Config) ->
    PriorityString =
        maybe_quote_tuple_list("[{priority,"++integer_to_list(Prio)++"}]"),
    Options = "-kernel inet_dist_listen_options " ++ PriorityString,
    gen_dist_test(listen_options_test, [{prio, Prio}, {tls_only_basic_opts, Options} | Config]).

listen_options_test(NH1, NH2, Config) ->
    Prio = proplists:get_value(prio, Config),
    Node2 = NH2#node_handle.nodename,
    pong = apply_on_ssl_node(NH1, fun () -> net_adm:ping(Node2) end),

    PrioritiesNode1 =
	apply_on_ssl_node(NH1, fun get_socket_priorities/0),
    PrioritiesNode2 =
	apply_on_ssl_node(NH2, fun get_socket_priorities/0),

    Elevated1 = [P || P <- PrioritiesNode1, P =:= Prio],
    ct:pal("Elevated1: ~p~n", [Elevated1]),
    Elevated2 = [P || P <- PrioritiesNode2, P =:= Prio],
    ct:pal("Elevated2: ~p~n", [Elevated2]),
    [_|_] = Elevated1,
    [_|_] = Elevated2.

do_connect_options(Prio, Config) ->
    PriorityString =
        maybe_quote_tuple_list("[{priority,"++integer_to_list(Prio)++"}]"),
    Options = "-kernel inet_dist_connect_options " ++ PriorityString,
    gen_dist_test(connect_options_test,
		  [{prio, Prio}, {tls_only_basic_opts, Options} | Config]).

connect_options_test(NH1, NH2, Config) ->
    Prio = proplists:get_value(prio, Config),
    Node2 = NH2#node_handle.nodename,

    pong = apply_on_ssl_node(NH1, fun () -> net_adm:ping(Node2) end),

    PrioritiesNode1 =
	apply_on_ssl_node(NH1, fun get_socket_priorities/0),
    PrioritiesNode2 =
	apply_on_ssl_node(NH2, fun get_socket_priorities/0),

    Elevated1 = [P || P <- PrioritiesNode1, P =:= Prio],
    ct:pal("Elevated1: ~p~n", [Elevated1]),
    Elevated2 = [P || P <- PrioritiesNode2, P =:= Prio],
    ct:pal("Elevated2: ~p~n", [Elevated2]),
    %% Node 1 will have a socket with elevated priority.
    [_|_] = Elevated1,
    %% Node 2 will not, since it only applies to outbound connections.
    [] = Elevated2.

net_ticker_spawn_options_test(NH1, NH2, _Config) ->
    Node1 = NH1#node_handle.nodename,
    Node2 = NH2#node_handle.nodename,

    pong = apply_on_ssl_node(NH1, fun () -> net_adm:ping(Node2) end),

    FullsweepOptionNode1 =
        apply_on_ssl_node(NH1, fun () -> get_dist_util_fullsweep_option(Node2) end),
    FullsweepOptionNode2 =
        apply_on_ssl_node(NH2, fun () -> get_dist_util_fullsweep_option(Node1) end),

    ct:pal("FullsweepOptionNode1: ~p~n", [FullsweepOptionNode1]),
    ct:pal("FullsweepOptionNode2: ~p~n", [FullsweepOptionNode2]),

    0 = FullsweepOptionNode1,
    0 = FullsweepOptionNode2.


verify_fun_fail_test(NH1, NH2, _) ->
    Node2 = NH2#node_handle.nodename,

    pang = apply_on_ssl_node(NH1, fun () -> net_adm:ping(Node2) end),

    [] = apply_on_ssl_node(NH1, fun () -> nodes() end),
    [] = apply_on_ssl_node(NH2, fun () -> nodes() end),

    %% Check that the function ran on the client node.
    [{verify_fail_always_ran, true}] =
        apply_on_ssl_node(NH1, fun () -> ets:tab2list(verify_fun_ran) end),
    %% On the server node, it wouldn't run, because the server didn't
    %% request a certificate from the client.
    undefined =
        apply_on_ssl_node(NH2, fun () -> ets:info(verify_fun_ran) end).

verify_fun_pass_test(NH1, NH2, _) ->
    Node1 = NH1#node_handle.nodename,
    Node2 = NH2#node_handle.nodename,

    pong = apply_on_ssl_node(NH1, fun () -> net_adm:ping(Node2) end),

    [Node2] = apply_on_ssl_node(NH1, fun () -> nodes() end),
    [Node1] = apply_on_ssl_node(NH2, fun () -> nodes() end),

    %% Check that the function ran on the client node.
    [{verify_pass_always_ran, true}] =
        apply_on_ssl_node(NH1, fun () -> ets:tab2list(verify_fun_ran) end),
    %% Check that it ran on the server node as well.  The server
    %% requested and verified the client's certificate because we
    %% passed fail_if_no_peer_cert.
    [{verify_pass_always_ran, true}] =
        apply_on_ssl_node(NH2, fun () -> ets:tab2list(verify_fun_ran) end).


get_socket_priorities() ->
    [Priority ||
	{ok,[{priority,Priority}]} <-
	    [inet:getopts(Port, [priority]) || Port <- inet_ports()]].

get_dist_util_fullsweep_option(Node) ->
    SenderPid = proplists:get_value(Node, erlang:system_info(dist_ctrl)),
    {links, Links1} = erlang:process_info(SenderPid, links),
    {links, Links2} = erlang:process_info(whereis(net_kernel), links),
    [DistUtilPid] = [X || X <- Links1, Y <- Links2, X =:= Y],
    {garbage_collection, GCOpts} = erlang:process_info(DistUtilPid, garbage_collection),
    proplists:get_value(fullsweep_after, GCOpts).

inet_ports() ->
     [Port || Port <- erlang:ports(),
              element(2, erlang:port_info(Port, name)) =:= "tcp_inet"].

start_ssl_node(Config) ->
    start_ssl_node(Config, "").

start_ssl_node(Config, XArgs) ->
    Name = mk_node_name(Config),
    App = proplists:get_value(app_opts, Config),
    SSLOpts = setup_tls_opts(Config),
    start_ssl_node_name(
      Name, App ++ " " ++ SSLOpts ++ XArgs).


mk_node_name(Config) ->
    N = erlang:unique_integer([positive]),
    Case = proplists:get_value(testcase, Config),
    Hostname =
        case proplists:get_value(hostname, Config) of
            undefined -> "";
            Host -> "@" ++ Host
        end,
    atom_to_list(?MODULE)
	++ "_"
	++ atom_to_list(Case)
	++ "_"
	++ integer_to_list(N) ++ Hostname.


setup_certs(Config) ->
    PrivDir = proplists:get_value(priv_dir, Config),
    DerConfig = public_key:pkix_test_data(#{server_chain => #{root => rsa_root_key(1),
                                                              intermediates => [rsa_intermediate(2)],
                                                              peer => rsa_peer_key(3)},
                                            client_chain => #{root => rsa_root_key(1), 
                                                              intermediates => [rsa_intermediate(5)],
                                                              peer => rsa_peer_key(6)}}), 
    ClientBase = filename:join([PrivDir, "rsa"]),
    SeverBase =  filename:join([PrivDir, "rsa"]),   
   
    _  = x509_test:gen_pem_config_files(DerConfig, ClientBase, SeverBase).
    
setup_tls_opts(Config) ->    
    PrivDir = proplists:get_value(priv_dir, Config),
    SC = filename:join([PrivDir, "rsa_server_cert.pem"]),
    SK = filename:join([PrivDir, "rsa_server_key.pem"]),
    SCA = filename:join([PrivDir, "rsa_server_cacerts.pem"]),
    CC = filename:join([PrivDir, "rsa_client_cert.pem"]),
    CK = filename:join([PrivDir, "rsa_client_key.pem"]),
    CCA = filename:join([PrivDir, "rsa_client_cacerts.pem"]),

    case proplists:get_value(tls_only_basic_opts, Config, []) of
        [_|_] = BasicOpts -> %% No verify but server still need to have cert
            "-proto_dist inet_tls " ++ "-ssl_dist_opt server_certfile " ++ SC ++ " "
                ++ "-ssl_dist_opt server_keyfile " ++ SK ++ " " ++ BasicOpts;
        [] -> %% Verify
            TlsVerifyOpts = proplists:get_value(tls_verify_opts, Config, []),
             case TlsVerifyOpts of
                 [_|_] ->
                     "-proto_dist inet_tls "
                         ++ "-ssl_dist_opt server_certfile " ++ SC ++ " "
                         ++ "-ssl_dist_opt server_keyfile " ++ SK ++ " "
                         ++ "-ssl_dist_opt server_cacertfile " ++ SCA ++ " "
                         ++ "-ssl_dist_opt server_verify verify_peer "
                         ++ "-ssl_dist_opt server_fail_if_no_peer_cert true "
                         ++ "-ssl_dist_opt client_certfile " ++ CC ++ " "
                         ++ "-ssl_dist_opt client_keyfile " ++ CK ++ " "
                         ++ "-ssl_dist_opt client_cacertfile " ++ CCA ++ " "
                         ++ "-ssl_dist_opt client_verify verify_peer "
                         ++  TlsVerifyOpts;
                 _ ->  %% No verify, no extra opts
                     "-proto_dist inet_tls " ++ "-ssl_dist_opt server_certfile " ++ SC ++ " "
                         ++ "-ssl_dist_opt server_keyfile " ++ SK ++ " "
             end
    end.

%%
%% Start scripts etc...
%%

add_ssl_opts_config(Config) ->
    %%
    %% Start with boot scripts if on an installed system; otherwise,
    %% just point out ssl ebin with -pa.
    %%
    try
	Dir = proplists:get_value(priv_dir, Config),
	LibDir = code:lib_dir(),
	Apps = application:which_applications(),
	{value, {stdlib, _, STDL_VSN}} = lists:keysearch(stdlib, 1, Apps),
	{value, {kernel, _, KRNL_VSN}} = lists:keysearch(kernel, 1, Apps),
	StdlDir = filename:join([LibDir, "stdlib-" ++ STDL_VSN]),
	KrnlDir = filename:join([LibDir, "kernel-" ++ KRNL_VSN]),
	{ok, _} = file:read_file_info(StdlDir),
	{ok, _} = file:read_file_info(KrnlDir),
	SSL_VSN = vsn(ssl),
	VSN_CRYPTO = vsn(crypto),
	VSN_PKEY = vsn(public_key),

	SslDir = filename:join([LibDir, "ssl-" ++ SSL_VSN]),
	{ok, _} = file:read_file_info(SslDir),
	%% We are using an installed otp system, create the boot script.
	Script = filename:join(Dir, atom_to_list(?MODULE)),
	{ok, RelFile} = file:open(Script ++ ".rel", [write]),
        io:format(RelFile,
		  "{release, ~n"
		  " {\"SSL distribution test release\", \"~s\"},~n"
		  " {erts, \"~s\"},~n"
		  " [{kernel, \"~s\"},~n"
		  "  {stdlib, \"~s\"},~n"
		  "  {crypto, \"~s\"},~n"
		  "  {public_key, \"~s\"},~n"
		  "  {ssl, \"~s\"}]}.~n",
		  [case catch erlang:system_info(otp_release) of
		       {'EXIT', _} -> "R11B";
		       Rel -> Rel
		   end,
		   erlang:system_info(version),
		   KRNL_VSN,
		   STDL_VSN,
		   VSN_CRYPTO,
		   VSN_PKEY,
		   SSL_VSN]),
	ok = file:close(RelFile),
	ok = systools:make_script(Script, []),
	[{app_opts, "-boot " ++ Script} | Config]
    catch
	_:_ ->
	    [{app_opts, "-pa \"" ++ filename:dirname(code:which(ssl))++"\""}
	     | add_comment_config(
		 "Bootscript wasn't used since the test wasn't run on an "
		 "installed OTP system.",
		 Config)]
    end.

add_comment_config(Comment, []) ->
    [{comment, Comment}];
add_comment_config(Comment, [{comment, OldComment} | Cs]) ->
    [{comment, Comment ++ " " ++ OldComment} | Cs];
add_comment_config(Comment, [C|Cs]) ->
    [C|add_comment_config(Comment, Cs)].


success(Config) ->
    case lists:keysearch(comment, 1, Config) of
	{value, {comment, _} = Res} -> Res;
	_ -> ok
    end.

vsn(App) ->
    application:start(App),
    try
	{value,
	 {ssl,
	  _,
	  VSN}} = lists:keysearch(App,
				  1,
				  application:which_applications()),
	VSN
     after
	 application:stop(ssl)
     end.

verify_fail_always(_Certificate, _Event, _State) ->
    %% Create an ETS table, to record the fact that the verify function ran.
    %% Spawn a new process, to avoid the ETS table disappearing.
    Parent = self(),
    spawn(
      fun() ->
              catch ets:delete(verify_fun_ran),
	      ets:new(verify_fun_ran, [public, named_table]),
	      ets:insert(verify_fun_ran, {verify_fail_always_ran, true}),
	      Parent ! go_ahead,
	      timer:sleep(infinity)
      end),
    receive go_ahead -> ok end,
    {fail, bad_certificate}.

verify_pass_always(_Certificate, _Event, State) ->
    %% Create an ETS table, to record the fact that the verify function ran.
    %% Spawn a new process, to avoid the ETS table disappearing.
    Parent = self(),
    spawn(
      fun() ->
              catch ets:delete(verify_fun_ran),
	      ets:new(verify_fun_ran, [public, named_table]),
	      ets:insert(verify_fun_ran, {verify_pass_always_ran, true}),
	      Parent ! go_ahead,
	      timer:sleep(infinity)
      end),
    receive go_ahead -> ok end,
    {valid, State}.

localhost_ip(InetVer) ->
    {ok, Addr} = inet:getaddr(net_adm:localhost(), InetVer),
    Addr.

localhost_ipstr(InetVer) ->
    {ok, Addr} = inet:getaddr(net_adm:localhost(), InetVer),
    Str = case InetVer of
              inet ->
                  io_lib:format("{~p,~p,~p,~p}", erlang:tuple_to_list(Addr));
              inet6 ->
                  io_lib:format("{~p,~p,~p,~p,~p,~p,~p,~p}", erlang:tuple_to_list(Addr))
          end,
    Qouted = case os:type() of
                 {win32, _} -> Str;
                 _ -> [$',Str,$']
             end,
    lists:flatten(Qouted).

inet_ver() ->
    inet.

rsa_root_key(N) ->
    %% As rsa keygen is not guaranteed to be fast
    [{key, ssl_test_lib:hardcode_rsa_key(N)}].

rsa_peer_key(N) ->
    %% As rsa keygen is not guaranteed to be fast
    [{key, ssl_test_lib:hardcode_rsa_key(N)}].

rsa_intermediate(N) ->
    [{key, ssl_test_lib:hardcode_rsa_key(N)}].


maybe_quote_tuple_list(String) ->
    case os:cmd("echo [{a,1}]") of
        "[{a,1}]"++_ ->
            String;
        _ ->
            %% Some shells need quoting of [{}]
            "'"++String++"'"
    end.
