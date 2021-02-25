%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2007-2020. All Rights Reserved.
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
-module(ssl_session_SUITE).

-behaviour(ct_suite).

-include("tls_handshake.hrl").
-include("ssl_record.hrl").

-include_lib("common_test/include/ct.hrl").
-include_lib("public_key/include/public_key.hrl").

%% Common test
-export([all/0,
         groups/0,
         init_per_suite/1,
         init_per_group/2,
         init_per_testcase/2,
         end_per_suite/1,
         end_per_group/2,
         end_per_testcase/2
        ]).

%% Test cases
-export([reuse_session/0,
         reuse_session/1,
         reuse_session_expired/0,
         reuse_session_expired/1,
         server_does_not_want_to_reuse_session/0,
         server_does_not_want_to_reuse_session/1,
         explicit_session_reuse/0,
         explicit_session_reuse/1,
         no_reuses_session_server_restart_new_cert/0,
         no_reuses_session_server_restart_new_cert/1,
         no_reuses_session_server_restart_new_cert_file/0,
         no_reuses_session_server_restart_new_cert_file/1,
         session_table_stable_size_on_tcp_close/0,
         session_table_stable_size_on_tcp_close/1
        ]).

-define(SLEEP, 500).
-define(EXPIRE, 10).

%%--------------------------------------------------------------------
%% Common Test interface functions -----------------------------------
%%--------------------------------------------------------------------
all() -> 
    [
     {group, 'tlsv1.2'},
     {group, 'tlsv1.1'},
     {group, 'tlsv1'},
     {group, 'dtlsv1.2'},
     {group, 'dtlsv1'}
    ].

groups() ->
    [{'dtlsv1.2', [], session_tests()},
     {'dtlsv1', [], session_tests()},
     {'tlsv1.3', [], session_tests() ++ tls_session_tests()},
     {'tlsv1.2', [], session_tests() ++ tls_session_tests()},
     {'tlsv1.1', [], session_tests() ++ tls_session_tests()},
     {'tlsv1', [], session_tests() ++ tls_session_tests()}
    ].

session_tests() ->
    [reuse_session,
     reuse_session_expired,
     server_does_not_want_to_reuse_session,
     explicit_session_reuse,
     no_reuses_session_server_restart_new_cert,
     no_reuses_session_server_restart_new_cert_file].

tls_session_tests() ->
       [session_table_stable_size_on_tcp_close].

init_per_suite(Config0) ->
    catch crypto:stop(),
    try crypto:start() of
	ok ->
	    ssl_test_lib:clean_start(),
            Config = ssl_test_lib:make_rsa_cert(Config0),
            ssl_test_lib:make_rsa_1024_cert(Config)
    catch _:_ ->
	    {skip, "Crypto did not start"}
    end.

end_per_suite(_Config) ->
    ssl:stop(),
    application:stop(crypto).

init_per_group(GroupName, Config) ->
    ssl_test_lib:init_per_group(GroupName, Config). 

end_per_group(GroupName, Config) ->
  ssl_test_lib:end_per_group(GroupName, Config).

init_per_testcase(reuse_session_expired, Config)  ->
    Versions = ssl_test_lib:protocol_version(Config),
    ssl:stop(),
    application:load(ssl),    
    ssl_test_lib:clean_env(),
    ssl_test_lib:set_protocol_versions(Versions),
    application:set_env(ssl, session_lifetime, ?EXPIRE),
    ssl:start(),
    ssl_test_lib:ct_log_supported_protocol_versions(Config),
    ct:timetrap({seconds, 30}),
    Config;
init_per_testcase(_, Config)  ->
    ssl_test_lib:ct_log_supported_protocol_versions(Config),
    ct:timetrap({seconds, 15}),
    Config.

end_per_testcase(reuse_session_expired, Config) ->
    application:unset_env(ssl, session_lifetime),    
    Config;
end_per_testcase(_, Config) ->
    Config.

%%--------------------------------------------------------------------
%% Test Cases --------------------------------------------------------
%%--------------------------------------------------------------------
reuse_session() ->
    [{doc,"Test reuse of sessions (short handshake)"}].
