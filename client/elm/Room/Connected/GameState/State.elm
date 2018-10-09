module GameState.State exposing (playstateTick, update, tick, tickEnd, resolvable, resMapPlay)

import Audio exposing (playSound)
import CharacterSelect.State as CharacterSelect
import Game.State as Game
import GameState.Decoders exposing (playStateDecoder, stateDecoder)
import GameState.Encoders exposing (encodeHoverIndex)
import GameState.Messages exposing (Msg(..), PlayingOnly(..), TurnOnly(..))
import GameState.Types exposing (GameState(..), PlayState(..))
import Json.Decode as Json
import List.Extra as List
import Main.Messages as Main
import Main.Types exposing (Flags)
import Math.Vector2 exposing (vec2)
import Mode as Mode
import Model.Decoders as Model
import Model.Types exposing (Model)
import Model.ViewModel
import Navigation
import Ports exposing (reload)
import Resolvable.Decoders exposing (resolveDiffDataDecoder)
import Resolvable.State as Resolvable
import Resolvable.Types as Resolvable
import Util exposing (message, send, unsafeForceDecode)
import WhichPlayer.Types exposing (WhichPlayer(..))


update : Msg -> GameState -> Mode.Mode -> Flags -> ( GameState, Cmd Main.Msg )
update msg state mode flags =
    case msg of
        Sync str ->
            ( syncState state str, Cmd.none )

        HoverSelf i ->
            case state of
                Started (Playing ({ res } as game)) ->
                    let
                        { vm } =
                            res

                        newVm : Model.ViewModel.ViewModel
                        newVm =
                            { vm | hover = i }
                    in
                        ( Started <| Playing { game | res = { res | vm = newVm } }
                        , Cmd.none
                        )

                s ->
                    ( s, Cmd.none )

        HoverOutcome i ->
            case state of
                Started (Playing ({ res } as game)) ->
                    let
                        { final } =
                            res

                        newFinal : Model
                        newFinal =
                            { final | otherHover = i }
                    in
                        ( Started <| Playing { game | res = { res | final = newFinal } }
                        , Cmd.none
                        )

                s ->
                    ( s, Cmd.none )

        ResolveOutcome str ->
            let
                oldResList : List Resolvable.ResolveData
                oldResList =
                    case state of
                        Started playState ->
                            .resList <| resolvable playState

                        _ ->
                            []

                oldTick : Float
                oldTick =
                    case ( state, oldResList ) of
                        ( Started _, [] ) ->
                            0

                        ( Started playState, _ ) ->
                            .tick <| resolvable playState

                        _ ->
                            0

                initial : Model
                initial =
                    unsafeForceDecode (Json.field "initial" Model.decoder) str

                resDiffList : List Resolvable.ResolveDiffData
                resDiffList =
                    unsafeForceDecode (Json.field "list" (Json.list resolveDiffDataDecoder)) str

                resList : List Resolvable.ResolveData
                resList =
                    Resolvable.resDiffToData initial resDiffList

                finalState : PlayState
                finalState =
                    unsafeForceDecode (Json.field "final" playStateDecoder) str

                model : Model
                model =
                    .final <| resolvable finalState

                res : Resolvable.Model
                res =
                    { vm = Model.ViewModel.init
                    , tick = oldTick
                    , final = model
                    , resList = oldResList ++ resList
                    }

                newState : GameState
                newState =
                    carryVm state <|
                        resMap
                            (\_ -> res)
                            (Started finalState)
            in
                ( newState, Cmd.none )

        ReplaySaved replayId ->
            case state of
                Started (Ended winner res _) ->
                    ( Started (Ended winner res (Just replayId)), Cmd.none )

                _ ->
                    ( state, Cmd.none )

        SelectingMsg selectMsg ->
            case state of
                Selecting m ->
                    let
                        ( newModel, cmd ) =
                            CharacterSelect.update selectMsg m
                    in
                        ( Selecting newModel, cmd )

                _ ->
                    Debug.log
                        "Expected a selecting state"
                        ( state, Cmd.none )

        PlayingOnly playingOnly ->
            updatePlayingOnly playingOnly state mode flags

        GotoReplay replayId ->
            state
                ! [ Navigation.newUrl <| "/replay/" ++ replayId
                  , reload ()
                  ]

        Mouse { x, y } ->
            let
                pos =
                    vec2 (toFloat x) (toFloat y)

                newState =
                    case state of
                        Started (Playing game) ->
                            Started (Playing { game | mouse = pos })

                        Started (Ended w game r) ->
                            Started (Ended w { game | mouse = pos } r)

                        _ ->
                            state
            in
                ( newState, Cmd.none )

        MouseClick { x, y } ->
            let
                pos =
                    vec2 (toFloat x) (toFloat y)
            in
                case state of
                    Started (Playing { entities }) ->
                        let
                            mIndex =
                                Maybe.map .index <|
                                    List.find (Game.hitTest pos 28) entities.hand
                        in
                            case mIndex of
                                Just index ->
                                    update
                                        (PlayingOnly <| TurnOnly <| PlayCard index)
                                        state
                                        mode
                                        flags

                                Nothing ->
                                    ( state, Cmd.none )

                    _ ->
                        ( state, Cmd.none )


