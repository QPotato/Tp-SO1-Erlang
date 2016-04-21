%archivo: {nombre, host, contenido}
%archivo abierto: {FD, puntero, archivo}
%sesion: {Pid, [archivos abiertos]} % Implica que CLO tiene que guardar cambios a la lista de archivos del worker que tiene el archivo

%worker:
%   -lista de archivos
%   -lista de sesiones abiertas (con archivos abiertos)
%   -referencia a los otros workers
%   -Ultima ID que asigno
%   -Ultimo FD que asigno
% El worker no tiene constancia de que archivos suyos estan abiertos por otros, pero cada vez que quiere abrir un archivo, aunque sea de el, le consulta a todos que no este abierto.

-module(workers).
-compile(export_all).
-import(lists, [filter/2, foreach/2, any/2, flatten/1, delete/2, keyfind/3, keydelete/3, keyreplace/4, map/2, max/1, sublist/3, sublist/2]).
-import(synch, [tryLock/1, unlock/1]).

initWorker() ->
    receive {listaworkers, Lista} -> ListaWorkers = filter(fun(X) -> X /= self() end, Lista) end,
    put(workers, ListaWorkers),
    put(sesiones, []),
    put(archivos, []),
    put(maxID, 0),
    put(maxFD, 0),
    put(lock, synch:createLock()),
    put(o, true),
    worker().

