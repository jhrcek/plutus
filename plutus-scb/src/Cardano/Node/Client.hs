{-# LANGUAGE TypeApplications #-}

module Cardano.Node.Client where

import           Cardano.Node.API      (API)
import           Data.Proxy            (Proxy (Proxy))
import           Ledger                (Block, Slot, Tx)
import           Servant               ((:<|>) (..), NoContent)
import           Servant.Client        (ClientM, client)
import           Wallet.Emulator.Chain (ChainEvent)

healthcheck :: ClientM NoContent
getCurrentSlot :: ClientM Slot
addTx :: Tx -> ClientM NoContent
randomTx :: ClientM Tx
blocksSince :: Slot -> ClientM [Block]
consumeEventHistory :: ClientM [ChainEvent]
(healthcheck, addTx, getCurrentSlot, randomTx, blocksSince, consumeEventHistory) =
    ( healthcheck_
    , addTx_
    , getCurrentSlot_
    , randomTx_
    , blocksSince_
    , consumeEventHistory_)
  where
    healthcheck_ :<|> addTx_ :<|> getCurrentSlot_ :<|> (randomTx_ :<|> blocksSince_ :<|> consumeEventHistory_) =
        client (Proxy @API)
