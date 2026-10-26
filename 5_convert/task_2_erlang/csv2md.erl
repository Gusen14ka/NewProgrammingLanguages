#!/usr/bin/env escript
-mode(compile).

main(Args) ->
    In = case Args of [F | _] -> F; [] -> "data.csv" end,
    Out = case Args of [_, O | _] -> O; _ -> filename:rootname(In) ++ ".md" end,
    case file:read_file(In) of
        {ok, Bin} ->
            Rows = normalize(parse(unicode:characters_to_list(Bin))),
            Md = to_markdown(Rows),
            io:format("~ts", [Md]),
            ok = file:write_file(Out, unicode:characters_to_binary(Md)),
            io:format("~nRows: ~p, columns: ~p. Saved to ~s~n",
                      [length(Rows) - 1, length(hd(Rows)), Out]);
        {error, Reason} ->
            io:format("Cannot read ~s: ~p~n", [In, Reason]),
            halt(1)
    end.

parse(Chars) -> parse(Chars, [], [], [], false).

parse([$" | T], [], Row, Rows, false) -> parse(T, [], Row, Rows, true);
parse([$", $" | T], F, Row, Rows, true) -> parse(T, [$" | F], Row, Rows, true);
parse([$" | T], F, Row, Rows, true) -> parse(T, F, Row, Rows, false);
parse([C | T], F, Row, Rows, true) -> parse(T, [C | F], Row, Rows, true);
parse([$, | T], F, Row, Rows, false) -> parse(T, [], [lists:reverse(F) | Row], Rows, false);
parse([$\r, $\n | T], F, Row, Rows, false) -> parse([$\n | T], F, Row, Rows, false);
parse([$\n | T], F, Row, Rows, false) ->
    parse(T, [], [], [lists:reverse([lists:reverse(F) | Row]) | Rows], false);
parse([C | T], F, Row, Rows, false) -> parse(T, [C | F], Row, Rows, false);
parse([], [], [], Rows, _) -> lists:reverse(Rows);
parse([], F, Row, Rows, _) -> lists:reverse([lists:reverse([lists:reverse(F) | Row]) | Rows]).

normalize(Rows) ->
    NonEmpty = [R || R <- Rows, R =/= [[]]],
    Width = lists:max([length(R) || R <- NonEmpty]),
    [[cell(C) || C <- R ++ lists:duplicate(Width - length(R), "")] || R <- NonEmpty].

cell(Text) ->
    Escaped = lists:flatmap(fun($|) -> "\\|"; ($\n) -> "<br>"; ($\r) -> ""; (C) -> [C] end, Text),
    string:trim(Escaped).

is_number_cell(S) ->
    case {string:to_float(S), string:to_integer(S)} of
        {{_, []}, _} -> true;
        {_, {_, []}} -> true;
        _ -> false
    end.

to_markdown([Header | Body]) ->
    Columns = lists:zip(lists:seq(1, length(Header)), Header),
    Info = [begin
                Col = [lists:nth(I, R) || R <- Body],
                Numeric = Col =/= [] andalso lists:all(fun is_number_cell/1, [C || C <- Col, C =/= ""]),
                W = lists:max([3, string:length(H) | [string:length(C) || C <- Col]]),
                {W, Numeric}
            end || {I, H} <- Columns],
    Line = fun(Cells) ->
                   Parts = [pad(C, W, Num) || {C, {W, Num}} <- lists:zip(Cells, Info)],
                   "| " ++ lists:join(" | ", Parts) ++ " |\n"
           end,
    Sep = "|" ++ lists:join("|", [case Num of
                                      true -> lists:duplicate(W + 1, $-) ++ ":";
                                      false -> ":" ++ lists:duplicate(W + 1, $-)
                                  end || {W, Num} <- Info]) ++ "|\n",
    lists:flatten([Line(Header), Sep | [Line(R) || R <- Body]]).

pad(Text, Width, true) -> lists:duplicate(Width - string:length(Text), $\s) ++ Text;
pad(Text, Width, false) -> Text ++ lists:duplicate(Width - string:length(Text), $\s).
