-module(synch).
-compile(export_all).

lockMgr(Estado) ->
    if  Estado == lockeado ->
        receive
            {Pid, tryy} -> Pid ! {self(), false}, Nuevo_estado = lockeado;
            {Pid, unlock} -> Pid ! {self(), ok}, Nuevo_estado = unlockeado;
            {Pid, destroy} -> Pid !{self(), ok}, Nuevo_estado = lockeado, exit(ok)
        end;
    Estado == unlockeado ->
        receive
            {Pid, tryy} -> Pid ! {self(), true}, Nuevo_estado = lockeado;
            {Pid, lock} -> Pid ! {self(), ok}, Nuevo_estado = lockeado;
            {Pid, unlock} -> io:format("warning, ~p intento deslockear un lock que no lockeo previamente.~n", [Pid]),  Pid ! {self(), {error, notlocked}}, Nuevo_estado = lockeado;
            {Pid, destroy} -> Pid !{self(), ok}, Nuevo_estado = lockeado, exit(ok)
        end
    end,
    lockMgr(Nuevo_estado).
lock (L) ->
    L ! {self(), lock},
    receive {L, ok} -> ok end.

tryLock(L) ->
    L ! {self(), tryy},
    receive {L, Res} -> Res end.

unlock (L) ->
    L ! {self(), unlock},
    receive {L, Result} -> Result end.
createLock () ->
    spawn(?MODULE, lockMgr, [unlockeado]).
destroyLock (L) ->
    L ! {self(), destroy},
    receive {L, ok} -> ok end.


semMgr(Num) ->
    if Num > 1 ->
        receive
            {Pid, p} -> Nuevo_num = Num -1, Pid ! {self(), ok};
            {Pid, destroy} -> Pid !{self(), ok}, Nuevo_num = 1337, exit(ok)
        end;
    Num < 2 ->
        receive
            {Pid, v} -> Nuevo_num = Num + 1, Pid ! {self(), ok};
            {Pid, destroy} -> Pid !{self(), ok}, Nuevo_num = 1337, exit(ok)
        end
    end,
    semMgr(Nuevo_num).

createSem (N) ->
    spawn(?MODULE, semMgr, [N]).

destroySem (S) ->
    S ! {self(), destroy},
    receive {S, ok} -> ok end.

semP (S) ->
    S ! {self(), p},
    receive {S, ok} -> ok end.
semV (S) ->
    S ! {self(), v},
    receive {S, ok} -> ok end.

f (L,W) -> lock(L),
  %   regioncritica(),
  io:format("uno ~p~n",[self()]),
  io:format("dos ~p~n",[self()]),
  io:format("tre ~p~n",[self()]),
  io:format("cua ~p~n",[self()]),
  unlock(L),
  W!finished.

waiter (L,0)  -> destroyLock(L);
waiter (L,N)  -> receive finished -> waiter(L,N-1) end.

waiter_sem (S,0)  -> destroySem(S);
waiter_sem (S,N)  -> receive finished -> waiter_sem(S,N-1) end.


testLock () -> L = createLock(),
  W=spawn(?MODULE,waiter,[L,3]),
  spawn(?MODULE,f,[L,W]),
  spawn(?MODULE,f,[L,W]),
  spawn(?MODULE,f,[L,W]),
  ok.
 
sem (S,W) -> 
  semP(S),
  %regioncritica(), bueno, casi....
  io:format("uno ~p~n",[self()]),
  io:format("dos ~p~n",[self()]),
  semV(S),
  W!finished.

testSem () -> S = createSem(2), % a lo sumo dos usando io al mismo tiempo
  W=spawn(?MODULE,waiter_sem,[S,5]),
  spawn(?MODULE,sem,[S,W]),
  spawn(?MODULE,sem,[S,W]),
  spawn(?MODULE,sem,[S,W]),
  spawn(?MODULE,sem,[S,W]),
  spawn(?MODULE,sem,[S,W]).
