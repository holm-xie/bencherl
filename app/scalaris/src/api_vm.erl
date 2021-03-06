%  @copyright 2011 Zuse Institute Berlin

%   Licensed under the Apache License, Version 2.0 (the "License");
%   you may not use this file except in compliance with the License.
%   You may obtain a copy of the License at
%
%       http://www.apache.org/licenses/LICENSE-2.0
%
%   Unless required by applicable law or agreed to in writing, software
%   distributed under the License is distributed on an "AS IS" BASIS,
%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%   See the License for the specific language governing permissions and
%   limitations under the License.

%% @author Nico Kruber <kruber@zib.de>
%% @doc    Administrative functions available for external programs.
%% @end
%% @version $Id$
-module(api_vm).
-author('kruber@zib.de').
-vsn('$Id$ ').

-export([get_version/0, get_info/0,
         number_of_nodes/0, get_nodes/0, add_nodes/1,
         shutdown_node/1, shutdown_nodes/1, shutdown_nodes_by_name/1,
         kill_node/1, kill_nodes/1, kill_nodes_by_name/1,
         get_other_vms/1,
         shutdown_vm/0, kill_vm/0]).

-include("scalaris.hrl").

%% @doc Gets the version of Scalaris.
-spec get_version() -> string().
get_version() ->
    ?SCALARIS_VERSION.

%% @doc Gets some information about the VM and Scalaris.
-spec get_info() -> [{scalaris_version | erlang_version, string()} |
                     {mem_total, non_neg_integer()} | {uptime, Ms::non_neg_integer()} |
                     {erlang_node, node()} | {ip, inet:ip_address()} |
                     {port, non_neg_integer()} | {yaws_port, non_neg_integer()}].
get_info() ->
    [{scalaris_version, ?SCALARIS_VERSION},
     {erlang_version, erlang:system_info(otp_release)},
     {mem_total, erlang:memory(total)},
     {uptime, erlang:element(1, erlang:statistics(wall_clock))},
     {erlang_node, node()},
     {ip, comm:get_ip(comm:this())},
     {port, comm:get_port(comm:this())},
     {yaws_port, config:read(yaws_port)}
    ].

%% @doc Gets the number of Scalaris nodes inside this VM.
-spec number_of_nodes() -> non_neg_integer().
number_of_nodes() ->
    length(get_nodes()).

%% @doc Gets the names of all Scalaris nodes inside this VM.
-spec get_nodes() -> [pid_groups:groupname()].
get_nodes() ->
    DhtModule = config:read(dht_node),
    [pid_groups:group_of(Pid) || Pid <- pid_groups:find_all(dht_node),
                                 DhtModule:is_alive(gen_component:get_state(Pid))].

%% @doc Adds Number Scalaris nodes to this VM.
-spec add_nodes(non_neg_integer()) -> {[pid_groups:groupname()], [{error, term()}]}.
add_nodes(Number) when is_integer(Number) andalso Number >= 0 ->
    Result = {Ok, _Failed} = admin:add_nodes(Number),
    % at least wait for the successful nodes to have joined, i.e. left the join phases
    util:wait_for(
      fun() ->
              DhtModule = config:read(dht_node),
              NotReady = [Name || Name <- Ok,
                                  not DhtModule:is_alive(
                                    gen_component:get_state(
                                      pid_groups:pid_of(Name, dht_node)))],
              [] =:= NotReady
      end),
    Result.

%% @doc Wait for the given nodes to disappear.
-spec wait_for_nodes_to_disappear(Names::[pid_groups:groupname()]) -> ok.
wait_for_nodes_to_disappear(Names) ->
    util:wait_for(
      fun() ->
              [] =:= [Name || Name <- Names,
                              pid_groups:pid_of(Name, dht_node) =/= failed]
      end).

%% @doc Sends a graceful leave request to a given node.
-spec shutdown_node(pid_groups:groupname()) -> ok | not_found.
shutdown_node(Name) ->
    case element(1, shutdown_nodes_by_name([Name])) of
        [] -> not_found;
        _  -> ok
    end.
%% @doc Sends a graceful leave request to multiple nodes.
-spec shutdown_nodes(Count::non_neg_integer()) -> Ok::[pid_groups:groupname()].
shutdown_nodes(Count) when is_integer(Count) andalso Count >= 0 ->
    Ok = admin:del_nodes(Count, true),
    wait_for_nodes_to_disappear(Ok),
    Ok.
-spec shutdown_nodes_by_name(Names::[pid_groups:groupname()]) -> {Ok::[pid_groups:groupname()], NotFound::[pid_groups:groupname()]}.
shutdown_nodes_by_name(Names) when is_list(Names) ->
    Result = {Ok, _NotFound} = admin:del_nodes_by_name(Names, true),
    wait_for_nodes_to_disappear(Ok),
    Result.

%% @doc Kills a given node.
-spec kill_node(pid_groups:groupname()) -> ok | not_found.
kill_node(Name) ->
    case element(1, kill_nodes_by_name([Name])) of
        [] -> not_found;
        _  -> ok
    end.
%% @doc Kills multiple nodes.
-spec kill_nodes(Count::non_neg_integer()) -> Ok::[pid_groups:groupname()].
kill_nodes(Count) when is_integer(Count) andalso Count >= 0 ->
    Ok = admin:del_nodes(Count, false),
    wait_for_nodes_to_disappear(Ok),
    Ok.
-spec kill_nodes_by_name(Names::[pid_groups:groupname()]) -> {Ok::[pid_groups:groupname()], NotFound::[pid_groups:groupname()]}.
kill_nodes_by_name(Names) when is_list(Names) ->
    Result = {Ok, _NotFound} = admin:del_nodes_by_name(Names, false),
    wait_for_nodes_to_disappear(Ok),
    Result.

%% @doc Gets connection info for a random subset of known nodes by the cyclon
%%      processes of the dht_node processes in this VM.
-spec get_other_vms(MaxVMs::pos_integer()) -> [{ErlNode::node(), Ip::inet:ip_address(), Port::non_neg_integer(), YawsPort::non_neg_integer()}].
get_other_vms(MaxVMs) when is_integer(MaxVMs) andalso MaxVMs > 0 ->
    DhtModule = config:read(dht_node),
    RandomConns =
        lists:append(
          [begin
               GlobalPid = comm:make_global(Pid),
               comm:send(GlobalPid, {get_subset_rand, MaxVMs, self()},
                         [{group_member, cyclon}]),
               receive
                   {cy_cache, Cache} ->
                       [{node:erlNode(Node),
                         comm:get_ip(node:pidX(Node)),
                         comm:get_port(node:pidX(Node)),
                         node:yawsPort(Node)} || Node <- Cache]
               end
           end || Pid <- pid_groups:find_all(dht_node),
                  DhtModule:is_alive_fully_joined(gen_component:get_state(Pid))]),
    util:random_subset(MaxVMs, lists:usort(RandomConns)).

%% @doc Graceful shutdown of this VM.
-spec shutdown_vm() -> no_return().
shutdown_vm() ->
    _ = shutdown_nodes(number_of_nodes()),
    util:wait_for(fun() -> number_of_nodes() =:= 0 end),
    erlang:halt().

%% @doc Kills this VM.
-spec kill_vm() -> no_return().
kill_vm() ->
    erlang:halt().
