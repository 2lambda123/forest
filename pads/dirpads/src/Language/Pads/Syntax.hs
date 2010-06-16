{-# LANGUAGE DeriveDataTypeable #-}

module Language.Pads.Syntax where

import Data.Generics
import Language.Haskell.TH as TH

data PadsTy = Plit Char 
            | Pname String
            | Ptuple [PadsTy] 
            | Precord PadsTy
            | Papp PadsTy TH.Exp
   deriving (Eq, Data, Typeable)

newtype PadsDecl = PadsDecl (Id, Maybe TH.Pat, PadsTy)
   deriving (Eq, Data, Typeable)

data Id = Id String
        | AntiId String
    deriving (Eq, Ord, Data, Typeable)

