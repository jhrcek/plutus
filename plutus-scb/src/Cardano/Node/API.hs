{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Cardano.Node.API
    ( API
    , MockNodeAPI(..)
    ) where

import           Ledger                (Block, Slot, Tx)
import           Servant.API           ((:<|>), (:>), Get, JSON, NoContent, Post, ReqBody)
import           Wallet.Emulator.Chain (ChainEvent)

type API
     = "healthcheck" :> Get '[ JSON] NoContent
       :<|> "mempool" :> ReqBody '[ JSON] Tx :> Post '[ JSON] NoContent
       :<|> "slot" :> Get '[ JSON] Slot
       :<|> "mock" :> MockAPI

-- Routes that are not guaranteed to exist on the real node
type MockAPI
     = "random-tx" :> Get '[ JSON] Tx
       :<|> "blocks-since" :> ReqBody '[ JSON] Slot :> Get '[ JSON] [Block]
       :<|> "consume-event-history" :> Post '[ JSON] [ChainEvent]

class Monad m =>
      MockNodeAPI m
    where
    blocksSince :: Slot -> m [Block]
