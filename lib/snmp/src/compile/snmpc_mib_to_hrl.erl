%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1996-2021. All Rights Reserved.
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

-module(snmpc_mib_to_hrl).

-include_lib("stdlib/include/erl_compile.hrl").
-include("snmp_types.hrl").
-include("snmpc_lib.hrl").

%% External exports
-export([convert/1, convert/3, compile/3]).


%%-----------------------------------------------------------------
%% Func: convert/1
%% Args: MibName = string() without extension.
%% Purpose: Produce a .hrl file with oid for tables and variables,
%%          column numbers for columns and values for enums.
%%          Writes only the first occurrence of a name.  Prints a
%%          warning if a duplicate name is found.
%% Returns: ok | {error, Reason}
%% Note: The Mib must be compiled.
%%-----------------------------------------------------------------
convert(MibName) ->
    MibFile = MibName ++ ".bin",
    HrlFile = MibName ++ ".hrl",
    put(verbosity, trace),
    convert(MibFile, HrlFile, MibName).

convert(MibFile, HrlFile, MibName) ->
    ?vtrace("convert -> entry with"
	    "~n   MibFile: ~s"
	    "~n   HrlFile: ~s"
	    "~n   MibName: ~s", [MibFile, HrlFile, MibName]),
    case snmpc_misc:read_mib(MibFile) of
	{ok, #mib{asn1_types = Types, mes = MEs, traps = Traps}} ->
	    ?vdebug("mib successfully read", []),
	    resolve(Types, MEs, Traps, HrlFile, 
		    filename:basename(MibName)),
	    ok;
	{error, Reason} ->
	    ?vinfo("failed reading mib: "
		   "~n   Reason: ~p", [Reason]),
	    {error, Reason}
    end.

resolve(Types, MEs, Traps, HrlFile, MibName) ->
    ?vtrace("resolve -> entry", []),
    case file:open(HrlFile, [write]) of
	{ok, Fd} ->
	    insert_header(Fd),
	    insert_begin(Fd, MibName),
	    insert_notifs(Traps, Fd),
	    insert_oids(MEs, Fd),
	    insert_range(MEs, Fd),
	    insert_enums(Types, MEs, Fd),
	    insert_defvals(MEs, Fd),
	    insert_end(Fd),
	    file:close(Fd),
	    ?vlog("~s written", [HrlFile]);
	{error, Reason} ->
	    ?vinfo("failed opening output file: "
		   "~n   Reason: ~p", [Reason]),
	    {error, Reason}
    end.

insert_header(Fd) ->
    ?vdebug("insert file header", []),
    io:format(Fd, "%%% This file was automatically generated by "
	      "snmpc_mib_to_hrl~n", []).

insert_begin(Fd, MibName) ->
    ?vdebug("insert file begin", []),
    io:format(Fd, 
	      "-ifndef('~s').~n"
	      "-define('~s', true).~n", [MibName, MibName]).

insert_end(Fd) ->
    ?vdebug("insert file end", []),
    io:format(Fd, "-endif.~n", []).

insert_oids(MEs, Fd) ->
    ?vdebug("insert oids", []),
    io:format(Fd, "~n%% Oids~n", []),
    insert_oids2(MEs, Fd),
    io:format(Fd, "~n", []).

insert_oids2([#me{imported = true} | T], Fd) ->
    insert_oids2(T, Fd);
insert_oids2([#me{entrytype = table_column, oid = Oid, aliasname = Name} | T],
	     Fd) ->
    ?vtrace("insert oid [table column]: ~p - ~w", [Name, Oid]),
    io:format(Fd, "-define(~w, ~w).~n", [Name, lists:last(Oid)]),
    insert_oids2(T, Fd);
insert_oids2([#me{entrytype = variable, oid = Oid, aliasname = Name} | T],
	    Fd) ->
    ?vtrace("insert oid [variable]: ~p - ~w", [Name, Oid]),
    io:format(Fd, "-define(~w, ~w).~n", [Name, Oid]),
    io:format(Fd, "-define(~w, ~w).~n", [merge_atoms(Name, instance),
					 Oid ++ [0]]),
    insert_oids2(T, Fd);
insert_oids2([#me{oid = Oid, aliasname = Name} | T], Fd) ->
    ?vtrace("insert oid: ~p - ~w", [Name, Oid]),
    io:format(Fd, "~n-define(~w, ~w).~n", [Name, Oid]),
    insert_oids2(T, Fd);
insert_oids2([], _Fd) -> 
    ok.


insert_notifs(Traps, Fd) ->
    ?vdebug("insert notifications", []),
    Notifs = [Notif || Notif <- Traps, is_record(Notif, notification)],
    case Notifs of
	[] ->
	    ok;
	_ -> 
	    io:format(Fd, "~n%% Notifications~n", []),
	    insert_notifs2(Notifs, Fd)
    end.
    
insert_notifs2([], _Fd) ->
    ok;
insert_notifs2([#notification{trapname = Name, oid = Oid}|T], Fd) ->
    ?vtrace("insert notification ~p - ~w", [Name, Oid]),
    io:format(Fd, "-define(~w, ~w).~n", [Name, Oid]),
    insert_notifs2(T, Fd).


%%-----------------------------------------------------------------
%% There's nothing strange with this function!  Enums can be
%% defined in types and in mibentries; therefore, we first call
%% ins_types and then ins_mes to insert enums from different places.
%%-----------------------------------------------------------------
insert_enums(Types, MEs, Fd) ->
    ?vdebug("insert enums", []),
    T = ins_types(Types, Fd, []),
    ins_mes(MEs, T, Fd).

%% Insert all types, but not the imported.  Ret the names of inserted
%% types.
ins_types([#asn1_type{aliasname = Name, 
		      assocList = Alist, 
		      imported  = false} | T],
	  Fd, Res) 
  when is_list(Alist) ->
    case lists:keysearch(enums, 1, Alist) of
	{value, {enums, Enums}} when Enums =/= [] ->
	    case Enums of
		[] -> ins_types(T, Fd, Res);
		NewEnums ->
		    io:format(Fd, "~n%% Definitions from ~w~n", [Name]),
		    ins_enums(NewEnums, Name, Fd),
		    ins_types(T, Fd, [Name | Res])
	    end;
	_ -> ins_types(T, Fd, Res)
    end;
ins_types([_ | T], Fd, Res)  ->
    ins_types(T, Fd, Res);
ins_types([], _Fd, Res) -> Res.

ins_mes([#me{entrytype = internal} | T], Types, Fd) ->
    ins_mes(T, Types, Fd);
ins_mes([#me{entrytype = table} | T], Types, Fd) ->
    ins_mes(T, Types, Fd);
ins_mes([#me{aliasname = Name, 
	     asn1_type = #asn1_type{assocList = Alist,
				    aliasname = Aname},
	     imported  = false} | T],
	Types, Fd)
  when is_list(Alist) ->
    case lists:keysearch(enums, 1, Alist) of
	{value, {enums, Enums}} when Enums =/= [] ->
	    case Enums of
		[] -> ins_mes(T, Types, Fd);
		NewEnums ->
		    %% Now, check if the type is already inserted
                    %% (by ins_types).
		    case lists:member(Aname, Types) of
			false ->
			    io:format(Fd, "~n%% Enum definitions from ~w~n",
				      [Name]),
			    ins_enums(NewEnums, Name, Fd),
			    ins_mes(T, Types, Fd);
			_ -> ins_mes(T, Types, Fd)
		    end
	    end;
	_ -> ins_mes(T, Types, Fd)
    end;
ins_mes([_ | T], Types, Fd) ->
    ins_mes(T, Types, Fd);
ins_mes([], _Types, _Fd) -> ok.

ins_enums([{Name, Val} | T], Origin, Fd) ->
    EnumName = merge_atoms(Origin, Name),
    io:format(Fd, "-define(~w, ~w).~n", [EnumName, Val]),
    ins_enums(T, Origin, Fd);
ins_enums([], _Origin,  _Fd) ->
    ok.

%%----------------------------------------------------------------------
%% Solves the problem with placing '' around some atoms.
%% You can't write two atoms using ~w_~w.
%%----------------------------------------------------------------------
merge_atoms(TypeOrigin, Name) ->
    list_to_atom(lists:append([atom_to_list(TypeOrigin), "_",
			       atom_to_list(Name)])).

insert_defvals(Mes, Fd) ->
    ?vdebug("insert default values", []),
    io:format(Fd, "~n%% Default values~n", []),
    insert_defvals2(Mes, Fd),
    io:format(Fd, "~n", []).

insert_defvals2([#me{imported = true} | T], Fd) ->
    insert_defvals2(T, Fd);
insert_defvals2([#me{entrytype = table_column, assocList = Alist, 
		    aliasname = Name} | T],
	    Fd) ->
    case snmpc_misc:assq(defval, Alist) of
	{value, Val} ->
	    Atom = merge_atoms('default', Name),
	    io:format(Fd, "-define(~w, ~w).~n", [Atom, Val]);
	_ -> ok
    end,
    insert_defvals2(T, Fd);
insert_defvals2([#me{entrytype = variable, assocList = Alist, aliasname = Name}
		| T],
	    Fd) ->
    case snmpc_misc:assq(variable_info, Alist) of
	{value, VarInfo} ->
	    case VarInfo#variable_info.defval of
		undefined -> ok;
		Val ->
		    Atom = merge_atoms('default', Name),
		    io:format(Fd, "-define(~w, ~w).~n", [Atom, Val])
	    end;
	_ -> ok
    end,
    insert_defvals2(T, Fd);
insert_defvals2([_ | T], Fd) ->
    insert_defvals2(T, Fd);
insert_defvals2([], _Fd) -> ok.

insert_range(Mes, Fd) ->
    ?vdebug("insert range", []),
    io:format(Fd, "~n%% Range values~n", []),
    insert_range2(Mes, Fd),
    io:format(Fd, "~n", []).

insert_range2([#me{imported = true} | T], Fd)->
    insert_range2(T,Fd);
insert_range2([#me{asn1_type=#asn1_type{bertype='OCTET STRING',lo=Low,hi=High},aliasname=Name}|T],Fd)->
    case Low =:= undefined of
	true->
	    insert_range2(T,Fd);
	false->
	    AtomLow = merge_atoms('low', Name),
	    AtomHigh = merge_atoms('high', Name),
	    io:format(Fd,"-define(~w, ~w).~n",[AtomLow,Low]),
	    io:format(Fd,"-define(~w, ~w).~n",[AtomHigh,High]),
	    insert_range2(T,Fd)
    end;
insert_range2([#me{asn1_type=#asn1_type{bertype='Unsigned32',lo=Low,hi=High},aliasname=Name}|T],Fd)->
	    AtomLow = merge_atoms('low', Name),
	    AtomHigh = merge_atoms('high', Name),
	    io:format(Fd,"-define(~w, ~w).~n",[AtomLow,Low]),
	    io:format(Fd,"-define(~w, ~w).~n",[AtomHigh,High]),
	    insert_range2(T,Fd);
insert_range2([#me{asn1_type=#asn1_type{bertype='Counter32',lo=Low,hi=High},aliasname=Name}|T],Fd)->
	    AtomLow = merge_atoms('low', Name),
	    AtomHigh = merge_atoms('high', Name),
	    io:format(Fd,"-define(~w, ~w).~n",[AtomLow,Low]),
	    io:format(Fd,"-define(~w, ~w).~n",[AtomHigh,High]),
	    insert_range2(T,Fd);
insert_range2([#me{asn1_type=#asn1_type{bertype='INTEGER',lo=Low,hi=High},aliasname=Name}|T],Fd)->
    case Low =:= undefined of
	true->
	    insert_range2(T,Fd);
	false->
	    AtomLow = merge_atoms('low', Name),
	    AtomHigh = merge_atoms('high', Name),
	    io:format(Fd,"-define(~w, ~w).~n",[AtomLow,Low]),
	    io:format(Fd,"-define(~w, ~w).~n",[AtomHigh,High]),
	    insert_range2(T,Fd)
    end; 
insert_range2([_|T],Fd) ->
    insert_range2(T,Fd);
insert_range2([],_Fd) ->
    ok.

%%%-----------------------------------------------------------------
%%% Interface for erl_compile.
%%%-----------------------------------------------------------------

%% Opts#options.specific
compile(Input, Output, Opts) ->
    set_verbosity(Opts),
    set_filename(Input),
    ?vtrace("compile -> entry with"
	    "~n   Input:  ~s"
	    "~n   Output: ~s"
	    "~n   Opts:   ~p", [Input, Output, Opts]),
    case convert(Input++".bin", Output++".hrl", Input) of
	ok ->
	    ok;
	{error, Reason} ->
	    io:format("~p", [Reason]),
	    error
    end.

set_verbosity(#options{verbose = Verbose, specific = Spec}) ->
    set_verbosity(Verbose, Spec).

set_verbosity(Verbose, Spec) ->
    Verbosity = 
	case lists:keysearch(verbosity, 1, Spec) of
	    {value, {verbosity, V}} ->
		case (catch snmpc_lib:vvalidate(V)) of
		    ok ->
			case Verbose of
			    true ->
				case V of
				    silence ->
					log;
				    info ->
					log;
				    _ -> 
					V
				end;
			    _ ->
				V
			end;
		   _ ->
			case Verbose of
			    true ->
				log;
			    false ->
				silence
			end
		end;
	    false ->
		case Verbose of
		    true ->
			log;
		    false ->
			silence
		end
	end,
    put(verbosity, Verbosity).


set_filename(Filename) ->
    Rootname = filename:rootname(Filename),
    Basename = filename:basename(Rootname ++ ".mib"),
    put(filename, Basename).




