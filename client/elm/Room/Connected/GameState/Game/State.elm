module Game.State exposing (..)

import Animation.State as Animation
import Game.Types exposing (Context, Entities, Model)
import Hand.Entities as Hand
import List.Extra as List
import Main.Types exposing (Flags)
import Math.Vector2 exposing (Vec2, vec2)
import Maybe.Extra as Maybe
import Resolvable.State as Resolvable exposing (activeAnim, activeModel, activeStackCard)
import Resolvable.Types as Resolvable
import Stack.Entities as Stack
import Stack.Types exposing (StackCard)
import Texture.State as Texture
import Texture.Types as Texture
import WhichPlayer.Types exposing (WhichPlayer(..))


gameInit : Resolvable.Model -> Model
gameInit res =
    { focus = Nothing
    , mouse = vec2 0 0
    , entities = { hand = [], otherHand = [], stack = [] }
    , res = res
    }


contextInit : ( Int, Int ) -> Resolvable.Model -> Texture.Model -> Context
contextInit ( width, height ) res textures =
    let
        w =
            toFloat width

        h =
            toFloat height

        radius =
            if h < w then
                0.8 * h * 0.5
            else
                1.2 * w * 0.5

        anim =
            activeAnim res
    in
        { w = w
        , h = h
        , radius = radius
        , anim = anim
        , model = activeModel res
        , stackCard = activeStackCard res
        , tick = res.tick
        , progress = Animation.progress anim res.tick
        , textures = textures
        }


entitiesInit : Entities
entitiesInit =
    { stack = []
    , hand = []
    , otherHand = []
    }


tick : Flags -> Model -> Float -> Model
tick { dimensions } model dt =
    let
        ctx =
            contextInit dimensions model.res Texture.init
    in
        { model
            | res = Resolvable.tick dt model.res
            , entities =
                { stack = Stack.entities ctx
                , hand = Hand.entities ctx
                , otherHand = Hand.otherEntities ctx
                }
            , focus = getFocus ctx model
        }


hitTest : Vec2 -> Float -> { a | position : Vec2 } -> Bool
hitTest pos dist { position } =
    Math.Vector2.distance position pos < dist


getFocus : Context -> Model -> Maybe StackCard
getFocus { stackCard } { entities, mouse } =
    let
        hoverCard =
            Maybe.or
                (Maybe.map (\{ card, owner } -> { owner = owner, card = card }) <|
                    List.find (hitTest mouse 64) entities.stack
                )
                (Maybe.map (\{ card } -> { owner = PlayerA, card = card }) <|
                    List.find (hitTest mouse 28) entities.hand
                )
    in
        Maybe.or stackCard hoverCard