% Labura
worker() ->
    Sesiones = get(sesiones),
    Archivos = get(archivos),
    MaxFD = get(maxFD),
    MaxID = get(maxID),
    receive
        {Pid, tarea, Tarea} ->
            case Tarea of
                {'CON', []} ->  case estaConectado(Pid, Sesiones) of
                                    true -> Pid !{self(), "ERROR Ya conectado."},
                                        NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD;
                                    false -> Nueva = {Pid, []},
                                        ID = nuevaID(MaxID),
                                        NSesiones = [Nueva | Sesiones],
                                        NMaxID = ID + 1,
                                        NArchivos = Archivos, NMaxFD = MaxFD,
                                        Pid !{self(), "OK ID " ++ integer_to_list(ID)}
                                end;
                {'BYE', []} ->  case estaConectado(Pid, Sesiones) of
                                    true -> {_Pid, Abiertos} = keyfind(Pid, 1, Sesiones),
                                        NArchivos = cerrarTodo(Abiertos, Archivos),
                                        NSesiones = keydelete(Pid, 1, Sesiones), NMaxID = MaxID, NMaxFD = MaxFD,
                                        Pid ! {self(), close};
                                    false -> Pid ! {self(), "ERROR no conectado."},
                                        NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD
                                end;
                    
                {'LSD', []} ->  case estaConectado(Pid, Sesiones) of
                                    true -> Pid ! {self(),  "OK" ++ flatten(map(fun({N, _, _}) -> [" "] ++ N end, listarArchivos(Archivos)))};
                                    false -> Pid ! {self(), "ERROR no conectado."}
                                end,
                                NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD;
                    
                {'CRE', [Nombre]} -> case estaConectado(Pid, Sesiones) of
                                        true -> L1 = listarArchivos(Archivos),
                                            case existe(Nombre, L1) of
                                                true -> Pid ! {self(), "ERROR el archivo ya existe."},
                                                    NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD;
                                                false -> Pid ! {self(), "OK"},
                                                    Nuevo = {Nombre, self(), []},
                                                    NArchivos = [Nuevo | Archivos], NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD
                                            end;
                                        false -> Pid ! {self(), "ERROR no conectado."},
                                            NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD
                                    end;
                {'DEL', [Nombre]} -> case estaConectado(Pid, Sesiones) of
                                        true -> L1 = listarArchivos(Archivos),
                                                case existe(Nombre, L1) of
                                                    true -> L2 = listarAbiertos(Sesiones),
                                                            case existe2(Nombre, L2) of
                                                                true -> Pid ! {self(), "ERROR archivo abierto."},
                                                                    NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD;
                                                                false -> NArchivos = borrar(Nombre, L1, Archivos),
                                                                        NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD,
                                                                        Pid ! {self(), "OK"}
                                                            end;
                                                    false -> Pid ! {self(), "ERROR el archivo no existe."},
                                                        NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD
                                                end;
                                        false -> Pid ! {self(), "ERROR no conectado."},
                                            NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD
                                    end;
                {'OPN', [Nombre]} -> case estaConectado(Pid, Sesiones) of
                                        true -> L1 = listarArchivos(Archivos),
                                                case existe(Nombre, L1) of
                                                    true -> L2 = listarAbiertos(Sesiones),
                                                            case existe2(Nombre, L2) of
                                                                true -> Pid ! {self(), "ERROR el archivo ya esta abierto."}, NArchivos = Archivos, NMaxID = MaxID, NSesiones = Sesiones, NMaxFD = MaxFD;
                                                                false -> {NSesiones, FD} = abrirArchivo(Pid, Nombre, MaxFD, Sesiones, L1),
                                                                        NMaxFD = FD + 1,
                                                                        NArchivos = Archivos, NMaxID = MaxID,
                                                                        Pid ! {self(), "OK FD " ++ integer_to_list(FD)}
                                                            end;
                                                    false -> Pid ! {self(), "ERROR el archivo no existe."}, NArchivos = Archivos, NMaxID = MaxID, NSesiones = Sesiones, NMaxFD = MaxFD
                                                end;
                                        false -> Pid ! {self(), "ERROR no conectado."}, NArchivos = Archivos, NMaxID = MaxID, NSesiones = Sesiones, NMaxFD = MaxFD
                                    end;
                {'CLO', [Fd]} -> case estaConectado(Pid, Sesiones) of
                                        true -> case loAbrio(Fd, Pid, Sesiones) of
                                                    true -> {NArchivos, NSesiones} = cerrar(Fd, Pid, Archivos, Sesiones),
                                                            NMaxID = MaxID, NMaxFD = MaxFD,
                                                            Pid ! {self(), "OK"};
                                                    false -> NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD,
                                                            Pid ! {self(), "ERROR la sesion no abrio un archivo con ese FD"}
                                                end;
                                        false -> Pid ! {self(), "ERROR no conectado."},
                                            NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD
                                end;
                {'REA', [Fd, Size]} -> case estaConectado(Pid, Sesiones) of                                    %CREO QUE ANDA!!!
                                           true -> case loAbrio(Fd, Pid, Sesiones) of
                                               true -> {Buffer, NSesiones} = leer(Pid, Fd, Size, Sesiones),
                                                   NMaxID = MaxID, NMaxFD = MaxFD, NArchivos = Archivos,
                                                   Pid ! {self(), "OK SIZE " ++ integer_to_list(length(Buffer)) ++" "++ Buffer};
                                               false -> NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD,
                                                   Pid ! {self(), "ERROR la sesion no abrio un archivo con ese FD"}
                                               end;
                                           false -> Pid ! {self(), "ERROR no conectado."},
                                               NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD
                                       end;
                {'WRT', [Fd, Size, Buffer]} -> case estaConectado(Pid, Sesiones) of                                    %CREO QUE ANDA!!!
                                                      true -> case loAbrio(Fd, Pid, Sesiones) of
                                                          true -> NSesiones = escribir(Pid, Fd, Size, Buffer, Sesiones),
                                                                    NArchivos = Archivos, NMaxID = MaxID, NMaxFD = MaxFD,
                                                                    Pid ! {self(), "OK"};
                                                          false -> NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD,
                                                              Pid ! {self(), "ERROR la sesion no abrio un archivo con ese FD"}
                                                          end;
                                                      false -> Pid ! {self(), "ERROR no conectado."},
                                                          NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD
                                               end
            end;
        {Pid, ayuda, Tarea} ->
            case Tarea of
                'LSD' ->
                    Pid ! {self(), Archivos},
                    NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD;
                abiertos ->
                    Pid ! {self(), listarAbiertosLocales(Sesiones)},
                    NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD;
                id ->
                    Pid ! {self(), MaxID},
                    NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD;
                fd ->
                    Pid ! {self(), MaxFD},
                    NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD;
                {borrar, Nombre} ->
                    NArchivos = keydelete(Nombre, 1, Archivos),
                    NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD,
                    Pid ! {self(), ok};
                {cerrar, {Nombre, Host, Contenido}} -> 
                    NArchivos = keyreplace(Nombre, 1, Archivos, {Nombre, Host, Contenido}),
                    NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD,
                    Pid ! {self(), ok}
            end
    end,
    put(sesiones, NSesiones),
    put(archivos, NArchivos),
    put(maxFD, NMaxFD),
    put(maxID, NMaxID),
    worker().

