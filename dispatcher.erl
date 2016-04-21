%arreglar: mensaje con enter solo la pudre


-module(dispatcher).
-compile(export_all).
-import(random, [uniform/1, seed/1]).
-import(string, [tokens/2, to_integer/1, join/2]).
-import(lists, [nth/2, any/2, foreach/2]).

start(Puerto) ->
    {ok, ListenSocket} = gen_tcp:listen(Puerto, [{active, false}]),
    ListaWorkers = [spawn(workers, initWorker, []), spawn(workers, initWorker, []), spawn(workers, initWorker, []), spawn(workers, initWorker, []), spawn(workers, initWorker, [])],
    lists:foreach(fun(W) -> W ! {listaworkers , ListaWorkers} end, ListaWorkers),
    proc_dispatcher(ListenSocket, ListaWorkers).

proc_dispatcher(ListenSocket, ListaWorkers) ->
    {ok, Socket} = gen_tcp:accept(ListenSocket),
    spawn(?MODULE, proc_socket, [Socket, ListaWorkers]),
    proc_dispatcher(ListenSocket, ListaWorkers).

proc_socket(Sock, ListaWorkers) ->
    random:seed(now()),
    W = lists:nth(random:uniform(4), ListaWorkers),
    io:format("Worker ~p~n", [W]),
    proc_socket2(Sock, W).

proc_socket2(Sock, Worker) ->
    case gen_tcp:recv(Sock, 0) of
        {ok, Msg} ->
            {Res, Parceado} = validar(lists:sublist(Msg, length(Msg))),
            if
                Res == ok ->
                    Worker ! {self(), tarea, Parceado},
                    receive
                       {Worker, close} -> gen_tcp:send(Sock, "OK" ++ [10, 0]), gen_tcp:close(Sock), exit(ok);
                       {Worker, Respuesta} -> gen_tcp:send(Sock, Respuesta ++ [10, 0])
                    end;
                Res == invalido -> gen_tcp:send(Sock, Parceado)
            end;
        {error, _} -> exit(ok)
    end,
    proc_socket2(Sock, Worker).

validar(Mensajee) ->
    ComandosValidos = ["CON", "LSD", "DEL", "CRE", "OPN", "WRT", "REA", "CLO", "BYE"],
    Mensaje = lists:filter(fun(C) -> not(lists:member(C, [0, 10, 13])) end, Mensajee),
    if
        Mensaje == [] -> {invalido, "ERROR Numero incorrecto de argumentos" ++ [10, 0]};
        Mensaje /= [] ->
            [H | T] = string:tokens(Mensaje, " "),
            case lists:any(fun(X) -> H == X end, ComandosValidos) of
                true -> % Si la primer palabra es un comando valido, nos fijamos cual.
                    case H of
                        "CON" -> 
                            if
                                length(T) == 0 -> {ok, {list_to_atom(H), []}};
                                length(T) /= 0 -> {invalido, "ERROR Numero incorrecto de argumentos" ++ [10, 0]}
                            end;
                        "LSD" ->
                            if
                                length(T) == 0 -> {ok, {list_to_atom(H), []}};
                                length(T) /= 0 -> {invalido, "ERROR Numero incorrecto de argumentos" ++ [10, 0]}
                            end;
                       "BYE" ->
                            if
                                length(T) == 0 -> {ok, {list_to_atom(H), []}};
                                length(T) /= 0 -> {invalido, "ERROR Numero incorrecto de argumentos" ++ [10, 0]}
                            end;
                        "DEL" ->
                            if
                                length(T) == 1 -> {ok, {list_to_atom(H), T}};
                                length(T) /= 1 -> {invalido, "ERROR Numero incorrecto de argumentos" ++ [10, 0]}
                            end;
                        "CRE" ->
                            if
                                length(T) == 1 -> {ok, {list_to_atom(H), T}};
                                length(T) /= 1 -> {invalido, "ERROR Numero incorrecto de argumentos" ++ [10, 0]}
                            end;
                       "OPN" ->
                            if
                                length(T) == 1 -> {ok, {list_to_atom(H), T}};
                                length(T) /= 1 -> {invalido, "ERROR Numero incorrecto de argumentos" ++ [10, 0]}
                            end;
                        "CLO" ->
                            case T of
                                ["FD" | TT] when length(TT) == 1 -> {Arg, _ } = string:to_integer(lists:nth(1, TT)), {ok, {list_to_atom(H), [Arg]}};
                                _ -> {invalido, "ERROR Argumentos Invalidos" ++ [10, 0]}
                            end;
                        "REA" ->
                            case T of
                                ["FD" | [SArg1 | ["SIZE" | [SArg2 | []]]]] -> {Arg1, _ } = string:to_integer(SArg1),
                                                                                    {Arg2, _ } = string:to_integer(SArg2),
                                                                                    {ok, {list_to_atom(H), [Arg1, Arg2]}};
                                _ -> {invalido, "ERROR Argumentos invalidos" ++ [10, 0]}
                            end;
                        "WRT" ->
                            case T of
                                ["FD" | [SArg1 | ["SIZE" | [SArg2 | [HT | TT]]]]] -> {Arg1, _ } = string:to_integer(SArg1),
                                                                        {Arg2, _ } = string:to_integer(SArg2),
                                                                        Arg3 = string:join([HT | TT], " "),
                                                                        {ok, {list_to_atom(H), [Arg1, Arg2, Arg3]}};
                                 _ -> {invalido, "ERROR Argumentos invalidos" ++ [10, 0]}
                            end                    
                    end;
                false ->
                    {invalido, "ERROR Comando Invalido" ++ [10, 0]}
            end
    end.

