{-# LANGUAGE DataKinds, ConstraintKinds, TupleSections, FlexibleContexts, ScopedTypeVariables, GADTs, FlexibleInstances,MultiParamTypeClasses,UndecidableInstances, ViewPatterns #-}

module Language.Forest.IC.IO.ZDeltaStoring where

import Control.Monad.Trans
import Language.Forest.IC.IO.ZStoring
import Control.Monad.Writer (Writer(..),WriterT(..))
import qualified Control.Monad.Writer as Writer
import Language.Forest.Manifest
import Prelude hiding (const,read,mod)
import qualified Prelude
import Language.Forest.IO.Utils
import Language.Forest.Syntax
import Language.Forest.IC.BX as BX
import Language.Forest.FS.Diff
import Language.Forest.IC.ValueDelta
import Language.Forest.IC.ICRep
import Language.Pads.Padsc hiding (lift,numErrors)
import qualified Language.Pads.Padsc as Pads
import Language.Forest.IC.MetaData
import Language.Forest.IC.Default
import Language.Forest.IC.Generic
import Language.Forest.IC.IO.Storing
import Language.Forest.Errors
import Language.Forest.FS.FSDelta
import Language.Forest.Pure.MetaData (FileInfo(..),FileType(..),(:*:)(..))
import qualified Language.Forest.Pure.MetaData as Pure
import Control.Monad.Incremental as Inc hiding (memo)
import Data.IORef
import Data.List as List
import Language.Forest.IO.Shell

import qualified System.FilePath.Posix
import System.FilePath.Glob
import System.Posix.Env
import System.Posix.Files
import System.Process
import System.Exit
import System.Directory
import System.IO
import System.IO.Unsafe
import Text.Regex
import System.FilePath.Posix
import Control.Monad
import Data.Monoid
import Data.List
import Language.Forest.FS.FSRep
--import Control.Monad.IO.Class
import Data.WithClass.MData



import qualified Control.Exception as CE

import Data.Data
import Data.Maybe
import System.Random
import Data.Proxy
import Control.Monad.Reader (Reader(..),ReaderT(..))
import qualified Control.Monad.Reader as Reader
import Language.Pads.Generic as Pads

doZDeltaManifestNamed :: ZippedICForest fs args rep =>
	Proxy args -> LoadDeltaArgs ICData fs args -> FilePath -> FilePath -> FSTree fs -> FSTreeD fs -> FSTree fs -> (ForestFSThunkI fs rep) -> ValueDelta fs (ForestFSThunkI fs rep) -> Manifest fs -> MManifestForestO fs
doZDeltaManifestNamed proxy (margs,dargs) path path' tree df tree' rep dv man = do
	irep <- lift $ Inc.getOutside rep
	idv <- lift $ diffValueBelow dv diffValue tree irep
	zupdateManifestDeltaGeneric proxy (margs,dargs) path path' tree df tree' irep idv man

-- updates the thunks that keep track of the arguments of a top-level declaration
doZDeltaManifestArgs :: (ForestArgs fs args,ICRep fs) =>
	Proxy args -> LoadDeltaArgs ICData fs args -> rep -> ValueDelta fs rep
	-> (ForestICThunksI fs args -> rep -> ValueDelta fs rep -> Manifest fs -> MManifestForestO fs)
	->  Manifest fs -> MManifestForestO fs
doZDeltaManifestArgs proxy (margs,_) rep dv manifestD (man :: Manifest fs) = debug ("doStoreDeltaArgs") $ do
	arg_thunks <- lift $ inside $ newArgs (Proxy :: Proxy fs) proxy margs -- creates new thunks to hold the new expressions
	manifestD arg_thunks rep dv man

doZDeltaManifestFile1 :: (FTK fs (Pure.Arg arg) (ForestFSThunkI fs ((Forest_md fs,md),pads)) ((Forest_md fs,md),pads) ((Pure.FileInfo,md),padsc)
	,IncK (IncForest fs) Forest_err,IncK (IncForest fs) ((Forest_md fs, md), pads),ZippedICMemo fs,MData NoCtx (ForestI fs) arg,ForestInput fs FSThunk Inside,Eq arg,Typeable arg,ICRep fs,Pads1 arg pads md) =>
	Bool -> ForestI fs arg -> FilePath -> FilePath -> FSTree fs -> FSTreeD fs -> FSTree fs -> ForestFSThunkI fs ((Forest_md fs,md),pads) -> ValueDelta fs (ForestFSThunkI fs ((Forest_md fs,md),pads)) -> Manifest fs -> MManifestForestO fs
doZDeltaManifestFile1 isEmptyDArg marg path path' (tree :: FSTree fs) df tree' rep_t dv man = do
	let fs = Proxy :: Proxy fs
	let argProxy = Proxy :: Proxy (Pure.Arg arg)
	case (isEmptyDArg,path == path',isIdValueDelta dv,df) of
		(True,True,True,(isEmptyFSTreeD fs -> True)) -> do -- no conflict tests are issued
			Writer.tell $ inside . addZippedMemo path' argProxy marg rep_t . Just
			return man -- nothing changed
		otherwise -> doZManifestFile1 marg path' tree' rep_t man

doZDeltaManifestFileInner1 :: (IncK (IncForest fs) FileInfo,IncK (IncForest fs) Forest_err,IncK (IncForest fs) ((Forest_md fs, md), pads),ZippedICMemo fs,MData NoCtx (ForestI fs) arg,ForestInput fs FSThunk Inside,Eq arg,Typeable arg,ICRep fs,Pads1 arg pads md) =>
	Bool -> ForestI fs arg -> FilePath -> FilePath -> FSTree fs -> FSTreeD fs -> FSTree fs -> ((Forest_md fs,md),pads) -> ValueDelta fs (((Forest_md fs,md),pads)) -> Manifest fs -> MManifestForestO fs
doZDeltaManifestFileInner1 isEmptyDArg marg path path' (tree :: FSTree fs) df tree' rep_t dv man = do
	let fs = Proxy :: Proxy fs
	let argProxy = Proxy :: Proxy (Pure.Arg arg)
	case (isEmptyDArg,path == path',isIdValueDelta dv,df) of
		(True,True,True,(isEmptyFSTreeD fs -> True)) -> do -- no conflict tests are issued
			return man -- nothing changed
		otherwise -> doZManifestFileInner1 marg path' tree' rep_t man

doZDeltaManifestArchive :: (IncK (IncForest fs) (Forest_md fs, rep),ForestMD fs rep,Typeable rep,ZippedICMemo fs,ICRep fs,toprep ~ ForestFSThunkI fs (Forest_md fs,rep)) =>
	Bool -> [ArchiveType] -> FilePath -> FilePath -> FSTree fs -> FSTreeD fs -> FSTree fs
	-> toprep -> ValueDelta fs toprep
	-> (FilePath -> FSTree fs -> rep -> Manifest fs -> MManifestForestO fs)
	-> (FilePath -> FilePath -> FSTree fs -> FSTreeD fs -> FSTree fs -> rep -> ValueDelta fs rep -> Manifest fs -> MManifestForestO fs)
	-> (FSTree fs -> rep -> ForestO fs (ValueDelta fs rep))
	-> Manifest fs -> MManifestForestO fs
doZDeltaManifestArchive isClosed archTy path path' (tree :: FSTree fs) df tree' arch_rep arch_dv manifest manifestD diffValue man = do
	let fs = Proxy :: Proxy fs
	
	let mani_arch = doZManifestArchive isClosed archTy path' tree' arch_rep manifest manifestD diffValue man
	
	topdv <- lift $ diffTopValueThunk tree arch_rep
	if (not $ isIdValueDelta topdv) then mani_arch else do
		isRepairMd <- Reader.ask
		exists <- lift $ forestM $ doesFileExistInTree path tree
		exists' <- if isEmptyTopFSTreeD fs df then return exists else lift (forestM $ doesFileExistInTree path' tree')
		(fmd,rep) <- lift $ Inc.getOutside arch_rep
		err_t <- lift $ get_errors_thunk fmd
		path_fmd <- lift $ get_fullpath fmd
		exists_dir <- lift $ doesFileExistInMD fmd
    	
		case (exists,exists_dir,exists') of
			(False,False,False) -> case (path == path',isIdValueDelta arch_dv,isEmptyTopFSTreeD fs df) of
				(True,True,True) -> return man
				otherwise -> do
					let testm = do
						status1 <- if isRepairMd then return Valid else liftM (boolStatus $ ConflictingMdValidity) $ forestO $ inside (get_errors rep) >>= sameValidity' fmd
						status2 <- liftM (boolStatus $ ConflictingPath path path_fmd) $ latestTree >>= sameCanonicalFullPathInTree path_fmd path
						return $ status1 `mappend` status2
					Writer.tell $ Prelude.const $ replaceForestMDErrorsWith fmd $ liftM (:[]) $ liftM (Pure.missingDirForestErr path `Pure.mergeForestErrs`) $ get_errors rep
					return $ addTestToManifest testm man -- errors in the metadata must be consistent
					
			(True,True,True) -> do
				canpath' <- lift $ forestM $ canonalizeDirectoryInTree path' tree'
				dskpath' <- lift $ forestM $ pathInTree canpath' tree'
				let arch_canpath' = cardinalPath canpath'
				avfsTree' <- lift $ forestM $ virtualTree tree'
				avfsTree <- lift $ forestM $ virtualTree tree
				
				archiveDir' <- lift $ forestM $ forestIO $ getTempPath -- unlogged temporary directory, since we remove it ourselves
				archiveManifest <- lift $ forestM $ newManifestWith arch_canpath' tree'
				lift $ forestM $ forestIO $ CE.onException (decompressArchive archTy dskpath' archiveDir') (createDirectoryIfMissing True archiveDir') -- decompress the original content, since some of it may be preserved in the new archive
				
				archiveDf <- lift $ forestM $ focusDiffFSTreeD tree arch_canpath' tree' arch_canpath'
				dv <- lift $ diffValueBelow arch_dv diffValue tree rep
				archiveManifest' <- manifestD arch_canpath' arch_canpath' avfsTree archiveDf avfsTree' rep dv archiveManifest		
				
				-- NOTE: we only need to commit the writes that contribute to the new archive, inside the forest temp dir; if we chose otherwise we could unsafely commit to the filesystem!
				man1 <- lift $ forestM $ storeManifestAt archiveDir' archiveManifest' -- store the manifest at the temp dir, and return all the modifications outside the archive
				archiveFile <- lift $ forestM tempPath
				lift $ forestM $ forestIO $ compressArchive archTy archiveDir' archiveFile -- compresses the new data into a new temp file
				lift $ forestM $ forestIO $ removePath archiveDir' -- purges all temporary archive data 
				
				top <- lift $ diffTopValueThunk tree arch_rep -- if the current thunk hasn't changed
				toperror <- lift $ diffTopValueThunk tree err_t -- if the error thunk hasn't changed
				let testm = case (path==path',isIdValueDelta top && isIdValueDelta toperror) of
					(True,True) -> return Valid
					otherwise -> do
						status1 <- if isRepairMd then return Valid else liftM (boolStatus ConflictingMdValidity) $ forestO $ inside (get_errors rep) >>= sameValidity' fmd
						status2 <- liftM (boolStatus $ ConflictingPath path path_fmd) $ latestTree >>= sameCanonicalFullPathInTree path_fmd path
						return $ status1 `mappend` status2
				Writer.tell $ Prelude.const $ replaceForestMDErrorsWith fmd $ liftM (:[]) $ get_errors rep
					
				let man2 = addTestToManifest testm man -- errors in the metadata must be consistent
				
				abspath' <- lift $ forestM $ forestIO $ absolutePath path'
				let man3 = addFileToManifest' canpath' abspath' archiveFile man2
				
				return $ mergeManifests man1 man3
			otherwise -> mani_arch

doZDeltaManifestArchiveInner :: (IncK (IncForest fs) (Forest_md fs, rep),ForestMD fs rep,Typeable rep,ZippedICMemo fs,ICRep fs,toprep ~ (Forest_md fs,rep)) =>
	Bool -> [ArchiveType] -> FilePath -> FilePath -> FSTree fs -> FSTreeD fs -> FSTree fs
	-> toprep -> ValueDelta fs toprep
	-> (FilePath -> FSTree fs -> rep -> Manifest fs -> MManifestForestO fs)
	-> (FilePath -> FilePath -> FSTree fs -> FSTreeD fs -> FSTree fs -> rep -> ValueDelta fs rep -> Manifest fs -> MManifestForestO fs)
	-> (FSTree fs -> rep -> ForestO fs (ValueDelta fs rep))
	-> Manifest fs -> MManifestForestO fs
doZDeltaManifestArchiveInner isClosed archTy path path' (tree :: FSTree fs) df tree' (fmd,rep) arch_dv manifest manifestD diffValue man = do
	let fs = Proxy :: Proxy fs
	isRepairMd <- Reader.ask
	exists <- lift $ forestM $ doesFileExistInTree path tree
	exists' <- if isEmptyTopFSTreeD fs df then return exists else lift (forestM $ doesFileExistInTree path' tree')
	err_t <- lift $ get_errors_thunk fmd
	path_fmd <- lift $ get_fullpath fmd
	exists_dir <- lift $ doesFileExistInMD fmd

	case (exists,exists_dir,exists') of
		(False,False,False) -> case (path == path',isIdValueDelta arch_dv,isEmptyTopFSTreeD fs df) of
			(True,True,True) -> return man
			otherwise -> do
				let testm = do
					status1 <- if isRepairMd then return Valid else liftM (boolStatus $ ConflictingMdValidity) $ forestO $ inside (get_errors rep) >>= sameValidity' fmd
					status2 <- liftM (boolStatus $ ConflictingPath path path_fmd) $ latestTree >>= sameCanonicalFullPathInTree path_fmd path
					return $ status1 `mappend` status2
				Writer.tell $ Prelude.const $ replaceForestMDErrorsWith fmd $ liftM (:[]) $ liftM (Pure.missingDirForestErr path `Pure.mergeForestErrs`) $ get_errors rep
				return $ addTestToManifest testm man -- errors in the metadata must be consistent
				
		(True,True,True) -> do
			canpath' <- lift $ forestM $ canonalizeDirectoryInTree path' tree'
			dskpath' <- lift $ forestM $ pathInTree canpath' tree'
			let arch_canpath' = cardinalPath canpath'
			avfsTree' <- lift $ forestM $ virtualTree tree'
			avfsTree <- lift $ forestM $ virtualTree tree
			
			archiveDir' <- lift $ forestM $ forestIO $ getTempPath -- unlogged temporary directory, since we remove it ourselves
			archiveManifest <- lift $ forestM $ newManifestWith arch_canpath' tree'
			lift $ forestM $ forestIO $ CE.onException (decompressArchive archTy dskpath' archiveDir') (createDirectoryIfMissing True archiveDir') -- decompress the original content, since some of it may be preserved in the new archive
			
			archiveDf <- lift $ forestM $ focusDiffFSTreeD tree arch_canpath' tree' arch_canpath'
			dv <- lift $ diffValueBelow arch_dv diffValue tree rep
			archiveManifest' <- manifestD arch_canpath' arch_canpath' avfsTree archiveDf avfsTree' rep dv archiveManifest		
			
			-- NOTE: we only need to commit the writes that contribute to the new archive, inside the forest temp dir; if we chose otherwise we could unsafely commit to the filesystem!
			man1 <- lift $ forestM $ storeManifestAt archiveDir' archiveManifest' -- store the manifest at the temp dir, and return all the modifications outside the archive
			archiveFile <- lift $ forestM tempPath
			lift $ forestM $ forestIO $ compressArchive archTy archiveDir' archiveFile -- compresses the new data into a new temp file
			lift $ forestM $ forestIO $ removePath archiveDir' -- purges all temporary archive data 
			
			let testm = do
				status1 <- if isRepairMd then return Valid else liftM (boolStatus ConflictingMdValidity) $ forestO $ inside (get_errors rep) >>= sameValidity' fmd
				status2 <- liftM (boolStatus $ ConflictingPath path path_fmd) $ latestTree >>= sameCanonicalFullPathInTree path_fmd path
				return $ status1 `mappend` status2
			Writer.tell $ Prelude.const $ replaceForestMDErrorsWith fmd $ liftM (:[]) $ get_errors rep
				
			let man2 = addTestToManifest testm man -- errors in the metadata must be consistent
			
			abspath' <- lift $ forestM $ forestIO $ absolutePath path'
			let man3 = addFileToManifest' canpath' abspath' archiveFile man2
			
			return $ mergeManifests man1 man3
		otherwise -> doZManifestArchiveInner archTy path' tree' (fmd,rep) manifest man

doZDeltaManifestSymLink :: (IncK (IncForest fs) FileInfo,sym ~ ForestFSThunkI fs ((Forest_md fs,Base_md),FilePath),IncK (IncForest fs) Forest_err,IncK (IncForest fs) ((Forest_md fs, Base_md), FilePath),ICRep fs) => FilePath -> FilePath -> FSTree fs -> FSTreeD fs -> FSTree fs -> sym -> ValueDelta fs sym -> Manifest fs -> MManifestForestO fs
doZDeltaManifestSymLink path path' tree df (tree' :: FSTree fs) (rep_t) dv man = do
	let fs = Proxy :: Proxy fs
	case (path == path',isIdValueDelta dv,df) of
		(True,True,isEmptyFSTreeD fs -> True) -> debug "symlink unchanged" $ return man
		otherwise -> doZManifestSymLink path' tree' (rep_t) man

doZDeltaManifestSymLinkInner :: (IncK (IncForest fs) FileInfo,sym ~ ((Forest_md fs,Base_md),FilePath),IncK (IncForest fs) Forest_err,IncK (IncForest fs) ((Forest_md fs, Base_md), FilePath),ICRep fs) => FilePath -> FilePath -> FSTree fs -> FSTreeD fs -> FSTree fs -> sym -> ValueDelta fs sym -> Manifest fs -> MManifestForestO fs
doZDeltaManifestSymLinkInner path path' tree df (tree' :: FSTree fs) (rep_t) dv man = do
	let fs = Proxy :: Proxy fs
	case (path == path',isIdValueDelta dv,df) of
		(True,True,isEmptyFSTreeD fs -> True) -> debug "symlink unchanged" $ return man
		otherwise -> doZManifestSymLinkInner path' tree' (rep_t) man

doZDeltaManifestConstraint :: (Typeable rep,ForestContent fs rep content,IncK (IncForest fs) (ForestFSThunkI fs Forest_err, rep),ForestMD fs rep,ICRep fs, toprep ~ ForestFSThunkI fs (ForestFSThunkI fs Forest_err,rep)) =>
	Bool -> (content -> ForestI fs Bool) -> FSTree fs -> toprep -> ValueDelta fs toprep
	-> (rep -> Manifest fs -> MManifestForestO fs)
	-> (rep -> ValueDelta fs rep -> Manifest fs -> MManifestForestO fs)
	-> (FSTree fs -> rep -> ForestO fs (ValueDelta fs rep))
	-> Manifest fs -> MManifestForestO fs
doZDeltaManifestConstraint emptyDArgs pred tree rep_t dv manifest manifestD diffValue man = do
	
	let mani_k = doZManifestConstraint pred rep_t manifest man
	
	topdv <- lift $ diffTopValueThunk tree rep_t
	if (not $ isIdValueDelta topdv) then mani_k else do
		(err_t,rep) <- lift $ Inc.getOutside rep_t
		idv <- lift $ diffValueBelow dv diffValue tree rep
		doZDeltaManifestConstraintInner emptyDArgs pred tree (err_t,rep) (mapValueDelta Proxy idv) manifestD diffValue man

doZDeltaManifestConstraintInner :: (ForestContent fs rep content,ForestMD fs rep,ICRep fs, toprep ~ (ForestFSThunkI fs Forest_err,rep)) =>
	Bool -> (content -> ForestI fs Bool) -> FSTree fs -> toprep -> ValueDelta fs toprep
	-> (rep -> ValueDelta fs rep -> Manifest fs -> MManifestForestO fs)
	-> (FSTree fs -> rep -> ForestO fs (ValueDelta fs rep))
	-> Manifest fs -> MManifestForestO fs
doZDeltaManifestConstraintInner emptyDArgs pred tree (err_t,rep) dv manifestD diffValue man = do
	isRepairMd <- Reader.ask
	idv <- lift $ diffValueBelow dv diffValue tree rep
	man1 <- manifestD rep idv man
	
	Writer.tell $ \latest -> do
		overwrite err_t $ do
			err_cond <- predForestErr . pred =<< BX.getM lens_content (return rep)
			err_inner <- get_errors rep
			return $ Pure.mergeForestErrs err_cond err_inner
	
	case (emptyDArgs,isIdValueDelta idv) of
		(True,True) -> return man1
		otherwise -> do
			let testm = do -- constraint errors need to be accounted for
				if isRepairMd then return Valid else liftM (boolStatus $ ConflictingMdValidity) $ forestO $ inside $ do
					err_cond <- predForestErr . pred =<< BX.getM lens_content (return rep)
					err_inner <- get_errors rep
					errors <- Inc.get err_t
					return $ isValidForestErr errors == isValidForestErr (Pure.mergeForestErrs err_cond err_inner)
			return $ addTestToManifest testm man1
	

doZDeltaManifestConstraintCompound :: (ForestMD fs rep,ICRep fs) =>
	Bool -> ForestI fs Bool -> rep -> ValueDelta fs rep
	-> (rep -> ValueDelta fs rep -> Manifest fs -> MManifestForestO fs)
	-> Manifest fs -> MManifestForestO fs
doZDeltaManifestConstraintCompound emptyDArgs pred rep dv manifestD man = do
	man1 <- manifestD rep dv man
	case (emptyDArgs,isIdValueDelta dv) of
		(True,True) -> return man1
		otherwise -> do
			let testm = do -- constraint errors need to be accounted for
				liftM (boolStatus $ ConflictingMdValidity) $ forestO $ inside $ do
					cond <- pred
					valid <- liftM ((==0) . numErrors) $ get_errors rep
					-- valid reps need to satisfy the predicate
					return $ valid <= cond
			return $ addTestToManifest testm man1

-- assumes that, before any changes occured, the original error thunk was computing the sum of the errors of the inner representation.
doZDeltaManifestDirectory :: (IncK (IncForest fs) FileInfo,IncK (IncForest fs) Forest_err,Typeable rep,IncK (IncForest fs) (Forest_md fs, rep),ICRep fs,dirrep ~ ForestFSThunkI fs (Forest_md fs,rep)) => 
	FilePath -> FilePath -> FSTree fs -> FSTreeD fs -> FSTree fs
	-> dirrep -> ValueDelta fs dirrep
	-> (rep -> ForestI fs Forest_err)
	-> (rep -> Manifest fs -> MManifestForestO fs)
	-> (rep -> ValueDelta fs rep -> Manifest fs -> MManifestForestO fs)
	-> (FSTree fs -> rep -> ForestO fs (ValueDelta fs rep))
	-> Manifest fs -> MManifestForestO fs
doZDeltaManifestDirectory path path' tree df (tree' :: FSTree fs) dirrep_t dv collectMDErrors manifest manifestD diffValue man = do
	let fs = Proxy :: Proxy fs
	
	let mani_dir = doZManifestDirectory path' tree' collectMDErrors dirrep_t manifest man
	
	topdv <- lift $ diffTopValueThunk tree dirrep_t
	if (not $ isIdValueDelta topdv) then mani_dir else do
		isRepairMd <- Reader.ask
		exists <- lift $ forestM $ doesDirectoryExistInTree path tree
		exists' <- if isEmptyTopFSTreeD fs df then return exists else lift (forestM $ doesDirectoryExistInTree path' tree')
		(fmd,rep) <- lift $ Inc.getOutside dirrep_t
		err_t <- lift $ get_errors_thunk fmd
		path_fmd <- lift $ get_fullpath fmd
		exists_dir <- lift $ doesDirectoryExistInMD fmd
    	
		case (exists,exists_dir,exists') of
			(False,False,False) -> case (path == path',isIdValueDelta dv,isEmptyTopFSTreeD fs df) of
				(True,True,True) -> return man
				otherwise -> do
					let testm = do
						status1 <- if isRepairMd then return Valid else liftM (boolStatus $ ConflictingMdValidity) $ forestO $ inside (collectMDErrors rep) >>= sameValidity' fmd
						status2 <- liftM (boolStatus $ ConflictingPath path path_fmd) $ latestTree >>= sameCanonicalFullPathInTree path_fmd path
						return $ status1 `mappend` status2
					Writer.tell $ \latest -> replaceForestMDErrorsWith fmd $ liftM (:[]) $ liftM (Pure.missingDirForestErr path `Pure.mergeForestErrs`) $ collectMDErrors rep
					return $ addTestToManifest testm man -- errors in the metadata must be consistent
					
			(True,True,True) -> do
				top <- lift $ diffTopValueThunk tree dirrep_t -- if the current thunk hasn't changed
				toperror <- lift $ diffTopValueThunk tree err_t -- if the error thunk hasn't changed
				let testm = case (path==path',isIdValueDelta top && isIdValueDelta toperror) of
					(True,True) -> return Valid
					otherwise -> do
						status11 <- if isRepairMd then return Valid else liftM (boolStatus ConflictingMdValidity) $ forestO $ inside (collectMDErrors rep) >>= sameValidity' fmd
						status12 <- liftM (boolStatus $ ConflictingPath path path_fmd) $ latestTree >>= sameCanonicalFullPathInTree path_fmd path
						return $ status11 `mappend` status12
				idv <- lift $ diffValueBelow dv diffValue tree rep
				Writer.tell $ \latest -> replaceForestMDErrorsWith fmd $ liftM (:[]) $ collectMDErrors rep
				manifestD rep idv $ addTestToManifest testm man
			otherwise -> mani_dir

doZDeltaManifestDirectoryInner :: (IncK (IncForest fs) FileInfo,IncK (IncForest fs) Forest_err,Typeable rep,IncK (IncForest fs) (Forest_md fs, rep),ICRep fs,dirrep ~ (Forest_md fs,rep)) => 
	FilePath -> FilePath -> FSTree fs -> FSTreeD fs -> FSTree fs
	-> dirrep -> ValueDelta fs dirrep
	-> (rep -> ForestI fs Forest_err)
	-> (rep -> Manifest fs -> MManifestForestO fs)
	-> (rep -> ValueDelta fs rep -> Manifest fs -> MManifestForestO fs)
	-> (FSTree fs -> rep -> ForestO fs (ValueDelta fs rep))
	-> Manifest fs -> MManifestForestO fs
doZDeltaManifestDirectoryInner path path' tree df (tree' :: FSTree fs) (fmd,rep) dv collectMDErrors manifest manifestD diffValue man = do
	let fs = Proxy :: Proxy fs
	isRepairMd <- Reader.ask
	exists <- lift $ forestM $ doesDirectoryExistInTree path tree
	exists' <- if isEmptyTopFSTreeD fs df then return exists else lift (forestM $ doesDirectoryExistInTree path' tree')
	err_t <- lift $ get_errors_thunk fmd
	path_fmd <- lift $ get_fullpath fmd
	exists_dir <- lift $ doesDirectoryExistInMD fmd

	case (exists,exists_dir,exists') of
		(False,False,False) -> case (path == path',isIdValueDelta dv,isEmptyTopFSTreeD fs df) of
			(True,True,True) -> return man
			otherwise -> do
				let testm = do
					status1 <- if isRepairMd then return Valid else liftM (boolStatus $ ConflictingMdValidity) $ forestO $ inside (collectMDErrors rep) >>= sameValidity' fmd
					status2 <- liftM (boolStatus $ ConflictingPath path path_fmd) $ latestTree >>= sameCanonicalFullPathInTree path_fmd path
					return $ status1 `mappend` status2
				Writer.tell $ \latest -> replaceForestMDErrorsWith fmd $ liftM (:[]) $ liftM (Pure.missingDirForestErr path `Pure.mergeForestErrs`) $ collectMDErrors rep
				return $ addTestToManifest testm man -- errors in the metadata must be consistent
				
		(True,True,True) -> do
			let testm = do
				status1 <- if isRepairMd then return Valid else liftM (boolStatus ConflictingMdValidity) $ forestO $ inside (collectMDErrors rep) >>= sameValidity' fmd
				status2 <- liftM (boolStatus $ ConflictingPath path path_fmd) $ latestTree >>= sameCanonicalFullPathInTree path_fmd path
				return $ status1 `mappend` status2
			idv <- lift $ diffValueBelow dv diffValue tree rep
			Writer.tell $ \latest -> replaceForestMDErrorsWith fmd $ liftM (:[]) $ collectMDErrors rep
			manifestD rep idv $ addTestToManifest testm man
		otherwise -> doZManifestDirectoryInner path' tree' collectMDErrors (fmd,rep) manifest man

-- assumes that, before any changes occured, the original error thunk was computing the sum of the errors of the inner representation.
doZDeltaManifestMaybe :: (Typeable rep,IncK (IncForest fs) (Forest_md fs, Maybe rep),ForestMD fs rep,ICRep fs,mbrep ~ ForestFSThunkI fs (Forest_md fs,Maybe rep)) =>
	FilePath -> FilePath -> FSTree fs -> FSTreeD fs -> FSTree fs -> mbrep -> ValueDelta fs mbrep
	-> (rep -> Manifest fs -> MManifestForestO fs) -- inner store function
	-> (rep -> ValueDelta fs rep -> Manifest fs -> MManifestForestO fs) -- inner incremental store function
	-> (FSTree fs -> rep -> ForestO fs (ValueDelta fs rep))
	-> Manifest fs -> MManifestForestO fs
doZDeltaManifestMaybe path path' tree df (tree' :: FSTree fs) mbrep_t dv manifest manifestD diffValue man = do
	let fs = Proxy :: Proxy fs
	
	let mani_maybe = doZManifestMaybe path' tree' mbrep_t manifest man
	
	topdv <- lift $ diffTopValueThunk tree mbrep_t
	
	if (not $ isIdValueDelta topdv) then mani_maybe else do
		isRepairMd <- Reader.ask
		exists <- lift $ forestM $ doesExistInTree path tree
		exists' <- if isEmptyTopFSTreeD fs df then return exists else lift (forestM $ doesExistInTree path' tree')
		(fmd,mb_rep) <- lift $ Inc.getOutside mbrep_t
		err_t <- lift $ get_errors_thunk fmd
		path_fmd <- lift $ inside $ get_fullpath fmd
		
		-- guarantee that the error thunk is being updated on inner changes 
		Writer.tell $ Prelude.const $ get_errors_thunk fmd >>= flip overwrite (maybe (return cleanForestErr) get_errors mb_rep)
		
		case (exists,mb_rep,exists') of
			(False,Nothing,False) -> do
				case (path == path',isIdValueDelta dv,isEmptyTopFSTreeD fs df) of
					(True,True,True) -> do
						let testm = liftM (boolStatus $ ExistingPath path) $ latestTree >>= liftM not . doesExistInTree path
						return $ addTestToManifest testm man
					otherwise -> do
						let testm = do
							status1 <- liftM (boolStatus $ ExistingPath path) $ latestTree >>= liftM not . doesExistInTree path
							status2 <- if isRepairMd then return Valid else liftM (boolStatus ConflictingRepMd) $ forestO $ inside $ liftM (==fmd) $ cleanForestMDwithFile path'
							return $ status1 `mappend` status2
						return $ addTestToManifest testm man
			(True,Just irep,True) -> do
				top <- lift $ diffTopValueThunk tree mbrep_t -- if the current thunk hasn't changed
				toperror <- lift $ diffTopValueThunk tree err_t -- if the error thunk hasn't changed
				let testm = do
					status1 <- case (path==path',isIdValueDelta top && isIdValueDelta toperror) of
						(True,True) -> return Valid
						otherwise -> do
							status11 <- if isRepairMd then return Valid else liftM (boolStatus ConflictingMdValidity) $ forestO $ sameValidity fmd irep
							status12 <- liftM (boolStatus $ ConflictingPath path path_fmd) $ latestTree >>= sameCanonicalFullPathInTree path_fmd path
							return $ status11 `mappend` status12
					status2 <- liftM (boolStatus $ NonExistingPath path) $ latestTree >>= doesExistInTree path
					return $ status1 `mappend` status2
				idv <- lift $ diffValueBelow dv diffValue tree irep
				manifestD irep idv $ addTestToManifest testm man
			otherwise -> mani_maybe
			
-- assumes that, before any changes occured, the original error thunk was computing the sum of the errors of the inner representation.
doZDeltaManifestMaybeInner :: (ForestMD fs rep,ICRep fs) =>
	FilePath -> FilePath -> FSTree fs -> FSTreeD fs -> FSTree fs -> Maybe rep -> ValueDelta fs (Maybe rep)
	-> (rep -> Manifest fs -> MManifestForestO fs) -- inner store function
	-> (rep -> ValueDelta fs rep -> Manifest fs -> MManifestForestO fs) -- inner incremental store function
	-> (FSTree fs -> rep -> ForestO fs (ValueDelta fs rep))
	-> Manifest fs -> MManifestForestO fs
doZDeltaManifestMaybeInner path path' tree df (tree' :: FSTree fs) mb_rep dv manifest manifestD diffValue man = do
	isRepairMd <- Reader.ask
	let fs = Proxy :: Proxy fs
	exists <- lift $ forestM $ doesExistInTree path tree
	exists' <- if isEmptyTopFSTreeD fs df then return exists else lift (forestM $ doesExistInTree path' tree')
	
	case (exists,mb_rep,exists') of
		(False,Nothing,False) -> do
			let testm = liftM (boolStatus $ ExistingPath path) $ latestTree >>= liftM not . doesExistInTree path
			return $ addTestToManifest testm man
		(True,Just irep,True) -> do
			let testm = liftM (boolStatus $ NonExistingPath path) $ latestTree >>= doesExistInTree path
			idv <- lift $ diffValueBelow dv diffValue tree irep
			manifestD irep idv $ addTestToManifest testm man
		otherwise -> doZManifestMaybeInner path' tree' mb_rep manifest man			

doZDeltaManifestFocus :: (Matching fs a,ICRep fs) => 
	a -> FilePath -> FilePath -> FSTree fs -> FSTreeD fs -> FSTree fs
	-> (FilePath -> FilePath -> FSTreeD fs -> Manifest fs -> MManifestForestO fs)
	-> Manifest fs -> MManifestForestO fs
doZDeltaManifestFocus matching path path' tree df (tree' :: FSTree fs) manifestD man = do
	let fs = Proxy :: Proxy fs
	files <- lift $ forestM $ getMatchingFilesInTree path matching tree
	let name = pickFile files
	child_path <- lift $ forestM $ stepPathInTree tree path name
	
	files' <- lift $ forestM $ getMatchingFilesInTree path' matching tree'
	let name' = pickFile files'
	let testm = testFocus path' name' (\file tree -> return True) [name']
	child_path' <- lift $ forestM $ stepPathInTree tree' path' name'
	
	let newdf = focusFSTreeD fs df path' name' child_path'
	
	manifestD child_path child_path' newdf $ addTestToManifest testm man

doZDeltaManifestSimple :: (ICRep fs,Matching fs a) => 
	Lens dir_rep rep
	-> FilePath -> FilePath -> ForestI fs a -> FSTree fs -> FSTreeD fs -> FSTree fs
	-> dir_rep -> ValueDelta fs dir_rep
	-> (rep -> ValueDelta fs rep -> FilePath -> FilePath -> FSTreeD fs -> Manifest fs -> MManifestForestO fs)
	-> (FSTree fs -> rep -> ForestO fs (ValueDelta fs rep))
	-> Manifest fs -> MManifestForestO fs
doZDeltaManifestSimple lens path path' matchingM tree df tree' dir_rep dir_dv manifestD diffValue man = do
	matching <- lift $ inside matchingM
	let rep = BX.get lens dir_rep
	dv <- lift $ diffValueBelow dir_dv diffValue tree rep
	doZDeltaManifestFocus matching path path' tree df tree' (manifestD rep dv) man

doZDeltaManifestSimpleWithConstraint :: (ForestContent fs rep content,ForestMD fs rep,ICRep fs,Matching fs a,err_rep ~ (ForestFSThunkI fs Forest_err, rep)) => 
	Lens dir_rep err_rep -> Bool -> (content -> ForestI fs Bool)
	-> FilePath -> FilePath -> ForestI fs a -> FSTree fs -> FSTreeD fs -> FSTree fs
	-> dir_rep -> ValueDelta fs dir_rep
	-> (rep -> ValueDelta fs rep -> FilePath -> FilePath -> FSTreeD fs -> Manifest fs -> MManifestForestO fs)
	-> (FSTree fs -> rep -> ForestO fs (ValueDelta fs rep))
	-> Manifest fs -> MManifestForestO fs
doZDeltaManifestSimpleWithConstraint lens emptyDArgs pred path path' matchingM tree df tree' dir_rep dir_dv manifestD diffValue man = do
	matching <- lift $ inside matchingM
	let rep = BX.get lens dir_rep
	dv <- lift $ diffValueBelow dir_dv diffValue tree (snd rep)
	doZDeltaManifestConstraintInner emptyDArgs pred tree rep (mapValueDelta Proxy dv) (\rep dv -> doZDeltaManifestFocus matching path path' tree df tree' $ manifestD rep dv) diffValue man

doZDeltaManifestCompound :: (Pads1 key_arg key key_md,IncK (IncForest fs) FileInfo,ForestMD fs rep',Matching fs a,list_rep' ~ [(key,rep')]) =>
	Lens dir_rep container_rep' -> Iso container_rep' list_rep' -> ForestI fs key_arg
	-> FilePath -> FilePath -> ForestI fs a -> FSTree fs -> FSTreeD fs -> FSTree fs
	-> dir_rep -> ValueDelta fs dir_rep
	-> (key -> key -> ForestFSThunkI fs FileInfo -> SValueDelta (ForestICThunkI fs FileInfo) -> rep' -> ValueDelta fs rep' -> FilePath -> FilePath -> FSTreeD fs -> Manifest fs -> MManifestForestO fs)
	-> (FSTree fs -> rep' -> ForestO fs (ValueDelta fs rep'))
	-> Manifest fs -> MManifestForestO fs
doZDeltaManifestCompound lens isoRep mkeyarg path path' matchingM tree df tree' dir_rep dir_dv manifestD diffValue man = do
	key_arg <- lift $ inside mkeyarg
	matching <- lift $ inside $ matchingM
	
	current_files <- lift $ forestM $ getMatchingFilesInTree path' matching tree'
	
	let crep = BX.get lens dir_rep
	let newreplist = to isoRep crep
	let (new_keys,newreps) = unzip newreplist
	let new_files = map (\key -> Pads.printS1 key_arg (key,Pads.defaultMd1 key_arg key)) new_keys
	let new_fileskeys = zip new_files new_keys
	repinfos <- lift $ inside $ mapM (\rep -> mod (get_info rep) >>= \fileInfo_t -> return (rep,fileInfo_t)) newreps

	let rem_files = current_files \\ new_files -- files to be removed
	man1 <- lift $ forestM $ foldr (\rem_path man0M -> man0M >>= removePathFromManifestInTree rem_path tree') (return man) $ map (path' </>) rem_files -- remove deprecated files

	let manifestEach ((n,key),(rep,fileInfo_t)) man0M = do
		idv <- lift $ diffValueBelow dir_dv diffValue tree rep
		man0M >>= doZDeltaManifestFocus n path path' tree df tree' (manifestD key key fileInfo_t Delta rep idv)
	let testm = testFocus path' matching (\file tree -> return True) new_files
	liftM (addTestToManifest testm) $ foldr manifestEach (return man1) (zip new_fileskeys repinfos)

doZDeltaManifestCompoundWithConstraint :: (Pads1 key_arg key key_md,IncK (IncForest fs) FileInfo,ForestMD fs rep',Matching fs a,list_rep' ~ [(key,rep')]) =>
	Lens dir_rep container_rep' -> Iso container_rep' list_rep' -> ForestI fs key_arg
	-> FilePath -> FilePath -> ForestI fs a -> FSTree fs -> FSTreeD fs -> FSTree fs
	-> dir_rep -> ValueDelta fs dir_rep
	-> (key -> ForestFSThunkI fs FileInfo -> ForestI fs Bool)
	-> (key -> key -> ForestFSThunkI fs FileInfo -> SValueDelta (ForestICThunkI fs FileInfo) -> rep' -> ValueDelta fs rep' -> FilePath -> FilePath -> FSTreeD fs -> Manifest fs -> MManifestForestO fs)
	-> (FSTree fs -> rep' -> ForestO fs (ValueDelta fs rep'))
	-> Manifest fs -> MManifestForestO fs
doZDeltaManifestCompoundWithConstraint lens isoRep mkeyarg path path' matchingM (tree :: FSTree fs) df tree' dir_rep dir_dv pred manifestD diffValue man = do
	
	key_arg <- lift $ inside mkeyarg
	let fs = Proxy :: Proxy fs
	matching <- lift $ inside $ matchingM
	
	let crep = BX.get lens dir_rep
	let newreplist = to isoRep crep
	let (new_keys,newreps) = unzip newreplist
	let new_files = map (\key -> Pads.printS1 key_arg (key,Pads.defaultMd1 key_arg key)) new_keys
	let new_fileskeys = zip new_files new_keys
	repinfos <- lift $ inside $ mapM (\rep -> mod (get_info rep) >>= \fileInfo_t -> return (rep,fileInfo_t)) newreps

	current_files <- lift $ forestM $ getMatchingFilesInTree path' matching tree'
	let current_files' = current_files \\ new_files -- old files that are not in the view
	let current_fileskeys' = map (\file -> (file,fst $ Pads.parseString1 key_arg file)) current_files'
	current_metadatas' <- lift $ mapM (getRelForestMDInTree path' tree) current_files'
	-- we need to check which old files satisfy the predicate
	current_values' <- lift $ inside $ filterM (\((n,key),fmd) -> pred key (fileInfo fmd)) $ zip current_fileskeys' current_metadatas'
	let rem_fileskeys = map fst current_values' -- files to be removed

	man1 <- lift $ forestM $ foldr (\rem_path man0M -> man0M >>= removePathFromManifestInTree rem_path tree') (return man) $ map ((path' </>) . fst) rem_fileskeys -- remove deprecated files

	let manifestEach ((n,key),(rep,fileInfo_t)) man0M = do
		idv <- lift $ diffValueBelow dir_dv diffValue tree rep
		man0M >>= doZDeltaManifestFocus n path path' tree df tree' (manifestD key key fileInfo_t Delta rep idv)
	let testm = testFocus path' matching (\file tree -> return True) new_files
	liftM (addTestToManifest testm) $ foldr manifestEach (return man1) (zip new_fileskeys repinfos)

zskipManifestIf :: (Typeable rep,Typeable irep,IncK (IncForest fs) irep,ForestMD fs rep,ICRep fs,ForestRep rep (ForestFSThunkI fs irep),StableMD fs rep,DeltaClass d) =>
	Bool -> FilePath -> FilePath -> FSTreeD fs -> FSTree fs -> rep -> ValueDelta fs rep
	-> (FSTree fs -> ForestI fs rep)
	-> (FSTreeD fs -> FSTree fs -> ValueDelta fs rep -> (rep,GetForestMD fs) -> ForestO fs (d rep)) -- delta loading function
	-> (rep -> ValueDelta fs rep -> Manifest fs -> MManifestForestO fs) -- delta storing function
	-> Manifest fs -> MManifestForestO fs
zskipManifestIf isEmptyEnv path path' df (tree' :: FSTree fs) rep dv load loadD manifestD man = do
	let fs = Proxy :: Proxy fs
	if (isEmptyEnv && isIdValueDelta dv && path == path' && isEmptyFSTreeD fs df)
		then debug ("skipped storeDelta "++show path') $ do
			-- since we don't check data dependencies here (what would involve traversing the whole value...), we allow side-effects stemming from other FS modifications
			-- such side-effects can only be computed after all the data has been stored.
			Writer.tell $ \latest_tree -> do
				mb_latest_df <- forestM $ diffFS tree' latest_tree path'
				case mb_latest_df of
					Just latest_df -> do
						latest_dv <- diffValueThunk tree' rep
						loadD latest_df latest_tree latest_dv (rep,getForestMDInTree)
						return ()
					Nothing -> overwrite (to iso_rep_thunk rep) $ Inc.get =<< liftM (to iso_rep_thunk) (load latest_tree)
			return man
		else manifestD rep dv man