updatePlayingOnly : PlayingOnly -> GameState -> Mode.Mode -> Flags -> ( GameState, Cmd Main.Msg )
updatePlayingOnly msg state mode flags =
    let
        legal =
            case mode of
                Mode.Playing ->
                    True

                Mode.Spectating ->
                    False
    in
        if not legal then
            ( state, Cmd.none )
        else
            case msg of
                Rematch ->
                    case state of
                        Started (Ended _ _ _) ->
                            ( state, send flags "rematch:" )

                        _ ->
                            ( state, Cmd.none )

                HoverCard mIndex ->
                    let
                        ( newState, cmd ) =
                            update (HoverSelf mIndex) state mode flags

                        sound =
                            case mIndex of
                                Nothing ->
                                    Cmd.none

                                _ ->
                                    playSound "/sfx/hover.wav"
                    in
                        newState
                            ! [ cmd
                              , message <|
                                    Main.Send <|
                                        "hover:"
                                            ++ encodeHoverIndex mIndex
                              , sound
                              ]

                TurnOnly turnOnly ->
                    updateTurnOnly turnOnly state mode flags


updateTurnOnly : TurnOnly -> GameState -> Mode.Mode -> Flags -> ( GameState, Cmd Main.Msg )
updateTurnOnly msg state mode flags =
    let
        legal =
            case state of
                Started (Playing { res }) ->
                    res.final.turn == PlayerA

                _ ->
                    False
    in
        if not legal then
            ( state, Cmd.none )
        else
            case msg of
                EndTurn ->
                    state
                        ! [ send flags "end:"
                          , playSound "/sfx/endTurn.wav"
                          ]

                PlayCard index ->
                    let
                        ( newState, cmd ) =
                            update (HoverSelf Nothing) state mode flags
                    in
                        newState
                            ! [ send flags <| "play:" ++ toString index
                              , playSound "/sfx/playCard.wav"
                              , cmd
                              ]


syncState : GameState -> String -> GameState
syncState oldState msg =
    case Json.decodeString stateDecoder msg of
        Ok newState ->
            carryVm oldState newState

        Err err ->
            Debug.log
                err
                oldState


carryVm : GameState -> GameState -> GameState
carryVm old new =
    case old of
        Selecting { vm } ->
            case new of
                Selecting selecting ->
                    Selecting { selecting | vm = vm }

                _ ->
                    new

        Started oldStarted ->
            case new of
                Started newStarted ->
                    let
                        oldVm : Model.ViewModel.ViewModel
                        oldVm =
                            .vm <| resolvable oldStarted
                    in
                        Started <|
                            resMapPlay (\r -> { r | vm = oldVm }) newStarted

                _ ->
                    new

        _ ->
            new


resMap : (Resolvable.Model -> Resolvable.Model) -> GameState -> GameState
resMap f state =
    case state of
        Started started ->
            Started <| resMapPlay f started

        _ ->
            state


resMapPlay : (Resolvable.Model -> Resolvable.Model) -> PlayState -> PlayState
resMapPlay f started =
    resolvableSet started <|
        f (resolvable started)


resolvableSet : PlayState -> Resolvable.Model -> PlayState
resolvableSet s r =
    case s of
        Playing game ->
            Playing { game | res = r }

        Ended w game replay ->
            Ended w { game | res = r } replay


tick : Flags -> GameState -> Float -> GameState
tick flags state dt =
    case state of
        Started started ->
            Started <| playstateTick flags started dt

        _ ->
            state


playstateTick : Flags -> PlayState -> Float -> PlayState
playstateTick flags state dt =
    case state of
        Playing game ->
            Playing <| Game.tick flags game dt

        Ended w game replay ->
            Ended w (Game.tick flags game dt) replay


tickEnd : PlayState -> Bool
tickEnd started =
    let
        res =
            resolvable started
    in
        Resolvable.tickEnd res.tick <|
            Resolvable.activeAnim res


resolvable : PlayState -> Resolvable.Model
resolvable state =
    case state of
        Playing { res } ->
            res

        Ended _ { res } _ ->
            res
