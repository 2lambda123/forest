{-# LANGUAGE DataKinds, ConstraintKinds, ViewPatterns, OverlappingInstances, UndecidableInstances, FlexibleContexts, FlexibleInstances, TypeSynonymInstances, MultiParamTypeClasses, GADTs, ScopedTypeVariables #-}

module Language.Forest.Draw where

------------------------------------------------------------------------------

import System.Posix.Time
import System.Posix.Types
import Foreign.C.Types
import Language.Pads.CoreBaseTypes
import Language.Forest.Errors
import Control.Monad.Incremental.Draw
import Control.Monad
import Data.WithClass.MData
import Data.Data(Data)
import Text.ParserCombinators.ReadP
import Data.ByteString (ByteString)
import qualified Data.ByteString as B
--import Control.Monad.IO.Class
import Language.Forest.FS.FSRep
import Control.Monad.Incremental
import Language.Forest.Shell
import Language.Forest.MetaData
import Control.Monad.Trans

import Data.GraphViz.Types
import Data.GraphViz.Types.Generalised
import Data.GraphViz.Attributes
import Data.GraphViz.Attributes.Complete
import Data.GraphViz.Commands hiding (addExtension)
import Data.Maybe
import qualified Data.Text.Lazy as Text
import Control.Monad.Incremental.Adapton


--import Data.UUID -- for unique graphviz identifiers
--import Data.UUID.V1
import Data.Unique
import Data.IORef
import System.IO.Unsafe
import System.FilePath.Posix
import Language.Forest.IO.Utils
import qualified Data.Sequence as Seq
import Control.Concurrent
import qualified Data.Text.Lazy.IO as Text
import Data.Set (Set(..))
import qualified Data.Set as Set
import Data.Map (Map(..))
import qualified Data.Map as Map
--import Language.Forest.Show
import Language.Forest.FS.NILFS

------------------------------------------------------------------------------

type ForestDraw fs = Draw (IncForest fs) IORef IO

forestDrawToPDF :: ForestDraw fs a => Proxy fs -> a -> FilePath ->  ForestO fs ()
forestDrawToPDF fs = drawToPDF (proxyIncForest fs) Proxy Proxy

forestDrawToDot :: ForestDraw fs a => Proxy fs -> a -> FilePath ->  ForestO fs ()
forestDrawToDot fs = drawToDot (proxyIncForest fs) Proxy Proxy

forestDraw :: ForestDraw fs a => Proxy fs -> a -> ForestO fs DrawDot
forestDraw fs = draw (proxyIncForest fs) Proxy Proxy

drawForestProxy :: Proxy fs -> Proxy (DrawDict (IncForest fs) IORef IO)
drawForestProxy _ = Proxy

fSThunkNode :: Bool -> String -> DotNode String
fSThunkNode isUnevaluated thunkID = DotNode {nodeID = thunkID, nodeAttributes = [Color [WC {wColor = color, weighting = Nothing}],Shape Square,Label (StrLabel $ Text.pack thunkID),Style [SItem Filled []],FillColor [WC {wColor = fillcolor, weighting = Nothing}]]}
	where fillcolor = if isUnevaluated then X11Color CadetBlue4 else X11Color White
	      color = if isUnevaluated then X11Color Black else X11Color CadetBlue4

-- special instance to avoid entering @Forest_md@
instance (MonadIO m,Incremental inc r m) => Draw inc r m (Forest_err) where
	draw inc r m fmd = do
		let str = "Forest_err"
		draw inc r m str

-- special instance to avoid entering @FileInfo@
instance (MonadIO m,Incremental inc r m) => Draw inc r m FileInfo where
	draw inc r m fmd = do
		let str = takeFileName (fullpath fmd) ++ "FileInfo"
		draw inc r m str

instance (MonadIO m,Incremental inc r m) => Draw inc r m ByteString where
	draw inc r m fmd = draw inc r m "<Bytestring>"

instance (FSRep fs,ForestInput fs FSThunk l,Eq a,MData (DrawDict (IncForest fs) IORef IO) (ForestO fs) a,ForestLayer fs l,ForestInput fs FSThunk Outside) => Draw (IncForest fs) IORef IO (ForestFSThunk fs l a) where
	draw (inc :: Proxy (IncForest fs)) r m t = do
		let thunkID = show $ hashUnique $ fsthunkID t
		isUnevaluated <- inside $ isUnevaluatedFSThunk t
		if isUnevaluated
			then return ([thunkID],[DN $ fSThunkNode True thunkID])
			else do
				let thunkNode = fSThunkNode False thunkID
				(childrenIDs,childrenDot) <- drawDict dict inc r m =<< outside (fsforce t)
				let childrenEdges = map (DE . constructorEdge thunkID) childrenIDs
				let childrenRank = sameRank childrenIDs
				return ([thunkID],DN (fSThunkNode False thunkID) : childrenEdges ++ SG childrenRank : childrenDot)

-- for NILFS thunks, we also print IC information
instance (Input L l (IncForest NILFS) IORef IO,ForestInput NILFS FSThunk l,Eq a,MData (DrawDict (IncForest NILFS) IORef IO) (ForestO NILFS) a) => Draw (IncForest NILFS) IORef IO (ForestFSThunk NILFS l a) where
	draw inc r m = draw inc r m . adaptonThunk

instance (FSRep fs,ForestOutput fs ICThunk l,Eq a,MData (DrawDict (IncForest fs) IORef IO) (ForestO fs) a,ForestLayer fs l,ForestOutput fs ICThunk Outside) => Draw (IncForest fs) IORef IO (ForestICThunk fs l a) where
	draw (inc :: Proxy (IncForest fs)) r m t = do
		let tid = show $ hashUnique $ icthunkID t
		isUnevaluated <- inside $ isUnevaluatedICThunk t
		let thunkNode = uNode (if isUnevaluated then Nothing else Just False) tid
		if isUnevaluated
			then return ([tid],[DN thunkNode])
			else do
				(childrenIDs,childrenDot) <- drawDict dict inc r m =<< outside (force t)
				let childrenEdges = map (DE . constructorEdge tid) childrenIDs
				let childrenRank = sameRank childrenIDs
				return ([tid],DN thunkNode : childrenEdges ++ SG childrenRank : childrenDot)

-- for NILFS thunks, we also print IC information
instance (Output U l (IncForest 'NILFS) IORef IO,ForestOutput NILFS ICThunk l,Eq a,MData (DrawDict (IncForest NILFS) IORef IO) (ForestO NILFS) a) => Draw (IncForest NILFS) IORef IO (ForestICThunk NILFS l a) where
	draw inc r m = draw inc r m . adaptonU