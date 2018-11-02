{-# LANGUAGE DeriveGeneric    #-}
{-# LANGUAGE FlexibleContexts #-}
-- | A model of the types involved in transactions. These types are intented to
--   be used in PLC scripts.
module Wallet.UTXO.Runtime (-- * Transactions and related types
                PubKey(..)
              , Value
              , Height
              , PendingTxOutRef(..)
              , Signature(..)
              -- ** Hashes (see note [Hashes in validator scripts])
              , DataScriptHash(..)
              , RedeemerHash(..)
              , ValidatorHash(..)
              , TxHash(..)
              , plcDataScriptHash
              , plcValidatorHash
              , plcValidatorDigest
              , plcRedeemerHash
              , plcTxHash
              -- * Pending transactions
              , PendingTx(..)
              , PendingTxOut(..)
              , PendingTxIn(..)
              , PendingTxOutType(..)
              -- * Oracles
              , Signed(..)
              , OracleValue(..)
              ) where

import           Codec.Serialise      (serialise)
import           Crypto.Hash          (Digest, SHA256, hash)
import qualified Data.ByteArray       as BA
import qualified Data.ByteString.Lazy as BSL
import           GHC.Generics         (Generic)
import           Language.Plutus.Lift (LiftPlc (..), TypeablePlc (..))
import           Wallet.UTXO.Types    (PubKey (..), Signature (..))
import qualified Wallet.UTXO.Types    as UTXO

data PendingTxOutType =
    PubKeyTxOut PubKey -- ^ Pub key address
    | DataTxOut -- ^ The data script of the pending transaction output (see note [Script types in pending transactions])
    deriving Generic

instance TypeablePlc PendingTxOutType
instance LiftPlc PendingTxOutType

-- | Output of a pending transaction.
data PendingTxOut = PendingTxOut {
    pendingTxOutValue  :: Value,
    pendingTxOutHashes :: Maybe (ValidatorHash, DataScriptHash), -- ^ Hashes of validator script and data script
    pendingTxOutData   :: PendingTxOutType
    } deriving Generic

instance TypeablePlc PendingTxOut
instance LiftPlc PendingTxOut

data PendingTxOutRef = PendingTxOutRef {
    pendingTxOutRefId  :: TxHash, -- ^ Transaction whose outputs are consumed
    pendingTxOutRefIdx :: Int, -- ^ Index into the referenced transaction's list of outputs
    pendingTxOutSigs   :: [Signature]
    } deriving Generic

instance TypeablePlc PendingTxOutRef
instance LiftPlc PendingTxOutRef

-- | Input of a pending transaction.
data PendingTxIn = PendingTxIn {
    pendingTxInRef       :: PendingTxOutRef,
    pendingTxInRefHashes :: Maybe (ValidatorHash, RedeemerHash), -- ^ Hashes of validator and redeemer scripts
    pendingTxInValue     :: Value -- ^ Value consumed by this txn input
    } deriving Generic

instance TypeablePlc PendingTxIn
instance LiftPlc PendingTxIn

-- | A pending transaction as seen by validator scripts.
data PendingTx = PendingTx {
    pendingTxInputs      :: [PendingTxIn], -- ^ Transaction inputs
    pendingTxOutputs     :: [PendingTxOut],
    pendingTxFee         :: Value,
    pendingTxForge       :: Value,
    pendingTxBlockHeight :: Height,
    pendingTxSignatures  :: [Signature]
    } deriving Generic

instance TypeablePlc PendingTx
instance LiftPlc PendingTx

-- `OracleValue a` is the value observed at a time signed by
-- an oracle.
newtype OracleValue a = OracleValue (Signed (Height, a))
    deriving Generic

instance TypeablePlc a => TypeablePlc (OracleValue a)
instance (TypeablePlc a, LiftPlc a) => LiftPlc (OracleValue a)

newtype Signed a = Signed (PubKey, a)
    deriving Generic

instance TypeablePlc a => TypeablePlc (Signed a)
instance (TypeablePlc a, LiftPlc a) => LiftPlc (Signed a)

-- | Ada value
--
-- TODO: Use [[Wallet.UTXO.Types.Value]] when Integer is supported
type Value = Int

{- Note [Hashes in validator scripts]

We need to deal with hashes of four different things in a validator script:

1. Transactions
2. Validator scripts
3. Data scripts
4. Redeemer scripts

The mockchain code in [[Wallet.UTXO.Types]] only deals with the hashes of(1)
and (2), and uses the [[Wallet.UTXO.Types.TxId']] and `Digest SHA256` types for
them.

In PLC validator scripts the situation is different: First, they need to work
with hashes of (1-4). Second, the `Digest SHA256` type is not available in PLC
- we have to represent all hashes as `ByteStrings`.

To ensure that we only compare hashes of the correct type inside a validator
script, we define a newtype for each of them, as well as functions for creating
them from the correct types in Haskell, and for comparing them (in
`Language.Plutus.Runtime.TH`).

-}

-- | PLC runtime representation of a `Digest SHA256`
newtype ValidatorHash = ValidatorHash BSL.ByteString
    deriving (Eq, Generic)

instance TypeablePlc ValidatorHash
instance LiftPlc ValidatorHash

newtype DataScriptHash = DataScriptHash BSL.ByteString
    deriving (Eq, Generic)

instance TypeablePlc DataScriptHash
instance LiftPlc DataScriptHash

newtype RedeemerHash = RedeemerHash BSL.ByteString
    deriving (Eq, Generic)

instance TypeablePlc RedeemerHash
instance LiftPlc RedeemerHash

newtype TxHash = TxHash BSL.ByteString
    deriving (Eq, Generic)

instance TypeablePlc TxHash
instance LiftPlc TxHash

plcDataScriptHash :: UTXO.DataScript -> DataScriptHash
plcDataScriptHash = DataScriptHash . plcHash

plcValidatorHash :: UTXO.Validator -> ValidatorHash
plcValidatorHash = ValidatorHash . plcHash

plcValidatorDigest :: Digest SHA256 -> ValidatorHash
plcValidatorDigest = ValidatorHash . plcDigest

plcRedeemerHash :: UTXO.Redeemer -> RedeemerHash
plcRedeemerHash = RedeemerHash . plcHash

plcTxHash :: UTXO.TxId' -> TxHash
plcTxHash = TxHash . plcDigest . UTXO.getTxId

-- | PLC-compatible hash of a hashable value
plcHash :: BA.ByteArrayAccess a => a -> BSL.ByteString
plcHash = plcDigest . hash

-- | Convert a `Digest SHA256` to a PLC `Hash`
plcDigest :: Digest SHA256 -> BSL.ByteString
plcDigest = serialise

-- | Blockchain height
--   TODO: Use [[Wallet.UTXO.Height]] when Integer is supported
type Height = Int