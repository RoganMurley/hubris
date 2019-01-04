module Stack.View exposing (view)

import Animation.Types exposing (Anim(..))
import Array
import Card.Types as Card
import Card.View as Card
import Game.Types exposing (Context)
import WebGL
import WhichPlayer.State exposing (other)


view : List (Card.Entity {}) -> Context -> List WebGL.Entity
view entities ctx =
    let
        n =
            List.length entities
                - 1

        makeEntity i =
            case ctx.anim of
                Hubris _ ->
                    if i == n then
                        Card.view ctx

                    else
                        Card.dissolvingView ctx

                Reflect _ ->
                    if i == n then
                        Card.view ctx

                    else
                        \entity ->
                            let
                                ca =
                                    { owner = other entity.owner
                                    , card = entity.card
                                    }

                                cb =
                                    { owner = entity.owner
                                    , card = entity.card
                                    }
                            in
                            Card.transmutingView ctx ca cb entity

                Transmute _ ca cb ->
                    if i == 0 then
                        Card.transmutingView ctx ca cb

                    else
                        Card.view ctx

                Fabricate _ ->
                    if i == 0 then
                        Card.fabricatingView ctx

                    else
                        Card.view ctx

                Bounce _ _ z ->
                    let
                        bouncing =
                            Maybe.withDefault False <|
                                Array.get i <|
                                    Array.fromList z
                    in
                    if bouncing then
                        \_ -> []

                    else
                        Card.view ctx

                _ ->
                    Card.view ctx
    in
    List.concat <| List.indexedMap makeEntity entities
