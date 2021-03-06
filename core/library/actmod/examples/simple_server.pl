:- module(simple_server, [population/2, shutdown/0], [actmod]).

% A simple server (an active module)

:- actmod_reg_protocol(filebased).
:- dist_node.

population(belgium,9).
population(france,52).
population(germany,80).
population(italy,60).
population(spain,42).
population(sweden,8).
population(united_kingdom,55).

% NOTE: must be called with actmod_cast/1 (no return)
shutdown :- halt.
