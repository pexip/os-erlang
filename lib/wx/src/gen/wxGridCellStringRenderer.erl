%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2009-2016. All Rights Reserved.
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

%% @doc See external documentation: <a href="http://www.wxwidgets.org/manuals/2.8.12/wx_wxgridcellstringrenderer.html">wxGridCellStringRenderer</a>.
%% <p>This class is derived (and can use functions) from:
%% <br />{@link wxGridCellRenderer}
%% </p>
%% @type wxGridCellStringRenderer().  An object reference, The representation is internal
%% and can be changed without notice. It can't be used for comparsion
%% stored on disc or distributed for use on other nodes.

-module(wxGridCellStringRenderer).
-include("wxe.hrl").
-export([destroy/1,new/0]).

%% inherited exports
-export([draw/8,getBestSize/6,parent_class/1]).

-export_type([wxGridCellStringRenderer/0]).
%% @hidden
parent_class(wxGridCellRenderer) -> true;
parent_class(_Class) -> erlang:error({badtype, ?MODULE}).

-type wxGridCellStringRenderer() :: wx:wx_object().
%% @doc See <a href="http://www.wxwidgets.org/manuals/2.8.12/wx_wxgridcellstringrenderer.html#wxgridcellstringrendererwxgridcellstringrenderer">external documentation</a>.
-spec new() -> wxGridCellStringRenderer().
new() ->
  wxe_util:construct(?wxGridCellStringRenderer_new,
  <<>>).

%% @doc Destroys this object, do not use object again
-spec destroy(This::wxGridCellStringRenderer()) -> 'ok'.
destroy(Obj=#wx_ref{type=Type}) ->
  ?CLASS(Type,wxGridCellStringRenderer),
  wxe_util:destroy(?wxGridCellStringRenderer_destroy,Obj),
  ok.
 %% From wxGridCellRenderer
%% @hidden
getBestSize(This,Grid,Attr,Dc,Row,Col) -> wxGridCellRenderer:getBestSize(This,Grid,Attr,Dc,Row,Col).
%% @hidden
draw(This,Grid,Attr,Dc,Rect,Row,Col,IsSelected) -> wxGridCellRenderer:draw(This,Grid,Attr,Dc,Rect,Row,Col,IsSelected).