%Devuelve la lista de archivos de todos los workers
listarArchivos(ArchivosLocales) ->
    flatten([ArchivosLocales | pedirAyuda('LSD')]).
    
% Devuelve true sii el Pid hizo un CON
estaConectado(Pid, Sesiones) ->
    any(fun({P, _}) -> P == Pid end, Sesiones).
    
% Devuelve true sii el archivo Nombre está en ListaArchivos
existe(Nombre, ListaArchivos) ->
    any(fun({N, _, _}) -> N == Nombre end, ListaArchivos).
    
% Devuelve true sii si Nombre está en ListaArchivosAbiertos
existe2(Nombre, ListaArchivosAbiertos) ->
    any(fun({_, _, {N, _, _}}) -> N == Nombre end, ListaArchivosAbiertos).
    
% Devuelve la lista de archivos abiertos localmente
listarAbiertosLocales(ListaSesiones) -> 
    flatten(map(fun({_, Archivos}) -> Archivos end, ListaSesiones)).
    
% Devuelve la lista de archivos abiertos por todos los workers
listarAbiertos(ListaSesiones) ->
    V = flatten(pedirAyuda(abiertos)),
    listarAbiertosLocales(ListaSesiones) ++ V.
    
% Devuelve el máximo MaxID entre todos los workers
nuevaID(MaxLocal) ->
    max([MaxLocal | pedirAyuda(id)]).

% Devuelve el máximo MaxFD entre todos los workers
nuevoFD(MaxLocal) ->
    max([MaxLocal | pedirAyuda(fd)]).

% Abre el archivo Nombre y devuelve {NSesiones, NMaxFD}
abrirArchivo(Pid, Nombre, MaxFD, ListaSesiones, ListaArchivos) ->
    FD = nuevoFD(MaxFD),
    {_, ListaAbiertos} = keyfind(Pid, 1, ListaSesiones),
    Archivo = keyfind(Nombre, 1, ListaArchivos),
    H = {Pid, [{FD, 1, Archivo} | ListaAbiertos]},
    {keyreplace(Pid, 1, ListaSesiones, H), FD}.

% Devuelve true si el usuario con ese Pid abrió el archivo con ese FD
loAbrio(FD, Pid, ListaSesiones) ->
    {_, Abiertos} = keyfind(Pid, 1, ListaSesiones),
    case keyfind(FD, 1, Abiertos) of
        false -> false;
        _ -> true
    end.

% Cierra un archivo guardando los cambios. Devuelve {NArchivos, NSesiones}
cerrar(FD, Pid, ListaArchivosLocales, ListaSesiones) ->
    {_, Abiertos} = keyfind(Pid, 1, ListaSesiones),
    {_, _, {Nombre, Host, Contenido}} = keyfind(FD, 1, Abiertos),
    case Host == self() of
        true ->
            NArchivos = keyreplace(Nombre, 1, ListaArchivosLocales, {Nombre, Host, Contenido});
        false ->
            pedirAyuda(Host, {cerrar, {Nombre, Host, Contenido}}),
            NArchivos = ListaArchivosLocales
    end,
    Sesion = {Pid, keydelete(FD, 1, Abiertos)},
    NSesiones = keyreplace(Pid, 1, ListaSesiones, Sesion),
    {NArchivos, NSesiones}.
            

% Borra un archivo, devuelve NArchivos
borrar(Nombre, ListaArchivos, ListaArchivosLocales) ->
    {_, Host, _} = keyfind(Nombre, 1, ListaArchivos),
    case Host == self() of
        true ->
            keydelete(Nombre, 1, ListaArchivosLocales);
        false ->
            pedirAyuda(Host, {borrar, Nombre}),
            ListaArchivosLocales
    end.

% Guarda los cambios de una lista de archivos. Devuelve NArchivos.
cerrarTodo([], ListaArchivosLocales) ->
    ListaArchivosLocales;
