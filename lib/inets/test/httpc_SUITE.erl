%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 2004-2018. All Rights Reserved.
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

%% 
%% ct:run("../inets_test", httpc_SUITE).
%%

-module(httpc_SUITE).

-include_lib("kernel/include/file.hrl").
-include_lib("common_test/include/ct.hrl").
-include("inets_test_lib.hrl").
-include("http_internal.hrl").
-include("httpc_internal.hrl").
%% Note: This directive should only be used in test suites.
-compile(export_all).

-define(URL_START, "http://").
-define(TLS_URL_START, "https://").
-define(NOT_IN_USE_PORT, 8997).

%% Using hardcoded file path to keep it below 107 charaters
%% (maximum length supported by erlang)
-define(UNIX_SOCKET, "/tmp/inets_httpc_SUITE.sock").

-record(sslsocket, {fd = nil, pid = nil}).
%%--------------------------------------------------------------------
%% Common Test interface functions -----------------------------------
%%--------------------------------------------------------------------
suite() ->
    [{ct_hooks,[ts_install_cth]},
     {timetrap,{seconds, 30}}
    ].

all() ->
    [
     {group, http},
     {group, http_ipv6},
     {group, sim_http},
     {group, http_internal},
     {group, http_unix_socket},
     {group, https},
     {group, sim_https},
     {group, misc},
     {group, sim_mixed} % HTTP and HTTPS sim servers
    ].

groups() ->
    [
     {http, [], real_requests()},
     {http_ipv6, [], [request_options]},
     %% process_leak_on_keepalive is depending on stream_fun_server_close
     %% and it shall be the last test case in the suite otherwise cookie
     %% will fail.
     {sim_http, [], only_simulated() ++ server_closing_connection() ++ [process_leak_on_keepalive]},
     {http_internal, [], real_requests_esi()},
     {http_unix_socket, [], simulated_unix_socket()},
     {https, [], real_requests()},
     {sim_https, [], only_simulated()},
     {misc, [], misc()},
     {sim_mixed, [], sim_mixed()}
    ].

real_requests()->
    [
     head,
     get,
     get_query_string,
     post,
     delete,
     post_stream,
     patch,
     async,
     pipeline,
     persistent_connection,
     save_to_file,
     save_to_file_async,
     headers_as_is,
     page_does_not_exist,
     emulate_lower_versions,
     headers,
     headers_as_is,
     empty_body,
     stream,
     stream_to_pid,
     stream_through_fun,
     stream_through_mfa,
     streaming_error,
     inet_opts,
     invalid_headers,
     invalid_body,
     no_scheme,
     invalid_uri,
     undefined_port,
     binary_url
    ].

real_requests_esi() ->
    [slow_connection].

simulated_unix_socket() ->
    [unix_domain_socket].

only_simulated() ->
    [
     cookie,
     cookie_profile,
     empty_set_cookie,
     invalid_set_cookie,
     trace,
     stream_once,
     stream_single_chunk,
     stream_no_length,
     not_streamed_once,
     stream_large_not_200_or_206,
     no_content_204,
     tolerate_missing_CR,
     userinfo,
     bad_response,
     timeout_redirect,
     internal_server_error,
     invalid_http,
     invalid_chunk_size,
     headers_dummy,
     headers_with_obs_fold,
     headers_conflict_chunked_with_length,
     empty_response_header,
     remote_socket_close,
     remote_socket_close_async,
     transfer_encoding,
     transfer_encoding_identity,
     redirect_loop,
     redirect_moved_permanently,
     redirect_multiple_choises,
     redirect_found,
     redirect_see_other,
     redirect_temporary_redirect,
     redirect_relative_uri,
     port_in_host_header,
     redirect_port_in_host_header,
     relaxed,
     multipart_chunks,
     get_space,
     delete_no_body,
     post_with_content_type,
     stream_fun_server_close
    ].

server_closing_connection() ->
    [
     server_closing_connection_on_first_response,
     server_closing_connection_on_second_response
    ].

misc() ->
    [
     server_does_not_exist,
     timeout_memory_leak,
     wait_for_whole_response,
     post_204_chunked,
     head_chunked_empty_body,
     head_empty_body,
     chunkify_fun
    ].

sim_mixed() ->
    [
     redirect_http_to_https,
     redirect_relative_different_port
    ].

%%--------------------------------------------------------------------

init_per_suite(Config) ->
    PrivDir = proplists:get_value(priv_dir, Config),
    DataDir = proplists:get_value(data_dir, Config),
    inets_test_lib:start_apps([inets]),
    ServerRoot = filename:join(PrivDir, "server_root"),
    DocRoot = filename:join(ServerRoot, "htdocs"),
    setup_server_dirs(ServerRoot, DocRoot, DataDir),
    [{server_root, ServerRoot}, {doc_root, DocRoot}  | Config].

end_per_suite(Config) ->
    inets_test_lib:stop_apps([inets]),
    PrivDir = proplists:get_value(priv_dir, Config),
    inets_test_lib:del_dirs(PrivDir),
    ok.

%%--------------------------------------------------------------------
init_per_group(misc = Group, Config) ->
    start_apps(Group),
    Inet = inet_version(),
    ok = httpc:set_options([{ipfamily, Inet}]),
    Config;


init_per_group(Group, Config0) when Group =:= sim_https; Group =:= https;
                                    Group =:= sim_mixed ->
    catch crypto:stop(),
    try crypto:start() of
        ok ->
            start_apps(Group),
            do_init_per_group(Group, Config0)
    catch
        _:_ ->
            {skip, "Crypto did not start"}
    end;
init_per_group(http_unix_socket = Group, Config0) ->
    case os:type() of
        {win32,_} ->
            {skip, "Unix Domain Sockets are not supported on Windows"};
        _ ->
            file:delete(?UNIX_SOCKET),
            start_apps(Group),
            Config = proplists:delete(port, Config0),
            Port = server_start(Group, server_config(Group, Config)),
            [{port, Port} | Config]
    end;
init_per_group(http_ipv6 = Group, Config0) ->
    case is_ipv6_supported() of
        true ->
            start_apps(Group),
            Config = proplists:delete(port, Config0),
            Port = server_start(Group, server_config(Group, Config)),
            [{port, Port} | Config];
        false ->
            {skip, "Host does not support IPv6"}
     end;
init_per_group(Group, Config0) ->
    start_apps(Group),
    Config = proplists:delete(port, Config0),
    Port = server_start(Group, server_config(Group, Config)),
    [{port, Port} | Config].

end_per_group(http_unix_socket,_Config) ->
    file:delete(?UNIX_SOCKET),
    ok;
end_per_group(_, _Config) ->
    ok.

do_init_per_group(Group=sim_mixed, Config0) ->
    % The mixed group uses two server ports (http and https), so we use
    % different config names here.
    Config1 = init_ssl(Config0),
    Config2 = proplists:delete(http_port, proplists:delete(https_port, Config1)),
    {HttpPort, HttpsPort} = server_start(Group, server_config(sim_https, Config2)),
    [{http_port, HttpPort} | [{https_port, HttpsPort} | Config2]];
do_init_per_group(Group, Config0) ->
    Config1 =
        case Group of
            https ->
                init_ssl(Config0);
            sim_https ->
                init_ssl(Config0);
            _ ->
                Config0
        end,
    Config = proplists:delete(port, Config1),
    Port = server_start(Group, server_config(Group, Config)),
    [{port, Port} | Config].

init_ssl(Config) ->
    ClientFileBase = filename:join([proplists:get_value(priv_dir, Config), "client"]),
    ServerFileBase = filename:join([proplists:get_value(priv_dir, Config), "server"]),
    GenCertData =
        public_key:pkix_test_data(#{server_chain => 
                                        #{root => [{key, inets_test_lib:hardcode_rsa_key(1)}],
                                          intermediates => [[{key, inets_test_lib:hardcode_rsa_key(2)}]],
                                          peer => [{key, inets_test_lib:hardcode_rsa_key(3)}
                                                  ]},
                                    client_chain => 
                                        #{root => [{key, inets_test_lib:hardcode_rsa_key(4)}],
                                          intermediates => [[{key, inets_test_lib:hardcode_rsa_key(5)}]],
                                          peer => [{key, inets_test_lib:hardcode_rsa_key(6)}]}}),

    Conf = inets_test_lib:gen_pem_config_files(GenCertData, ClientFileBase, ServerFileBase),
    [{ssl_conf, Conf} | Config].

%%--------------------------------------------------------------------
init_per_testcase(pipeline, Config) ->
    inets:start(httpc, [{profile, pipeline}]),
    httpc:set_options([{pipeline_timeout, 50000},
                       {max_pipeline_length, 3}], pipeline),

    Config;
init_per_testcase(persistent_connection, Config) ->
    inets:start(httpc, [{profile, persistent}]),
    httpc:set_options([{keep_alive_timeout, 50000},
		       {max_keep_alive_length, 3}], persistent),

    Config;
init_per_testcase(wait_for_whole_response, Config) ->
    ct:timetrap({seconds, 60*3}),
    Config;
init_per_testcase(Case, Config) when Case == post;
				     Case == delete;
				     Case == post_delete;
				     Case == post_stream ->
    ct:timetrap({seconds, 30}),
    Config;
init_per_testcase(_Case, Config) ->
    Config.

end_per_testcase(pipeline, _Config) ->
    inets:stop(httpc, pipeline);
end_per_testcase(persistent_connection, _Config) ->
    inets:stop(httpc, persistent);
end_per_testcase(Case, Config)
  when Case == server_closing_connection_on_first_response;
       Case == server_closing_connection_on_second_response ->
    %% Test case uses at most one session.  Ensure no leftover
    %% sessions left behind.
    {_, Status} = proplists:lookup(tc_status, Config),
    ShallCleanup = case Status of
                       ok -> true;
                       {failed, _} -> true;
                       {skipped, _} -> false
                   end,
    if ShallCleanup =:= true ->
            httpc:request(url(group_name(Config), "/just_close.html", Config)),
            ok;
       true ->
            ct:pal("Not cleaning up because test case status was ~p", [Status]),
            ok
    end;

end_per_testcase(_Case, _Config) ->
    ok.



%%--------------------------------------------------------------------
%% Test Cases --------------------------------------------------------
%%--------------------------------------------------------------------

head() ->
    [{doc, "Test http head request against local server."}].

head(Config) when is_list(Config) ->
    Request  = {url(group_name(Config), "/dummy.html", Config), []},
    {ok, {{_,200,_}, [_ | _], []}} = httpc:request(head, Request, [], []).
%%--------------------------------------------------------------------
get() ->
    [{doc, "Test http get request against local server"}].
get(Config) when is_list(Config) ->
    Request  = {url(group_name(Config), "/dummy.html", Config), []},
    {ok, {{_,200,_}, [_ | _], Body = [_ | _]}} = httpc:request(get, Request, [], []),

    inets_test_lib:check_body(Body),

    {ok, {{_,200,_}, [_ | _], BinBody}} =  httpc:request(get, Request, [], [{body_format, binary}]),
    true = is_binary(BinBody).


get_query_string() ->
    [{doc, "Test http get request with query string against local server"}].
get_query_string(Config) when is_list(Config) ->
    Request  = {url(group_name(Config), "/dummy.html?foo=bar", Config), []},
    {ok, {{_,200,_}, [_ | _], Body = [_ | _]}} = httpc:request(get, Request, [], []),

    inets_test_lib:check_body(Body).

%%--------------------------------------------------------------------
get_space() ->
    [{"Test http get request with '%20' in the path of the URL."}].
get_space(Config) when is_list(Config) ->
    Request  = {url(group_name(Config), "/space%20.html", Config), []},
    {ok, {{_,200,_}, [_ | _], Body = [_ | _]}} = httpc:request(get, Request, [], []),

    inets_test_lib:check_body(Body).

%%--------------------------------------------------------------------
post() ->
    [{"Test http post request against local server. We do in this case "
     "only care about the client side of the the post. The server "
     "script will not actually use the post data."}].
post(Config) when is_list(Config) ->
    CGI = case test_server:os_type() of
	      {win32, _} ->
		  "/cgi-bin/cgi_echo.exe";
	      _ ->
		  "/cgi-bin/cgi_echo"
	  end,

     URL = url(group_name(Config), CGI, Config),

    %% Cgi-script expects the body length to be 100
    Body = lists:duplicate(100, "1"),

    {ok, {{_,200,_}, [_ | _], [_ | _]}} =
	httpc:request(post, {URL, [{"expect","100-continue"}],
			     "text/plain", Body}, [], []),

    {ok, {{_,504,_}, [_ | _], []}} =
	httpc:request(post, {URL, [{"expect","100-continue"}],
			     "text/plain", "foobar"}, [], []).
%%--------------------------------------------------------------------
delete() ->
    [{"Test http delete request against local server. We do in this case "
     "only care about the client side of the the delete. The server "
     "script will not actually use the delete data."}].
delete(Config) when is_list(Config) ->
    CGI = case test_server:os_type() of
          {win32, _} ->
          "/cgi-bin/cgi_echo.exe";
          _ ->
          "/cgi-bin/cgi_echo"
      end,

    URL  = url(group_name(Config), CGI, Config),
    Body = lists:duplicate(100, "1"),

    {ok, {{_,200,_}, [_ | _], [_ | _]}} =
    httpc:request(delete, {URL, [{"expect","100-continue"}],
                 "text/plain", Body}, [], []),

    {ok, {{_,504,_}, [_ | _], []}} =
    httpc:request(delete, {URL, [{"expect","100-continue"}],
                 "text/plain", "foobar"}, [], []).

%%--------------------------------------------------------------------
patch() ->
    [{"Test http patch request against local server. We do in this case "
     "only care about the client side of the the patch. The server "
     "script will not actually use the patch data."}].
patch(Config) when is_list(Config) ->
    CGI = case test_server:os_type() of
	      {win32, _} ->
		  "/cgi-bin/cgi_echo.exe";
	      _ ->
		  "/cgi-bin/cgi_echo"
	  end,

     URL = url(group_name(Config), CGI, Config),

    %% Cgi-script expects the body length to be 100
    Body = lists:duplicate(100, "1"),

    {ok, {{_,200,_}, [_ | _], [_ | _]}} =
	httpc:request(patch, {URL, [{"expect","100-continue"}],
			     "text/plain", Body}, [], []).

%%--------------------------------------------------------------------
post_stream() ->
    [{"Test streaming http post request against local server. "
     "We only care about the client side of the the post. "
     "The server script will not actually use the post data."}].
