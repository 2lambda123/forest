{-# LANGUAGE TypeOperators, ConstraintKinds, FunctionalDependencies, FlexibleInstances, TupleSections, MultiParamTypeClasses, UndecidableInstances, FlexibleContexts, Rank2Types, GADTs, ViewPatterns #-}

-- these are lightweight lenses that often do WRONG thing for non-syncrhonized values.

module Language.Forest.IC.BX where

import Language.Forest.FS.FSRep
import Language.Forest.IC.ICRep
import Data.Map (Map(..))
import qualified Data.Map as Map
import Control.Monad
import Control.Monad.Incremental as IC
import Data.DeepTypeable
import Prelude hiding (mod)
import Data.Typeable
import Control.Monad.Reader as Reader

getMTree :: (FSRep fs,Monad m) => LensM (ReaderT (FSTree fs) m) s v -> FSTree fs -> m s -> m v
getMTree l tree m = runReaderT ((getM l) (lift m)) tree

isoComp :: Iso a b -> Iso b c -> Iso a c
isoComp (Iso to1 from1) (Iso to2 from2) = Iso (to2 . to1) (from1 . from2)

data Lens s v = Lens { get :: s -> v, put :: s -> v -> s }

isoLens :: Iso a b -> Lens a b
isoLens iso = Lens (to iso) (\s -> from iso)

data LensM m s v = LensM { getM :: m s -> m v, putM :: m s -> m v -> m s }

lensM :: Monad m => Lens s v -> LensM m s v
lensM (Lens get put) = LensM (liftM get) (\ms mv -> ms >>= \s -> mv >>= \v -> return $ put s v)

icThunkLensI :: (ForestLayer fs Inside,IncK (IncForest fs) a,FSRep fs,ForestOutput fs ICThunk Inside) => LensM (ReaderT (FSTree fs) (ForestI fs)) (ICThunk fs Inside (IncForest fs) a) a
icThunkLensI = LensM (\mt -> mt >>= lift . force) (\ms mv -> Reader.ask >>= \tree -> lift (thunk $ runReaderT mv tree))

fsThunkLensI :: (ForestLayer fs Inside,IncK (IncForest fs) a,FSRep fs,ForestInput fs FSThunk Inside) => LensM (ReaderT (FSTree fs) (ForestI fs)) (FSThunk fs Inside (IncForest fs) a) a
fsThunkLensI = LensM (\mt -> mt >>= lift . fsForce) (\ms mv -> Reader.ask >>= \tree -> lift (fsThunk tree $ runReaderT mv tree))

idLens :: Lens a a
idLens = Lens id (curry snd)

idLensM :: Monad m => LensM m a a
idLensM = lensM idLens

fstLens :: Lens (a,b) a
fstLens = Lens fst (\(x,y) x' -> (x',y))

sndLens :: Lens (a,b) b
sndLens = Lens snd (\(x,y) y' -> (x,y'))

fstLensM :: Monad m => LensM m (a,b) a
fstLensM = lensM fstLens

sndLensM :: Monad m => LensM m (a,b) b
sndLensM = lensM sndLens

prodLens :: Lens a b -> Lens c d -> Lens (a , c) (b , d)
prodLens l1 l2 = Lens get' put' where
	get' (x,y) = (Language.Forest.IC.BX.get l1 x,Language.Forest.IC.BX.get l2 y)
	put' (x,y) (z,w) = (put l1 x z,put l2 y w)	

compLens :: Lens a b -> Lens b c -> Lens a c
compLens l1 l2 = Lens get' put' where
	get' = Language.Forest.IC.BX.get l2 . Language.Forest.IC.BX.get l1
	put' s v = put l1 s (put l2 (Language.Forest.IC.BX.get l1 s) v)

prodLensM :: Monad m => LensM m a b -> LensM m c d -> LensM m (a , c) (b , d)
prodLensM l1 l2 = LensM get put where
	get ms = do
		(x , y) <- ms
		z <- getM l1 (return x)
		w <- getM l2 (return y)
		return (z , w)
	put ms mv = do
		(x , y) <- ms
		(z , w) <- mv
		x' <- putM l1 (return x) (return z)
		y' <- putM l2 (return y) (return w)
		return (x' , y')	

prodFLensM :: Monad m => LensM m a b -> LensM m c d -> LensM m (a :.: c) (b :.: d)
prodFLensM l1 l2 = LensM get put where
	get ms = do
		(x :.: y) <- ms
		z <- getM l1 (return x)
		w <- getM l2 (return y)
		return (z :.: w)
	put ms mv = do
		(x :.: y) <- ms
		(z :.: w) <- mv
		x' <- putM l1 (return x) (return z)
		y' <- putM l2 (return y) (return w)
		return (x' :.: y')	

compLensM :: Monad m => LensM m a b -> LensM m b c -> LensM m a c
compLensM l1 l2 = LensM get put where
	get = getM l2 . getM l1
	put ms mv = putM l1 ms (putM l2 (getM l1 ms) mv)

maybeLensM :: Monad m => LensM m a b -> LensM m (Maybe a) (Maybe b)
maybeLensM l1 = LensM get put where
	get ms = do
		mb <- ms
		case mb of
			Nothing -> return Nothing
			Just s -> liftM Just $ getM l1 (return s)
	put ms mv = do
		mbv <- mv
		case mbv of
			Nothing -> return Nothing
			Just v -> do
				mbs <- ms
				case mbs of
					Nothing -> error "maybeLensM"
					Just s -> liftM Just $ putM l1 (return s) (return v)

mapElemsLens :: Lens (Map k v) [v]
mapElemsLens = Lens Map.elems (\s v -> Map.fromDistinctAscList $ Map.keys s `zip` v)

mapElemsLensM :: Monad m => LensM m (Map k v) [v]
mapElemsLensM = lensM mapElemsLens

zipFLens :: Lens ([a] :.: [b]) [a :.: b]
zipFLens = Lens get put where
	get (xs :.: ys) = zipF xs ys
	put s xys' = unzipF xys'
	zipF [] [] = []
	zipF (x:xs) (y:ys) = (x :.: y) : zipF xs ys
	unzipF [] = ([] :.: [])
	unzipF ((x :.: y):zs) = let (xs :.: ys) = unzipF zs in (x:xs) :.: (y:ys)

zipFLensM :: Monad m => LensM m ([a] :.: [b]) [a :.: b]
zipFLensM = lensM zipFLens

zipFMaybeLens :: Lens (Maybe a :.: Maybe b) (Maybe (a :.: b))
zipFMaybeLens = Lens get put where
	get (Nothing :.: Nothing) = Nothing
	get (Just x :.: Just y) = Just (x :.: y)
	put s Nothing = Nothing :.: Nothing
	put s (Just (x :.: y)) = Just x :.: Just y

zipFMaybeLensM :: Monad m => LensM m (Maybe a :.: Maybe b) (Maybe (a :.: b))
zipFMaybeLensM = lensM zipFMaybeLens

mapLensM :: Monad m => LensM m a b -> LensM m [a] [b]
mapLensM l = LensM get put where
	get ms = ms >>= get'
	get' [] = return []
	get' (x:xs) = do
		v <- getM l (return x)
		vs <- get' xs
		return $ v:vs
	put ms mv = ms >>= \s -> mv >>= \v -> put' s v
	put' [] [] = return []
	put' (s:ss) (v:vs) = do
		s' <- putM l (return s) (return v)
		ss' <- put' ss vs
		return $ s':ss'

