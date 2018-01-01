module Main.Messages exposing (Msg(..))

import Http
import Navigation exposing (Location)
import Room.Messages as Room
import Settings.Messages as Settings


type Msg
    = CopyInput String
    | Frame Float
    | Receive String
    | Resize Int Int
    | RoomMsg Room.Msg
    | SelectAllInput String
    | Send String
    | SettingsMsg Settings.Msg
    | SetVolume Int
    | UrlChange Location
    | Logout
    | LogoutCallback (Result Http.Error ())
    | GetAuth
    | GetAuthCallback (Result Http.Error (Maybe String))