post_stream(Config) when is_list(Config) ->
    CGI = case test_server:os_type() of
	      {win32, _} ->
		  "/cgi-bin/cgi_echo.exe";
	      _ ->
		  "/cgi-bin/cgi_echo"
	  end,

     URL = url(group_name(Config), CGI, Config),

    %% Cgi-script expects the body length to be 100
    BodyFun = fun(0) ->
		      eof;
		 (LenLeft) ->
		      {ok, lists:duplicate(10, "1"), LenLeft - 10}
	      end,

    {ok, {{_,200,_}, [_ | _], [_ | _]}} =
	httpc:request(post, {URL,
			     [{"expect", "100-continue"},
			      {"content-length", "100"}],
			     "text/plain", {BodyFun, 100}}, [], []),

    {ok, {{_,504,_}, [_ | _], []}} =
	httpc:request(post, {URL,
			     [{"expect", "100-continue"},
			      {"content-length", "10"}],
			     "text/plain", {BodyFun, 10}}, [], []).

%%--------------------------------------------------------------------
trace() ->
    [{doc, "Perform a TRACE request."}].
trace(Config) when is_list(Config) ->
    Request  = {url(group_name(Config), "/trace.html", Config), []},
    case httpc:request(trace, Request, [], []) of
	{ok, {{_,200,_}, [_ | _], "TRACE /trace.html" ++ _}} ->
	    ok;
	 Other ->
	    ct:fail({unexpected, Other})
    end.  

%%--------------------------------------------------------------------

pipeline(Config) when is_list(Config) ->
    Request  = {url(group_name(Config), "/dummy.html", Config), []},
    {ok, _} = httpc:request(get, Request, [], [], pipeline),

    %% Make sure pipeline session is registerd
    ct:sleep(4000),
    keep_alive_requests(Request, pipeline).

%%--------------------------------------------------------------------

persistent_connection(Config) when is_list(Config) ->
    Request  = {url(group_name(Config), "/dummy.html", Config), []},
    {ok, _} = httpc:request(get, Request, [], [], persistent),

    %% Make sure pipeline session is registerd
    ct:sleep(4000),
    keep_alive_requests(Request, persistent).

%%-------------------------------------------------------------------------
async() ->
    [{doc, "Test an asynchrony http request."}].
async(Config) when is_list(Config) ->
    Request  = {url(group_name(Config), "/dummy.html", Config), []},

    {ok, RequestId} =
	httpc:request(get, Request, [], [{sync, false}]),
    Body =
	receive
	    {http, {RequestId, {{_, 200, _}, _, BinBody}}} ->
		BinBody;
	    {http, Msg} ->
		ct:fail(Msg)
	end,
    inets_test_lib:check_body(binary_to_list(Body)),

    {ok, NewRequestId} =
	httpc:request(get, Request, [], [{sync, false}]),
    ok = httpc:cancel_request(NewRequestId).

%%-------------------------------------------------------------------------
save_to_file() ->
    [{doc, "Test to save the http body to a file"}].
save_to_file(Config) when is_list(Config) ->
    PrivDir = proplists:get_value(priv_dir, Config),
    FilePath = filename:join(PrivDir, "dummy.html"),
    URL = url(group_name(Config), "/dummy.html", Config),
    Request = {URL, []},
    {ok, saved_to_file}
	= httpc:request(get, Request, [], [{stream, FilePath}]),
    {ok, Bin} = file:read_file(FilePath),
    {ok, {{_,200,_}, [_ | _], Body}} = httpc:request(URL),
    Bin == Body.

%%-------------------------------------------------------------------------
save_to_file_async() ->
    [{doc,"Test to save the http body to a file"}].
save_to_file_async(Config) when is_list(Config) ->
    PrivDir = proplists:get_value(priv_dir, Config),
    FilePath = filename:join(PrivDir, "dummy.html"),
    URL = url(group_name(Config), "/dummy.html", Config),
    Request = {URL, []},
    {ok, RequestId} = httpc:request(get, Request, [],
				    [{stream, FilePath},
				     {sync, false}]),
    receive
	{http, {RequestId, saved_to_file}} ->
	    ok;
	{http, Msg} ->
	    ct:fail(Msg)
    end,

    {ok, Bin} = file:read_file(FilePath),
    {ok, {{_,200,_}, [_ | _], Body}} = httpc:request(URL),
    Bin == Body.
%%-------------------------------------------------------------------------
stream() ->
    [{doc, "Test the option stream for asynchrony requests"}].
stream(Config) when is_list(Config) ->
    Request  = {url(group_name(Config), "/dummy.html", Config), []},
    stream_test(Request, {stream, self}).
%%-------------------------------------------------------------------------
stream_once() ->
    [{doc, "Test the option stream for asynchrony requests"}].
stream_once(Config) when is_list(Config) ->
    Request0  = {url(group_name(Config), "/dummy.html", Config), []},
    stream_test(Request0, {stream, {self, once}}),

    Request1  = {url(group_name(Config), "/once.html", Config), []},
    stream_test(Request1, {stream, {self, once}}),

    Request2  = {url(group_name(Config), "/once_chunked.html", Config), []},
    stream_test(Request2, {stream, {self, once}}).
%%-------------------------------------------------------------------------
stream_single_chunk() ->
    [{doc, "Test the option stream for asynchrony requests"}].
stream_single_chunk(Config) when is_list(Config) ->
    Request  = {url(group_name(Config), "/single_chunk.html", Config), []},
    stream_test(Request, {stream, self}).
%%-------------------------------------------------------------------------
stream_no_length() ->
    [{doc, "Test the option stream for asynchrony requests with HTTP 1.0 "
      "body end on closed connection" }].
stream_no_length(Config) when is_list(Config) ->
    Request1 = {url(group_name(Config), "/http_1_0_no_length_single.html", Config), []},
    stream_test(Request1, {stream, self}),
    Request2 = {url(group_name(Config), "/http_1_0_no_length_multiple.html", Config), []},
    stream_test(Request2, {stream, self}).
%%-------------------------------------------------------------------------
stream_large_not_200_or_206() ->
    [{doc, "Test the option stream for large responses with status codes "
      "other than 200 or 206" }].
stream_large_not_200_or_206(Config) when is_list(Config) ->
    Request = {url(group_name(Config), "/large_404_response.html", Config), []},
    {404, _} = not_streamed_test(Request, {stream, self}).
%%-------------------------------------------------------------------------
not_streamed_once() ->
    [{doc, "Test not streamed responses with once streaming"}].
not_streamed_once(Config) when is_list(Config) ->
    Request0 = {url(group_name(Config), "/404.html", Config), []},
    {404, _} = not_streamed_test(Request0, {stream, {self, once}}),
    Request1 = {url(group_name(Config), "/404_chunked.html", Config), []},
    {404, _} = not_streamed_test(Request1, {stream, {self, once}}).


%%-------------------------------------------------------------------------
redirect_multiple_choises() ->
    [{doc, "The user agent, selection of the most appropriate choice MAY "
      "be performed automatically."}].