reuse_session(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_rsa_verify_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_rsa_verify_opts, Config),
    Version = ssl_test_lib:protocol_version(Config),
    ssl_test_lib:reuse_session([{versions,[Version]} | ClientOpts], 
                               [{versions,[Version]} | ServerOpts], Config).
%%--------------------------------------------------------------------
reuse_session_expired() ->
    [{doc,"Test sessions is not reused when it has expired"}].
reuse_session_expired(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_rsa_verify_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_rsa_verify_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    
    Server0 =
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
				   {from, self()},
				   {mfa, {ssl_test_lib, no_result, []}},
				   {tcp_options, [{active, false}]},
				   {options, ServerOpts}]),
    Port0 = ssl_test_lib:inet_port(Server0),
    
    Client0 = ssl_test_lib:start_client([{node, ClientNode},
                                         {port, Port0}, {host, Hostname},
                                         {mfa, {ssl_test_lib, session_id, []}},
                                         {from, self()},  {options, [{reuse_sessions, save} | ClientOpts]}]),
    Server0 ! listen,
    
    Client1 = ssl_test_lib:start_client([{node, ClientNode},
                                         {port, Port0}, {host, Hostname},
                                         {mfa, {ssl_test_lib, session_id, []}},
                                         {from, self()},  {options, ClientOpts}]),    
    
    SID = receive
              {Client0, Id0} ->
                  Id0
          end,
       
    receive
        {Client1, SID} ->
            ok
    after ?SLEEP ->
              ct:fail(session_not_reused)
    end,
    
    Server0 ! listen,
    
    %% Make sure session is unregistered due to expiration
    ct:sleep((?EXPIRE*2)),

    make_sure_expired(Hostname, Port0, SID),
    
    Client2 =
	ssl_test_lib:start_client([{node, ClientNode}, 
				   {port, Port0}, {host, Hostname},
				   {mfa, {ssl_test_lib, session_id, []}},
				   {from, self()}, {options, ClientOpts}]),   
    receive
	{Client2, SID} ->
            end_per_testcase(?FUNCTION_NAME, Config),
	    ct:fail(session_reused_when_session_expired);
	{Client2, _} ->
	    ok
    end,
    process_flag(trap_exit, false),
    ssl_test_lib:close(Server0),
    ssl_test_lib:close(Client0),
    ssl_test_lib:close(Client1),
    ssl_test_lib:close(Client2).

make_sure_expired(Host, Port, Id) ->
    {status, _, _, StatusInfo} = sys:get_status(whereis(ssl_manager)),
    [_, _,_, _, Prop] = StatusInfo,
    State = ssl_test_lib:state(Prop),
    ClientCache = element(2, State),

    case ssl_session_cache:lookup(ClientCache, {{Host,  Port}, Id}) of
	undefined ->
   	   ok; 
	#session{is_resumable = false} ->
   	   ok;
	_ ->
	    ct:sleep(?SLEEP),
            make_sure_expired(Host, Port, Id)
    end.     

%%--------------------------------------------------------------------
server_does_not_want_to_reuse_session() ->
    [{doc,"Test reuse of sessions (short handshake)"}].
