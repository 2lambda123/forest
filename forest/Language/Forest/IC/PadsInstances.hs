{-# LANGUAGE ScopedTypeVariables, TypeFamilies, UndecidableInstances, FlexibleContexts, MultiParamTypeClasses, FlexibleInstances, TemplateHaskell #-}

module Language.Forest.IC.PadsInstances where

import Data.WithClass.MData
import Data.DeriveTH
import Data.WithClass.Derive.MData
import Data.Int
import Data.Word
import Foreign.ForeignPtr
import qualified Data.Data as Data

import Language.Pads.Errors
import Language.Pads.MetaData
import Language.Pads.Source
import Language.Pads.CoreBaseTypes
import Language.Pads.Padsc


import Data.DeepTypeable
import Data.WithClass.Derive.DeepTypeable
import Language.Haskell.TH.Syntax hiding (Loc(..))

import Data.ByteString (ByteString)
import qualified Data.ByteString as B

import System.IO.Unsafe
import System.Mem.StableName
import System.Mem.Weak as Weak
import System.Mem.WeakTable as WeakTable
import System.Mem.MemoTable
import System.Mem.WeakKey
import Language.Pads.BaseTypes
import Data.Time
import Data.Time.Clock.POSIX
import Data.Hashable
import Data.Set as Set



$( derive makeMData ''Base_md )
$( derive makeMData ''ErrMsg )
$( derive makeMData ''ErrInfo )
$( derive makeMDataAbstract ''Pos )
$( derive makeMDataAbstract ''Loc )
$( derive makeMData ''Text )
$( derive makeMData ''Binary )
$( derive makeMData ''PMaybe )
$( derive makeMData ''PMaybe_imd )
$( derive makeMData ''UTCTime )
$( derive makeMDataAbstract ''Day )
instance (Sat (ctx DiffTime),Monad m) => MData ctx m DiffTime

$( derive makeDeepTypeable ''Base_md )
$( derive makeDeepTypeable ''ErrMsg )
$( derive makeDeepTypeable ''ErrInfo )
$( derive makeDeepTypeableAbstract ''Pos )
$( derive makeDeepTypeableAbstract ''Loc )
$( derive makeDeepTypeable ''Text )
$( derive makeDeepTypeable ''Binary )
$( derive makeDeepTypeable ''PMaybe )
$( derive makeDeepTypeable ''PMaybe_imd )
$( derive makeDeepTypeable ''UTCTime )
$( derive makeDeepTypeableAbstract ''Day )
$( derive makeDeepTypeableAbstract ''DiffTime )

instance Hashable Day where
	hashWithSalt i = hashWithSalt i . fromEnum
	
instance Hashable DiffTime where
	hashWithSalt i = hashWithSalt i
	
instance Hashable UTCTime where
	hashWithSalt i = hashWithSalt i . fromEnum . utcTimeToPOSIXSeconds

instance Memo Day where
	type Key Day = Day
	{-# INLINE memoKey #-}
	memoKey d = (MkWeak $ Weak.mkWeak d,d)

instance Memo DiffTime where
	type Key DiffTime = DiffTime
	{-# INLINE memoKey #-}
	memoKey d = (MkWeak $ Weak.mkWeak d,d)

instance Memo UTCTime where
	type Key UTCTime = UTCTime
	{-# INLINE memoKey #-}
	memoKey d = (MkWeak $ Weak.mkWeak d,d)

instance Memo ByteString where
	type Key ByteString = ByteString
	{-# INLINE memoKey #-}
	memoKey d = (MkWeak $ Weak.mkWeak d,d)

instance Memo Binary where
	type Key Binary = StableName Binary
	{-# INLINE memoKey #-}
	memoKey x = (MkWeak $ mkWeak x,unsafePerformIO $ makeStableName x)

instance Memo Base_md where
	type Key Base_md = StableName Base_md
	{-# INLINE memoKey #-}
	memoKey x = (MkWeak $ mkWeak x,unsafePerformIO $ makeStableName x)
	
instance Memo Loc where
	type Key Loc = StableName Loc
	{-# INLINE memoKey #-}
	memoKey x = (MkWeak $ mkWeak x,unsafePerformIO $ makeStableName x)
	
$( derive makeDeepTypeableAbstract ''ByteString )

instance (Monad m,Sat (ctx ByteString)) => MData ctx m ByteString where
  toConstr ctx _   = error "Data.MData.toConstr(ByteString)"
  gunfold ctx _ z c = error "Data.MData.gunfold(ByteString)"
  dataTypeOf ctx _ = return $ mkNoRepType "Data.ByteString.ByteString"

instance Memo ErrMsg where
	type Key ErrMsg = StableName ErrMsg
	{-# INLINE memoKey #-}
	memoKey x = (MkWeak $ Weak.mkWeak x,unsafePerformIO $ makeStableName x)
	
instance Memo Pos where
	type Key Pos = StableName Pos
	{-# INLINE memoKey #-}
	memoKey x = (MkWeak $ Weak.mkWeak x,unsafePerformIO $ makeStableName x)

instance Memo ErrInfo where
	type Key ErrInfo = StableName ErrInfo
	{-# INLINE memoKey #-}
	memoKey x = (MkWeak $ Weak.mkWeak x,unsafePerformIO $ makeStableName x)






