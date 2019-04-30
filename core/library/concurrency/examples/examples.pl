:- module(_, [main/0], [datafacts]).

:- use_module(library(streams)).
:- use_module(library(concurrency)).
:- use_module(library(format)).
:- use_module(library(random)).
:- use_module(library(system)).
:- use_module(library(lists)).

main:-
        display_message("Creating agents"),
        agent_creation(10),
        display_message("Waiting for an agent to finish"),
        wait_for_agent,
        display_message("Waiting for remote failing goal"),
        wait_for_failure,
        display_message("Asking a remote agent for backtracking"),
        rem_back,
        display_message("Cutting the execution in a remote agent"),
        rem_cut,
        display_message("Starting a daemon with a new thread per query"),
        daemon(10),
        display_message("Waiting for facts"),
        wait_facts,
        display_message("Two-way communication using the database"),
        two_way,
        display_message("Add the numbers from 1 to N using two threads"),
        count(2000),
        display_message("The 5 philosophers"),
        philo_start(100),
        display_message("All examples finished!").



display_message(S):-
        display('------------------------------------------------------'),
        nl,
        format("~s~n", S),
        display('------------------------------------------------------'),
        nl.

agent_creation(0):-
        pause(1).
agent_creation(N):-
        eng_call(pause(1), create, create),
        N1 is N - 1,
        agent_creation(N1).



%% Start, try waiting several times, release.

status:-
	display('-------------------------------------------'),
	nl,
	eng_status.

% Start goal, wait for its completion

wait_for_agent:-
	eng_call(pause(5), create, create, Id),
	eng_wait(Id),
	eng_release(Id).


%% Failure of remote goals do not affect locally.   The wam is 
%% released immediately, but the goal definition remains until we free it.

wait_for_failure:-
	eng_call(fail, create, create, Id),
	eng_wait(Id),
	eng_release(Id).


%% Backtracking in separate thread

:- concurrent finished/0.

rem_back:-
	eng_call(do_append_notify, create, self, Id),
	repeat,
	eng_backtrack(Id, create),
        eng_wait(Id),
	retract_fact_nb(finished),
	eng_release(Id).

do_append_notify:- 
        L =  [1,2,3,4,5,6],
	append(X, Y, L),
	display(append(X, Y, L)),
	nl.
do_append_notify:- asserta_fact(finished).


%% Cut in backtracking

rem_cut:-
	eng_call(do_append_notify, create, create, Id),
	eng_wait(Id),
	eng_cut(Id),
	\+ eng_backtrack(Id, self),
	eng_release(Id).



%% A possible skeleton of a daemon.  A thread is launched and
%% receives queries.  Every query is just a number, generated by the
%% daemon itself, but which could come from, say, a socket connection.
%% When the query arrives a process is launched.  This process executes
%% (concurrently) the server code, which just prints out its thread
%% number and which query arrived.  Simultaneously, the main daemon is
%% "listening" for more queries, actually implementing a loop.  After
%% a given number of queries is receive, the initial damon dies.


daemon(0):- pause(2).
daemon(N):-
        N > 0,
        wait_for_query(Query),
        eng_call(daemon_handler(Query), create, create),
        N1 is N - 1,
        daemon(N1).

daemon_handler(X):- 
        display('daemon received query '),
        display(X),
        nl.

wait_for_query(Q):-
        pause(1),
        random(Q).



%% Threads can communicate and synchronize using facts: a thread
%% will wait for concurrent facts to appear.  The thread is suspended
%% and does not waste cpu.

:- concurrent proceed/1.

wait_facts:-
        eng_call(wait_for_a_fact, create, create),
        eng_call(wait_for_a_fact, create, create),
        eng_call(wait_for_a_fact, create, create),
        pause(1),
        asserta_fact(proceed(1)),
        pause(1),
        asserta_fact(proceed(2)),
        pause(1),
        asserta_fact(proceed(3)),
        pause(1).


wait_for_a_fact:-
        retract_fact(proceed(X)),
        display(proceeding(X)), 
        nl.

        
