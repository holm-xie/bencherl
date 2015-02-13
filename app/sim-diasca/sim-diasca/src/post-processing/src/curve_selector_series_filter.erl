% Copyright (C) 2011-2014 EDF R&D

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



% This series filter allows to select which curves are to be kept among the ones
% defined in a time series, and to reorder them (write them in the specified
% order in the corresponding data file).
%
-module(curve_selector_series_filter).


-export([ create/3 ]).


% To avoid unused notifications:
-export([ selection_to_string_as_list/3 ]).


-type curve_index() :: basic_utils:count().



% We specify at creation:
%
% - the name of the data file to produce
%
% - an ordered list of curve indexes, which tells which curves are to be kept,
% and in which order; for example if CurveNames = [ "Foo", "Bar", "Baz", "Other"
% ], then to generate a time series containing only [ "Baz", "Bar" ] (in that
% order) following indexes list should be specified: [ 3, 2 ]
%
-spec create( string(), [ string() ], [ curve_index() ] ) ->
					'ok' | { 'onFilterEnded', pid() }.
create( SeriesName, CurveNames, CurveIndexList ) ->

	check_curve_indexes( CurveIndexList, length(CurveNames) ),

	% List like: [ true, false, true ], telling that only curves #1 and #3 are
	% selected here:
	SelectionList = build_selection( CurveIndexList, length(CurveNames) ),

	TargetFilename = file_utils:convert_to_filename( SeriesName )
		++ "-selectioned.dat",

	io:format( "Among the curves ~s the ones corresponding to indexes ~p "
			   "will be written (in that order) in file '~s'.~n",
			   [ text_utils:string_list_to_string(CurveNames), CurveIndexList,
				 TargetFilename ] ),

	file_utils:remove_file_if_existing( TargetFilename ),

	File = file_utils:open( TargetFilename,
						   [ raw, write, delayed_write, exclusive ] ),

	SelectionString = selection_to_string( CurveNames, SelectionList ),

	file_utils:write( File, io_lib:format(
			"# Created by the selector filter at ~s,~n"
			"# operating on the '~s' time series,~n"
			"# with following selection filter:~n"
			"# ~p.~n~n~s",
			[ basic_utils:get_textual_timestamp(), SeriesName,
			  SelectionList, SelectionString ] ) ),

	filter_loop( TargetFilename, File, SelectionList ).



% Ensures that specified curve indexes are valid.
%
check_curve_indexes( [], _CurveCount ) ->
	ok;

check_curve_indexes( [ CurveIndex | T ], CurveCount )
  when is_integer(CurveIndex) andalso CurveIndex > 0
	   andalso CurveIndex =< CurveCount ->
	check_curve_indexes( T, CurveCount );

check_curve_indexes( [ CurveIndex | _T ], CurveCount ) ->

	io:format( "Error, '~p' is an invalid curve index, it must be an integer "
			   "in [1..~B].~n", [ CurveIndex, CurveCount ] ),

	erlang:halt( 10 ).




% Returns a list of booleans telling, for each position,(k) whether curve k is
% selected.
%
build_selection( CurveIndexList, CurveCount ) ->
	build_selection( CurveIndexList, _CurrentIndex=1, _MaxIndex=CurveCount+1,
					_Acc=[] ).


build_selection( _CurveIndexList, _CurrentIndex=MaxIndex, MaxIndex, Acc ) ->
	lists:reverse( Acc );

build_selection( CurveIndexList, CurrentIndex, MaxIndex, Acc ) ->
	IsWanted = lists:member( CurrentIndex, CurveIndexList ),
	build_selection( CurveIndexList, CurrentIndex+1, MaxIndex, [IsWanted|Acc] ).



filter_loop( TargetFilename, File, SelectionList ) ->

	receive

		{ setSample, [ Tick, SampleList ] } ->

			case selector_helper( SelectionList, SampleList ) of

				{} ->
					ok;

				T ->
					class_Probe:write_row( File, Tick, T )

			end,
			filter_loop( TargetFilename, File, SelectionList );


		{ onEndOfSeriesData, ScannerPid } ->
			ok = file:write( File, "\n# End of selector filter writing." ),
			file_utils:close( File),
			io:format( "File '~s' has been generated by the "
					   "curve selector filter.~n~n", [ TargetFilename ] ),
			ScannerPid ! { onFilterEnded, self() };

		delete ->
			ok;

		{ getProducedFilename, [], ScannerPid } ->
			ScannerPid ! { wooper_result, TargetFilename },
			filter_loop( TargetFilename, File, SelectionList );

		Other ->
			throw( { unexpected_series_filter_message, Other } )

	end.



