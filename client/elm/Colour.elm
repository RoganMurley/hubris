module Colour exposing (Colour, black, blue, card, focusBackground, green, red, white, yellow)

import Math.Vector3 exposing (Vec3, vec3)
import WhichPlayer.Types exposing (WhichPlayer(..))


type alias Colour =
    Vec3


white : Colour
white =
    vec3 0.91 0.95 0.87


black : Colour
black =
    vec3 1 1 1


red : Colour
red =
    vec3 0.65 0.12 0.14


green : Colour
green =
    vec3 0.27 0.95 0.45


blue : Colour
blue =
    vec3 0 0 1


yellow : Colour
yellow =
    vec3 0.96 0.95 0.37


card : WhichPlayer -> Colour
card which =
    case which of
        PlayerA ->
            vec3 0.95 0.27 0.29

        PlayerB ->
            vec3 0.14 0.52 0.75


focusBackground : WhichPlayer -> Colour
focusBackground which =
    case which of
        PlayerA ->
            vec3 0.95 0.27 0.29

        PlayerB ->
            vec3 0.14 0.52 0.75