% Two-way communication: a concurrent goal produces tokens, which are
% consumed by another concurrent goal, which in turn produces another
% token which is brought back to the initial producer.


:- concurrent go_token/1, return_token/1. 

number_of_tokens(2000).

two_way:-
        number_of_tokens(N),
        p19(N).


p19(NTokens):-
        retractall_fact(go_token(_)),
        retractall_fact(return_token(_)),
        eng_call(token_return, create, create, GId1),
        eng_call(token_go, create, create, GId2),
        asserta_fact(go_token(NTokens)),  % This actually triggers execution...
        eng_wait(GId1),
        eng_release(GId1),
        eng_wait(GId2),
        eng_release(GId2).

token_go:-
        retract_fact(go_token(What)),
        Answ is What - 1,
        assertz_fact(return_token(Answ)),
        Answ = 0.

token_return:-
        repeat,
        retract_fact(return_token(What)),
        assertz_fact(go_token(What)),
        What = 0.



% add the numbers from 1 to N.  One worker writes down facts for the
% numbers, the other reads them and adds.  Note the cuts after
% retraction.

:- concurrent counter/1.

count(N):-
        retractall_fact(counter(_)),
        eng_call(generate_numbers(N), create, create),
        eng_call(sum_up_numbers, create, create, Id2),
        eng_wait(Id2),
        eng_release(Id2),
        retract_fact(counter(Res)),
        display(result(Res)), nl.

generate_numbers(0):-
        assertz_fact(counter(0)).
generate_numbers(N):-
        N > 0,
        assertz_fact(counter(N)),
        N1 is N - 1,
        generate_numbers(N1).

sum_up_numbers:-
        retract_fact(counter(CurrNum)), !,
        sum_them_up(CurrNum, 0, Res),
        asserta_fact(counter(Res)).

sum_them_up(0, SoFar, SoFar).
sum_them_up(Current, Added, Res):-
        Current > 0,
        NewAdded is Current + Added,
        retract_fact(counter(NewCurrent)), !,
        sum_them_up(NewCurrent, NewAdded, Res).
        



 %% The 5 philosophers.  Yes, the code below does precisely what I told
 %% you not to do: wait for clauses of a predicate others were modifying,
 %% but anyway coding it like this is easier.  I could assign a different
 %% predicate to every fork, but it would not add up to readability.  Yes,
 %% it goes slow.


:- concurrent
        start_philosophers/0,
        f1/0, f2/0, f3/0, f4/0, f5/0,
        room/0.

philo_start(Cicles):-
        launch_philosophers(5, Cicles, GoalIds),
        asserta_fact(start_philosophers),
        wait_and_release_goals(GoalIds),
        retract_fact_nb(start_philosophers).

launch_philosophers(0, _Cicles, []).
launch_philosophers(N, Cicles, [G|Gs]):- 
        N > 0,
        eng_call(philo(N, Cicles), create, create, G),
        N1 is N - 1,
        launch_philosophers(N1, Cicles, Gs).

philo(N, Time):-
        current_fact(start_philosophers),
        philosopher(N, Time).
philosopher(_N, 0).
philosopher(Fork, Time):-
        Time > 0,
        NextTime is Time - 1,
        NextFork is (Fork mod 5) + 1 ,
        fork(Fork, F1),
        fork(NextFork, F2),
        retract_fact(room),
        retract_fact(F1),
        retract_fact(F2),
        some_time_eating(100),
        assertz_fact(F1),
        assertz_fact(F2),
        assertz_fact(room),
        philosopher(Fork, NextTime).

some_time_eating(0).
some_time_eating(N):- 
        N > 0,
        N1 is N - 1,
        some_time_eating(N1).

fork(1,f1).
fork(2,f2).
fork(3,f3).
fork(4,f4).
fork(5,f5).

f1.
f2.
f3.
f4.
f5.

room.
room.
room.
room.

wait_and_release_goals([]).
wait_and_release_goals([Id|Ids]):-
        eng_wait(Id),
        eng_release(Id),
        wait_and_release_goals(Ids).
