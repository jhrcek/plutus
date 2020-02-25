{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE NamedFieldPuns             #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TemplateHaskell            #-}

-- | A test version of the 'App' stack which runs all operations in memory.
-- No networking, no filesystem.
module Plutus.SCB.TestApp
    ( runScenario
    , sync
    , TestApp
    ) where

import           Cardano.Node.API                              (MockNodeAPI, blocksSince)
import           Cardano.Node.Mock                             (NodeServerEffects)
import qualified Cardano.Node.Mock                             as NodeServer
import qualified Cardano.Node.Types                            as NodeServer
import qualified Cardano.Wallet.Mock                           as WalletServer
import           Control.Concurrent.MVar                       (MVar, newMVar)
import           Control.Lens                                  (assign, makeLenses, use, view, zoom)
import           Control.Monad                                 (void)
import           Control.Monad.Except                          (ExceptT, MonadError, runExceptT)
import           Control.Monad.Freer                           (Eff)
import           Control.Monad.IO.Class                        (MonadIO, liftIO)
import           Control.Monad.Logger                          (LoggingT, MonadLogger, logDebugN, logInfoN,
                                                                runStderrLoggingT)
import           Control.Monad.State                           (MonadState, StateT (StateT), runStateT)
import           Data.Aeson                                    as JSON
import           Data.Aeson.Types                              as JSON
import           Data.Bifunctor                                (first)
import           Data.Foldable                                 (traverse_)
import           Data.Text                                     (Text)
import qualified Data.Text                                     as Text
import           Eventful                                      (commandStoredAggregate, getLatestStreamProjection,
                                                                streamEventEvent)
import           Eventful.Store.Memory                         (EventMap, emptyEventMap, stateEventStoreReader,
                                                                stateEventStoreWriter, stateGlobalEventStoreReader)
import           Language.Plutus.Contract.Resumable            (ResumableError)
import           Language.Plutus.Contract.Servant              (initialResponse, runUpdate)
import qualified Language.PlutusTx.Coordination.Contracts.Game as Contracts.Game
import qualified Ledger
import qualified Ledger.AddressMap                             as AM
import           Plutus.SCB.Command                            ()
import           Plutus.SCB.Core
import           Plutus.SCB.Events                             (ChainEvent)
import           Plutus.SCB.Query                              (pureProjection)
import           Plutus.SCB.Types                              (SCBError (ContractCommandError, ContractNotFound))
import           Plutus.SCB.Utils                              (abbreviate, tshow)
import           Test.QuickCheck.Instances.UUID                ()
import           Wallet.API                                    (ChainIndexAPI, NodeAPI, WalletAPI, WalletDiagnostics,
                                                                logMsg, ownOutputs, ownPubKey, sign, slot,
                                                                startWatching, submitTxn, updatePaymentWithChange,
                                                                watchedAddresses)

data TestState =
    TestState
        { _eventStore  :: EventMap ChainEvent
        , _walletState :: WalletServer.State
        , _nodeState   :: MVar NodeServer.AppState
        }

makeLenses 'TestState

newtype TestApp a =
    TestApp
        { runTestApp :: StateT TestState (LoggingT (ExceptT SCBError IO)) a
        }
    deriving newtype ( Functor
                     , Applicative
                     , Monad
                     , MonadLogger
                     , MonadIO
                     , MonadState TestState
                     , MonadError SCBError
                     )

initialTestState :: MonadIO m => m TestState
initialTestState =
    liftIO $ do
        let _eventStore = emptyEventMap
        -- ^ Set up the event log.
        -- Set up the node.
        _nodeState <- liftIO $ newMVar NodeServer.initialAppState
        -- Set up the wallet.
        let _walletState = WalletServer.initialState
        pure TestState {_eventStore, _nodeState, _walletState}

runScenario :: TestApp a -> IO ()
runScenario action = do
    testState <- initialTestState
    result <-
        runExceptT $
        runStderrLoggingT $
        flip runStateT testState $
        runTestApp $ do
            sync
            action
            events :: [ChainEvent] <-
                fmap streamEventEvent <$> runGlobalQuery pureProjection
            logDebugN "Final Event Stream"
            logDebugN "--"
            traverse_ (logDebugN . abbreviate 120 . tshow) events
            logDebugN "--"
    case result of
        Left err -> error $ show err
        Right _  -> pure ()

sync :: TestApp ()
sync = use walletState >>= WalletServer.syncState >>= assign walletState

instance MonadEventStore ChainEvent TestApp where
    refreshProjection projection =
        TestApp . zoom eventStore $
        getLatestStreamProjection stateGlobalEventStoreReader projection
    runCommand aggregate source command =
        TestApp . zoom eventStore $
        commandStoredAggregate
            stateEventStoreWriter
            stateEventStoreReader
            aggregate
            (toUUID source)
            command

instance MonadContract TestApp where
    invokeContract (InitContract "game") =
        pure $ do
            value <- fromResumable $ initialResponse Contracts.Game.game
            fromString $ JSON.eitherDecode (JSON.encode value)
    invokeContract (UpdateContract "game" payload) =
        pure $ do
            request <- fromString $ JSON.parseEither JSON.parseJSON payload
            value <- fromResumable $ runUpdate Contracts.Game.game request
            fromString $ JSON.eitherDecode (JSON.encode value)
    invokeContract (InitContract contractPath) =
        pure $ Left $ ContractNotFound contractPath
    invokeContract (UpdateContract contractPath _) =
        pure $ Left $ ContractNotFound contractPath

instance WalletDiagnostics TestApp where
    logMsg = logInfoN

instance WalletAPI TestApp where
    ownPubKey = WalletServer.getOwnPubKey
    sign = WalletServer.sign
    updatePaymentWithChange _ _ = error "UNIMPLEMENTED: updatePaymentWithChange"
    ownOutputs = do
        pk <- ownPubKey
        am <- watchedAddresses
        pure $ view (AM.fundsAt (Ledger.pubKeyAddress pk)) am

instance ChainIndexAPI TestApp where
    watchedAddresses =
        TestApp . zoom walletState $ WalletServer.getWatchedAddresses
    startWatching address =
        TestApp . zoom walletState $ void $ WalletServer.startWatching address

instance NodeAPI TestApp where
    submitTxn tx = runChainEffects $ void $ NodeServer.addTx tx
    slot = runChainEffects NodeServer.getCurrentSlot

instance MockNodeAPI TestApp where
    blocksSince = runChainEffects . NodeServer.getBlocksSince

runChainEffects :: Eff (NodeServerEffects IO) a -> TestApp a
runChainEffects action =
    TestApp . zoom nodeState . StateT $ \stateMVar -> do
        result <- NodeServer.processChainEffects stateMVar action
        pure (result, stateMVar)

fromString :: Either String a -> Either SCBError a
fromString = first (ContractCommandError 0 . Text.pack)

fromResumable :: Either (ResumableError Text) a -> Either SCBError a
fromResumable = first (ContractCommandError 0 . Text.pack . show)