redirect_multiple_choises(Config) when is_list(Config) ->
    URL300 = url(group_name(Config), "/300.html", Config),

    catch {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(get, {URL300, []}, [], []),

    {ok, {{_,300,_}, [_ | _], _}} =
	httpc:request(get, {URL300, []}, [{autoredirect, false}], []).
%%-------------------------------------------------------------------------
redirect_moved_permanently() ->
    [{doc, "The server SHOULD generate a Location header field in the response "
      "containing a preferred URI reference for the new permanent URI.  The user "
      "agent MAY use the Location field value for automatic redirection.  The server's " 
      "response payload usually contains a short hypertext note with a "
      "hyperlink to the new URI(s)."}].
redirect_moved_permanently(Config) when is_list(Config) ->

    URL301 = url(group_name(Config), "/301.html", Config),

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(get, {URL301, []}, [], []),

    {ok, {{_,200,_}, [_ | _], []}}
	= httpc:request(head, {URL301, []}, [], []),

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(post, {URL301, [],"text/plain", "foobar"},
			[], []).
%%-------------------------------------------------------------------------
redirect_found() ->
    [{doc, "The server SHOULD generate a Location header field in the response "
      "containing a URI reference for the different URI.  The user agent MAY "
      "use the Location field value for automatic redirection.  The server's "
      "response payload usually contains a short hypertext note with a "
      "hyperlink to the different URI(s)."}].
redirect_found(Config) when is_list(Config) ->

    URL302 = url(group_name(Config), "/302.html", Config),

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(get, {URL302, []}, [], []),

    {ok, {{_,200,_}, [_ | _], []}}
	= httpc:request(head, {URL302, []}, [], []),

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(post, {URL302, [],"text/plain", "foobar"},
			[], []).
%%-------------------------------------------------------------------------
redirect_see_other() ->
    [{doc, "The different URI SHOULD be given by the Location field in the response. "
      "Unless the request method was HEAD, the entity of the response SHOULD contain a short "
      "hypertext note with a hyperlink to the new URI(s)."}].
redirect_see_other(Config) when is_list(Config) ->

    URL303 =  url(group_name(Config), "/303.html", Config),

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(get, {URL303, []}, [], []),

    {ok, {{_,200,_}, [_ | _], []}}
	= httpc:request(head, {URL303, []}, [], []),

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(post, {URL303, [],"text/plain", "foobar"},
			[], []).
%%-------------------------------------------------------------------------
redirect_temporary_redirect() ->
    [{doc, "The server SHOULD generate a Location header field in the response "
      "containing a URI reference for the different URI.  The user agent MAY "
      "use the Location field value for automatic redirection.  The server's "
      "response payload usually contains a short hypertext note with a "
      "hyperlink to the different URI(s)."}].
redirect_temporary_redirect(Config) when is_list(Config) ->

    URL307 =  url(group_name(Config), "/307.html", Config),

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(get, {URL307, []}, [], []),

    {ok, {{_,200,_}, [_ | _], []}}
	= httpc:request(head, {URL307, []}, [], []),

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(post, {URL307, [],"text/plain", "foobar"},
			[], []).
%%-------------------------------------------------------------------------
redirect_relative_uri() ->
    [{doc, "The server SHOULD generate a Location header field in the response "
      "containing a preferred URI reference for the new permanent URI.  The user "
      "agent MAY use the Location field value for automatic redirection.  The server's "
      "response payload usually contains a short hypertext note with a "
      "hyperlink to the new URI(s)."}].
redirect_relative_uri(Config) when is_list(Config) ->

    URL301 = url(group_name(Config), "/301_rel_uri.html", Config),

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(get, {URL301, []}, [], []),

    {ok, {{_,200,_}, [_ | _], []}}
	= httpc:request(head, {URL301, []}, [], []),

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(post, {URL301, [],"text/plain", "foobar"},
			[], []).
%%-------------------------------------------------------------------------
redirect_loop() ->
    [{"doc, Test redirect loop detection"}].
redirect_loop(Config) when is_list(Config) ->

    URL =  url(group_name(Config), "/redirectloop.html", Config),

    {ok, {{_,300,_}, [_ | _], _}}
	= httpc:request(get, {URL, []}, [], []).

%%-------------------------------------------------------------------------
redirect_http_to_https() ->
    [{doc, "Test that a 30X redirect from one scheme to another is handled "
      "correctly."}].
redirect_http_to_https(Config) when is_list(Config) ->
    URL301 = mixed_url(http, "/301_custom_url.html", Config),
    TargetUrl = mixed_url(https, "/dummy.html", Config),
    Headers = [{"x-test-301-url", TargetUrl}],

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(get, {URL301, Headers}, [], []),

    {ok, {{_,200,_}, [_ | _], []}}
	= httpc:request(head, {URL301, Headers}, [], []),

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(post, {URL301, Headers, "text/plain", "foobar"},
			[], []).
%%-------------------------------------------------------------------------
redirect_relative_different_port() ->
    [{doc, "Test that a 30X redirect with a relative target, but different "
      "port, is handled correctly."}].
redirect_relative_different_port(Config) when is_list(Config) ->
    URL301 = mixed_url(http, "/301_custom_url.html", Config),

    % We need an extra server of the same protocol here, so spawn a new
    % HTTP-protocol one
    Port = server_start(sim_http, []),
    {ok, Host} = inet:gethostname(),
    % Prefix the URI with '/' instead of a scheme
    TargetUrl = "//" ++ Host ++ ":" ++ integer_to_list(Port) ++ "/dummy.html",
    Headers = [{"x-test-301-url", TargetUrl}],

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(get, {URL301, Headers}, [], []),

    {ok, {{_,200,_}, [_ | _], []}}
	= httpc:request(head, {URL301, Headers}, [], []),

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(post, {URL301, Headers, "text/plain", "foobar"},
			[], []).
%%-------------------------------------------------------------------------
cookie() ->
    [{doc, "Test cookies."}].
cookie(Config) when is_list(Config) ->
    ok = httpc:set_options([{cookies, enabled}]),

    Request0 = {url(group_name(Config), "/cookie.html", Config), []},

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(get, Request0, [], []),

    %% Populate table to be used by the "dummy" server
    ets:new(cookie, [named_table, public, set]),
    ets:insert(cookie, {cookies, true}),

    Request1 = {url(group_name(Config), "/", Config), []},

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(get, Request1, [], []),

   [{session_cookies, [_|_]}] = httpc:which_cookies(httpc:default_profile()),

    ets:delete(cookie),
    ok = httpc:set_options([{cookies, disabled}]).



%%-------------------------------------------------------------------------
cookie_profile() ->
    [{doc, "Test cookies on a non default profile."}].
cookie_profile(Config) when is_list(Config) ->   
    inets:start(httpc, [{profile, cookie_test}]),
    ok = httpc:set_options([{cookies, enabled}], cookie_test),

    Request0 = {url(group_name(Config), "/cookie.html", Config), []},

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(get, Request0, [], [], cookie_test),

    %% Populate table to be used by the "dummy" server
    ets:new(cookie, [named_table, public, set]),
    ets:insert(cookie, {cookies, true}),

    Request1 = {url(group_name(Config), "/", Config), []},

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(get, Request1, [], [], cookie_test),

    ets:delete(cookie),
    inets:stop(httpc, cookie_test).

%%-------------------------------------------------------------------------
empty_set_cookie() ->
    [{doc, "Test empty Set-Cookie header."}].
empty_set_cookie(Config) when is_list(Config) ->
    ok = httpc:set_options([{cookies, enabled}]),

    Request0 = {url(group_name(Config), "/empty_set_cookie.html", Config), []},

    {ok, {{_,200,_}, [_ | _], [_|_]}}
	= httpc:request(get, Request0, [], []),

    ok = httpc:set_options([{cookies, disabled}]).

%%-------------------------------------------------------------------------
invalid_set_cookie(doc) ->
    ["Test ignoring invalid Set-Cookie header"];
invalid_set_cookie(Config) when is_list(Config) ->
    ok = httpc:set_options([{cookies, enabled}]),

    URL = url(group_name(Config), "/invalid_set_cookie.html", Config),
    {ok, {{_,200,_}, [_|_], [_|_]}} =
        httpc:request(get, {URL, []}, [], []),

    ok = httpc:set_options([{cookies, disabled}]).

%%-------------------------------------------------------------------------
headers_as_is(doc) ->
    ["Test the option headers_as_is"];
headers_as_is(Config) when is_list(Config) ->
    URL = url(group_name(Config), "/dummy.html", Config),
    {ok, {{_,200,_}, [_|_], [_|_]}} =
	httpc:request(get, {URL, [{"Host", "localhost"},{"Te", ""}]},
		     [], [{headers_as_is, true}]),

    {ok, {{_,400,_}, [_|_], [_|_]}} =
	httpc:request(get, {URL, [{"Te", ""}]},[], [{headers_as_is, true}]).
%%-------------------------------------------------------------------------

userinfo(doc) ->
    [{doc, "Test user info e.i. http://user:passwd@host:port/"}];
userinfo(Config) when is_list(Config) ->
    
    {ok,Host} = inet:gethostname(),
    
    URLAuth = url(group_name(Config), "alladin:sesame@" ++ Host ++ ":","/userinfo.html", Config),

    {ok, {{_,200,_}, [_ | _], _}}
	= httpc:request(get, {URLAuth, []}, [], []),

    URLUnAuth = url(group_name(Config), "alladin:foobar@" ++ Host ++ ":","/userinfo.html", Config),

    {ok, {{_,401, _}, [_ | _], _}} =
	httpc:request(get, {URLUnAuth, []}, [], []).

%%-------------------------------------------------------------------------

page_does_not_exist(doc) ->
    ["Test that we get a 404 when the page is not found."];
page_does_not_exist(Config) when is_list(Config) ->
    URL = url(group_name(Config), "/doesnotexist.html", Config),
    {ok, {{_,404,_}, [_ | _], [_ | _]}}
	= httpc:request(get, {URL, []}, [], []).
%%-------------------------------------------------------------------------

streaming_error(doc) ->
    [{doc, "Only async requests can be stremed - Solves OTP-8056"}];

streaming_error(Config) when is_list(Config) ->
    Method      = get,
    Request     = {url(group_name(Config), "/dummy.html", Config), []},
    {error, streaming_error} = httpc:request(Method, Request,
					     [],  [{sync, true}, {stream, {self, once}}]),
    {error, streaming_error} = httpc:request(Method, Request,
					     [], [{sync, true}, {stream, self}]).
%%-------------------------------------------------------------------------

server_does_not_exist(doc) ->
    [{doc, "Test that we get an error message back when the server "
      "does note exist."}];
server_does_not_exist(Config) when is_list(Config) ->
    {error, _} =
	httpc:request(get, {"http://localhost:" ++
				integer_to_list(?NOT_IN_USE_PORT)
			    ++ "/", []},[], []).
%%-------------------------------------------------------------------------

no_content_204(doc) ->
    ["Test the case that the HTTP 204 no content header - Solves OTP 6982"];
no_content_204(Config) when is_list(Config) ->
    URL = url(group_name(Config), "/no_content.html", Config),
    {ok, {{_,204,_}, [], []}} = httpc:request(URL).

%%-------------------------------------------------------------------------

tolerate_missing_CR() ->
    [{doc, "Test the case that the HTTP server uses only LF instead of CRLF"
     "as delimitor. Solves OTP-7304"}].
tolerate_missing_CR(Config) when is_list(Config) ->
    URL = url(group_name(Config), "/missing_CR.html", Config),
    {ok, {{_,200,_}, _, [_ | _]}} = httpc:request(URL).
%%-------------------------------------------------------------------------

empty_body() ->
    [{doc, "An empty body was not returned directly. There was a delay for several"
      "seconds. Solves OTP-6243."}].
empty_body(Config) when is_list(Config) ->
    URL = url(group_name(Config), "/empty.html", Config),
    {ok, {{_,200,_}, [_ | _], []}} =
	httpc:request(get, {URL, []}, [], []).

%%-------------------------------------------------------------------------

transfer_encoding() ->
    [{doc, "Transfer encoding is case insensitive. Solves OTP-6807"}].
transfer_encoding(Config) when is_list(Config) ->
    URL = url(group_name(Config), "/capital_transfer_encoding.html", Config),
    {ok, {{_,200,_}, [_|_], [_ | _]}} = httpc:request(URL).

%%-------------------------------------------------------------------------

transfer_encoding_identity(Config) when is_list(Config) ->
    URL = url(group_name(Config), "/identity_transfer_encoding.html", Config),
    {ok, {{_,200,_}, [_|_], "IDENTITY"}} = httpc:request(URL).

%%-------------------------------------------------------------------------

empty_response_header() ->
    [{doc, "Test the case that the HTTP server does not send any headers. Solves OTP-6830"}].
empty_response_header(Config) when is_list(Config) ->
    URL = url(group_name(Config), "/no_headers.html", Config),
    {ok, {{_,200,_}, [], [_ | _]}} = httpc:request(URL).

%%-------------------------------------------------------------------------

bad_response(doc) ->
    [{doc, "Test what happens when the server does not follow the protocol"}];

bad_response(Config) when is_list(Config) ->

    URL0 = url(group_name(Config), "/missing_crlf.html", Config),
    URL1 = url(group_name(Config), "/wrong_statusline.html", Config),

    {error, timeout} = httpc:request(get, {URL0, []}, [{timeout, 400}], []),
    {error, Reason} = httpc:request(URL1),

    ct:print("Wrong Statusline: ~p~n", [Reason]).
%%-------------------------------------------------------------------------

timeout_redirect() ->
    [{doc, "Test that timeout works for redirects, check ERL-420."}].
timeout_redirect(Config) when is_list(Config) ->
    URL = url(group_name(Config), "/redirect_to_missing_crlf.html", Config),
    {error, timeout} = httpc:request(get, {URL, []}, [{timeout, 400}], []).

%%-------------------------------------------------------------------------

internal_server_error(doc) ->
    ["Test 50X codes"];
internal_server_error(Config) when is_list(Config) ->

    URL500 = url(group_name(Config), "/500.html", Config),

    {ok, {{_,500,_}, [_ | _], _}}
	= httpc:request(get, {URL500, []}, [], []),

    URL503 = url(group_name(Config), "/503.html", Config),

    %% Used to be able to make the service available after retry.
    ets:new(unavailable, [named_table, public, set]),
    ets:insert(unavailable, {503, unavailable}),

    {ok, {{_,200, _}, [_ | _], [_|_]}} =
	httpc:request(get, {URL503, []}, [], []),

    ets:insert(unavailable, {503, long_unavailable}),

    {ok, {{_,503, _}, [_ | _], [_|_]}} =
	httpc:request(get, {URL503, []}, [], []),

    ets:delete(unavailable).

%%-------------------------------------------------------------------------

invalid_http(doc) ->
    ["Test parse error"];
invalid_http(suite) ->
    [];
invalid_http(Config) when is_list(Config) ->

    URL = url(group_name(Config), "/invalid_http.html", Config),

    {error, {could_not_parse_as_http, _} = Reason} =
	httpc:request(get, {URL, []}, [], []),

    ct:print("Parse error: ~p ~n", [Reason]).

%%-------------------------------------------------------------------------

invalid_chunk_size(doc) ->
    ["Test parse error of HTTP chunk size"];
invalid_chunk_size(suite) ->
    [];
invalid_chunk_size(Config) when is_list(Config) ->

    URL = url(group_name(Config), "/invalid_chunk_size.html", Config),

    {error, {chunk_size, _} = Reason} =
	httpc:request(get, {URL, []}, [], []),

    ct:print("Parse error: ~p ~n", [Reason]).

%%-------------------------------------------------------------------------

emulate_lower_versions(doc) ->
    [{doc, "Perform request as 0.9 and 1.0 clients."}];
emulate_lower_versions(Config) when is_list(Config) ->

    URL = url(group_name(Config), "/dummy.html", Config),

    {ok, Body0} =
	httpc:request(get, {URL, []}, [{version, "HTTP/0.9"}], []),
    inets_test_lib:check_body(Body0),
    {ok, {{"HTTP/1.0", 200, _}, [_ | _], Body1 = [_ | _]}} =
	httpc:request(get, {URL, []}, [{version, "HTTP/1.0"}], []),
    inets_test_lib:check_body(Body1),
    {ok, {{"HTTP/1.1", 200, _}, [_ | _], Body2 = [_ | _]}} =
	httpc:request(get, {URL, []}, [{version, "HTTP/1.1"}], []),
    inets_test_lib:check_body(Body2).

%%-------------------------------------------------------------------------

relaxed(doc) ->
    ["Test relaxed mode"];
relaxed(Config) when is_list(Config) ->

    URL = url(group_name(Config), "/missing_reason_phrase.html", Config),

    {error, Reason} =
	httpc:request(get, {URL, []}, [{relaxed, false}], []),

    ct:print("Not relaxed: ~p~n", [Reason]),

    {ok, {{_, 200, _}, [_ | _], [_ | _]}} =
	httpc:request(get, {URL, []}, [{relaxed, true}], []).

%%-------------------------------------------------------------------------

headers() ->
    [{doc,"Use as many request headers as possible not used in proxy_headers"}].
headers(Config) when is_list(Config) ->

    URL = url(group_name(Config), "/dummy.html", Config),
    DocRoot = proplists:get_value(doc_root, Config),

    {ok, FileInfo} =
	file:read_file_info(filename:join([DocRoot,"dummy.html"])),
    CreatedSec =
	calendar:datetime_to_gregorian_seconds(
	  FileInfo#file_info.mtime),

    Mod = httpd_util:rfc1123_date(
	    calendar:gregorian_seconds_to_datetime(
	      CreatedSec-1)),

    Date = httpd_util:rfc1123_date({date(), time()}),

    {ok, {{_,200,_}, [_ | _], [_ | _]}} =
	httpc:request(get, {URL, [{"If-Modified-Since",
				   Mod},
				  {"From","webmaster@erlang.se"},
				  {"Date", Date}
				 ]}, [], []),

    Mod1 =  httpd_util:rfc1123_date(
	      calendar:gregorian_seconds_to_datetime(
		CreatedSec+1)),

    {ok, {{_,200,_}, [_ | _], [_ | _]}} =
	httpc:request(get, {URL, [{"If-UnModified-Since",
				   Mod1}
				 ]}, [], []),

    Tag = httpd_util:create_etag(FileInfo),


    {ok, {{_,200,_}, [_ | _], [_ | _]}} =
	httpc:request(get, {URL, [{"If-Match",
				   Tag}
				 ]}, [], []),

    {ok, {{_,200,_}, [_ | _], _}} =
	httpc:request(get, {URL, [{"If-None-Match",
				   "NotEtag,NeihterEtag"},
				  {"Connection", "Close"}
				 ]}, [], []).
%%-------------------------------------------------------------------------
headers_dummy() ->
    ["Test the code for handling headers we do not want/can send "
     "to a real server. Note it is not logical to send"
     "all of these headers together, we only want to test that"
     "the code for handling headers will not crash."].

headers_dummy(Config) when is_list(Config) ->

    URL = url(group_name(Config), "/dummy_headers.html", Config),

    Foo = http_chunk:encode("foobar") ++
	binary_to_list(http_chunk:encode_last()),
    FooBar =  Foo ++ "\r\n\r\nOther:inets_test\r\n\r\n",

    UserPasswd = base64:encode_to_string("Alladin:Sesame"),
    Auth = "Basic " ++ UserPasswd,

    %% The dummy server will ignore the headers, we only want to test
    %% that the client header-handling code. This would not
    %% be a vaild http-request!
    {ok, {{_,200,_}, [_ | _], [_|_]}} =
	httpc:request(post,
		     {URL,
		      [{"Via",
			"1.0 fred, 1.1 nowhere.com (Apache/1.1)"},
		       {"Warning","1#pseudonym foobar"},
		       {"Vary","*"},
		       {"Upgrade","HTTP/2.0"},
		       {"Pragma", "1#no-cache"},
		       {"Cache-Control", "no-cache"},
		       {"Connection", "close"},
		       {"Date", "Sat, 29 Oct 1994 19:43:31 GMT"},
		       {"Accept", " text/plain; q=0.5, text/html"},
		       {"Accept-Language", "en"},
		       {"Accept-Encoding","chunked"},
		       {"Accept-Charset", "ISO8859-1"},
		       {"Authorization", Auth},
		       {"Expect", "1#100-continue"},
		       {"User-Agent","inets"},
		       {"Transfer-Encoding","chunked"},
		       {"Range", " bytes=0-499"},
		       {"If-Range", "Sat, 29 Oct 1994 19:43:31 GMT"},
		       {"If-Match", "*"},
		       {"Content-Type", "text/plain"},
		       {"Content-Length", "6"},
		       {"Content-Language", "en"},
		       {"Content-Location", "http://www.foobar.se"},
		       {"Content-MD5",
			"104528739076276072743283077410617235478"},
		       {"Content-Range", "bytes 0-499/1234"},
		       {"Allow", "GET"},
		       {"Proxy-Authorization", Auth},
		       {"Expires", "Sat, 29 Oct 1994 19:43:31 GMT"},
		       {"Upgrade", "HTTP/2.0"},
		       {"Last-Modified", "Sat, 29 Oct 1994 19:43:31 GMT"},
		       {"Trailer","1#User-Agent"}
		      ], "text/plain", FooBar},
		     [], []).


%%-------------------------------------------------------------------------

headers_with_obs_fold(Config) when is_list(Config) ->
    Request = {url(group_name(Config), "/obs_folded_headers.html", Config), []},
    {ok, {{_,200,_}, Headers, [_|_]}} = httpc:request(get, Request, [], []),
    "a b" = proplists:get_value("folded", Headers).

%%-------------------------------------------------------------------------

headers_conflict_chunked_with_length(doc) ->
    ["Test the code for handling headers with both Transfer-Encoding"
     "and Content-Length which must receive error in default (not relaxed) mode"
     "and must receive successful response in relaxed mode"];
headers_conflict_chunked_with_length(Config) when is_list(Config) ->
    Request = {url(group_name(Config), "/headers_conflict_chunked_with_length.html", Config), []},
    {error, {could_not_parse_as_http, _}} = httpc:request(get, Request, [{relaxed, false}], []),
    {ok,{{_,200,_},_,_}} = httpc:request(get, Request, [{relaxed, true}], []),
    ok.

%%-------------------------------------------------------------------------

invalid_headers(Config) ->
    Request  = {url(group_name(Config), "/dummy.html", Config), [{"cookie", undefined}]},
    {error, _} = httpc:request(get, Request, [], []).

%%-------------------------------------------------------------------------

invalid_body(Config) ->
    URL = url(group_name(Config), "/dummy.html", Config),
    try 
	httpc:request(post, {URL, [], <<"text/plain">>, "foobar"},
		      [], []),
	ct:fail(accepted_invalid_input)
    catch 
	error:function_clause ->
	    ok
    end.

%%-------------------------------------------------------------------------

binary_url(Config) ->
    URL = uri_string:normalize(url(group_name(Config), "/dummy.html", Config)),
    {ok, _Response} = httpc:request(unicode:characters_to_binary(URL)).


%%-------------------------------------------------------------------------

no_scheme(_Config) ->
    {error,{bad_scheme,"ftp"}} = httpc:request("ftp://foobar"),
    {error,{no_scheme}} = httpc:request("//foobar"),
    {error,{no_scheme}} = httpc:request("foobar"),
    ok.


%%-------------------------------------------------------------------------

invalid_uri(Config) ->
    URL = url(group_name(Config), "/bar?x[]=a", Config),
    {error, invalid_uri} = httpc:request(URL),
    ok.

%%-------------------------------------------------------------------------

undefined_port(_Config) ->
    {error, {failed_connect, _Reason}} = httpc:request("http://:"),
    ok.


%%-------------------------------------------------------------------------
remote_socket_close(Config) when is_list(Config) ->
    URL = url(group_name(Config), "/just_close.html", Config),
    {error, socket_closed_remotely} = httpc:request(URL).


%%-------------------------------------------------------------------------

remote_socket_close_async(Config) when is_list(Config) ->
    Request = {url(group_name(Config), "/just_close.html", Config), []},
    Options     = [{sync, false}],
    Profile     = httpc:default_profile(),
    {ok, RequestId} =
	httpc:request(get, Request, [], Options, Profile),
    receive
	{http, {RequestId, {error, socket_closed_remotely}}} ->
	    ok
    end.

%%-------------------------------------------------------------------------

process_leak_on_keepalive(Config) ->
    Request  = {url(group_name(Config), "/dummy.html", Config), []},
    HttpcHandlers0 = supervisor:which_children(httpc_handler_sup),
    {ok, {{_, 200, _}, _, Body}} = httpc:request(get, Request, [], []),
    HttpcHandlers1 = supervisor:which_children(httpc_handler_sup),
    ChildrenCount = supervisor:count_children(httpc_handler_sup),
    %% Assuming that the new handler will be selected for keep_alive
    %% which could not be the case if other handlers existed
    [{undefined, Pid, worker, [httpc_handler]}] =
        ordsets:to_list(
          ordsets:subtract(ordsets:from_list(HttpcHandlers1),
                           ordsets:from_list(HttpcHandlers0))),
    State = sys:get_state(Pid),
    #session{socket=Socket} = element(3, State),
    gen_tcp:close(Socket),

    {ok, {{_, 200, _}, _, Body}} = httpc:request(get, Request, [], []),
    %% bad handler with the closed socket should get replaced by
    %% the new one, so children count should stay the same
    ChildrenCount = supervisor:count_children(httpc_handler_sup),
    ok.

%%-------------------------------------------------------------------------

stream_to_pid(Config) when is_list(Config) ->
    ReceiverPid = create_receiver(pid),
    Receiver    = ReceiverPid,

    stream(ReceiverPid, Receiver, Config),

    stop_receiver(ReceiverPid).

stream_through_fun(Config) when is_list(Config) ->
    ReceiverPid = create_receiver(function),
    Receiver = stream_deliver_fun(ReceiverPid),

    stream(ReceiverPid, Receiver, Config),

    stop_receiver(ReceiverPid).

stream_through_mfa(Config) when is_list(Config) ->
    ReceiverPid = create_receiver(mfa),
    Receiver    = {?MODULE, stream_deliver, [mfa, ReceiverPid]},

    stream(ReceiverPid, Receiver, Config).

%%-------------------------------------------------------------------------

inet_opts(Config) when is_list(Config) ->
    MaxSessions      = 5,
    MaxKeepAlive     = 10,
    KeepAliveTimeout = timer:minutes(2),
    ConnOptions = [{max_sessions,          MaxSessions},
		   {max_keep_alive_length, MaxKeepAlive},
		   {keep_alive_timeout,    KeepAliveTimeout}],
    httpc:set_options(ConnOptions),

    Request  = {url(group_name(Config), "/dummy.html", Config), []},
    Timeout      = timer:seconds(1),
    ConnTimeout  = Timeout + timer:seconds(1),
    HttpOptions = [{timeout, Timeout}, {connect_timeout, ConnTimeout}],
    Options0     = [{socket_opts, [{tos,    87},
				   {recbuf, 16#FFFF},
				   {sndbuf, 16#FFFF}]}],

    {ok, {{_,200,_}, [_ | _], ReplyBody0 = [_ | _]}} = httpc:request(get, Request, HttpOptions, Options0),
    inets_test_lib:check_body(ReplyBody0),

    Options1 = [{socket_opts, [{tos,    84},
			       {recbuf, 32#1FFFF},
			       {sndbuf, 32#1FFFF}]}],
    {ok, {{_,200,_}, [_ | _], ReplyBody1 = [_ | _]}} = httpc:request(get, Request, [], Options1),
    inets_test_lib:check_body(ReplyBody1).

%%-------------------------------------------------------------------------
port_in_host_header(Config) when is_list(Config) ->

    Request = {url(group_name(Config), "/ensure_host_header_with_port.html", Config), []},
    {ok, {{_, 200, _}, _, Body}} = httpc:request(get, Request, [], []),
    inets_test_lib:check_body(Body).
%%-------------------------------------------------------------------------
redirect_port_in_host_header(Config) when is_list(Config) ->

    Request = {url(group_name(Config), "/redirect_ensure_host_header_with_port.html", Config), []},
    {ok, {{_, 200, _}, _, Body}} = httpc:request(get, Request, [], []),
    inets_test_lib:check_body(Body).

%%-------------------------------------------------------------------------
multipart_chunks(Config) when is_list(Config) ->
    Request = {url(group_name(Config), "/multipart_chunks.html", Config), []},
    {ok, Ref} = httpc:request(get, Request, [], [{sync, false}, {stream, self}]),
    ok = receive_stream_n(Ref, 10),
    httpc:cancel_request(Ref).
    
%%-------------------------------------------------------------------------
timeout_memory_leak() ->
    [{doc, "Check OTP-8739"}].
timeout_memory_leak(Config) when is_list(Config) ->
    {_DummyServerPid, Port} = otp_8739_dummy_server(),
    {ok,Host} = inet:gethostname(),
    Request = {?URL_START ++ Host ++ ":" ++ integer_to_list(Port) ++ "/dummy.html", []},
    case httpc:request(get, Request, [{connect_timeout, 500}, {timeout, 1}], [{sync, true}]) of
	{error, timeout} ->
	    %% And now we check the size of the handler db
	    Info = httpc:info(),
	    ct:print("Info: ~p", [Info]),
	    {value, {handlers, Handlers}} =
		lists:keysearch(handlers, 1, Info),
	    case Handlers of
		[] ->
		    ok;
		_ ->
		    ct:fail({unexpected_handlers, Handlers})
	    end;
	Unexpected ->
	    ct:fail({unexpected, Unexpected})
    end.

%%--------------------------------------------------------------------

wait_for_whole_response() ->
    [{doc, "Check OTP-8154"}].
wait_for_whole_response(Config) when is_list(Config) ->

     ReqSeqNumServer = start_sequence_number_server(),
     RespSeqNumServer = start_sequence_number_server(),
     {ok, Server, Port} = start_slow_server(RespSeqNumServer),
     Clients = run_clients(105, Port, ReqSeqNumServer),
     ok = wait4clients(Clients, timer:minutes(3)),
     Server ! shutdown,
     RespSeqNumServer ! shutdown,
     ReqSeqNumServer ! shutdown.

%%--------------------------------------------------------------------
post_204_chunked() ->
    [{doc,"Test that chunked encoded 204 responses do not freeze the http client"}].
post_204_chunked(_Config) ->
    Msg = "HTTP/1.1 204 No Content\r\n" ++
        "Date: Thu, 23 Aug 2018 13:36:29 GMT\r\n" ++
        "Content-Type: text/html\r\n" ++
        "Server: inets/6.5.2.3\r\n" ++
        "Cache-Control: no-cache\r\n" ++
        "Pragma: no-cache\r\n" ++
        "Expires: Fri, 24 Aug 2018 07:49:35 GMT\r\n" ++
        "Transfer-Encoding: chunked\r\n" ++
        "\r\n",
    Chunk = "0\r\n\r\n",

    {ok, ListenSocket} = gen_tcp:listen(0, [{active,once}, binary]),
    {ok,{_,Port}} = inet:sockname(ListenSocket),
    spawn(fun () -> custom_server(Msg, Chunk, ListenSocket,
                                  fun custom_receive/0) end),

    {ok,Host} = inet:gethostname(),
    End = "/cgi-bin/erl/httpd_example:post_204",
    URL = ?URL_START ++ Host ++ ":" ++ integer_to_list(Port) ++ End,
    {ok, _} = httpc:request(post, {URL, [], "text/html", []}, [], []),
    timer:sleep(500),
    %% Second request times out in the faulty case.
    {ok, _} = httpc:request(post, {URL, [], "text/html", []}, [], []).

custom_receive() ->
    receive
        {tcp, _, Msg} ->
            ct:log("Message received: ~p", [Msg])
    after
        1000 ->
            ct:fail("Timeout: did not recive packet")
    end.

%% Custom server is used to test special cases when using chunked encoding
custom_server(Msg, Chunk, ListenSocket, ReceiveFun) ->
    {ok, Accept} = gen_tcp:accept(ListenSocket),
    ReceiveFun(),
    send_response(Msg, Chunk, Accept),
    custom_server_loop(Msg, Chunk, Accept, ReceiveFun).

custom_server_loop(Msg, Chunk, Accept, ReceiveFun) ->
    ReceiveFun(),
    send_response(Msg, Chunk, Accept),
    custom_server_loop(Msg, Chunk, Accept, ReceiveFun).

send_response(Msg, Chunk, Socket) ->
    inet:setopts(Socket, [{active, once}]),
    gen_tcp:send(Socket, Msg),
    timer:sleep(250),
    gen_tcp:send(Socket, Chunk).

%%--------------------------------------------------------------------
head_chunked_empty_body() ->
    [{doc,"Test that HTTP responses (to HEAD requests) with 'Transfer-Encoding: chunked' and empty chunked-encoded body do not freeze the http client"}].
head_chunked_empty_body(_Config) ->
    Msg = "HTTP/1.1 403 Forbidden\r\n" ++
        "Date: Thu, 23 Aug 2018 13:36:29 GMT\r\n" ++
        "Content-Type: text/html\r\n" ++
        "Server: inets/6.5.2.3\r\n" ++
        "Cache-Control: no-cache\r\n" ++
        "Pragma: no-cache\r\n" ++
        "Expires: Fri, 24 Aug 2018 07:49:35 GMT\r\n" ++
        "Transfer-Encoding: chunked\r\n" ++
        "\r\n",
    Chunk = "0\r\n\r\n",

    {ok, ListenSocket} = gen_tcp:listen(0, [{active,once}, binary]),
    {ok,{_,Port}} = inet:sockname(ListenSocket),
    spawn(fun () -> custom_server(Msg, Chunk, ListenSocket,
                                  fun custom_receive/0) end),
    {ok,Host} = inet:gethostname(),
    URL = ?URL_START ++ Host ++ ":" ++ integer_to_list(Port),
    {ok, _} = httpc:request(head, {URL, []}, [], []),
    timer:sleep(500),
    %% Second request times out in the faulty case.
    {ok, _} = httpc:request(head, {URL, []}, [], []).

%%--------------------------------------------------------------------
head_empty_body() ->
    [{doc,"Test that HTTP responses (to HEAD requests) with 'Transfer-Encoding: chunked' and empty body do not freeze the http client"}].
head_empty_body(_Config) ->
    Msg = "HTTP/1.1 403 Forbidden\r\n" ++
        "Date: Thu, 23 Aug 2018 13:36:29 GMT\r\n" ++
        "Content-Type: text/html\r\n" ++
        "Server: inets/6.5.2.3\r\n" ++
        "Cache-Control: no-cache\r\n" ++
        "Pragma: no-cache\r\n" ++
        "Expires: Fri, 24 Aug 2018 07:49:35 GMT\r\n" ++
        "Transfer-Encoding: chunked\r\n" ++
        "\r\n",
    NoChunk = "", %% Do not chunk encode!

    {ok, ListenSocket} = gen_tcp:listen(0, [{active,once}, binary]),
    {ok,{_,Port}} = inet:sockname(ListenSocket),
    spawn(fun () -> custom_server(Msg, NoChunk, ListenSocket,
                                  fun custom_receive/0) end),
    {ok,Host} = inet:gethostname(),
    URL = ?URL_START ++ Host ++ ":" ++ integer_to_list(Port),
    {ok, _} = httpc:request(head, {URL, []}, [], []),
    timer:sleep(500),
    %% Second request times out in the faulty case.
    {ok, _} = httpc:request(head, {URL, []}, [], []).

%%--------------------------------------------------------------------
chunkify_fun() ->
    [{doc,"Test that a chunked encoded request does not include the 'Content-Length header'"}].
chunkify_fun(_Config) ->
    Msg = "HTTP/1.1 204 No Content\r\n" ++
        "Date: Thu, 23 Aug 2018 13:36:29 GMT\r\n" ++
        "Content-Type: text/html\r\n" ++
        "Server: inets/6.5.2.3\r\n" ++
        "Cache-Control: no-cache\r\n" ++
        "Pragma: no-cache\r\n" ++
        "Expires: Fri, 24 Aug 2018 07:49:35 GMT\r\n" ++
        "Transfer-Encoding: chunked\r\n" ++
        "\r\n",
    Chunk = "0\r\n\r\n",

    {ok, ListenSocket} = gen_tcp:listen(0, [{active,once}, binary]),
    {ok,{_,Port}} = inet:sockname(ListenSocket),
    spawn(fun () -> custom_server(Msg, Chunk, ListenSocket,
                                  fun chunkify_receive/0) end),

    {ok,Host} = inet:gethostname(),
    End = "/cgi-bin/erl/httpd_example",
    URL = ?URL_START ++ Host ++ ":" ++ integer_to_list(Port) ++ End,
    Fun = fun(_) -> {ok,<<1>>,eof_body} end,
    Acc = start,

    {ok, {{_,204,_}, _, _}} =
        httpc:request(put, {URL, [], "text/html", {chunkify, Fun, Acc}}, [], []).

chunkify_receive() ->
    Error = "HTTP/1.1 500 Internal Server Error\r\n" ++
        "Content-Length: 0\r\n\r\n",
    receive
        {tcp, Port, Msg} ->
            case binary:match(Msg, <<"content-length">>) of
                nomatch ->
                    ct:log("Message received: ~s", [binary_to_list(Msg)]);
                {_, _} ->
                    ct:log("Message received (negative): ~s", [binary_to_list(Msg)]),
                    %% Signal a testcase failure when the received HTTP request
                    %% contains a 'Content-Length' header.
                    gen_tcp:send(Port, Error),
                    ct:fail("Content-Length present in received headers.")
            end
    after
        1000 ->
            ct:fail("Timeout: did not recive packet")
    end.
%%--------------------------------------------------------------------
stream_fun_server_close() ->
    [{doc, "Test that an error msg is received when using a receiver fun as stream target"}].
stream_fun_server_close(Config) when is_list(Config) ->
    Request  = {url(group_name(Config), "/delay_close.html", Config), []},
    Self = self(),
    Fun = fun(X) -> Self ! X end,
    {ok, RequestId} = httpc:request(get, Request, [], [{sync, false}, {receiver, Fun}]),
    receive
        {RequestId, {error, Reason}} ->
            ct:pal("Close ~p", [Reason]),
            ok
    after 13000 ->
            ct:fail(did_not_receive_close)
    end. 

%%--------------------------------------------------------------------
server_closing_connection_on_first_response() ->
    [{doc, "Client receives \"Connection: close\" on first response."
      "A client that receives a \"close\" connection option MUST cease sending"
      "requests on that connection and close the connection after reading"
      "the response message containing the \"close\""}].
server_closing_connection_on_first_response(Config) when is_list(Config) ->
    ReqSrvSendOctFun =
        fun(V, U, S) ->
                {ok, {{V, S, _}, Headers0, []}} =
                    httpc:request(get, {U, []}, [{version, V}], []),
                {_, SendOctStr} =
                    proplists:lookup("x-socket-stat-send-oct", Headers0),
                list_to_integer(SendOctStr)
        end,
    V = "HTTP/1.1",
    Url0 = url(group_name(Config), "/http_1_1_send_oct.html", Config),
    Url1 = url(group_name(Config), "/http_1_1_send_oct_and_connection_close.html", Config),
    %% Test case assumes at most one reusable past session.
    _ = ReqSrvSendOctFun(V, Url1, 204),
    0 = ReqSrvSendOctFun(V, Url0, 204),
    ok.

%%--------------------------------------------------------------------
server_closing_connection_on_second_response() ->
    [{doc, "Client receives \"Connection: close\" on second response."
      "A client that receives a \"close\" connection option MUST cease sending"
      "requests on that connection and close the connection after reading"
      "the response message containing the \"close\""}].
server_closing_connection_on_second_response(Config) when is_list(Config) ->
    ReqSrvSendOctFun =
        fun(V, U, S) ->
                {ok, {{V, S, _}, Headers0, []}} =
                    httpc:request(get, {U, []}, [{version, V}], []),
                {_, SendOctStr} =
                    proplists:lookup("x-socket-stat-send-oct", Headers0),
                list_to_integer(SendOctStr)
        end,
    V = "HTTP/1.1",
    Url0 = url(group_name(Config), "/http_1_1_send_oct.html", Config),
    Url1 = url(group_name(Config), "/http_1_1_send_oct_and_connection_close.html", Config),
    %% Test case assumes no reusable past sessions.
    SendOct0 = 0 = ReqSrvSendOctFun(V, Url0, 204),
    case ReqSrvSendOctFun(V, Url1, 204) of SendOct1 when SendOct1 > SendOct0 -> ok end,
    0 = ReqSrvSendOctFun(V, Url0, 204),
    ok.

%%--------------------------------------------------------------------
slow_connection() ->
    [{doc, "Test that a request on a slow keep-alive connection won't crash the httpc_manager"}].
slow_connection(Config) when is_list(Config) ->
    BodyFun = fun(0) -> eof;
                 (LenLeft) -> timer:sleep(1000),
                              {ok, lists:duplicate(10, "1"), LenLeft - 10}
              end,
    Request  = {url(group_name(Config), "/httpc_SUITE:esi_post", Config),
                [{"content-length", "100"}],
                "text/plain",
                {BodyFun, 100}},
    {ok, _} = httpc:request(post, Request, [], []),
    %% Second request causes a crash if gen_server timeout is not set to infinity
    %% in httpc_handler.
    {ok, _} = httpc:request(post, Request, [], []).

%%-------------------------------------------------------------------------
unix_domain_socket() ->
    [{"doc, Test HTTP requests over unix domain sockets"}].
unix_domain_socket(Config) when is_list(Config) ->

    URL = "http:///v1/kv/foo",

    {ok,[{unix_socket,?UNIX_SOCKET}]} =
        httpc:get_options([unix_socket]),
    {ok, {{_,200,_}, [_ | _], _}}
	= httpc:request(put, {URL, [], [], ""}, [], []),
    {ok, {{_,200,_}, [_ | _], _}}
        = httpc:request(get, {URL, []}, [], []).

%%-------------------------------------------------------------------------
delete_no_body(doc) ->
    ["Test that a DELETE request without Body does not send a Content-Type header - Solves ERL-536"];
delete_no_body(Config) when is_list(Config) ->
    URL = url(group_name(Config), "/delete_no_body.html", Config),
    %% Simulated server replies 500 if 'Content-Type' header is present
    {ok, {{_,200,_}, _, _}} =
        httpc:request(delete, {URL, []}, [], []),
    {ok, {{_,500,_}, _, _}} =
        httpc:request(delete, {URL, [], "text/plain", "TEST"}, [], []).

%%--------------------------------------------------------------------
post_with_content_type(doc) ->
    ["Test that a POST request with explicit 'Content-Type' does not drop the 'Content-Type' header - Solves ERL-736"];
post_with_content_type(Config) when is_list(Config) ->
    URL = url(group_name(Config), "/delete_no_body.html", Config),
    %% Simulated server replies 500 if 'Content-Type' header is present
    {ok, {{_,500,_}, _, _}} =
        httpc:request(post, {URL, [], "application/x-www-form-urlencoded", ""}, [], []).

%%--------------------------------------------------------------------
request_options() ->
    [{require, ipv6_hosts},
     {doc, "Test http get request with socket options against local server (IPv6)"}].
request_options(Config) when is_list(Config) ->
    Request  = {url(group_name(Config), "/dummy.html", Config), []},
    {ok, {{_,200,_}, [_ | _], _ = [_ | _]}} = httpc:request(get, Request, [],
                                                            [{socket_opts,[{ipfamily, inet6}]}]),
    {error,{failed_connect,_ }} = httpc:request(get, Request, [], []).



%%--------------------------------------------------------------------
%% Internal Functions ------------------------------------------------
%%--------------------------------------------------------------------
stream(ReceiverPid, Receiver, Config) ->
    Request  = {url(group_name(Config), "/dummy.html", Config), []},
    Options     = [{sync, false}, {receiver, Receiver}],
    {ok, RequestId} =
	 httpc:request(get, Request, [], Options),
     Body =
	 receive
	     {reply, ReceiverPid, {RequestId, {{_, 200, _}, _, B}}} ->
		 B;
	     {reply, ReceiverPid, Msg} ->
		 ct:fail(Msg);
	     {bad_reply, ReceiverPid, Msg} ->
		 ct:fail(Msg)
	 end,

     inets_test_lib:check_body(binary_to_list(Body)).

create_receiver(Type) ->
    Parent = self(),
    Receiver = fun() -> receiver(Type, Parent) end,
    spawn_link(Receiver).

stop_receiver(Pid) ->
    Pid ! {stop, self()}.

receiver(Type, Parent) ->
    receive
	{stop, Parent} ->
	    ok;
	{http, ReplyInfo} when (Type =:= pid) ->
	    Parent ! {reply, self(), ReplyInfo},
	    receiver(Type, Parent);

	{Type, ReplyInfo} ->
	    Parent ! {reply, self(), ReplyInfo},
	    receiver(Type, Parent);

	Crap ->
	    Parent ! {reply, self(), {bad_reply, Crap}},
	    receiver(Type, Parent)
    end.

stream_deliver_fun(ReceiverPid) ->
    fun(ReplyInfo) -> stream_deliver(ReplyInfo, function, ReceiverPid) end.

stream_deliver(ReplyInfo, Type, ReceiverPid) ->
    ReceiverPid ! {Type, ReplyInfo},
    ok.

stream_test(Request, To) ->
    {ok, {{_,200,_}, [_ | _], Body}} =
	httpc:request(get, Request, [], []),
    {ok, RequestId} =
	httpc:request(get, Request, [], [{sync, false}, To]),

    StreamedBody =
	receive
	    {http, {RequestId, stream_start, _Headers}} ->
		receive_streamed_body(RequestId, <<>>);
	    {http, {RequestId, stream_start, _Headers, Pid}}  ->
		receive_streamed_body(RequestId, <<>>, Pid);
	    {http, Msg} ->
		ct:fail(Msg)
	end,

    Body = binary_to_list(StreamedBody).

not_streamed_test(Request, To) ->
    {ok, {{_,Code,_}, [_ | _], Body}} =
	httpc:request(get, Request, [], [{body_format, binary}]),
    {ok, RequestId} =
	httpc:request(get, Request, [], [{body_format, binary}, {sync, false}, To]),

    receive
	{http, {RequestId, {{_, Code, _}, _Headers, Body}}} ->
	    {Code, binary_to_list(Body)};
	{http, Msg} ->
	    ct:fail(Msg)
    end.

url(http, End, Config) ->
    Port = proplists:get_value(port, Config),
    {ok,Host} = inet:gethostname(),
    ?URL_START ++ Host ++ ":" ++ integer_to_list(Port) ++ End;
url(http_ipv6, End, Config) ->
    Port = proplists:get_value(port, Config),
    ?URL_START ++ "[::1]" ++ ":" ++ integer_to_list(Port) ++ End;
url(https, End, Config) ->
    Port = proplists:get_value(port, Config),
    {ok,Host} = inet:gethostname(),
    ?TLS_URL_START ++ Host ++ ":" ++ integer_to_list(Port) ++ End;
url(sim_http, End, Config) ->
    url(http, End, Config);
url(http_internal, End, Config) ->
    url(http, End, Config);
url(sim_https, End, Config) ->
    url(https, End, Config).
url(http, UserInfo, End, Config) ->
    Port = proplists:get_value(port, Config),
    ?URL_START ++ UserInfo ++ integer_to_list(Port) ++ End;
url(https, UserInfo, End, Config) ->
    Port = proplists:get_value(port, Config),
    ?TLS_URL_START ++ UserInfo ++ integer_to_list(Port) ++ End;
url(sim_http, UserInfo, End, Config) ->
    url(http, UserInfo, End, Config);
url(sim_https, UserInfo, End, Config) ->
    url(https, UserInfo, End, Config).

% Only for use in the `mixed` test group, where both http and https
% URLs are possible.
mixed_url(http, End, Config) ->
    mixed_url(http_port, End, Config);
mixed_url(https, End, Config) ->
    mixed_url(https_port, End, Config);
mixed_url(PortType, End, Config) ->
    Port = proplists:get_value(PortType, Config),
    {ok, Host} = inet:gethostname(),
    Start = case PortType of
        http_port -> ?URL_START;
        https_port -> ?TLS_URL_START
    end,
    Start ++ Host ++ ":" ++ integer_to_list(Port) ++ End.

group_name(Config) ->
    GroupProp = proplists:get_value(tc_group_properties, Config),
    proplists:get_value(name, GroupProp).

server_start(sim_http, _) ->
    Inet = inet_version(),
    ok = httpc:set_options([{ipfamily, Inet},{unix_socket, undefined}]),
    {_Pid, Port} = http_test_lib:dummy_server(ip_comm, Inet, [{content_cb, ?MODULE}]),
    Port;

server_start(sim_https, SslConfig) ->
    Inet = inet_version(),
    ok = httpc:set_options([{ipfamily, Inet},{unix_socket, undefined}]),
    {_Pid, Port} = http_test_lib:dummy_server(ssl, Inet, [{ssl, SslConfig}, {content_cb, ?MODULE}]),
    Port;

server_start(http_unix_socket, Config) ->
    Inet = local,
    Socket = proplists:get_value(unix_socket, Config),
    ok = httpc:set_options([{ipfamily, Inet},{unix_socket, Socket}]),
    {_Pid, Port} = http_test_lib:dummy_server(unix_socket, Inet, [{content_cb, ?MODULE},
                                                                  {unix_socket, Socket}]),
    Port;
server_start(http_ipv6, HttpdConfig) ->
    {ok, Pid} = inets:start(httpd, HttpdConfig),
    Serv = inets:services_info(),
    {value, {_, _, Info}} = lists:keysearch(Pid, 2, Serv),
    proplists:get_value(port, Info);
server_start(sim_mixed, Config) ->
    % For the mixed http/https case, we start two servers and return both ports.
    {server_start(sim_http, []), server_start(sim_https, Config)};
server_start(_, HttpdConfig) ->
    {ok, Pid} = inets:start(httpd, HttpdConfig),
    Serv = inets:services_info(),
    ok = httpc:set_options([{ipfamily, inet_version()},{unix_socket, undefined}]),
    {value, {_, _, Info}} = lists:keysearch(Pid, 2, Serv),
    proplists:get_value(port, Info).

server_config(http, Config) ->
    ServerRoot = proplists:get_value(server_root, Config),
    [{port, 0},
     {server_name,"httpc_test"},
     {server_root, ServerRoot},
     {document_root, proplists:get_value(doc_root, Config)},
     {bind_address, any},
     {ipfamily, inet_version()},
     {mime_type, "text/plain"},
     {script_alias, {"/cgi-bin/", filename:join(ServerRoot, "cgi-bin") ++ "/"}}
    ];
server_config(http_ipv6, Config) ->
    ServerRoot = proplists:get_value(server_root, Config),
    [{port, 0},
     {server_name,"httpc_test"},
     {server_root, ServerRoot},
     {document_root, proplists:get_value(doc_root, Config)},
     {bind_address, {0,0,0,0,0,0,0,1}},
     {ipfamily, inet6},
     {mime_type, "text/plain"},
     {script_alias, {"/cgi-bin/", filename:join(ServerRoot, "cgi-bin") ++ "/"}}
    ];
server_config(http_internal, Config) ->
    ServerRoot = proplists:get_value(server_root, Config),
    [{port, 0},
     {server_name,"httpc_test"},
     {server_root, ServerRoot},
     {document_root, proplists:get_value(doc_root, Config)},
     {bind_address, any},
     {ipfamily, inet_version()},
     {mime_type, "text/plain"},
     {erl_script_alias, {"", [httpc_SUITE]}}
    ];
server_config(https, Config) ->
    [{socket_type, {essl, ssl_config(Config)}} | server_config(http, Config)];
server_config(sim_https, Config) ->
    ssl_config(Config);
server_config(http_unix_socket, _Config) ->
    Socket = ?UNIX_SOCKET,
    [{unix_socket, Socket}];

server_config(_, _) ->
    [].

esi_post(Sid, _Env, _Input) ->
    mod_esi:deliver(Sid, ["OK"]).

start_apps(https) ->
    inets_test_lib:start_apps([crypto, public_key, ssl]);
start_apps(sim_https) ->
    inets_test_lib:start_apps([crypto, public_key, ssl]);
start_apps(sim_mixed) ->
    inets_test_lib:start_apps([crypto, public_key, ssl]);
start_apps(_) ->
    ok.

ssl_config(Config) ->
    SSLConf = proplists:get_value(ssl_conf, Config),
    proplists:get_value(server_config, SSLConf).

setup_server_dirs(ServerRoot, DocRoot, DataDir) ->   
    CgiDir =  filename:join(ServerRoot, "cgi-bin"),
    ok = file:make_dir(ServerRoot),
    ok = file:make_dir(DocRoot),
    ok = file:make_dir(CgiDir),

    {ok, Files} = file:list_dir(DataDir),
    
    lists:foreach(fun(File) -> case lists:suffix(".html", File) of
				   true ->
				       inets_test_lib:copy_file(File, 
								DataDir, 
								DocRoot);
				   false ->
				       ok
			       end
		  end, Files),
    
    Cgi = case test_server:os_type() of
	      {win32, _} ->
		  "cgi_echo.exe";
	      _ ->
		  "cgi_echo"
	  end,
    
    inets_test_lib:copy_file(Cgi, DataDir, CgiDir),
    AbsCgi = filename:join([CgiDir, Cgi]),
    {ok, FileInfo} = file:read_file_info(AbsCgi),
    ok = file:write_file_info(AbsCgi, FileInfo#file_info{mode = 8#00755}).


keep_alive_requests(Request, Profile) ->
    {ok, RequestIdA0} =
	httpc:request(get, Request, [], [{sync, false}], Profile),
    {ok, RequestIdA1} =
	httpc:request(get, Request, [], [{sync, false}], Profile),
    {ok, RequestIdA2} =
	httpc:request(get, Request, [], [{sync, false}], Profile),

    receive_replys([RequestIdA0, RequestIdA1, RequestIdA2]),

    {ok, RequestIdB0} =
	httpc:request(get, Request, [], [{sync, false}], Profile),
    {ok, RequestIdB1} =
	httpc:request(get, Request, [], [{sync, false}], Profile),
    {ok, RequestIdB2} =
	httpc:request(get, Request, [], [{sync, false}], Profile),

    ok = httpc:cancel_request(RequestIdB1, Profile),
    ct:print("Cancel ~p~n", [RequestIdB1]),
    receive_replys([RequestIdB0, RequestIdB2]).


receive_replys([]) ->
    ok;
receive_replys([ID|IDs]) ->
    receive
	{http, {ID, {{_, 200, _}, [_|_], _}}} ->
	    receive_replys(IDs);
	{http, {Other, {{_, 200, _}, [_|_], _}}} ->
	    ct:pal({recived_canceld_id, Other})
    end.



inet_version() ->
    inet. %% Just run inet for now
    %% case gen_tcp:listen(0,[inet6]) of
    %% 	{ok, S} ->
    %% 	    gen_tcp:close(S),
    %% 	    inet6;
    %% 	_ ->
    %% 	    inet
    %%end.

dummy_server(Inet) ->
    dummy_server(self(), ip_comm, Inet, []).

dummy_server(SocketType, Inet, Extra) ->
    dummy_server(self(), SocketType, Inet, Extra).

dummy_server(Caller, SocketType, Inet, Extra) ->
    Args = [Caller, SocketType, Inet, Extra],
    Pid = spawn(httpc_SUITE, dummy_server_init, Args),
    receive
	{port, Port} ->
	    {Pid, Port}
    end.

dummy_server_init(Caller, ip_comm, Inet, _) ->
    BaseOpts = [binary, {packet, 0}, {reuseaddr,true}, {keepalive, true}, {active, false}], 
    {ok, ListenSocket} = gen_tcp:listen(0, [Inet | BaseOpts]),
    {ok, Port} = inet:port(ListenSocket),
    Caller ! {port, Port},
    dummy_ipcomm_server_loop({httpd_request, parse, [[{max_uri,    ?HTTP_MAX_URI_SIZE},
						      {max_header, ?HTTP_MAX_HEADER_SIZE},
						      {max_version,?HTTP_MAX_VERSION_STRING}, 
						      {max_method, ?HTTP_MAX_METHOD_STRING},
						      {max_content_length, ?HTTP_MAX_CONTENT_LENGTH},
						      {customize, httpd_custom}
						     ]]},
    [], ListenSocket);

dummy_server_init(Caller, ssl, Inet, SSLOptions) ->
    BaseOpts = [binary, {reuseaddr,true}, {active, false} |
	        SSLOptions], 
    dummy_ssl_server_init(Caller, BaseOpts, Inet).

dummy_ssl_server_init(Caller, BaseOpts, Inet) ->
    {ok, ListenSocket} = ssl:listen(0, [Inet | BaseOpts]),
    {ok, {_, Port}} = ssl:sockname(ListenSocket),
    Caller ! {port, Port},
    dummy_ssl_server_loop({httpd_request, parse, [[{max_uri,    ?HTTP_MAX_URI_SIZE},
						   {max_method, ?HTTP_MAX_METHOD_STRING},
						   {max_version,?HTTP_MAX_VERSION_STRING}, 
						   {max_method, ?HTTP_MAX_METHOD_STRING},
						   {max_content_length, ?HTTP_MAX_CONTENT_LENGTH},
						   {customize, httpd_custom}
						  ]]},
			  [], ListenSocket).

dummy_ipcomm_server_loop(MFA, Handlers, ListenSocket) ->
    receive
	stop ->
	    lists:foreach(fun(Handler) -> Handler ! stop end, Handlers);
	{stop, From} ->
	    Stopper = fun(Handler) -> Handler ! stop end, 
	    lists:foreach(Stopper, Handlers),
	    From ! {stopped, self()}
    after 0 ->
	    {ok, Socket} = gen_tcp:accept(ListenSocket),
	    HandlerPid  = dummy_request_handler(MFA, Socket),
	    gen_tcp:controlling_process(Socket, HandlerPid),
	    HandlerPid ! ipcomm_controller,
	    dummy_ipcomm_server_loop(MFA, [HandlerPid | Handlers],
				     ListenSocket)
    end.

dummy_ssl_server_loop(MFA, Handlers, ListenSocket) ->
    receive
	stop ->
	    lists:foreach(fun(Handler) -> Handler ! stop end, Handlers);
	{stop, From} ->
	    Stopper = fun(Handler) -> Handler ! stop end, 
	    lists:foreach(Stopper, Handlers),
	    From ! {stopped, self()}
    after 0 ->
	    {ok, Socket} = ssl:transport_accept(ListenSocket),
	    ok = ssl:ssl_accept(Socket, infinity),
	    HandlerPid  = dummy_request_handler(MFA, Socket),
	    ssl:controlling_process(Socket, HandlerPid),
	    HandlerPid ! ssl_controller,
	    dummy_ssl_server_loop(MFA, [HandlerPid | Handlers],
				  ListenSocket)
    end.

dummy_request_handler(MFA, Socket) ->
    spawn(httpc_SUITE, dummy_request_handler_init, [MFA, Socket]).

dummy_request_handler_init(MFA, Socket) ->
    SockType = 
	receive 
	    ipcomm_controller ->
		inet:setopts(Socket, [{active, true}]),
		ip_comm;
	    ssl_controller ->
		ssl:setopts(Socket, [{active, true}]),
		ssl
	end,
    dummy_request_handler_loop(MFA, SockType, Socket).
    
dummy_request_handler_loop({Module, Function, Args}, SockType, Socket) ->
    receive 
	{Proto, _, Data} when (Proto =:= tcp) orelse (Proto =:= ssl) ->
	    case handle_request(Module, Function, [Data | Args], Socket) of
		stop when Proto =:= tcp ->
		    gen_tcp:close(Socket);
		stop when Proto =:= ssl ->
		    ssl:close(Socket);
		NewMFA ->
		    dummy_request_handler_loop(NewMFA, SockType, Socket)
	    end;
	stop when SockType =:= ip_comm ->
	    gen_tcp:close(Socket);
	stop when SockType =:= ssl ->
	    ssl:close(Socket)
    end.

handle_request(Module, Function, Args, Socket) ->
    case Module:Function(Args) of
	{ok, Result} ->
	    case handle_http_msg(Result, Socket, []) of
		stop ->
		    stop;
		<<>> ->
		    {httpd_request, parse, [[{max_uri,?HTTP_MAX_URI_SIZE},
					     {max_header, ?HTTP_MAX_HEADER_SIZE},
					     {max_version,?HTTP_MAX_VERSION_STRING}, 
					     {max_method, ?HTTP_MAX_METHOD_STRING},
					     {max_content_length, ?HTTP_MAX_CONTENT_LENGTH},
					     {customize, httpd_custom}
					    ]]};
		Data ->	
		    handle_request(httpd_request, parse, 
				   [Data, [{max_uri,    ?HTTP_MAX_URI_SIZE},
					   {max_header, ?HTTP_MAX_HEADER_SIZE},
					    {max_version,?HTTP_MAX_VERSION_STRING}, 
					    {max_method, ?HTTP_MAX_METHOD_STRING},
					    {max_content_length, ?HTTP_MAX_CONTENT_LENGTH},
					   {customize, httpd_custom}
					  ]], Socket)
	    end;
	NewMFA ->
	    NewMFA
    end.

handle_http_msg({Method, RelUri, _, {_, Headers}, Body}, Socket, _) ->
    ct:print("Request: ~p ~p", [Method, RelUri]),

    NextRequest = 
	case RelUri of
	    "/dummy_headers.html" ->
		<<>>;
	    "/no_headers.html" ->
		stop;
	    "/just_close.html" ->
		stop;
	    _ ->
		ContentLength = content_length(Headers),    
		case size(Body) - ContentLength of
		    0 ->
			<<>>;
		    _ ->
			<<_BodyThisReq:ContentLength/binary, 
			  Next/binary>> = Body,
			Next
		end
	end,
   
    case (catch ets:lookup(cookie, cookies)) of 
	[{cookies, true}]->
	    check_cookie(Headers);
	_ ->
	    ok
    end,

   {ok, {_, Port}} = sockname(Socket),


    DefaultResponse = "HTTP/1.1 200 ok\r\n" ++
	"Content-Length:32\r\n\r\n"
	"<HTML><BODY>foobar</BODY></HTML>",

    Msg = handle_uri(Method,RelUri, Port, Headers, Socket, DefaultResponse),

    case Msg of
	ok ->
	    ok;
	close ->
	    %% Nothing to send, just close
	    close(Socket);
	_ when is_list(Msg) orelse is_binary(Msg) ->
	    case Msg of
		[] ->
		    ct:print("Empty Msg", []);
		_ ->
		    ct:print("Response: ~p", [Msg]),
		    send(Socket, Msg)
	    end
    end,
    NextRequest.

dummy_ssl_server_hang(Caller, Inet, SslOpt) ->
    Pid = spawn(httpc_SUITE, dummy_ssl_server_hang_init, [Caller, Inet, SslOpt]),
    receive
	{port, Port} ->
	    {Pid, Port}
    end.

dummy_ssl_server_hang_init(Caller, Inet, SslOpt) ->
    {ok, ListenSocket} =
	ssl:listen(0, [binary, Inet, {packet, 0},
			       {reuseaddr,true},
			       {active, false}] ++ SslOpt),
    {ok, {_,Port}} = ssl:sockname(ListenSocket),
    Caller ! {port, Port},
    {ok, AcceptSocket} = ssl:transport_accept(ListenSocket),
    dummy_ssl_server_hang_loop(AcceptSocket).

dummy_ssl_server_hang_loop(_) ->
    %% Do not do ssl:ssl_accept as we
    %% want to time out the underlying gen_tcp:connect
    receive
	stop ->
	    ok
    end.

ensure_host_header_with_port([]) ->
    false;
ensure_host_header_with_port([{"host", Host}| _]) ->
    case string:tokens(Host, [$:]) of
	[_ActualHost, _Port] ->
	    true;
	_ ->
	    false
    end;
ensure_host_header_with_port([_|T]) ->
    ensure_host_header_with_port(T).

auth_header([]) ->
    auth_header_not_found;
auth_header([{"authorization", Value} | _]) ->
    {ok, string:strip(Value)};
auth_header([_ | Tail]) ->
    auth_header(Tail).

content_type_header([]) ->
    not_found;
content_type_header([{"content-type", Value}|_]) ->
    {ok, string:strip(Value)};
content_type_header([_|T]) ->
    content_type_header(T).

handle_auth("Basic " ++ UserInfo, Challange, DefaultResponse) ->
    case string:tokens(base64:decode_to_string(UserInfo), ":") of
	["alladin", "sesame"] = Auth ->
	    ct:print("Auth: ~p~n", [Auth]),
	    DefaultResponse;
	Other ->
	    ct:print("UnAuth: ~p~n", [Other]),
	    Challange
    end.

check_cookie([]) ->
    ct:fail(no_cookie_header);
check_cookie([{"cookie", _} | _]) ->
    ok;
check_cookie([_Head | Tail]) ->
   check_cookie(Tail).

content_length([]) ->
    0;
content_length([{"content-length", Value}|_]) ->
    list_to_integer(string:strip(Value));
content_length([_Head | Tail]) ->
   content_length(Tail).

handle_uri("GET","/dummy.html?foo=bar",_,_,_,_) ->
    "HTTP/1.0 200 OK\r\n\r\nTEST";

handle_uri("GET","/space%20.html",_,_,_,_) ->
    Body = "<HTML><BODY>foobar</BODY></HTML>",
    "HTTP/1.1 200 OK\r\n" ++
        "Content-Length:" ++ integer_to_list(length(Body)) ++ "\r\n\r\n" ++
        Body;

handle_uri(_,"/just_close.html",_,_,_,_) ->
		close;
handle_uri(_,"/no_content.html",_,_,_,_) ->
    "HTTP/1.0 204 No Content\r\n\r\n";

handle_uri(_,"/no_headers.html",_,_,_,_) ->
    "HTTP/1.0 200 OK\r\n\r\nTEST";

handle_uri("TRACE","/trace.html",_,_,_,_) ->
    Body = "TRACE /trace.html simulate HTTP TRACE ",
    "HTTP/1.1 200 OK\r\n" ++ "Content-Length:" ++ integer_to_list(length(Body)) ++ "\r\n\r\n" ++ Body;

handle_uri(_,"/ensure_host_header_with_port.html",_,Headers,_,_) ->
    case ensure_host_header_with_port(Headers) of
	true ->
	    B =
		"<HTML><BODY>" ++
		"host with port" ++
		"</BODY></HTML>",
	    Len = integer_to_list(length(B)),
	    "HTTP/1.1 200 ok\r\n" ++
		"Content-Length:" ++ Len ++ "\r\n\r\n" ++ B;
	false ->
	    B =
		"<HTML><BODY>" ++
		"Internal Server Error - host without port" ++
		"</BODY></HTML>",
	    Len = integer_to_list(length(B)),
	    "HTTP/1.1 500 Internal Server Error\r\n" ++
		"Content-Length:" ++ Len ++ "\r\n\r\n" ++ B
    end;
handle_uri(_,"/redirect_ensure_host_header_with_port.html",Port,_,Socket,_) ->
    NewUri = url_start(Socket) ++
	integer_to_list(Port) ++ "/ensure_host_header_with_port.html",
    "HTTP/1.1 302 Found \r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:0\r\n\r\n";

handle_uri(_,"/300.html",Port,_,Socket,_) ->
    NewUri = url_start(Socket) ++
	integer_to_list(Port) ++ "/dummy.html",
  Body = "<HTML><BODY><a href=" ++ NewUri ++
	">New place</a></BODY></HTML>",
    "HTTP/1.1 300 Multiple Choices\r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:" ++ integer_to_list(length(Body))
	++ "\r\n\r\n" ++ Body;

handle_uri("HEAD","/301.html",Port,_,Socket,_) ->
    NewUri = url_start(Socket) ++
	integer_to_list(Port) ++ "/dummy.html",
    "HTTP/1.1 301 Moved Permanently\r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:0\r\n\r\n";

handle_uri(_,"/301.html",Port,_,Socket,_) ->
    NewUri = url_start(Socket) ++
	integer_to_list(Port) ++ "/dummy.html",
  Body = "<HTML><BODY><a href=" ++ NewUri ++
	">New place</a></BODY></HTML>",
    "HTTP/1.1 301 Moved Permanently\r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:" ++ integer_to_list(length(Body))
	++ "\r\n\r\n" ++ Body;


handle_uri("HEAD","/301_rel_uri.html",_,_,_,_) ->
    NewUri = "/dummy.html",
    "HTTP/1.1 301 Moved Permanently\r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:0\r\n\r\n";

handle_uri(_,"/301_rel_uri.html",_,_,_,_) ->
    NewUri = "/dummy.html",
  Body = "<HTML><BODY><a href=" ++ NewUri ++
	">New place</a></BODY></HTML>",
    "HTTP/1.1 301 Moved Permanently\r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:" ++ integer_to_list(length(Body))
	++ "\r\n\r\n" ++ Body;

handle_uri("HEAD","/301_custom_url.html",_,Headers,_,_) ->
    NewUri = proplists:get_value("x-test-301-url", Headers),
    "HTTP/1.1 301 Moved Permanently\r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:0\r\n\r\n";

handle_uri(_,"/301_custom_url.html",_,Headers,_,_) ->
    NewUri = proplists:get_value("x-test-301-url", Headers),
    Body = "<HTML><BODY><a href=" ++ NewUri ++
	">New place</a></BODY></HTML>",
    "HTTP/1.1 301 Moved Permanently\r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:" ++ integer_to_list(length(Body))
	++ "\r\n\r\n" ++ Body;

handle_uri("HEAD","/302.html",Port,_,Socket,_) ->
    NewUri = url_start(Socket) ++
	integer_to_list(Port) ++ "/dummy.html",
    "HTTP/1.1 302 Found \r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:0\r\n\r\n";

handle_uri(_,"/302.html",Port, _,Socket,_) ->
    NewUri = url_start(Socket) ++
	integer_to_list(Port) ++ "/dummy.html",
    Body = "<HTML><BODY><a href=" ++ NewUri ++
	">New place</a></BODY></HTML>",
    "HTTP/1.1 302 Found \r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:" ++ integer_to_list(length(Body))
	++ "\r\n\r\n" ++ Body;

handle_uri("HEAD","/303.html",Port,_,Socket,_) ->
    NewUri = url_start(Socket) ++
	integer_to_list(Port) ++ "/dummy.html",
    "HTTP/1.1 302 See Other \r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:0\r\n\r\n";
handle_uri(_,"/303.html",Port,_,Socket,_) ->
    NewUri = url_start(Socket) ++
	integer_to_list(Port) ++ "/dummy.html",
    Body = "<HTML><BODY><a href=" ++ NewUri ++
	">New place</a></BODY></HTML>",
    "HTTP/1.1 303 See Other \r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:" ++ integer_to_list(length(Body))
	++ "\r\n\r\n" ++ Body;
handle_uri("HEAD","/307.html",Port,_,Socket,_) ->
    NewUri = url_start(Socket) ++
	integer_to_list(Port) ++ "/dummy.html",
    "HTTP/1.1 307 Temporary Rediect \r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:0\r\n\r\n";
handle_uri(_,"/307.html",Port,_,Socket,_) ->
    NewUri = url_start(Socket) ++
	integer_to_list(Port) ++ "/dummy.html",
    Body = "<HTML><BODY><a href=" ++ NewUri ++
	">New place</a></BODY></HTML>",
    "HTTP/1.1 307 Temporary Rediect \r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:" ++ integer_to_list(length(Body))
	++ "\r\n\r\n" ++ Body;

handle_uri(_,"/404.html",_,_,_,_) ->
    "HTTP/1.1 404 not found\r\n" ++
	"Content-Length:14\r\n\r\n" ++
	"Page not found";

handle_uri(_,"/500.html",_,_,_,_) ->
    "HTTP/1.1 500 Internal Server Error\r\n" ++
	"Content-Length:47\r\n\r\n" ++
	"<HTML><BODY>Internal Server Error</BODY></HTML>";

handle_uri(_,"/503.html",_,_,_,DefaultResponse) ->
    case ets:lookup(unavailable, 503) of
	[{503, unavailable}] ->
	    ets:insert(unavailable, {503, available}),
	    "HTTP/1.1 503 Service Unavailable\r\n" ++
		"Retry-After:5\r\n" ++
		"Content-Length:47\r\n\r\n" ++
		"<HTML><BODY>Internal Server Error</BODY></HTML>";
	[{503, available}]   ->
	    DefaultResponse;
	[{503, long_unavailable}]  ->
	    "HTTP/1.1 503 Service Unavailable\r\n" ++
		"Retry-After:120\r\n" ++
		"Content-Length:47\r\n\r\n" ++
		"<HTML><BODY>Internal Server Error</BODY></HTML>"
    end;

handle_uri(_,"/redirectloop.html",Port,_,Socket,_) ->
    %% Create a potential endless loop!
    NewUri = url_start(Socket) ++
	integer_to_list(Port) ++ "/redirectloop.html",
     Body = "<HTML><BODY><a href=" ++ NewUri ++
	">New place</a></BODY></HTML>",
    "HTTP/1.1 300 Multiple Choices\r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:" ++ integer_to_list(length(Body))
	++ "\r\n\r\n" ++ Body;

handle_uri(_,"/userinfo.html", _,Headers,_, DefaultResponse) ->
    Challange = "HTTP/1.1 401 Unauthorized \r\n" ++
	"WWW-Authenticate:Basic" ++"\r\n" ++
	"Content-Length:0\r\n\r\n",
    case auth_header(Headers) of
	{ok, Value} ->
	    handle_auth(Value, Challange, DefaultResponse);
	_ ->
	    Challange
    end;

handle_uri(_,"/dummy_headers.html",_,_,Socket,_) ->
    %% The client will only care about the Transfer-Encoding
    %% header the rest of these headers are left to the
    %% user to evaluate. This is not a valid response
    %% it only tests that the header handling code works.
    Head = "HTTP/1.1 200 ok\r\n" ++
	"Pragma:1#no-cache\r\n"  ++
	"Via:1.0 fred, 1.1 nowhere.com (Apache/1.1)\r\n"  ++
	"Warning:1#pseudonym foobar\r\n"  ++
	"Vary:*\r\n"  ++
	"Trailer:Other:inets_test\r\n"  ++
	"Upgrade:HTTP/2.0\r\n"  ++
	"Age:4711\r\n" ++
	"Transfer-Encoding:chunked\r\n" ++
	"Content-Encoding:foo\r\n" ++
	"Content-Language:en\r\n"  ++
	"Content-Location:http://www.foobar.se\r\n"  ++
	"Content-MD5:104528739076276072743283077410617235478\r\n"
	++
	"Content-Range:Sat, 29 Oct 1994 19:43:31 GMT\r\n"  ++
	"Expires:Sat, 29 Oct 1994 19:43:31 GMT\r\n"  ++
	"Proxy-Authenticate:#1Basic"  ++
	"\r\n\r\n",
    send(Socket, Head),
    send(Socket, http_chunk:encode("<HTML><BODY>fo")),
    send(Socket, http_chunk:encode("obar</BODY></HTML>")),
    http_chunk:encode_last();

handle_uri(_,"/obs_folded_headers.html",_,_,_,_) ->
    "HTTP/1.1 200 ok\r\n"
    "Content-Length:5\r\n"
    "Folded: a\r\n"
    " b\r\n\r\n"
    "Hello";

handle_uri(_,"/headers_conflict_chunked_with_length.html",_,_,Socket,_) ->
    Head =  "HTTP/1.1 200 ok\r\n"
        "Content-Length:32\r\n"
	"Transfer-Encoding:Chunked\r\n\r\n",
    send(Socket, Head),
    send(Socket, http_chunk:encode("<HTML><BODY>fo")),
    send(Socket, http_chunk:encode("obar</BODY></HTML>")),
    http_chunk:encode_last();

handle_uri(_,"/capital_transfer_encoding.html",_,_,Socket,_) ->
    Head =  "HTTP/1.1 200 ok\r\n" ++
	"Transfer-Encoding:Chunked\r\n\r\n",
    send(Socket, Head),
    send(Socket, http_chunk:encode("<HTML><BODY>fo")),
    send(Socket, http_chunk:encode("obar</BODY></HTML>")),
    http_chunk:encode_last();

handle_uri(_,"/identity_transfer_encoding.html",_,_,_,_) ->
    "HTTP/1.0 200 OK\r\n"
    "Transfer-Encoding:identity\r\n"
    "Content-Length:8\r\n"
    "\r\n"
    "IDENTITY";

handle_uri(_,"/cookie.html",_,_,_,_) ->
    "HTTP/1.1 200 ok\r\n" ++
	"set-cookie:" ++ "test_cookie=true; path=/;" ++
	"max-age=60000\r\n" ++
	"Content-Length:32\r\n\r\n"++
	"<HTML><BODY>foobar</BODY></HTML>";

handle_uri(_,"/empty_set_cookie.html",_,_,_,_) ->
    "HTTP/1.1 200 ok\r\n" ++
	"set-cookie: \r\n" ++
	"Content-Length:32\r\n\r\n"++
	"<HTML><BODY>foobar</BODY></HTML>";

handle_uri(_,"/invalid_set_cookie.html",_,_,_,_) ->
    "HTTP/1.1 200 ok\r\n" ++
	"set-cookie: =\r\n" ++
	"set-cookie: name=\r\n" ++
	"set-cookie: name-or-value\r\n" ++
	"Content-Length:32\r\n\r\n"++
	"<HTML><BODY>foobar</BODY></HTML>";

handle_uri(_,"/missing_crlf.html",_,_,_,_) ->
    "HTTP/1.1 200 ok" ++
	"Content-Length:32\r\n" ++
	"<HTML><BODY>foobar</BODY></HTML>";

handle_uri(_,"/redirect_to_missing_crlf.html",Port,_,Socket,_) ->
    NewUri = url_start(Socket) ++
	integer_to_list(Port) ++ "/missing_crlf.html",
    Body = "<HTML><BODY><a href=" ++ NewUri ++
	">New place</a></BODY></HTML>",
    "HTTP/1.1 303 See Other \r\n" ++
	"Location:" ++ NewUri ++  "\r\n" ++
	"Content-Length:" ++ integer_to_list(length(Body))
	++ "\r\n\r\n" ++ Body;

handle_uri(_,"/wrong_statusline.html",_,_,_,_) ->
    "ok 200 HTTP/1.1\r\n\r\n" ++
	"Content-Length:32\r\n\r\n" ++
	"<HTML><BODY>foobar</BODY></HTML>";

handle_uri(_,"/once_chunked.html",_,_,Socket,_) ->
    Head =  "HTTP/1.1 200 ok\r\n" ++
	"Transfer-Encoding:Chunked\r\n\r\n",
    send(Socket, Head),
    send(Socket, http_chunk:encode("<HTML><BODY>fo")),
    send(Socket,
	 http_chunk:encode("obar</BODY></HTML>")),
    http_chunk:encode_last();

handle_uri(_,"/404_chunked.html",_,_,Socket,_) ->
    Head =  "HTTP/1.1 404 not found\r\n" ++
	"Transfer-Encoding:Chunked\r\n\r\n",
    send(Socket, Head),
    send(Socket, http_chunk:encode("<HTML><BODY>Not ")),
    send(Socket,
	 http_chunk:encode("found</BODY></HTML>")),
    http_chunk:encode_last();

handle_uri(_,"/single_chunk.html",_,_,Socket,_) ->
    Chunk =  "HTTP/1.1 200 ok\r\n" ++
        "Transfer-Encoding:Chunked\r\n\r\n" ++
        http_chunk:encode("<HTML><BODY>fo") ++
        http_chunk:encode("obar</BODY></HTML>") ++
        http_chunk:encode_last(),
    send(Socket, Chunk);

handle_uri(_,"/http_1_0_no_length_single.html",_,_,Socket,_) ->
    Body = "HTTP/1.0 200 ok\r\n"
        "Content-type:text/plain\r\n\r\n"
        "single packet",
    send(Socket, Body),
    close(Socket);

handle_uri(_,"/http_1_0_no_length_multiple.html",_,_,Socket,_) ->
    Head = "HTTP/1.0 200 ok\r\n"
        "Content-type:text/plain\r\n\r\n"
        "multiple packets, ",
    send(Socket, Head),
    %% long body to make sure it will be sent in multiple tcp packets
    send(Socket, string:copies("other multiple packets ", 200)),
    close(Socket);

handle_uri(_,"/large_404_response.html",_,_,Socket,_) ->
    %% long body to make sure it will be sent in multiple tcp packets
    Body = string:copies("other multiple packets ", 200),
    Head = io_lib:format("HTTP/1.1 404 not found\r\n"
                         "Content-length: ~B\r\n"
                         "Content-type: text/plain\r\n\r\n",
                         [length(Body)]),
    send(Socket, Head),
    send(Socket, Body),
    close(Socket);

handle_uri(_,"/once.html",_,_,Socket,_) ->
    Head =  "HTTP/1.1 200 ok\r\n" ++
	"Content-Length:32\r\n\r\n",
    send(Socket, Head),
    send(Socket, "<HTML><BODY>fo"),
    ct:sleep(1000),
    send(Socket, "ob"),
    ct:sleep(1000),
    send(Socket, "ar</BODY></HTML>");

handle_uri(_,"/invalid_http.html",_,_,_,_) ->
    "HTTP/1.1 301\r\nDate:Sun, 09 Dec 2007 13:04:18 GMT\r\n" ++
	"Transfer-Encoding:chunked\r\n\r\n";

handle_uri(_,"/invalid_chunk_size.html",_,_,_,_) ->
    "HTTP/1.1 200 ok\r\n" ++
	"Transfer-Encoding:chunked\r\n\r\nåäö\r\n";

handle_uri(_,"/missing_reason_phrase.html",_,_,_,_) ->
    "HTTP/1.1 200\r\n" ++
	"Content-Length: 32\r\n\r\n"
	"<HTML><BODY>foobar</BODY></HTML>";

handle_uri(_,"/missing_CR.html",_,_,_,_) ->
    "HTTP/1.1 200 ok\n" ++
	"Content-Length:32\r\n\n" ++
	"<HTML><BODY>foobar</BODY></HTML>";

handle_uri(_,"/multipart_chunks.html",_,_,Socket,_) ->
    Head = "HTTP/1.1 200 ok\r\n" ++
	"Transfer-Encoding:chunked\r\n" ++
	"Date: " ++ httpd_util:rfc1123_date() ++ "\r\n"
	"Connection: Keep-Alive\r\n" ++
	"Content-Type: multipart/x-mixed-replace; boundary=chunk_boundary\r\n" ++
	"\r\n",
    send(Socket, Head),
    send_multipart_chunks(Socket),
    http_chunk:encode_last();
handle_uri(_,"/delay_close.html",_,_,Socket,_) ->
    ct:sleep(10000),
    close(Socket);
handle_uri("HEAD",_,_,_,_,_) ->
    "HTTP/1.1 200 ok\r\n" ++
	"Content-Length:0\r\n\r\n";
handle_uri("PUT","/v1/kv/foo",_,_,_,_) ->
    "HTTP/1.1 200 OK\r\n" ++
        "Date: Tue, 20 Feb 2018 14:39:08 GMT\r\n" ++
        "Content-Length: 5\r\n\r\n" ++
        "Content-Type: application/json\r\n\r\n" ++
        "true\n";
handle_uri("GET","/v1/kv/foo",_,_,_,_) ->
    "HTTP/1.1 200 OK\r\n" ++
        "Date: Tue, 20 Feb 2018 14:39:08 GMT\r\n" ++
        "Content-Length: 24\r\n" ++
        "Content-Type: application/json\r\n\r\n" ++
        "[{\"Value\": \"aGVsbG8=\"}]\n";
handle_uri(_,"/http_1_1_send_oct.html",_,_,Socket,_) ->
    "HTTP/1.1 204 No Content\r\n" ++
        "X-Socket-Stat-Send-Oct: " ++ integer_to_list(get_stat(Socket, send_oct)) ++ "\r\n" ++
        "\r\n";
handle_uri(_,"/http_1_1_send_oct_and_connection_close.html",_,_,Socket,_) ->
    "HTTP/1.1 204 No Content\r\n" ++
        "X-Socket-Stat-Send-Oct: " ++ integer_to_list(get_stat(Socket, send_oct)) ++ "\r\n" ++
        "Connection: close\r\n" ++
        "\r\n";
handle_uri(_,"/delete_no_body.html", _,Headers,_, DefaultResponse) ->
    Error = "HTTP/1.1 500 Internal Server Error\r\n" ++
	"Content-Length:0\r\n\r\n",
    case content_type_header(Headers) of
	{ok, _} ->
	    Error;
	not_found ->
	    DefaultResponse
    end;
handle_uri(_,_,_,_,_,DefaultResponse) ->
    DefaultResponse.

get_stat(S, Opt) ->
    case getstat(S, [Opt]) of
        {ok, [{Opt, V}]} when is_integer(V) ->
            V;
        {error, _} = E ->
            E
    end.

getstat(#sslsocket{} = S, Opts) ->
    ssl:getstat(S, Opts);
getstat(S, Opts) ->
    inet:getstat(S, Opts).

url_start(#sslsocket{}) ->
    {ok,Host} = inet:gethostname(),
    ?TLS_URL_START ++ Host ++ ":";
url_start(_) ->
    {ok,Host} = inet:gethostname(),
    ?URL_START ++ Host ++ ":".

send(#sslsocket{} = S, Msg) ->
    ssl:send(S, Msg);
send(S, Msg) ->
    gen_tcp:send(S, Msg).

close(#sslsocket{} = S) ->
    ssl:close(S);
close(S) ->
    gen_tcp:close(S).

sockname(#sslsocket{}= S) ->
    ssl:sockname(S);
sockname(S) ->
    inet:sockname(S).

receive_streamed_body(RequestId, Body) ->
    receive
	{http, {RequestId, stream, BinBodyPart}} ->
	    receive_streamed_body(RequestId,
				  <<Body/binary, BinBodyPart/binary>>);
	{http, {RequestId, stream_end, _Headers}} ->
	    Body;
	{http, Msg} ->
	    ct:fail(Msg)
    end.

receive_streamed_body(RequestId, Body, Pid) ->
    httpc:stream_next(Pid),
    ct:print("~p:receive_streamed_body -> requested next stream ~n", [?MODULE]),
    receive
	{http, {RequestId, stream, BinBodyPart}} ->
	    %% Make sure the httpc hasn't sent us the next 'stream'
	    %% without our request.
	    receive
		{http, {RequestId, stream, _}} = Msg ->
		    ct:fail({unexpected_flood_of_stream, Msg})
	    after
		1000 ->
		    ok
	    end,
	    receive_streamed_body(RequestId,
				  <<Body/binary, BinBodyPart/binary>>,
				  Pid);
	{http, {RequestId, stream_end, _Headers}} ->
	    Body;
	{http, Msg} ->
	    ct:fail(Msg)
    end.

%% -----------------------------------------------------
%% A sequence number handler
%% The purpose is to be able to pair requests with responses.

start_sequence_number_server() ->
    proc_lib:spawn(fun() -> loop_sequence_number(1) end).

loop_sequence_number(N) ->
    receive
	shutdown ->
	    ok;
	{From, get_next} ->
	    From ! {next_is, N},
	    loop_sequence_number(N + 1)
    end.

get_next_sequence_number(SeqNumServer) ->
    SeqNumServer ! {self(), get_next},
    receive {next_is, N} -> N end.

%% -----------------------------------------------------
%% Client part
%% Sends requests randomly parallel

run_clients(NumClients, ServerPort, SeqNumServer) ->
    {ok,Host} = inet:gethostname(),
    set_random_seed(),
    lists:map(
      fun(Id) ->
	      Req = lists:flatten(io_lib:format("req~3..0w", [get_next_sequence_number(SeqNumServer)])),
	      Url = ?URL_START ++ Host ++ ":" ++ integer_to_list(ServerPort) ++  "/" ++ Req,
	      Pid = proc_lib:spawn(
		      fun() ->
			      case httpc:request(Url) of
				  {ok, {{_,200,_}, _, Resp}} ->
				      ct:print("[~w] 200 response: "
					       "~p~n", [Id, Resp]),
				      case lists:prefix(Req++"->", Resp) of
					  true -> exit(normal);
					  false -> exit({bad_resp,Req,Resp})
				      end;
				  {ok, {{_,EC,Reason},_,Resp}}  ->
				      ct:print("[~w] ~w response: "
					       "~s~n~s~n",
					       [Id, EC, Reason, Resp]),
				      exit({bad_resp,Req,Resp});
				  Crap ->
				      ct:print("[~w] bad response: ~p",
					       [Id, Crap]),
				      exit({bad_resp, Req, Crap})
			      end
		      end),
	      MRef = erlang:monitor(process, Pid),
	      timer:sleep(10 + rand:uniform(1334)),
	      {Id, Pid, MRef}
      end,
      lists:seq(1, NumClients)).

wait4clients([], _Timeout) ->
    ok;
wait4clients(Clients, Timeout) when Timeout > 0 ->
    Time = erlang:monotonic_time(),

    receive
	{'DOWN', _MRef, process, Pid, normal} ->
	    {value, {Id, _, _}} = lists:keysearch(Pid, 2, Clients),
	    NewClients = lists:keydelete(Id, 1, Clients),
	    wait4clients(NewClients, Timeout - inets_lib:millisec_passed(Time));
	{'DOWN', _MRef, process, Pid, Reason} ->
	    {value, {Id, _, _}} = lists:keysearch(Pid, 2, Clients),
	    ct:fail({bad_client_termination, Id, Reason})
    after Timeout ->
	    ct:fail({client_timeout, Clients})
    end;
wait4clients(Clients, _) ->
    ct:fail({client_timeout, Clients}).


%% -----------------------------------------------------
%% Webserver part:
%% Implements a web server that sends responses one character
%% at a time, with random delays between the characters.

start_slow_server(SeqNumServer) ->
    proc_lib:start(
      erlang, apply, [fun() -> init_slow_server(SeqNumServer) end, []]).

init_slow_server(SeqNumServer) ->
    Inet = inet_version(),
    {ok, LSock} = gen_tcp:listen(0, [binary, Inet, {packet,0}, {active,true},
				     {backlog, 100}]),
    {ok, {_IP, Port}} = inet:sockname(LSock),
    proc_lib:init_ack({ok, self(), Port}),
    loop_slow_server(LSock, SeqNumServer).

loop_slow_server(LSock, SeqNumServer) ->
    Master = self(),
    Acceptor = proc_lib:spawn(
		 fun() -> client_handler(Master, LSock, SeqNumServer) end),
    receive
	{accepted, Acceptor} ->
	    loop_slow_server(LSock, SeqNumServer);
	shutdown ->
	    gen_tcp:close(LSock),
	    exit(Acceptor, kill)
    end.


%% Handle one client connection
client_handler(Master, LSock, SeqNumServer) ->
    {ok, CSock} = gen_tcp:accept(LSock),
    Master ! {accepted, self()},
    set_random_seed(),
    loop_client(1, CSock, SeqNumServer).

loop_client(N, CSock, SeqNumServer) ->
    %% Await request, don't bother parsing it too much,
    %% assuming the entire request arrives in one packet.
    receive
	{tcp, CSock, Req} ->
	    ReqNum = parse_req_num(Req),
	    RespSeqNum = get_next_sequence_number(SeqNumServer),
	    Response = lists:flatten(io_lib:format("~s->resp~3..0w/~2..0w", [ReqNum, RespSeqNum, N])),
	    Txt = lists:flatten(io_lib:format("Slow server (~p) got ~p, answering with ~p",
					      [self(), Req, Response])),
	    ct:print("~s...~n", [Txt]),
	    slowly_send_response(CSock, Response),
	    case parse_connection_type(Req) of
		keep_alive ->
		    ct:print("~s...done~n", [Txt]),
		    loop_client(N+1, CSock, SeqNumServer);
		close ->
		    ct:print("~s...done (closing)~n", [Txt]),
		    gen_tcp:close(CSock)
	    end
    end.

slowly_send_response(CSock, Answer) ->
    Response =  lists:flatten(io_lib:format("HTTP/1.1 200 OK\r\nContent-Length: ~w\r\n\r\n~s",
					    [length(Answer), Answer])),
    lists:foreach(
      fun(Char) ->
	      timer:sleep(rand:uniform(500)),
	      gen_tcp:send(CSock, <<Char>>)
      end,
      Response).

parse_req_num(Request) ->
    Opts = [caseless,{capture,all_but_first,list}],
    {match, [ReqNum]} = re:run(Request, "GET /(.*) HTTP", Opts),
    ReqNum.

parse_connection_type(Request) ->
    Opts = [caseless,{capture,all_but_first,list}],
    {match,[CType]} = re:run(Request, "connection: *(keep-alive|close)", Opts),
    case string:to_lower(CType) of
	"close" -> close;
	"keep-alive" -> keep_alive
    end.

set_random_seed() ->
    Unique = erlang:unique_integer(),
    A = erlang:phash2([make_ref(), self(), Unique]),
    rand:seed(exsplus, {A, A, A}).


otp_8739(doc) ->
    ["OTP-8739"];
otp_8739(suite) ->
    [];
otp_8739(Config) when is_list(Config) ->
    {_DummyServerPid, Port} = otp_8739_dummy_server(),
    {ok,Host} = inet:gethostname(),
    URL = ?URL_START ++ Host ++ ":" ++ integer_to_list(Port) ++ "/dummy.html",
    Method      = get,
    Request     = {URL, []},
    HttpOptions = [{connect_timeout, 500}, {timeout, 1}],
    Options     = [{sync, true}],
    case httpc:request(Method, Request, HttpOptions, Options) of
	{error, timeout} ->
	    %% And now we check the size of the handler db
	    Info = httpc:info(),
	    ct:print("Info: ~p", [Info]),
	    {value, {handlers, Handlers}} =
		lists:keysearch(handlers, 1, Info),
	    case Handlers of
		[] ->
		    ok;
		_ ->
		    ct:fail({unexpected_handlers, Handlers})
	    end;
	Unexpected ->
	    ct:fail({unexpected, Unexpected})
    end.

otp_8739_dummy_server() ->
    Parent = self(),
    Pid = spawn_link(fun() -> otp_8739_dummy_server_init(Parent) end),
    receive
	{port, Port} ->
	    {Pid, Port}
    end.

otp_8739_dummy_server_init(Parent) ->
    Inet = inet_version(),
    {ok, ListenSocket} =
	gen_tcp:listen(0, [binary, Inet, {packet, 0},
			   {reuseaddr,true},
			   {active, false}]),
    {ok, Port} = inet:port(ListenSocket),
    Parent ! {port, Port},
    otp_8739_dummy_server_main(Parent, ListenSocket).

otp_8739_dummy_server_main(_Parent, ListenSocket) ->
    case gen_tcp:accept(ListenSocket) of
	{ok, Sock} ->
	    %% Ignore the request, and simply wait for the socket to close
	    receive
		{tcp_closed, Sock} ->
		    (catch gen_tcp:close(ListenSocket)),
		    exit(normal);
		{tcp_error, Sock, Reason} ->
		    ct:fail("socket error: ~p", [Reason]),
		    (catch gen_tcp:close(ListenSocket)),
		    exit(normal)
	    after 10000 ->
		    %% Just in case
		    (catch gen_tcp:close(Sock)),
		    (catch gen_tcp:close(ListenSocket)),
		    exit(timeout)
	    end;
	Error ->
	    exit(Error)
    end.

send_multipart_chunks(Socket) ->
    send(Socket, http_chunk:encode("--chunk_boundary\r\n")),
    send(Socket, http_chunk:encode("Content-Type: text/plain\r\nContent-Length: 4\r\n\r\n")),
    send(Socket, http_chunk:encode("test\r\n")),
    ct:sleep(500),
    send_multipart_chunks(Socket).

receive_stream_n(_, 0) ->
    ok;
receive_stream_n(Ref, N) ->
    receive
	{http, {Ref, stream_start, _}} ->
	    receive_stream_n(Ref, N);
	{http, {Ref,stream, Data}} ->
	    ct:pal("Data:  ~p", [Data]),
	    receive_stream_n(Ref, N-1)
    end.

is_ipv6_supported() ->
    {ok, Hostname0} = inet:gethostname(),
    try 
        lists:member(list_to_atom(Hostname0), ct:get_config(ipv6_hosts))
    catch
         _: _ ->
            false
    end.
