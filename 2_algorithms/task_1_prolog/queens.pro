:- initialization(main, main).

queens(N, Qs) :-
    numlist(1, N, Rows),
    place(Rows, [], Qs).

place([], Placed, Placed).
place(Free, Placed, Qs) :-
    select(Row, Free, Rest),
    safe(Row, Placed, 1),
    place(Rest, [Row|Placed], Qs).

safe(_, [], _).
safe(Row, [Q|Qs], Dist) :-
    abs(Row - Q) =\= Dist,
    Dist1 is Dist + 1,
    safe(Row, Qs, Dist1).

print_board(N, Qs) :-
    forall(between(1, N, R),
           ( forall(member(Q, Qs),
                    ( Q =:= R -> write('Q ') ; write('. ') )),
             nl )).

main(Argv) :-
    ( Argv = [A|_] -> atom_number(A, N) ; N = 8 ),
    findall(Qs, queens(N, Qs), All),
    length(All, Count),
    format("N = ~w, solutions: ~w~n", [N, Count]),
    ( All = [First|_] ->
        format("First solution (row of the queen in each column): ~w~n~n", [First]),
        print_board(N, First)
    ; true ).
