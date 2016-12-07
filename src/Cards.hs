module Cards where

import Data.Monoid ((<>))
import System.Random.Shuffle (shuffle')

import Model
import Util (times)


cardDagger :: Card
cardDagger = Card "Dagger" "Hurt for 8" "plain-dagger.svg" eff
  where
    eff :: CardEff
    eff p c m = hurt 8 (otherPlayer p) m


cardHubris :: Card
cardHubris = Card "Hubris" "Negate all cards to the right" "tower-fall.svg" eff
  where
    eff :: CardEff
    eff p c m = setStack [] m


cardFireball :: Card
cardFireball = Card "Fireball" "Hurt for 4 for each card to the right" "fire-ray.svg" eff
  where
    eff :: CardEff
    eff p c m = hurt (4 * (length (getStack m))) (otherPlayer p) m


cardBoomerang :: Card
cardBoomerang = Card "Boomerang" "Hurt for 2, return this card to your hand" "boomerang.svg" eff
  where
    eff :: CardEff
    eff p c m = modHand (addToHand c) p (hurt 2 (otherPlayer p) m)


cardPotion :: Card
cardPotion = Card "Potion" "Heal for 7" "heart-bottle.svg" eff
  where
    eff :: CardEff
    eff p c m = heal 7 p m


cardVampire :: Card
cardVampire = Card "Vampire" "Lifesteal for 5" "fangs.svg" eff
  where
    eff :: CardEff
    eff p c m = lifesteal 5 (otherPlayer p) m


cardSuccubus :: Card
cardSuccubus = Card "Succubus" "Lifesteal for 2 for each card to the right" "pretty-fangs.svg" eff
  where
    eff :: CardEff
    eff p c m = lifesteal (2 * (length (getStack m))) (otherPlayer p) m


cardReversal :: Card
cardReversal = Card "Reversal" "Reverse the order of cards to the right" "pocket-watch.svg" eff
  where
    eff :: CardEff
    eff p c m = modStack reverse m


cardReflect :: Card
cardReflect = Card "Reflect" "All cards to the right change owner" "shield-reflect.svg" eff
  where
    eff :: CardEff
    eff p c m = modStackAll reflectEff m
    reflectEff :: StackCard -> StackCard
    reflectEff (StackCard owner (Card name desc img cardEff)) =
      StackCard (otherPlayer owner) (Card name desc img cardEff)


-- cardEcho :: Card
-- cardEcho = Card "Echo" "All cards to the right happen twice" "echo-ripples.svg" eff
--   where
--     eff :: CardEff
--     eff p c m = modStackAll echoEff m
--     echoEff :: StackCard -> StackCard
--     echoEff (StackCard owner (Card name desc img cardEff)) =
--       StackCard owner (Card name desc img (echo cardEff))
--     echo :: CardEff -> CardEff
--     echo e = \which -> (e which) . (e which)


cardProphecy :: Card
cardProphecy = Card "Prophecy" "Return all cards to the right to their owner's hand" "crystal-ball.svg" eff
  where
    eff :: CardEff
    eff p c m =
      modHand (bounceAll PlayerA (getStack m)) PlayerA $
      modHand (bounceAll PlayerB (getStack m)) PlayerB $
      setStack [] m
    bounceAll :: WhichPlayer -> Stack -> Hand -> Hand
    bounceAll w s h = (fmap getCard (filter (owner w) s)) ++ h
    owner :: WhichPlayer -> StackCard -> Bool
    owner PlayerA (StackCard PlayerA _) = True
    owner PlayerB (StackCard PlayerB _) = True
    owner _ _ = False
    getCard :: StackCard -> Card
    getCard (StackCard _ card) = card


cardSiren :: Card
cardSiren = Card "Siren" "Your opponent gets two cards that hurt them for 8 damage when played" "harpy.svg" eff
  where
    eff :: CardEff
    eff p c m = modHand (times 2 (addToHand cardSong)) (otherPlayer p) m
    cardSong :: Card
    cardSong = Card "Siren's Song" "Hurt yourself for 8" "love-song.svg" (\p c -> hurt 8 p)


cardSickness :: Card
cardSickness = Card "Sickness" "Make all cards to the right's healing hurt instead" "bleeding-heart.svg" eff
  where
    eff :: CardEff
    eff p c m = modStackAll (patchedCard m) m
    patchedCard :: Model -> StackCard -> StackCard
    patchedCard model (StackCard owner (Card name desc img cardEff)) =
      StackCard owner (Card ("Sick " <> name) (desc <> "; afflicted by sickness.") img (patchedEff cardEff))
    patchedEff :: CardEff -> CardEff
    patchedEff eff =
      \w c m -> reverseHeal PlayerA m $ reverseHeal PlayerB m $ eff w c m
    reverseHeal :: WhichPlayer -> Model -> Model -> Model
    reverseHeal which m1 m2 =
      hurt (max 0 (((getLife which m2) - (getLife which m1)) * 2)) which m2


cardOffering :: Card
cardOffering = Card "Offering" "Discard your hand, then draw two cards" "chalice-drops.svg" eff
  where
    eff :: CardEff
    eff p c m = (drawCard p) . (drawCard p) $ setHand p [] m


cardGoatFlute :: Card
cardGoatFlute = Card "Goat Flute" "Both players get two useless goats" "pan-flute.svg" eff
  where
    eff :: CardEff
    eff p c m =
      modHand (times 2 (addToHand cardGoat)) p $
        modHand (times 2 (addToHand cardGoat)) (otherPlayer p) m
    cardGoat :: Card
    cardGoat = Card "Goat" "A useless card" "goat.svg" (\_ _ m -> m)


cardConfound :: Card
cardConfound = Card "Confound" "Shuffle the order of cards to the right" "moebius-star.svg" eff
  where
    eff :: CardEff
    eff p c m = modStack (\s -> shuffle' s (length s) (getGen m)) m


cardObscurer :: Card
cardObscurer = Card "Obscurer" "Hurt for 4 and obscure the next card your opponent draws" "orb-wand.svg" eff
  where
    eff :: CardEff
    eff p c m = hurt 4 (otherPlayer p) $ modDeckHead obs (otherPlayer p) m
    obs :: Card -> Card
    obs card = Card "???" "An obscured card" "sight-disabled.svg" (\p _ -> modStack ((:) (StackCard p card)))