module Main where

import Control.Concurrent (forkIO, threadDelay)
import Control.Monad.STM (atomically)
import Control.Concurrent.STM.TVar (TVar, newTVar, readTVar, readTVarIO)
import Control.Exception (finally)
import Control.Monad (forever, mzero, when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Maybe (runMaybeT)
import Data.Maybe (fromMaybe)
import Data.String.Conversions (cs)
import Data.Text (Text)
import Text.Printf (printf)

import Network.Wai (Application)
import Network.Wai.Handler.WebSockets
import Network.Wai.Handler.Warp (run)
import System.Environment (lookupEnv)
import System.IO (BufferMode(LineBuffering), hSetBuffering, stdout)
import System.Log.Logger (Priority(DEBUG), infoM, warningM, setLevel, updateGlobalLogger)

import Act (actPlay, actSpec, syncClient, syncPlayersRoom, syncRoomClients)
import ArtificalIntelligence (Action(..), chooseAction)
import Characters (CharModel(..), allSelected, character_name, toList)
import Database (Database(..), connectInfo)
import Negotiation (Prefix(..), RoomRequest(..), parseRoomReq, parsePrefix)
import Player (WhichPlayer(..), other)
import GameState (GameState(..), PlayState(..), WaitType(..))
import Username (Username(Username))
import Util (Gen, getGen, shuffle)

import qualified Server
import Server (addComputerClient, addPlayerClient, addSpecClient)

import qualified Client
import Client (Client(..), ClientConnection(..))

import qualified Command
import Command (Command(..))

import qualified Room
import Room (Room)

import qualified Network.WebSockets as WS

import qualified Auth as A
import qualified Database.Redis as R
import qualified Data.GUID as GUID


main :: IO ()
main = do
  updateGlobalLogger "app" $ setLevel DEBUG
  hSetBuffering stdout LineBuffering

  -- If we're on production, these env vars will be present.
  -- Defined in `redis.prod.env` secret.
  redisHost     <- lookupEnv "REDIS_HOST"
  redisPort     <- lookupEnv "REDIS_PORT"
  redisPassword <- lookupEnv "REDIS_PASSWORD"

  let connect = R.connect . (connectInfo (redisHost, redisPort, redisPassword))
  userConn   <- connect UserDatabase
  tokenConn  <- connect TokenDatabase
  replayConn <- connect ReplayDatabase

  authApp   <- A.app userConn tokenConn
  state     <- atomically $ newTVar Server.initState

  run 9160 $ waiApp state tokenConn replayConn authApp


waiApp :: TVar Server.State -> R.Connection -> R.Connection -> Application -> Application
waiApp state tokenConn replayConn backupApp =
  websocketsOr WS.defaultConnectionOptions (wsApp state tokenConn replayConn) backupApp


wsApp :: TVar Server.State -> R.Connection -> R.Connection -> WS.ServerApp
wsApp state tokenConn replayConn pending = do
  connection <- WS.acceptRequest pending
  msg        <- WS.receiveData connection
  usernameM  <- A.checkAuth tokenConn $ A.getToken pending
  WS.forkPingThread connection 30
  begin connection msg (Username <$> usernameM) state replayConn


begin :: WS.Connection -> Text -> Maybe Username -> TVar Server.State -> R.Connection -> IO ()
begin conn roomReq usernameM state replayConn =
  let
    username :: Username
    username = fromMaybe (Username "Guest") usernameM
    connectionFail :: String -> IO ()
    connectionFail str = do
      warningM "app" str
      (WS.sendTextData conn) . Command.toChat . ErrorCommand $ cs str
  in
    do
      infoM "app" $ printf "<%s>: New connection" (show username)
      case parseRoomReq roomReq of
        Just (RoomRequest roomName) -> do
          msg <- WS.receiveData conn
          case parsePrefix msg of
            Nothing ->
              connectionFail $ printf "<%s>: Connection protocol failure" msg
            Just prefix -> do
              gen <- getGen
              guid <- GUID.genText
              roomVar <- atomically $ Server.getOrCreateRoom roomName (prefixWaitType prefix) gen state
              beginPrefix
                prefix
                state
                (Client username (PlayerConnection conn) guid)
                roomVar
                replayConn
        Nothing ->
          connectionFail $ printf "<%s>: Bad room name protocol %s" (show username) roomReq
        Just ReconnectRequest ->
          return ()


beginPrefix :: Prefix -> TVar Server.State -> Client -> TVar Room -> R.Connection -> IO ()
beginPrefix PrefixPlay  = beginPlay
beginPrefix PrefixSpec  = beginSpec
beginPrefix PrefixCpu   = beginComputer
beginPrefix PrefixQueue = beginQueue


prefixWaitType :: Prefix -> WaitType
prefixWaitType PrefixPlay  = WaitCustom
prefixWaitType PrefixSpec  = WaitCustom
prefixWaitType PrefixCpu   = WaitCustom
prefixWaitType PrefixQueue = WaitQuickplay



beginPlay :: TVar Server.State -> Client -> TVar Room -> R.Connection -> IO ()
beginPlay state client roomVar replayConn = do
  infoM "app" $ printf "<%s>: Begin playing" (show $ Client.name client)
  added <- atomically $ addPlayerClient client roomVar
  case added of
    Nothing -> do
      infoM "app" $ printf "<%s>: Room is full" (show $ Client.name client)
      Client.send (Command.toChat $ ErrorCommand "room is full") client
    Just which ->
      finally
        (play which client roomVar replayConn)
        (disconnect client roomVar state)


beginSpec :: TVar Server.State -> Client -> TVar Room -> R.Connection -> IO ()
beginSpec state client roomVar _ = do
  infoM "app" $ printf "<%s>: Begin spectating" (show $ Client.name client)
  finally
    (spectate client roomVar)
    (disconnect client roomVar state)


beginComputer :: TVar Server.State -> Client -> TVar Room -> R.Connection -> IO ()
beginComputer state client roomVar replayConn = do
  infoM "app" $ printf "<%s>: Begin AI game" (show $ Client.name client)
  cpuGuid  <- GUID.genText
  (computer, added) <- atomically $ do
    computerAdded <- addComputerClient cpuGuid roomVar
    playerAdded <- addPlayerClient client roomVar
    return (computerAdded, playerAdded)
  case (,) <$> computer <*> added of
    Nothing -> do
      infoM "app" $ printf "<%s>: Room is full" (show $ Client.name client)
      Client.send (Command.toChat $ ErrorCommand "Room is full") client
    Just (computerClient, which) ->
      finally
        (do
          _ <- forkIO (computerPlay (other which) roomVar replayConn)
          (play which client roomVar replayConn))
        (do
          _ <- disconnect computerClient roomVar state
          (disconnect client roomVar state))


beginQueue :: TVar Server.State -> Client -> TVar Room -> R.Connection -> IO ()
beginQueue state client roomVar replayConn = do
  infoM "app" $ printf "<%s>: Begin quickplay game" (show $ Client.name client)
  roomM <- atomically $ Server.queue (client, roomVar) state
  case roomM of
    Just (_, existingRoom) -> do
      infoM "app" $ printf "<%s>: Joining existing quickplay room" (show $ Client.name client)
      beginPlay state client existingRoom replayConn
    Nothing -> do
      infoM "app" $ printf "<%s>: Creating new quickplay room" (show $ Client.name client)
      finally
        (beginPlay state client roomVar replayConn)
        (atomically $ Server.dequeue client state)


spectate :: Client -> TVar Room -> IO ()
spectate client roomVar = do
  room <- atomically $ addSpecClient client roomVar
  Client.send ("acceptSpec:" :: Text) client
  Room.broadcast (Command.toChat (SpectateCommand (Client.name client))) room
  syncClient client (Room.getState room)
  _ <- runMaybeT . forever $ do
    msg <- lift $ Client.receive client
    case msg of
      "reconnect:" ->
        mzero
      _ ->
        lift $ actSpec (Command.parse (Client.name client) msg) roomVar
  return ()


play :: WhichPlayer -> Client -> TVar Room -> R.Connection -> IO ()
play which client roomVar replayConn = do
  Client.send ("acceptPlay:" :: Text) client
  room <- atomically $ readTVar roomVar
  syncPlayersRoom room
  syncRoomClients room
  _ <- runMaybeT . forever $ do
    msg <- lift $ Client.receive client
    case msg of
      "reconnect:" ->
        mzero
      _ ->
        lift $ actPlay (Command.parse (Client.name client) msg) which roomVar replayConn
  return ()


computerPlay :: WhichPlayer -> TVar Room -> R.Connection -> IO ()
computerPlay which roomVar replayConn = do
  _ <- runMaybeT . forever $ do
    lift $ threadDelay 1000000
    gen <- lift $ getGen
    command <- lift $ chooseComputerCommand which roomVar gen
    case command of
      Just c -> do
        lift $ actPlay c which roomVar replayConn
        lift $ threadDelay 10000
      Nothing ->
        return ()
    -- Break out if the room's empty.
    room <- lift . atomically $ readTVar roomVar
    when (Room.empty room) mzero
  infoM "app" $ printf "AI signing off"
  return ()


chooseComputerCommand :: WhichPlayer -> TVar Room -> Gen -> IO (Maybe Command)
chooseComputerCommand which room gen = do
  r <- atomically $ readTVar room
  case Room.getState r of
    Selecting charModel _ _ ->
      if allSelected charModel which then
        return Nothing
          else
            return . Just . SelectCharacterCommand $ randomChar charModel
    Started (Playing m _) ->
      return $ trans <$> chooseAction gen which m
    _ ->
      return Nothing
  where
    trans :: Action -> Command
    trans EndAction          = EndTurnCommand
    trans (PlayAction index) = PlayCardCommand index
    randomChar :: CharModel -> Text
    randomChar (CharModel selected _ allChars) =
      character_name . head . (drop (length . Characters.toList $ selected))
        $ shuffle gen allChars


disconnect :: Client -> TVar Room -> TVar Server.State -> IO (Server.State)
disconnect client roomVar state = do
  room <- atomically $ Server.removeClient client roomVar
  Room.broadcast (Command.toChat . LeaveCommand $ Client.name client) room
  syncPlayersRoom room
  if Room.empty room then
    (do
      infoM "app" $ printf "<%s>: Room is empty, deleting room" (show $ Client.name client)
      atomically $ Server.deleteRoom (Room.getName room) state
    )
      else
        (do
          infoM "app" $ printf "<%s>: Room is not empty, retaining room" (show $ Client.name client)
          readTVarIO state
        )
