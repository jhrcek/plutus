{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TypeApplications  #-}
{-# LANGUAGE TypeOperators     #-}

module Cardano.Wallet.Mock where

import           Cardano.Node.API               (MockNodeAPI, blocksSince)
import           Cardano.Wallet.Types           (WalletId)
import           Control.Lens                   (makeLenses, modifying, over, set, use, view)
import           Control.Monad.Except           (MonadError, throwError)
import           Control.Monad.Freer            (runM)
import           Control.Monad.Freer.Error      (runError)
import           Control.Monad.IO.Class         (MonadIO, liftIO)
import           Control.Monad.Logger           (MonadLogger, logInfoN)
import           Control.Monad.State            (MonadState)
import           Data.Bifunctor                 (second)
import qualified Data.ByteString.Lazy           as BSL
import qualified Data.ByteString.Lazy.Char8     as BSL8
import           Data.Function                  ((&))
import           Data.List                      (genericLength)
import qualified Data.Map                       as Map
import           Data.Text.Encoding             (encodeUtf8)
import           Language.Plutus.Contract.Trace (allWallets)
import           Ledger                         (Address, PubKey, Signature, Slot (Slot), TxOutRef, Value, txOutTxOut,
                                                 txOutValue)
import           Ledger.AddressMap              (AddressMap, UtxoMap, addAddress, fundsAt)
import qualified Ledger.AddressMap              as AddressMap
import qualified Ledger.Crypto                  as Crypto
import           Plutus.SCB.Arbitrary           ()
import           Plutus.SCB.Utils               (tshow)
import           Servant                        (NoContent (NoContent), ServantErr, err401, err404, err500, errBody)
import           Test.QuickCheck                (arbitrary, generate)
import           Wallet.API                     (WalletAPIError (InsufficientFunds, OtherError, PrivateKeyNotFound))
import           Wallet.Emulator.Wallet         (Wallet (Wallet))
import qualified Wallet.Emulator.Wallet         as EM

data State =
    State
        { _watchedAddresses :: AddressMap
        , _lastSlotSeen     :: Slot
        }
    deriving (Show, Eq)

makeLenses 'State

-- TODO Should this call syncstate itself?
initialState :: State
initialState =
    State
        { _watchedAddresses =
              foldr (addAddress . EM.walletAddress) mempty allWallets
        , _lastSlotSeen = Slot 0
        }

wallets :: MonadLogger m => m [Wallet]
wallets = do
    logInfoN "wallets"
    pure allWallets

fromWalletAPIError :: WalletAPIError -> ServantErr
fromWalletAPIError (InsufficientFunds text) =
    err401 {errBody = BSL.fromStrict $ encodeUtf8 text}
fromWalletAPIError err@(PrivateKeyNotFound _) =
    err404 {errBody = BSL8.pack $ show err}
fromWalletAPIError (OtherError text) =
    err500 {errBody = BSL.fromStrict $ encodeUtf8 text}

selectCoin ::
       (MonadLogger m, MonadState State m, MonadError ServantErr m)
    => WalletId
    -> Value
    -> m ([(TxOutRef, Value)], Value)
selectCoin walletId target = do
    logInfoN "selectCoin"
    logInfoN $ "  Wallet ID: " <> tshow walletId
    logInfoN $ "     Target: " <> tshow target
    let address = EM.walletAddress (Wallet walletId)
    utxos :: UtxoMap <- use (watchedAddresses . fundsAt address)
    let funds :: [(TxOutRef, Value)]
        funds = fmap (second (txOutValue . txOutTxOut)) . Map.toList $ utxos
    result <- runM $ runError $ EM.selectCoin funds target
    logInfoN $ "     Result: " <> tshow result
    case result of
        Right value -> pure value
        Left err    -> throwError $ fromWalletAPIError err

allocateAddress :: (MonadIO m, MonadLogger m) => WalletId -> m PubKey
allocateAddress _ = do
    logInfoN "allocateAddress"
    liftIO $ generate arbitrary

getOwnPubKey :: MonadLogger m => m PubKey
getOwnPubKey = do
    logInfoN "getOwnPubKey"
    pure $ EM.walletPubKey activeWallet

activeWallet :: Wallet
activeWallet = Wallet 1

getWatchedAddresses ::
       (MonadIO m, MonadLogger m, MonadState State m) => m AddressMap
getWatchedAddresses = do
    logInfoN "getWatchedAddresses"
    use watchedAddresses

startWatching ::
       (MonadIO m, MonadLogger m, MonadState State m) => Address -> m NoContent
startWatching address = do
    logInfoN "startWatching"
    modifying watchedAddresses (addAddress address)
    pure NoContent

sign :: MonadLogger m => BSL.ByteString -> m Signature
sign bs = do
    logInfoN "sign"
    let privK = EM.walletPrivKey activeWallet
    pure (Crypto.sign (BSL.toStrict bs) privK)

------------------------------------------------------------
-- | Synchronise the initial state.
-- At the moment, this means, "as the node for UTXOs at all our watched addresses.
syncState :: (MonadLogger m, MockNodeAPI m) => State -> m State
syncState oldState = do
    let lastSeen = view lastSlotSeen oldState
    blockchain <- blocksSince lastSeen
    let newAddressMap = AddressMap.fromChain blockchain
        newState =
            oldState & set watchedAddresses newAddressMap &
            over lastSlotSeen (+ genericLength blockchain)
    pure newState
