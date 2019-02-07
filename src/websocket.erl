-module(websocket).

-export([
    connect/3,
    connect/4,
    send/2,
    close/1
]).

connect(Address, Port, Opts) ->
    connect(Address, Port, Opts, infinity).

connect(Address, Port, Opts, Timeout) ->
    Path = proplists:get_value(path, Opts, "/mqtt"),
    Headers = proplists:get_value(headers, Opts, []),
    Transport = proplists:get_value(transport, Opts, choose_transport(Port)),
    TransportOpts = proplists:delete(path, proplists:delete(headers, proplists:delete(transport, Opts))),
    GunOpts = #{
        connect_timeout => Timeout,
        retry => 0,
        transport => Transport,
        transport_opts => TransportOpts,
        ws_opts => #{protocols => [{<<"mqtt">>, gun_ws_h}]}
    },
    % cowboy and ssl has to be started before gun can be used
    {ok, _} = application:ensure_all_started(gun),
    case gun:open(Address, Port, GunOpts) of
        {ok, Sock} ->
            case gun:await_up(Sock, Timeout) of
                {ok, _} ->
                    upgrade(Sock, Path, Headers, Timeout);
                Other ->
                    Other
            end;
        Other ->
            Other
    end.

upgrade(Sock, Path, Headers, Timeout) ->
    StreamRef = gun:ws_upgrade(Sock, Path, Headers),
    receive
        {gun_upgrade, Sock, StreamRef, [<<"websocket">>], _} ->
            {ok, Sock};
        {gun_error, Sock, StreamRef, Reason} ->
            {error, Reason}
    after Timeout ->
        {error, timeout}
    end.

choose_transport(8443) ->
    tls;
choose_transport(443) ->
    tls;
choose_transport(_) ->
    tcp.

send(Sock, Data) ->
    gun:ws_send(Sock, {binary, Data}).

close(Sock) ->
    gun:close(Sock).
