module Room.Messages exposing (Msg(..))

import Connected.Messages as Connected
import Lab.Messages as Lab
import Lobby.Messages as Lobby
import Login.Messages as Login
import Menu.Messages as Menu
import Mode exposing (Mode)
import Replay.Messages as Replay


type Msg
    = ConnectedMsg Connected.Msg
    | LabMsg Lab.Msg
    | LobbyMsg Lobby.Msg
    | LoginMsg Login.Msg
    | MenuMsg Menu.Msg
    | ReplayMsg Replay.Msg
    | StartGame Mode