selector_helper( SelectionList, SampleList ) ->
	selector_helper( SelectionList, SampleList, _Acc=[] ).


selector_helper( _SelectionList=[], _SampleList=[], Acc ) ->
	list_to_tuple( lists:reverse(Acc) );

selector_helper( _SelectionList=[ true | TSel ], _SampleList=[ V | TSam ],
				 Acc ) ->
	selector_helper( TSel, TSam, [ V | Acc ] );

% checking it is a boolean indeed:
selector_helper( _SelectionList=[ false | TSel ], _SampleList=[ _V | TSam ],
				 Acc ) ->
	selector_helper( TSel, TSam, Acc ).



selection_to_string( CurveNames, SelectionList ) ->

	%io:format( "selection_to_string: CurveNames=~p "
	%		  "and SelectionList=~p~n", [ CurveNames, SelectionList ] ),

	{ Selected, Rejected } = sort_selected_curves( CurveNames, SelectionList,
												   { _AccSel=[], _AccRej=[] } ),

	%selection_to_string( CurveNames, SelectionList, _Acc=[] ).

	Bullet= "# - ",

	SelString = case Selected of

		[] ->
			"No curve was selected.";

		_ ->
			NumberedSelected = number_selected( Selected, _Count=1, _Acc=[] ),
			"Following curves were selected:"
				++ text_utils:string_list_to_string( NumberedSelected, Bullet )

	end,

	RejString = case Rejected of

		[] ->
			"No curve was rejected.";

		_ ->
			"Following curves were rejected:"
				++ text_utils:string_list_to_string( Rejected, Bullet )

	end,

	io_lib:format( "# ~s~n# ~s~n", [ SelString, RejString ] ).



% Adds a comment specifying the number of each selected curve.
%
number_selected( _Selected=[], _Count, Acc ) ->
	lists:reverse( Acc );

number_selected( _Selected=[ S | T ], Count, Acc ) ->
	number_selected( T, Count + 1, [ io_lib:format( "~s (curve #~B here)",
													[ S, Count ] ) | Acc ] ).



sort_selected_curves( _CurveNames=[], _SelectionList=[],
					  { AccSel, AccRej } ) ->
	{ lists:reverse( AccSel ), lists:reverse( AccRej ) };

sort_selected_curves( [ CurveName | Tc ], [ true | Ts ], { AccSel, AccRej } ) ->
	sort_selected_curves( Tc, Ts, { [ CurveName | AccSel ], AccRej } );

sort_selected_curves( [ CurveName | Tc ], [ false | Ts ],
					  { AccSel, AccRej } ) ->
	sort_selected_curves( Tc, Ts, { AccSel, [ CurveName | AccRej ] } ).



% Lists all curves in turn and specifies whether it was selected.
% (not currently used anymore)
%
-spec selection_to_string_as_list( [ string() ], [ boolean() ],
								   [ string() ] ) -> any().
selection_to_string_as_list( _CurveNames=[], _SelectionList=[], Acc ) ->
	CommentList = [ E || E <- lists:reverse( Acc ) ],
	text_utils:string_list_to_string( CommentList, _Bullet= "# - " );

selection_to_string_as_list( [ CurveName | Tc ], [ true | Ts ], Acc ) ->
	CurveString = io_lib:format( "curve '~s' (p was selected", [ CurveName ] ),
	selection_to_string_as_list( Tc, Ts, [ CurveString | Acc ] );

selection_to_string_as_list( [ CurveName | Tc ], [ false | Ts ], Acc ) ->
	CurveString = io_lib:format( "curve '~s' was not selected", [ CurveName ] ),
	selection_to_string_as_list( Tc, Ts, [ CurveString | Acc ] ).
