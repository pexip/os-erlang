%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2009-2020. All Rights Reserved.
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
%% This file is generated DO NOT EDIT

-module(wxSplitterEvent).
-include("wxe.hrl").
-export([getSashPosition/1,getWindowBeingRemoved/1,getX/1,getY/1,setSashPosition/2]).

%% inherited exports
-export([allow/1,getClientData/1,getExtraLong/1,getId/1,getInt/1,getSelection/1,
  getSkipped/1,getString/1,getTimestamp/1,isAllowed/1,isChecked/1,isCommandEvent/1,
  isSelection/1,parent_class/1,resumePropagation/2,setInt/2,setString/2,
  shouldPropagate/1,skip/1,skip/2,stopPropagation/1,veto/1]).

-type wxSplitterEvent() :: wx:wx_object().
-include("wx.hrl").
-type wxSplitterEventType() :: 'command_splitter_sash_pos_changed' | 'command_splitter_sash_pos_changing' | 'command_splitter_doubleclicked' | 'command_splitter_unsplit'.
-export_type([wxSplitterEvent/0, wxSplitter/0, wxSplitterEventType/0]).
%% @hidden
parent_class(wxNotifyEvent) -> true;
parent_class(wxCommandEvent) -> true;
parent_class(wxEvent) -> true;
parent_class(_Class) -> erlang:error({badtype, ?MODULE}).

%% @doc See <a href="http://www.wxwidgets.org/manuals/2.8.12/wx_wxsplitterevent.html#wxsplittereventgetsashposition">external documentation</a>.
-spec getSashPosition(This) -> integer() when
	This::wxSplitterEvent().
getSashPosition(#wx_ref{type=ThisT}=This) ->
  ?CLASS(ThisT,wxSplitterEvent),
  wxe_util:queue_cmd(This,?get_env(),?wxSplitterEvent_GetSashPosition),
  wxe_util:rec(?wxSplitterEvent_GetSashPosition).

%% @doc See <a href="http://www.wxwidgets.org/manuals/2.8.12/wx_wxsplitterevent.html#wxsplittereventgetx">external documentation</a>.
-spec getX(This) -> integer() when
	This::wxSplitterEvent().
getX(#wx_ref{type=ThisT}=This) ->
  ?CLASS(ThisT,wxSplitterEvent),
  wxe_util:queue_cmd(This,?get_env(),?wxSplitterEvent_GetX),
  wxe_util:rec(?wxSplitterEvent_GetX).

%% @doc See <a href="http://www.wxwidgets.org/manuals/2.8.12/wx_wxsplitterevent.html#wxsplittereventgety">external documentation</a>.
-spec getY(This) -> integer() when
	This::wxSplitterEvent().
getY(#wx_ref{type=ThisT}=This) ->
  ?CLASS(ThisT,wxSplitterEvent),
  wxe_util:queue_cmd(This,?get_env(),?wxSplitterEvent_GetY),
  wxe_util:rec(?wxSplitterEvent_GetY).

%% @doc See <a href="http://www.wxwidgets.org/manuals/2.8.12/wx_wxsplitterevent.html#wxsplittereventgetwindowbeingremoved">external documentation</a>.
-spec getWindowBeingRemoved(This) -> wxWindow:wxWindow() when
	This::wxSplitterEvent().
getWindowBeingRemoved(#wx_ref{type=ThisT}=This) ->
  ?CLASS(ThisT,wxSplitterEvent),
  wxe_util:queue_cmd(This,?get_env(),?wxSplitterEvent_GetWindowBeingRemoved),
  wxe_util:rec(?wxSplitterEvent_GetWindowBeingRemoved).

%% @doc See <a href="http://www.wxwidgets.org/manuals/2.8.12/wx_wxsplitterevent.html#wxsplittereventsetsashposition">external documentation</a>.
-spec setSashPosition(This, Pos) -> 'ok' when
	This::wxSplitterEvent(), Pos::integer().
setSashPosition(#wx_ref{type=ThisT}=This,Pos)
 when is_integer(Pos) ->
  ?CLASS(ThisT,wxSplitterEvent),
  wxe_util:queue_cmd(This,Pos,?get_env(),?wxSplitterEvent_SetSashPosition).

 %% From wxNotifyEvent
%% @hidden
veto(This) -> wxNotifyEvent:veto(This).
%% @hidden
isAllowed(This) -> wxNotifyEvent:isAllowed(This).
%% @hidden
allow(This) -> wxNotifyEvent:allow(This).
 %% From wxCommandEvent
%% @hidden
setString(This,String) -> wxCommandEvent:setString(This,String).
%% @hidden
setInt(This,IntCommand) -> wxCommandEvent:setInt(This,IntCommand).
%% @hidden
isSelection(This) -> wxCommandEvent:isSelection(This).
%% @hidden
isChecked(This) -> wxCommandEvent:isChecked(This).
%% @hidden
getString(This) -> wxCommandEvent:getString(This).
%% @hidden
getSelection(This) -> wxCommandEvent:getSelection(This).
%% @hidden
getInt(This) -> wxCommandEvent:getInt(This).
%% @hidden
getExtraLong(This) -> wxCommandEvent:getExtraLong(This).
%% @hidden
getClientData(This) -> wxCommandEvent:getClientData(This).
 %% From wxEvent
%% @hidden
stopPropagation(This) -> wxEvent:stopPropagation(This).
%% @hidden
skip(This, Options) -> wxEvent:skip(This, Options).
%% @hidden
skip(This) -> wxEvent:skip(This).
%% @hidden
shouldPropagate(This) -> wxEvent:shouldPropagate(This).
%% @hidden
resumePropagation(This,PropagationLevel) -> wxEvent:resumePropagation(This,PropagationLevel).
%% @hidden
isCommandEvent(This) -> wxEvent:isCommandEvent(This).
%% @hidden
getTimestamp(This) -> wxEvent:getTimestamp(This).
%% @hidden
getSkipped(This) -> wxEvent:getSkipped(This).
%% @hidden
getId(This) -> wxEvent:getId(This).