server_does_not_want_to_reuse_session(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_rsa_verify_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_rsa_verify_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = 
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
				   {from, self()},
		      {mfa, {ssl_test_lib, session_info_result, []}},
				   {options, [{reuse_session, fun(_,_,_,_) ->
								      false
							      end} | 
					      ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client0 =
	ssl_test_lib:start_client([{node, ClientNode}, 
		      {port, Port}, {host, Hostname},
			    {mfa, {ssl_test_lib, no_result, []}},
		      {from, self()},  {options, ClientOpts}]),   
    SessionInfo = 
	receive
	    {Server, Info} ->
		Info
	end,
       
    Server ! {listen, {mfa, {ssl_test_lib, no_result, []}}},
    
    %% Make sure session is registered
    ct:sleep(?SLEEP),

    Client1 =
	ssl_test_lib:start_client([{node, ClientNode}, 
		      {port, Port}, {host, Hostname},
		      {mfa, {ssl_test_lib, session_info_result, []}},
		      {from, self()},  {options, ClientOpts}]),    
    receive
	{Client1, SessionInfo} ->
	    ct:fail(session_reused_when_server_does_not_want_to);
	{Client1, _Other} ->
	   ok
    end,
    ssl_test_lib:close(Client0),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client1).

%%--------------------------------------------------------------------
explicit_session_reuse() ->
    [{doc,"Test {reuse_session, {ID, Data}}} option for explicit reuse of sessions not"
     " saved in the clients automated session reuse"}].
explicit_session_reuse(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_rsa_verify_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_rsa_verify_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server =
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
                                   {from, self()},
                                   {mfa, {ssl_test_lib, no_result, []}},
                                   {options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    {Client0, Client0Sock} =
	ssl_test_lib:start_client([{node, ClientNode},
                                   {port, Port}, {host, Hostname},
                                   {mfa, {ssl_test_lib, no_result, []}},
                                   {from, self()}, {options, [{reuse_sessions, false} | ClientOpts]},
                                   return_socket
                                  ]),

    {ok, [{session_id, ID}, {session_data, SessData}]} = ssl:connection_information(Client0Sock, [session_id, session_data]),

    ssl_test_lib:close(Client0),

    Server ! listen,

    {_, Client1Sock} =
	ssl_test_lib:start_client([{node, ClientNode},
                                   {port, Port}, {host, Hostname},
                                   {mfa, {ssl_test_lib, no_result, []}},
                                   {from, self()}, {options, [{reuse_session, {ID, SessData}} | ClientOpts]},
                                   return_socket]),

    {ok, [{session_id, ID}]} = ssl:connection_information(Client1Sock, [session_id]).


%%--------------------------------------------------------------------
no_reuses_session_server_restart_new_cert() ->
    [{doc,"Check that a session is not reused if the server is restarted with a new cert."}].
no_reuses_session_server_restart_new_cert(Config) when is_list(Config) ->

    ClientOpts = ssl_test_lib:ssl_options(client_rsa_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_rsa_verify_opts, Config),
    RSA1024ServerOpts = ssl_test_lib:ssl_options(server_rsa_1024_opts, Config),
    RSA1024ClientOpts = ssl_test_lib:ssl_options(client_rsa_1024_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server =
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
				   {from, self()},
		      {mfa, {ssl_test_lib, session_info_result, []}},
				   {options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client0 =
	ssl_test_lib:start_client([{node, ClientNode},
		      {port, Port}, {host, Hostname},
			    {mfa, {ssl_test_lib, no_result, []}},
		      {from, self()},  {options, [{reuse_sessions, save} | ClientOpts]}]),
    SessionInfo =
	receive
	    {Server, Info} ->
		Info
	end,

    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client0),

    Server1 =
	ssl_test_lib:start_server([{node, ServerNode}, {port, Port},
				   {from, self()},
		      {mfa, {ssl_test_lib, no_result, []}},
				   {options, [{reuseaddr, true} | RSA1024ServerOpts]}]),

    Client1 =
	ssl_test_lib:start_client([{node, ClientNode},
		      {port, Port}, {host, Hostname},
		      {mfa, {ssl_test_lib, session_info_result, []}},
		      {from, self()},  {options, RSA1024ClientOpts}]),
    receive
	{Client1, SessionInfo} ->
	    ct:fail(session_reused_when_server_has_new_cert);
	{Client1, _Other} ->
	   ok
    end,
    ssl_test_lib:close(Server1),
    ssl_test_lib:close(Client1).

%%--------------------------------------------------------------------
no_reuses_session_server_restart_new_cert_file() ->
    [{doc,"Check that a session is not reused if a server is restarted with a new "
      "cert contained in a file with the same name as the old cert."}].

no_reuses_session_server_restart_new_cert_file(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_rsa_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_rsa_verify_opts, Config),
    RSA1024ServerOpts = ssl_test_lib:ssl_options(server_rsa_1024_verify_opts, Config),
    PrivDir =  proplists:get_value(priv_dir, Config),

    NewServerOpts0 = ssl_test_lib:new_config(PrivDir, ServerOpts),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server =
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
				   {from, self()},
		      {mfa, {ssl_test_lib, session_info_result, []}},
				   {options, NewServerOpts0}]),
    Port = ssl_test_lib:inet_port(Server),
    Client0 =
	ssl_test_lib:start_client([{node, ClientNode},
		      {port, Port}, {host, Hostname},
			    {mfa, {ssl_test_lib, no_result, []}},
		      {from, self()},  {options, ClientOpts}]),
    SessionInfo =
	receive
	    {Server, Info} ->
		Info
	end,

    %% Make sure session is registered and we get
    %% new file time stamp when calling new_config!
    ct:sleep(?SLEEP* 2),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client0),

    ssl:clear_pem_cache(),

    NewServerOpts1 = ssl_test_lib:new_config(PrivDir, RSA1024ServerOpts),

    Server1 =
	ssl_test_lib:start_server([{node, ServerNode}, {port, Port},
				   {from, self()},
		      {mfa, {ssl_test_lib, no_result, []}},
				   {options,  [{reuseaddr, true} | NewServerOpts1]}]),
    Client1 =
	ssl_test_lib:start_client([{node, ClientNode},
		      {port, Port}, {host, Hostname},
		      {mfa, {ssl_test_lib, session_info_result, []}},
				   {from, self()},  {options, ClientOpts}]),
    receive
	{Client1, SessionInfo} ->
	    ct:fail(session_reused_when_server_has_new_cert);
	{Client1, _Other} ->
	   ok
    end,
    ssl_test_lib:close(Server1),
    ssl_test_lib:close(Client1).

session_table_stable_size_on_tcp_close() ->
      [{doc, "Check that new sessions are cleanup when connection is closed abruptly during first handshake"}].

session_table_stable_size_on_tcp_close(Config) when is_list(Config)->
    ServerOpts = ssl_test_lib:ssl_options(server_rsa_verify_opts, Config),
    {_, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
                                        {from, self()},
                                        {mfa, {ssl_test_lib, no_result, []}},
                                        {options,  [{reuseaddr, true} | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),

    Sup = whereis(ssl_server_session_cache_sup),

    %% Will only be one process, that is one server, in our test senario
    [{_, SessionCachePid, worker,[ssl_server_session_cache]}] = supervisor:which_children(Sup),


    {SessionCacheCb, SessionCacheDb} = session_cachce_info(SessionCachePid),

    N = SessionCacheCb:size(SessionCacheDb),

    faulty_client(Hostname, Port),
    check_table_did_not_grow(SessionCachePid, N).


%%--------------------------------------------------------------------
%% Internal functions ------------------------------------------------
%%--------------------------------------------------------------------
session_cachce_info(SessionCache) ->
    State = sys:get_state(SessionCache),
    ServerCacheDb = element(4, State),
    ServerCacheCb = element(2, State),
    {ServerCacheCb, ServerCacheDb}.


check_table_did_not_grow(SessionCachePid, N) ->
    {SessionCacheCb, SessionCacheDb} = session_cachce_info(SessionCachePid),
    ct:pal("Run ~p ~p", [SessionCacheCb, SessionCacheDb]),
    case catch SessionCacheCb:size(SessionCacheDb) of
        N ->
            ok;
        Size ->
            ct:fail({table_grew, [{expected, N}, {got, Size}]})
    end.

faulty_client(Host, Port) ->
    {ok, Sock} = gen_tcp:connect(Host, Port, [], 10000),
    Random = crypto:strong_rand_bytes(32),
    CH = client_hello(Random),
    CHBin = encode_client_hello(CH, Random),
    gen_tcp:send(Sock, CHBin),
    ct:sleep(100),
    gen_tcp:close(Sock).


encode_client_hello(CH, Random) ->
    HSBin = tls_handshake:encode_handshake(CH, {3,3}),
    CS = connection_states(Random),
    {Encoded, _} = tls_record:encode_handshake(HSBin, {3,3}, CS),
    Encoded.

client_hello(Random) ->
    CipherSuites = [<<0,255>>, <<"À,">>, <<"À0">>, <<"À$">>, <<"À(">>,
		    <<"À.">>, <<"À2">>, <<"À&">>, <<"À*">>, <<0,159>>,
		    <<0,163>>, <<0,107>>, <<0,106>>, <<"À+">>, <<"À/">>,
		    <<"À#">>, <<"À'">>, <<"À-">>, <<"À1">>, <<"À%">>,
		    <<"À)">>, <<0,158>>, <<0,162>>, <<0,103>>, <<0,64>>,
		    <<"À\n">>, <<192,20>>, <<0,57>>, <<0,56>>, <<192,5>>,
		    <<192,15>>, <<"À\t">>, <<192,19>>, <<0,51>>, <<0,50>>,
		    <<192,4>>, <<192,14>>],
    Extensions = #{alpn => undefined,
		   ec_point_formats =>
		       {ec_point_formats,
			[0]},
		   elliptic_curves =>
		       {elliptic_curves,
			[{1,3,132,0,39},
			 {1,3,132,0,38},
			 {1,3,132,0,35},
			 {1,3,36,3,3,2,
			  8,1,1,13},
			 {1,3,132,0,36},
			 {1,3,132,0,37},
			 {1,3,36,3,3,2,
			  8,1,1,11},
			 {1,3,132,0,34},
			 {1,3,132,0,16},
			 {1,3,132,0,17},
			 {1,3,36,3,3,2,
			  8,1,1,7},
			 {1,3,132,0,10},
			 {1,2,840,
			  10045,3,1,7},
			 {1,3,132,0,3},
			 {1,3,132,0,26},
			 {1,3,132,0,27},
			 {1,3,132,0,32},
			 {1,3,132,0,33},
			 {1,3,132,0,24},
			 {1,3,132,0,25},
			 {1,3,132,0,31},
			 {1,2,840,
			  10045,3,1,1},
			 {1,3,132,0,1},
			 {1,3,132,0,2},
			 {1,3,132,0,15},
			 {1,3,132,0,9},
			 {1,3,132,0,8},
			 {1,3,132,0,
			  30}]},
		   next_protocol_negotiation =>
		       undefined,
		   renegotiation_info =>
		       {renegotiation_info,
			undefined},
		   signature_algs =>
		       {hash_sign_algos,
			[{sha512,ecdsa},
			 {sha512,rsa},
			 {sha384,ecdsa},
			 {sha384,rsa},
			 {sha256,ecdsa},
			 {sha256,rsa},
			 {sha224,ecdsa},
			 {sha224,rsa},
			 {sha,ecdsa},
			 {sha,rsa},
			 {sha,dsa}]},
		   sni =>
		       {sni,
			"localhost"},
		   srp =>
		       undefined},

    #client_hello{client_version = {3,3},
		  random = Random,
		  session_id = crypto:strong_rand_bytes(32),
		  cipher_suites = CipherSuites,
		  compression_methods = [0],
		  extensions = Extensions
		 }.

connection_states(Random) ->
    #{current_write =>
          #{beast_mitigation => one_n_minus_one,cipher_state => undefined,
		 client_verify_data => undefined,compression_state => undefined,
		 mac_secret => undefined,secure_renegotiation => undefined,
            security_parameters =>
                #security_parameters{
                  cipher_suite = <<0,0>>,
                   connection_end = 1,
                   bulk_cipher_algorithm = 0,
                   cipher_type = 0,
                   iv_size = 0,
                   key_size = 0,
                   key_material_length = 0,
                   expanded_key_material_length = 0,
                   mac_algorithm = 0,
                   prf_algorithm = 0,
                   hash_size = 0,
                   compression_algorithm = 0,
                   master_secret = undefined,
                   resumption_master_secret = undefined,
                   client_random = Random,
                   server_random = undefined,
                   exportable = undefined},
            sequence_number => 0,server_verify_data => undefined,max_fragment_length => undefined}}.