cerrarTodo([{_Fd, _Pt, {Nombre, Host, Contenido}} | T], ListaArchivosLocales) ->
    case Host == self() of
        true ->
            NArchivos = keyreplace(Nombre, 1, ListaArchivosLocales, {Nombre, Host, Contenido});
        false ->
            pedirAyuda(Host, {cerrar, {Nombre, Host, Contenido}}),
            NArchivos = ListaArchivosLocales
    end,
    cerrarTodo(T, NArchivos).

% Devuelve lo leido y la nueva lista de sesiones actualizando el puntero del archivo abierto
leer(Pid, FD, Sz, ListaSesiones) ->
    {_, Abiertos} = keyfind(Pid, 1, ListaSesiones),
    {FDD, Pt, {Nombre, Host, Contenido}} = keyfind(FD, 1, Abiertos),
    {NPt, Buffer} = leerCaracteres(Contenido, Sz, Pt),
    Sesion = {Pid, keyreplace(FD, 1, Abiertos, {FDD, NPt, {Nombre, Host, Contenido}})},
    NSesiones = keyreplace(Pid, 1, ListaSesiones, Sesion),
    {Buffer, NSesiones}.

% Devuelve el puntero nuevo y lo leido
leerCaracteres(Texto, Cuantos, Desde) ->
	case Desde + Cuantos > length(Texto) of
        true -> Puntero = length(Texto) + 1;
        false -> Puntero = Desde + Cuantos
    end,
    Buff = sublist(Texto, Desde, Cuantos),
    {Puntero, Buff}.

% Devuelve NSesiones con el archivo modificado
escribir(Pid, FD, Sz, Buff, ListaSesiones) ->
    {_, Abiertos} = keyfind(Pid, 1, ListaSesiones),
    {FDD, Pt, {Nombre, Host, Contenido}} = keyfind(FD, 1, Abiertos),
    NContenido = escribirCaracteres(Contenido, Buff, Sz),
    Sesion = {Pid, keyreplace(FD, 1, Abiertos, {FDD, Pt, {Nombre, Host, NContenido}})},
    NSesiones = keyreplace(Pid, 1, ListaSesiones, Sesion),
    NSesiones.

% Devuelve el nuevo contenido del archivo (modo append).
escribirCaracteres(Texto, Buffer, Size) ->
    Texto ++ sublist(Buffer, Size).

pedirAyuda(Mensaje) ->
    L = get(lock),
    case tryLock(L) of
        true ->
            ListaWorkers = get(workers),
            foreach(fun(W) -> W ! {self(), ayuda, Mensaje} end, ListaWorkers),
            Res = [receive {W, ID} -> ID end || W <- ListaWorkers],
            unlock(L),
            Res;
        false ->
            responderAyuda(),
            pedirAyuda(Mensaje)
    end.
pedirAyuda(Pid, Mensaje) ->
    L = get(lock),
    case tryLock(L) of
        true ->
            Pid ! {self(), ayuda, Mensaje},
            receive {Pid, Respuesta} -> ok end,
            unlock(L),
            Respuesta;
        false ->
            responderAyuda(),
            pedirAyuda(Pid, Mensaje)
    end.
            
    

responderAyuda() ->
    Sesiones = get(sesiones),
    Archivos = get(archivos),
    MaxFD = get(maxFD),
    MaxID = get(maxID),
    receive
        {Pid, ayuda, Tarea} ->
                case Tarea of
                    'LSD' ->
                        Pid ! {self(), Archivos},
                        NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD;
                    abiertos ->
                        Pid ! {self(), listarAbiertosLocales(Sesiones)},
                        NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD;
                    id ->
                        Pid ! {self(), MaxID},
                        NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD;
                    fd ->
                        Pid ! {self(), MaxFD},
                        NArchivos = Archivos, NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD;
                    {borrar, Nombre} ->
                        NArchivos = keydelete(Nombre, 1, Archivos),
                        NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD,
                        Pid ! {self(), ok};
                    {cerrar, {Nombre, Host, Contenido}} -> 
                        NArchivos = keyreplace(Nombre, 1, Archivos, {Nombre, Host, Contenido}),
                        NSesiones = Sesiones, NMaxID = MaxID, NMaxFD = MaxFD,
                        Pid ! {self(), ok}
                end,
                put(sesiones, NSesiones),
                put(archivos, NArchivos),
                put(maxFD, NMaxFD),
                put(maxID, NMaxID)
    after 50 -> ok
    end.
