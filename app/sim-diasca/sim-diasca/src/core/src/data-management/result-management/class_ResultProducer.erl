% Copyright (C) 2010-2014 EDF R&D

% This file is part of Sim-Diasca.

% Sim-Diasca is free software: you can redistribute it and/or modify
% it under the terms of the GNU Lesser General Public License as
% published by the Free Software Foundation, either version 3 of
% the License, or (at your option) any later version.

% Sim-Diasca is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
% GNU Lesser General Public License for more details.

% You should have received a copy of the GNU Lesser General Public
% License along with Sim-Diasca.
% If not, see <http://www.gnu.org/licenses/>.

% Author: Olivier Boudeville (olivier.boudeville@edf.fr)



% Base class for all result producers.
%
% It allows them to be declared automatically to the result manager, and
% provides the basic behaviour so that they can interact with it.
%
-module(class_ResultProducer).


% Determines what are the mother classes of this class (if any):
-define( wooper_superclasses, [ class_TraceEmitter ] ).


% Parameters taken by the constructor ('construct').
-define( wooper_construct_parameters, ProducerName ).



% Declaring all variations of WOOPER standard life-cycle operations:
% (template pasted, two replacements performed to update arities)
-define( wooper_construct_export, new/1, new_link/1,
		 synchronous_new/1, synchronous_new_link/1,
		 synchronous_timed_new/1, synchronous_timed_new_link/1,
		 remote_new/2, remote_new_link/2, remote_synchronous_new/2,
		 remote_synchronous_new_link/2, remote_synchronisable_new_link/2,
		 remote_synchronous_timed_new/2, remote_synchronous_timed_new_link/2,
		 construct/2, delete/1 ).


% Member method declarations.
-define( wooper_method_export, setEnableStatus/2, getEnableStatus/1,
		 sendResults/2 ).


% Static method declarations.
-define( wooper_static_method_export, get_producer_options/0 ).



% Type section.

-type producer_name() :: string().


% Describes the types of output expected from a producer:
-type producer_option() :: 'data_only' | 'plot_only' | 'data_and_plot'.

-type producer_options() :: producer_option() | [ producer_option() ].




% Describes the precise nature of a producer:
-type producer_nature() :: 'basic_probe' | 'virtual_probe' | 'undefined'.

-type producer_result() ::  { pid(), 'archive', binary() }
				  | { pid(), 'raw', { file_utils:bin_file_name(), binary() } }.


-export_type([ producer_name/0, producer_option/0, producer_options/0,
			 producer_nature/0, producer_result/0 ]).



% Allows to define WOOPER base variables and methods for that class:
-include("wooper.hrl").


% Must be included before class_TraceEmitter header:
-define(TraceEmitterCategorization,"Core.ResultManagement.ResultProducer").


% Allows to use macros for trace sending:
-include("class_TraceEmitter.hrl").


% For result_manager_name:
-include("class_ResultManager.hrl").



% The class-specific attributes of a result producer are:
%
% - result_manager_pid :: pid() is the PID of the result manager, necessary for
% a producer to declare its outputs before being fed with data
%
% - enabled_producer :: boolean() is a boolean telling whether the outputs of
% this producer have a chance of being of interest for the simulation; if false,
% then the producer may simply drop incoming samples, if not being asked by the
% data source(s) that is using it about its enable status: it is still better to
% have data sources stop sending samples instead of having the producer drop
% them on receiving



% Constructs a new result producer.
%
% ProducerName is the name of this producer, specified as a plain string.
%
-spec construct( wooper_state(), string() ) -> wooper_state().
construct( State, ProducerName ) ->

	% First the direct mother classes:
	TraceState = class_TraceEmitter:construct( State, ProducerName ),

	TrackerPid = class_InstanceTracker:get_local_tracker(),

	{ _SameState, BinName } = executeRequest( TraceState, getName ),

	TrackerPid ! { registerResultProducer, BinName, self() },

	% Then look-up the result manager, so that the actual producer child class
	% can send a notification to it later.
	%
	% As the deployment is synchronous, the manager must already be available
	% (no specific waiting to perform):
	%
	ResultManagerPid = basic_utils:get_registered_pid_for( ?result_manager_name,
														  global ),

	%?send_debug_fmt( TraceState, "Creating result producer '~s'.",
	%				[ ProducerName ] ),

	% Deferred reception for registerResultProducer:
	receive

		{ wooper_result, result_producer_registered } ->
			ok

	end,

	setAttributes( TraceState, [

		{ result_manager_pid, ResultManagerPid },

		% By default:
		{ enabled_producer, true }

								] ).




% Overridden destructor.
%
-spec delete( wooper_state() ) -> wooper_state().
delete( State ) ->

	% Class-specific actions:

	%?trace( "Deleting result producer." ),

	TrackerPid = class_InstanceTracker:get_local_tracker(),

	TrackerPid ! { unregisterResultProducer, self() },

	% Then call the direct mother class counterparts and allow chaining:
	State.




% Methods section.


% Sets the enable status for this producer.
%
% (oneway)
%
-spec setEnableStatus( wooper_state(), boolean() ) -> oneway_return().
setEnableStatus( State, NewStatus ) ->
	?wooper_return_state_only(
				 setAttribute( State, enabled_producer, NewStatus ) ).



% Returns true iff the outputs of that producer are enabled.
%
% (const request)
%
-spec getEnableStatus( wooper_state() ) -> request_return( boolean() ).
getEnableStatus( State ) ->
	?wooper_return_state_result( State, ?getAttr(enabled_producer) ).



% Sends the specified results to the caller (generally the result manager).
%
% Note: must be overridden by the actual result producer.
%
% It expected to return either:
%
% - { self(), archive, BinArchive } where BinArchive is a binary corresponding
% to a ZIP archive of a set of files (ex: data and command file)
%
% - { self(), raw, { BinFilename, BinContent } } where BinFilename is the
% filename (as a binary) of the transferred file, and BinContent is a binary of
% its content (ex: a PNG file, which should better not be transferred as an
% archive)
%
% The PID of the producer is sent, so that the caller is able to discriminate
% between multiple parallel calls.
%
% (const request, for synchronous yet concurrent operations)
%
-spec sendResults( wooper_state(), producer_options() ) ->
						 request_return( producer_result() ).
sendResults( _State, _Options ) ->
	throw( result_sending_not_implemented ).



% Static section.


% Returns a list of all possible generation-time options for result producers.
%
% (static)
%
-spec get_producer_options() -> [ producer_option() ].
get_producer_options() ->
	[ data_only, plot_only, data_and_plot ].
