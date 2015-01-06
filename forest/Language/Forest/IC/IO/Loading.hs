{-# LANGUAGE OverlappingInstances, TupleSections, FlexibleContexts, ScopedTypeVariables, GADTs, FlexibleInstances,MultiParamTypeClasses,UndecidableInstances, ViewPatterns #-}



module Language.Forest.IC.IO.Loading where

import Language.Forest.IC.PadsInstances
import Prelude hiding (const,read,mod)
import qualified Prelude
import Language.Forest.IO.Utils
import Language.Forest.IO.Shell
import Language.Forest.Syntax
import Language.Forest.IC.FS.Diff
import Language.Forest.IC.ValueDelta
import Language.Forest.Pure.MetaData (FileInfo(..),FileType(..))
import qualified Language.Forest.Pure.MetaData as Pure
import Language.Pads.Padsc
import Language.Forest.IC.MetaData
import Language.Forest.IC.Generic
import Language.Forest.Errors
import Language.Forest.IC.FS.FSDelta
import Control.Monad.Incremental hiding (memo)
--import Language.Forest.ListDiff
import Data.IORef

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
import Data.List
import Language.Forest.FS.FSRep
import Language.Forest.IC.ICRep
--import Control.Monad.IO.Class
import Data.WithClass.MData

import Language.Forest.IC.IO.Memo

import qualified Control.Exception as CE

import Data.Data
import Data.Maybe
import System.Random
import Data.Proxy

doLoadArgs :: (ForestArgs fs args,Eq rep,Eq md,ICRep fs,imd ~ MDArgs mode md (ForestICThunksI fs args)) => 
	LiftedICMode mode -> Proxy args -> ForestICThunksI fs args -> ForestI fs (rep,md) -> ForestI fs (rep,imd)
doLoadArgs mode proxy args load = do
	(rep,md) <- load
	return (rep,mkMDArgs mode md args)

-- | lazy file loading
-- XXX: Pads errors do not contribute to the Forest error count
doLoadFile :: (ForestInput fs FSThunk Inside,Eq md,Eq pads,MData NoCtx (ForestI fs) pads,MData NoCtx (ForestI fs) md,ICRep fs,Pads pads md) => Proxy pads -> FilePath -> FSTree fs -> FSTreeDeltaNodeMay -> FSTree fs -> GetForestMD fs -> ForestI fs (ForestFSThunkI fs pads,ForestFSThunkI fs (Forest_md fs,ForestFSThunkI fs md))
doLoadFile repProxy path (oldtree::FSTree fs) df tree getMD = debug ("doLoadFile " ++ show (path,df)) $ do
	let fs = Proxy::Proxy fs
	-- default static loading
	let load_file = do
		parseThunk <- newHSThunk $ debug ("reading file "++show path) $ forestM $ pathInTree path tree >>= forestIO . parseFile
		rep_thunk <- checkPathData path tree (getRep $ read parseThunk)
		md_thunk <- checkPathMeta path tree $ do
			fmd <- getMD path tree
			md <- mod $ getMd $ read parseThunk -- to avoid reading the file unless strictly necessary
			return (fmd,md)
		memo path (rep_thunk,md_thunk,()) tree
		return (rep_thunk,md_thunk)
	-- memoized reuse
	let reuse_same_file = do
		mb <- lookupmemo path repProxy
		case mb of
			Just ((old_rep_thunk,old_md_thunk,()),(==oldtree) -> True) -> debug ("memo hit " ++ show path) $ do
				rep_thunk <- copyFSThunks fs proxyInside id old_rep_thunk
				md_thunk <- copyFSThunks fs proxyInside id old_md_thunk
				memo path (rep_thunk,md_thunk,()) tree -- overrides the old entry
				return (rep_thunk,md_thunk)
			Nothing -> load_file
	-- memoized reuse for moves
	let reuse_other_file from = do
		mb <- lookupmemo from repProxy
		case mb of
			Just ((old_rep_thunk,old_md_thunk,()),(==oldtree) -> True) -> debug ("memo hit " ++ show from) $ do
				rep_thunk <- copyFSThunks fs proxyInside id old_rep_thunk
				fmd' <- getMD path tree
				md_thunk <- get old_md_thunk >>= \(fmd::Forest_md fs,md) -> ref (fmd',md) -- since the old file may come from another location and/or its attributes may have changed
				unmemo fs from repProxy
				memo path (rep_thunk,md_thunk,()) tree
				return (rep_thunk,md_thunk)
			Nothing -> load_file
	case df of
		(isEmptyFSTreeDeltaNodeMay -> True) -> reuse_same_file
		Just (FSTreeChg _ _) -> reuse_other_file path
		Just (FSTreeNew _ (Just from) _) -> reuse_other_file from
		otherwise -> load_file

-- | lazy file loading
-- XXX: Pads specs currently accept a single optional argument and have no incremental loading, so a change in the argument's value requires recomputation
-- XXX: Pads errors do not contribute to the Forest error count
doLoadFile1 :: (ForestMD fs md,Typeable arg,Eq arg,Eq pads,Eq md,MData NoCtx (ForestI fs) pads,MData NoCtx (ForestI fs) md,FSRep fs,Pads1 arg pads md) => Proxy pads -> arg -> FilePath -> FSTree fs -> FSTreeDeltaNodeMay -> FSTree fs -> GetForestMD fs -> ForestI fs (ForestFSThunkI fs pads,ForestFSThunkI fs (Forest_md fs,ForestFSThunkI fs md))
doLoadFile1 repProxy arg path (oldtree::FSTree fs) df tree getMD = debug ("doLoadFile1 " ++ show (path,df)) $ do
	let fs = (Proxy::Proxy fs)
	-- default static loading
	let load_file = do
		parseThunk <- newHSThunk $ debug ("reading file "++show path) $ forestM $ pathInTree path tree >>= forestIO . parseFile1 arg
		rep_thunk <- checkPathData path tree (getRep $ read parseThunk)
		md_thunk <- checkPathMeta path tree $ do
			fmd <- getMD path tree
			md <- mod $ getMd $ read parseThunk -- to avoid reading the file unless strictly necessary
			return (fmd,md)
		memo path (rep_thunk,md_thunk,arg) tree
		return (rep_thunk,md_thunk)
	-- memoized reuse
	let reuse_same_file = do
		mb <- lookupmemo path repProxy
		case mb of
			Just ((old_rep_thunk,old_md_thunk,(== arg) -> True),(==oldtree) -> True) -> debug ("memo hit " ++ show path) $ do
				rep_thunk <- get old_rep_thunk >>= ref
				md_thunk <- get old_md_thunk >>= ref
				memo path (rep_thunk,md_thunk,()) tree -- overrides the old entry
				return (rep_thunk,md_thunk)
			Nothing -> load_file
	-- memoized reuse for moves
	let reuse_other_file from = do
		mb <- lookupmemo from repProxy
		case mb of
			Just ((old_rep_thunk,old_md_thunk,(== arg) -> True),(==oldtree) -> True) -> debug ("memo hit " ++ show from) $ do --XXX: revise this for thunk arguments!!!
				rep_thunk <- copyFSThunks fs proxyInside id old_rep_thunk
				fmd' <- getMD path tree
				md_thunk <- get old_md_thunk >>= \(fmd::Forest_md fs,md) -> fsRef (fmd',md) -- since the old file may come from another location and/or its attributes may have changed
				unmemo fs from repProxy
				memo path (rep_thunk,md_thunk,arg) tree
				return (rep_thunk,md_thunk)
			Nothing -> load_file
	case df of
		(isEmptyFSTreeDeltaNodeMay -> True) -> reuse_same_file
		Just (FSTreeChg _ _) -> reuse_other_file path
		Just (FSTreeNew _ (Just from) _) -> reuse_other_file from
		otherwise -> load_file

-- | compressed archive (tar,gz,zip)
-- incremental loading is only supported if the specification for the archive's contents is:
-- 1) closed = does not depend on free variables -- this ensures that specs can be reused locally
-- 2) static = its type contains no @ICThunk@s inside (or more specifically, only constant @ICThunk@s) -- this is due to a limitation that we cannot consistently copy an @ICThunk@ and its dependencies.
-- The copy operation needs to make a deep strict copy of the argument value, to ensure that we are copying the correct state of a @FSThunk@ and its recursively contained @FSThunk@s
doLoadArchive :: (
		 MData (CopyFSThunksDict fs Inside) (ForestI fs) rep,MData (CopyFSThunksDict fs Inside) (ForestI fs) md
		,ForestMD fs md,Eq rep,Eq md,MData NoCtx (ForestI fs) rep,FSRep fs,MData NoCtx (ForestI fs) md) =>
	Bool -> Proxy rep
	-> [ArchiveType] -> FilePath -> FSTree fs -> FSTreeDeltaNodeMay -> FSTree fs -> GetForestMD fs
	-> (FilePath -> GetForestMD fs -> FSTree fs -> FSTreeDeltaNodeMay -> FSTree fs -> ForestI fs (rep,md))
	-> (ForestI fs FilePath -> FilePath -> OldData fs rep md -> FSTree fs -> FSTreeDeltaNodeMay -> FSTree fs -> ForestO fs (SValueDelta rep,SValueDelta md))
	-> ForestI fs (ForestFSThunkI fs rep,ForestFSThunkI fs (Forest_md fs,md))
doLoadArchive isClosedAndStatic repProxy exts path oldtree df (tree :: FSTree fs) getMD load loadD = do
	-- static loading
	let load_folder = mkThunks tree $ doLoadArchive' exts path oldtree df tree getMD load
	-- memoized reuse
	let reuse_same_file = do
		mb <- lookupmemo path repProxy
		case mb of
			Just ((old_rep_thunk,old_md_thunk,()),(==oldtree) -> True) -> debug ("memo hit " ++ show path) $ do
				memo path (old_rep_thunk,old_md_thunk,()) tree
				return (old_rep_thunk,old_md_thunk)
			Nothing -> load_folder
	-- memoized reuse for moves
	let reuse_other_file from = do
		mb <- lookupmemo from repProxy
		case mb of
			Just ((old_rep_thunk,old_md_thunk,()),(==oldtree) -> True) -> debug ("memo hit " ++ show from) $ do
				-- since we are working at the inner layer, we need to copy the old data into new @FSThunk@s
				-- note that @copyInc@ is strict for lazy @FSThunk@s
				let updateRelative p = path </> (makeRelative from p)
				(rep_thunk,md_thunk) <- copyFSThunks (Proxy::Proxy fs) proxyInside updateRelative (old_rep_thunk,old_md_thunk)
				rep <- get rep_thunk
				md@(fmd,imd) <- get md_thunk
				
				-- compute the difference for the archive's content
				avfsTree <- forestM $ virtualTree tree
				avfsOldTree <- forestM $ virtualTree oldtree
				let fromC = cardinalPath from
				let pathC = cardinalPath path
				newdf <- forestM $ focusDiffFSTree oldtree fromC tree pathC
				
				-- load incrementally; this is safe because we are modifying fresh modifiables (the copies)
				unsafeWorld $ do
					loadD (return fromC) pathC ((rep,imd),getMD) avfsOldTree newdf avfsTree
					fmd' <- inside $ getMD path tree
					updateForestMDErrorsWith fmd' $ liftM (:[]) $ get_errors imd -- like a directory
					set md_thunk (fmd',imd)
				memo path (rep_thunk,md_thunk,()) tree
				return (rep_thunk,md_thunk)
			Nothing -> load_folder
	case df of
		(isEmptyFSTreeDeltaNodeMay -> True) -> reuse_same_file
		Just (FSTreeChg _ _) -> if isClosedAndStatic then reuse_other_file path else load_folder
		Just (FSTreeNew _ (Just from) _) -> if isClosedAndStatic then reuse_other_file from else load_folder
		otherwise -> load_folder

doLoadArchive' :: (ForestMD fs md,MData NoCtx (ForestI fs) rep,ICRep fs,MData NoCtx (ForestI fs) md) =>
	[ArchiveType] -> FilePath -> FSTree fs -> FSTreeDeltaNodeMay -> FSTree fs -> GetForestMD fs
	-> (FilePath -> GetForestMD fs -> FSTree fs -> FSTreeDeltaNodeMay -> FSTree fs -> ForestI fs (rep,md))
	-> ForestI fs (rep,(Forest_md fs,md))
doLoadArchive' exts path oldtree df tree getMD load = checkPath' (Just False) path tree $ checkFileExtension (archiveExtension exts) path $ do
	fmd <- getMD path tree
	avfsTree <- forestM $ virtualTree tree
	(rep,md_arch) <- load (cardinalPath path) getForestMDInTree avfsTree Nothing avfsTree -- since we use the same tree, there is no problem here
	fmd' <- updateForestMDErrorsInsideWith fmd $ liftM (:[]) $ get_errors md_arch -- like a directory
	return (rep,(fmd',md_arch))
		
doLoadSymLink :: (ForestInput fs FSThunk Inside,ICRep fs) => FilePath -> FSTreeDeltaNodeMay -> FSTree fs -> GetForestMD fs -> ForestI fs (ForestFSThunkI fs FilePath,ForestFSThunkI fs (Forest_md fs, Base_md))
doLoadSymLink path df tree getMD = mkThunks tree $ doLoadSymLink' path df tree getMD

doLoadSymLink' :: (ForestInput fs FSThunk Inside,ICRep fs) => FilePath -> FSTreeDeltaNodeMay -> FSTree fs -> GetForestMD fs -> ForestI fs (FilePath,(Forest_md fs, Base_md))
doLoadSymLink' path df tree getMD = checkPath' Nothing path tree $ do
	md <- getMD path tree
	case symLink (fileInfo md) of
		Just sym -> return (sym,(md,cleanBasePD))
		Nothing -> do
			md' <- updateForestMDErrorsInsideWith md $ return [Pure.ioExceptionForestErr]
			return ("", (md',cleanBasePD))

doLoadConstraint :: (Typeable imd,ForestOutput fs ICThunk Inside,Eq imd,ForestMD fs imd,MData NoCtx (ForestI fs) rep,md ~ ForestFSThunkI fs imd) =>
	LiftedICMode mode -> FSTree fs -> ((rep,md) -> ForestI fs Bool) -> ForestI fs (rep,md) -> ForestI fs (rep,MDArgs mode md (ForestICThunkI fs Bool))
doLoadConstraint mode tree pred load = do -- note that constraints do not consider the current path
	result@(rep,md) <- load
	cond_thunk <- inside $ icThunk $ pred result
	md' <- replace_errors md $ \err -> do
		cond <- force cond_thunk
		if cond
			then return err
			else return $ Pure.updateForestErr err [Pure.constraintViolationForestErr]
	return (rep,mkMDArgs mode md' cond_thunk)

-- changes the current path
doLoadFocus :: (Matching a,ForestMD fs md) => FilePath -> a -> FSTree fs -> FSTreeDeltaNodeMay -> FSTree fs -> GetForestMD fs -> (FilePath -> FSTreeDeltaNodeMay -> GetForestMD fs -> ForestI fs (rep,md)) -> ForestI fs (rep,md)
doLoadFocus path matching oldtree df tree getMD load = do
	files <- forestM $ Pure.getMatchingFilesInTree path matching tree
	case files of
		[file] -> doLoadNewPath path file oldtree df tree getMD load
		files -> doLoadNewPath path (pickFile files) oldtree df tree getMD $ \newpath newdf newgetMD -> do
			(rep,md) <- load newpath newdf newgetMD
			md' <- if length files == 0
				then return md -- if there is no match then an error will pop from the recursive load
				else addMultipleMatchesErrorMDInside newpath files md
			return (rep,md')

doLoadNewPath :: (ICRep fs) => FilePath -> FilePath -> FSTree fs -> FSTreeDeltaNodeMay -> FSTree fs -> GetForestMD fs -> (FilePath -> FSTreeDeltaNodeMay -> GetForestMD fs -> ForestI fs x) -> ForestI fs x
doLoadNewPath oldpath file oldtree df tree getMD load = debug ("doLoadNewPath " ++ show (oldpath </> file)) $ do
	newpath <- forestM $ stepPathInTree tree oldpath file -- changes the old path by a relative path, check the path traversal restrictions specific to each FS instantiation
	let newdf = focusFSTreeDeltaNodeMayByRelativePath df file -- focusing the tree deltas is important for the skipping conditions to fire for unchanged branches of the FS
	load newpath newdf getMD

doLoadDirectory :: (ForestInput fs FSThunk Inside,Eq rep,Eq md,MData NoCtx (ForestI fs) rep,ICRep fs,MData NoCtx (ForestI fs) md)
	=> FilePath -> FSTree fs -> (md -> ForestI fs Forest_err) -> GetForestMD fs -> ForestI fs (rep,md) -> ForestI fs (ForestFSThunkI fs rep,ForestFSThunkI fs (Forest_md fs,md))
doLoadDirectory path tree collectMDErrors getMD load = mkThunksM tree $ doLoadDirectory' path tree collectMDErrors getMD load

-- the error count of the directory is computed lazily, so that if we only want, e.g., the fileinfo of the directory we don't need to check its contents
doLoadDirectory' :: (ICRep fs,ForestInput fs FSThunk Inside,Eq rep,Eq md,MData NoCtx (ForestI fs) rep,MData NoCtx (ForestI fs) md)
	=> FilePath -> FSTree fs -> (md -> ForestI fs Forest_err) -> GetForestMD fs -> ForestI fs (rep,md) -> ForestI fs (ForestI fs rep,ForestI fs (Forest_md fs,md))
doLoadDirectory' path tree collectMDErrors getMD ifGood = debug ("doLoadDirectory: "++show path) $ do
	ifGoodThunk <- newHSThunk ifGood
	let loadData = checkPathData' True path tree $ getRep $ read ifGoodThunk
	let loadMeta = checkPathMeta' True path tree $ do
		fmd <- getMD path tree
		mds <- getMd $ read ifGoodThunk
		fmd' <- updateForestMDErrorsInsideWith fmd $ liftM (:[]) $ collectMDErrors mds
		return (fmd',mds)
	return (loadData,loadMeta)

doLoadMaybe :: (Typeable rep,Typeable md,Eq rep,Eq md,ForestMD fs md) => FilePath -> FSTreeDeltaNodeMay -> FSTree fs -> ForestI fs (rep,md) -> ForestI fs (ForestFSThunkI fs (Maybe rep),ForestFSThunkI fs (Forest_md fs,Maybe md))
doLoadMaybe path df tree ifExists = mkThunksM tree $ doLoadMaybe' path df tree ifExists

doLoadMaybe' :: (Typeable rep,Typeable md,Eq rep,Eq md,ForestMD fs md) => FilePath -> FSTreeDeltaNodeMay -> FSTree fs -> ForestI fs (rep,md) -> ForestI fs (ForestI fs (Maybe rep),ForestI fs (Forest_md fs,Maybe md))
doLoadMaybe' path df tree ifExists = do
	ifExistsThunk <- newHSThunk ifExists
	let loadData = do
		exists <- forestM $ doesExistInTree path tree
		if exists
			then liftM Just $ getRep $ read ifExistsThunk
			else return Nothing
	let loadMeta = do
		exists <- forestM $ doesExistInTree path tree
		debug ("doLoadMaybe: "++show (path,exists)) $ if exists
			then do
				md <- getMd $ read ifExistsThunk
				fmd <- get_fmd_header md
				return (fmd,Just md) -- use the same @Forest_md@
			else do
				fmd <- cleanForestMDwithFile path
				return (fmd,Nothing)
	return (loadData,loadMeta)

-- since the focus changes we need to compute the (eventually) previously loaded metadata of the parent node
doLoadSimple :: (Eq imd',ForestMD fs imd',Matching a,MData NoCtx (ForestI fs) rep',ForestMD fs md', md' ~ ForestFSThunkI fs imd') =>
	FilePath -> ForestI fs a -> FSTree fs -> FSTreeDeltaNodeMay -> FSTree fs
	-> (FilePath -> FSTreeDeltaNodeMay -> GetForestMD fs -> ForestI fs (rep',md'))
	-> ForestI fs (rep',md')
doLoadSimple path matching oldtree df tree load = matching >>= \m -> doLoadFocus path m oldtree df tree getForestMDInTree load

-- since the focus changes we need to compute the (eventually) previously loaded metadata of the parent node
doLoadSimpleWithConstraint :: (Typeable imd',ForestOutput fs ICThunk Inside,Eq imd',ForestMD fs imd',Matching a,MData NoCtx (ForestI fs) rep',ForestMD fs md', md' ~ ForestFSThunkI fs imd') =>
	LiftedICMode mode -> FilePath -> ForestI fs a -> FSTree fs -> FSTreeDeltaNodeMay -> FSTree fs -> ((rep',md') -> ForestI fs Bool)
	-> (FilePath -> FSTreeDeltaNodeMay -> GetForestMD fs -> ForestI fs (rep',md'))
	-> ForestI fs (rep',MDArgs mode md' (ForestICThunkI fs Bool))
doLoadSimpleWithConstraint mode path matching oldtree df tree pred load = doLoadConstraint mode tree pred $ matching >>= \m -> doLoadFocus path m oldtree df tree getForestMDInTree load

doLoadCompound :: (Typeable container_rep,Typeable container_md,Eq container_md,Eq container_rep,ForestMD fs (md',FSThunk fs Inside (IncForest fs) IORef IO FileInfo),Matching a,MData NoCtx (ForestI fs) rep',ForestMD fs imd, imd ~ MDArgs mode md' (ForestFSThunkI fs FileInfo)) =>
	LiftedICMode mode -> FilePath -> ForestI fs a -> FSTree fs -> FSTreeDeltaNodeMay -> FSTree fs
	-> ([(FilePath,rep')] -> container_rep) -> ([(FilePath,imd)] -> container_md)
	-> (FileName -> ForestFSThunkI fs FileInfo -> FilePath -> FSTreeDeltaNodeMay -> GetForestMD fs -> ForestI fs (rep',md'))
	-> ForestI fs (ForestFSThunkI fs container_rep,ForestFSThunkI fs container_md)
doLoadCompound mode path matchingM oldtree df tree buildContainerRep buildContainerMd load = mkThunks tree $ debug ("doLoadCompound: "++show path) $ do
	matching <- matchingM
	files <- forestM $ Pure.getMatchingFilesInTree path matching tree
	metadatas <- mapM (getRelForestMDInTree path tree) files
	let filesmetas = zip files metadatas
	let loadEach (n,n_md) = liftM (n,) $ doLoadFocus path n oldtree df tree (const2 $ return n_md) $ \newpath newdf newGetMD -> do
		fileInfo_thunk <- ref $ fileInfo n_md
		(rep',md') <- load n fileInfo_thunk newpath newdf newGetMD
		return (rep',mkMDArgs mode md' $ fileInfo_thunk)
	loadlist <- mapM loadEach filesmetas
	let replist = map (id >< fst) loadlist
	let mdlist = map (id >< snd) loadlist
	return (buildContainerRep replist,buildContainerMd mdlist)

doLoadCompoundWithConstraint :: (Typeable container_rep,Typeable container_md,Eq container_md,Eq container_rep,ForestOutput fs ICThunk Inside,Matching a,MData NoCtx (ForestI fs) rep',ForestMD fs md',imd ~ MDArgs mode md' (ForestFSThunkI fs FileInfo,ForestICThunkI fs Bool) ) =>
	LiftedICMode mode -> FilePath -> ForestI fs a -> FSTree fs -> FSTreeDeltaNodeMay -> FSTree fs
	-> (FilePath -> ForestFSThunkI fs FileInfo -> ForestI fs Bool)
	-> ([(FilePath,rep')] -> container_rep) -> ([(FilePath,imd)] -> container_md)
	-> (FileName -> ForestFSThunkI fs FileInfo -> FilePath -> FSTreeDeltaNodeMay -> GetForestMD fs -> ForestI fs (rep',md'))
	-> ForestI fs (ForestFSThunkI fs container_rep,ForestFSThunkI fs container_md)
doLoadCompoundWithConstraint mode path matchingM oldtree df tree pred buildContainerRep buildContainerMd load = mkThunks tree $ debug ("doLoadCompound: "++show path) $ do
	matching <- matchingM -- matching expressions are not saved for incremental reuse
	files <- forestM $ Pure.getMatchingFilesInTree path matching tree
	metadatas <- mapM (getRelForestMDInTree path tree) files
	let filesmetas = zip files metadatas
	let makeInfo (n,fmd) = do
		t <- ref $ fileInfo fmd -- we store the @FileInfo@ in a @FSThunk@ to allow incremental evaluation of the constraint expression
		u <- icThunk $ pred n t --the filename is a constant. during delta loading, whenever it changes we will load from scratch
		return (n,(fmd,(t,u)))
	filesmetasInfo <- mapM makeInfo filesmetas
	filesmetasInfo' <- filterM (force . snd . snd . snd) filesmetasInfo
	let loadEach (n,(n_md,(t,u))) = do
		(rep,md) <- doLoadFocus path n oldtree df tree (const2 $ return n_md) $ load n t
		return (n,(rep,mkMDArgs mode md (t,u)))
	loadlist <- mapM loadEach filesmetasInfo'
	let replist = map (id >< fst) loadlist
	let mdlist = map (id >< snd) loadlist
	return (buildContainerRep replist,buildContainerMd mdlist)

-- ** auxiliary functions

-- tries to pick a file that has been moved
pickFileNoDelta :: ICRep fs => FilePath -> [FileName] -> FSTreeDeltaNodeMay -> FSTree fs -> ForestI fs FileName
pickFileNoDelta path' files' df tree' = do
	let reorderFile xs file' = case focusFSTreeDeltaNodeMayByRelativePath df file' of
		Just (FSTreeNew _ (Just from) _) -> file' : xs
		otherwise -> xs ++ [file']
	let files'' = foldl' reorderFile [] files'
	return $ pickFile files''

checkPathData :: (ICRep fs,ForestInput fs FSThunk Inside,Eq rep,MData NoCtx (ForestI fs) rep) => FilePath -> FSTree fs -> ForestI fs rep -> ForestI fs (ForestFSThunkI fs rep)
checkPathData path tree ifExists = mod $ checkPathData' False path tree ifExists
checkPathMeta :: (MData NoCtx (ForestI fs) md,Eq md,ForestMD fs md) => FilePath -> FSTree fs -> ForestI fs md -> ForestI fs (ForestFSThunkI fs md)
checkPathMeta path tree ifExists = mod $ checkPathMeta' False path tree ifExists
checkPath :: (ICRep fs,MData NoCtx (ForestI fs) md,Eq rep,Eq md,MData NoCtx (ForestI fs) rep,ForestMD fs md) => FilePath -> FSTree fs -> ForestI fs (rep,md) -> ForestI fs (ForestFSThunkI fs rep,ForestFSThunkI fs md)
checkPath path tree ifExists = do
	ifExistsThunk <- newHSThunk ifExists
	dataThunk <- checkPathData path tree $ getRep $ read ifExistsThunk
	metaThunk <- checkPathMeta path tree $ getMd $ read ifExistsThunk
	return (dataThunk,metaThunk)
	
checkPathData' :: (ICRep fs,MData NoCtx (ForestI fs) rep,FSRep fs) => Bool -> FilePath -> FSTree fs -> ForestI fs rep -> ForestI fs rep
checkPathData' isDir path tree ifExists = do
	exists <- forestM $ if isDir then doesDirectoryExistInTree path tree else doesFileExistInTree path tree
	if exists then ifExists else forestdefault
checkPathMeta' :: (MData NoCtx (ForestI fs) md,ForestMD fs md) => Bool -> FilePath -> FSTree fs -> ForestI fs md -> ForestI fs md
checkPathMeta' isDir path tree ifExists = {-debug ("checkPathMeta' "++show path ++ showFSTree tree) $ -} do
	let (doesExist,missingErr) = if isDir then (doesDirectoryExistInTree,Pure.missingDirForestErr) else (doesFileExistInTree,Pure.missingPathForestErr)
	exists <- forestM $ doesExist path tree
	if exists
		then ifExists
		else do
			def_md <- forestdefault
			def_md' <- replace_errors def_md $ Prelude.const $ return $ missingErr path
			return def_md'
checkPath' :: (MData NoCtx (ForestI fs) md,MData NoCtx (ForestI fs) rep,ForestMD fs md) => Maybe Bool -> FilePath -> FSTree fs -> ForestI fs (rep,md) -> ForestI fs (rep,md)
checkPath' cond path tree ifExists = {-debug ("checkPath' "++show path ++ showFSTree tree) $ -} do
	exists <- case cond of
		Nothing -> forestM $ doesExistInTree path tree
		Just isDir -> forestM $ if isDir then doesDirectoryExistInTree path tree else doesFileExistInTree path tree
	if exists
		then ifExists
		else do
			def_rep <- forestdefault
			def_md <- forestdefault
			def_md' <- replace_errors def_md $ Prelude.const $ return $ Pure.missingPathForestErr path
			return (def_rep,def_md')
			
checkFileExtension :: (MData NoCtx (ForestI fs) md,MData NoCtx (ForestI fs) rep,ForestMD fs md) => String -> FilePath -> ForestI fs (rep,md) -> ForestI fs (rep,md)
checkFileExtension ext path ifExists = do
	if isSuffixOf ext path
		then ifExists
		else do
			def_rep <- forestdefault
			def_md <- forestdefault
			def_md' <- replace_errors def_md $ Prelude.const $ return $ Pure.wrongFileExtensionForestErr ext path
			return (def_rep,def_md')

mkThunks :: (Typeable rep,Typeable md,ForestInput fs FSThunk Inside,Eq rep,Eq md,ICRep fs) => FSTree fs -> ForestI fs (rep,md) -> ForestI fs (ForestFSThunkI fs rep,ForestFSThunkI fs md)
mkThunks tree load = do
	loadThunk <- newHSThunk load
	dataThunk <- mod $ getRep $ read loadThunk
	metaThunk <- mod $ getMd $ read loadThunk
	return (dataThunk,metaThunk)

mkThunksM :: (Typeable rep,Typeable md,ICRep fs,ForestInput fs FSThunk Inside,Eq rep,Eq md) => FSTree fs -> ForestI fs (ForestI fs rep,ForestI fs md) -> ForestI fs (ForestFSThunkI fs rep,ForestFSThunkI fs md)
mkThunksM tree load = do
	(loadData,loadMeta) <- load
	dataThunk <- mod loadData
	metaThunk <- mod loadMeta
	return (dataThunk,metaThunk)

