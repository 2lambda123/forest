{-# LANGUAGE ConstraintKinds, TupleSections, FlexibleContexts, ScopedTypeVariables, GADTs, FlexibleInstances,MultiParamTypeClasses,UndecidableInstances, ViewPatterns #-}

module Language.Forest.IC.IO.Storing where

import Language.Forest.Manifest
import Prelude hiding (const,read,mod)
import qualified Prelude
import Language.Forest.IO.Utils
import Language.Forest.Syntax
import Language.Forest.FS.Diff
import Language.Forest.IC.ValueDelta
import Language.Forest.IC.ICRep
import Language.Pads.Padsc
import Language.Forest.IC.MetaData
import Language.Forest.IC.Generic
import Language.Forest.Errors
import Language.Forest.FS.FSDelta
import Language.Forest.Pure.MetaData (FileInfo(..),FileType(..),(:*:)(..))
import qualified Language.Forest.Pure.MetaData as Pure
import Control.Monad.Incremental hiding (memo)
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

-- adds consistency checks for top-level specification arguments
doManifestArgs :: (ICRep fs,ForestArgs fs args) =>
	Proxy args -> ForestIs fs args
	-> (rep,(md,ForestICThunksI fs args))
	-> ((rep,md) -> Manifest fs -> ForestO fs (Manifest fs))
	-> Manifest fs -> ForestO fs (Manifest fs)
doManifestArgs proxy margs (rep,(md,targs)) manifestContent (man::Manifest fs) = do
	let man1 = addTestToManifest (forestO $ checkArgs (Proxy::Proxy fs) proxy margs targs) man
	manifestContent (rep,md) man1

doManifestFile :: (IncK (IncForest fs) FileInfo,IncK (IncForest fs) Forest_err,IncK (IncForest fs) pads,	IncK
	                        (IncForest fs) (Forest_md fs, ForestFSThunkI fs md),IncK (IncForest fs) md,ICRep fs,Pads pads md) => FSTree fs -> (ForestFSThunkI fs pads,ForestFSThunkI fs (Forest_md fs,ForestFSThunkI fs md)) -> Manifest fs -> ForestO fs (Manifest fs)
doManifestFile tree (rep_t,md_t) man = do
	rep <- inside $ get rep_t
	(fmd,md_t') <- inside $ get md_t
	md <- inside $ get md_t'
	path <- inside $ get_fullpath fmd
	canpath <- forestM $ canonalizePathInTree path tree
	dskpath <- forestM $ pathInTree canpath tree
	valid <- isValidMD fmd
	if valid
		then do -- for valid data we write it to disk
			forestM $ addFileToManifest (flip printFile (rep,md)) canpath path man
		else do
			isFile <- forestM $ doesFileExistInTree path tree 
			if isFile -- if the data is invalid and a file exists on disk, we remove it, otherwise we don't change anything
				then return $ removePathFromManifest canpath path man
				else return man

doManifestFile1 :: (IncK (IncForest fs) FileInfo,IncK (IncForest fs) Forest_err,IncK (IncForest fs) pads,				IncK
				                        (IncForest fs) (Forest_md fs, ForestFSThunkI fs md),IncK (IncForest fs) md,ICRep fs,Pads1 arg pads md) => arg -> FSTree fs -> (ForestFSThunkI fs pads,ForestFSThunkI fs (Forest_md fs,ForestFSThunkI fs md)) -> Manifest fs -> ForestO fs (Manifest fs)
doManifestFile1 arg tree (rep_t,md_t) man = do
	rep <- inside $ get rep_t
	(fmd,md_t') <- inside $ get md_t
	md <- inside $ get md_t'
	path <- inside $ get_fullpath fmd
	canpath <- forestM $ canonalizePathInTree path tree
	dskpath <- forestM $ pathInTree canpath tree
	valid <- isValidMD fmd
	if valid
		then do -- for valid data we write it to disk
			forestM $ addFileToManifest (\p -> printFile1 arg p (rep,md)) canpath path man
		else do
			isFile <- forestM $ doesFileExistInTree path tree 
			if isFile -- if the data is invalid and a file exists on disk, we remove it, otherwise we don't change anything
				then return $ removePathFromManifest canpath path man
				else return man

doManifestArchive :: (IncK (IncForest fs) md,IncK (IncForest fs) rep,IncK (IncForest fs) (Forest_md fs, md),ForestMD fs md,ForestInput fs FSThunk Inside,ICRep fs) =>
	[ArchiveType] -> FSTree fs 
	-> (ForestFSThunkI fs rep,ForestFSThunkI fs (Forest_md fs,md))
	-> (FSTree fs -> (rep,md) -> Manifest fs -> ForestO fs (Manifest fs))
	-> Manifest fs -> ForestO fs (Manifest fs)
doManifestArchive archTy tree (rep_t,md_t) manifestContents man = do
	rep <- inside $ get rep_t
	(fmd,md) <- inside $ get md_t
	path <- inside $ get_fullpath fmd
	canpath <- forestM $ canonalizePathInTree path tree
	dskpath <- forestM $ pathInTree canpath tree
	let arch_canpath = cardinalPath canpath
	avfsTree <- forestM $ virtualTree tree
	
	archiveDir <- forestM $ forestIO $ getTempPath -- unlogged temporary directory, since we remove it ourselves
	archiveManifest <- forestM $ newManifestWith arch_canpath tree
	ori_file <- forestM $ pathInTree canpath tree
	forestM $ forestIO $ decompressArchive archTy ori_file archiveDir -- decompress the original content, since some may be preserved in the new archive
	
	archiveManifest' <- manifestContents avfsTree (rep,md) archiveManifest
	
	-- NOTE: we only need to commit the writes that contribute to the new archive, inside the forest temp dir; if we chose otherwise we could unsafely commit to the filesystem!
	man1 <- forestM $ storeManifestAt archiveDir archiveManifest' -- store the manifest at the temp dir, and return all the modifications outside the archive
	archiveFile <- forestM tempPath
	forestM $ forestIO $ compressArchive archTy archiveDir archiveFile -- compresses the new data into a new temp file
	forestM $ forestIO $ removePath archiveDir -- purges all temporary archive data 
	
	let testm = do
		isValid <- forestO $ isValidMD fmd
		status <- forestO $ liftM (boolStatus ConflictingMdValidity) $ sameValidity fmd md
		return $ status
	let man2 = addTestToManifest testm man -- errors in the metadata must be consistent
	
	let man3 = addFileToManifest' canpath path archiveFile man2
	return $ mergeManifests man1 man3

doManifestSymLink :: (IncK (IncForest fs) FileInfo,IncK (IncForest fs) Forest_err,IncK (IncForest fs) FilePath,IncK (IncForest fs) (Forest_md fs, Base_md),ICRep fs) =>
	FSTree fs
	-> (ForestFSThunkI fs FilePath,ForestFSThunkI fs (Forest_md fs, Base_md))
	-> Manifest fs -> ForestO fs (Manifest fs)
doManifestSymLink tree (rep_t,md_t) man = do
	tgt <- inside $ get rep_t
	(fmd,base_md) <- inside $ get md_t
	path <- inside $ get_fullpath fmd
	
	canpath <- forestM $ canonalizePathInTree path tree
	dskpath <- forestM $ pathInTree canpath tree
	
	let testm = do
		sym <- forestO $ get_symLink fmd
		liftM (boolStatus $ ConflictingLink path tgt sym) $ return $ sym == Just tgt
	let man1 = addTestToManifest testm man
	
	return $ addLinkToManifest canpath path tgt man1

-- users may have arbitrarily changed the data, so we can't trust that the thunk still computes the correct predicate
doManifestConstraint :: (IncK (IncForest fs) Bool,ICRep fs) => FSTree fs -> ((rep,md) -> ForestI fs Bool) -> (rep,(md,ForestICThunkI fs Bool))
	-> ((rep,md) -> Manifest fs -> ForestO fs (Manifest fs))
	-> Manifest fs -> ForestO fs (Manifest fs)
doManifestConstraint tree pred (rep,(md,pred_t)) manifestContent man = do
	let testm = do
		oldb <- forestO $ inside $ force pred_t
		newb <- forestO $ inside $ pred (rep,md)
		return $ boolStatus ConflictingConstraint (oldb == newb)
	let man1 = addTestToManifest testm man
	manifestContent (rep,md) man1

doManifestDirectory :: (IncK (IncForest fs) FileInfo,IncK (IncForest fs) Forest_err,IncK (IncForest fs) rep,IncK (IncForest fs) (Forest_md fs, md),ICRep fs) => 
	FSTree fs -> (md -> ForestI fs Forest_err)
	-> (ForestFSThunkI fs rep,ForestFSThunkI fs (Forest_md fs,md))
	-> (FilePath -> (rep,md) -> Manifest fs -> ForestO fs (Manifest fs))
	-> Manifest fs -> ForestO fs (Manifest fs)
doManifestDirectory tree collectMDErrors (rep_t,md_t) manifestContent man = do
	rep <- inside $ get rep_t
	(fmd,md) <- inside $ get md_t
	path <- inside $ get_fullpath fmd
	canpath <- forestM $ canonalizePathInTree path tree
	dskpath <- forestM $ pathInTree canpath tree
	let man1 = addDirToManifest canpath path man -- adds a new directory
	let testm = liftM (boolStatus ConflictingMdValidity) $ forestO $ inside (collectMDErrors md) >>= sameValidity' fmd
	let man2 = addTestToManifest testm man1 -- errors in the metadata must be consistent
	manifestContent path (rep,md) man2

doManifestMaybe :: (IncK (IncForest fs) (Maybe rep),IncK (IncForest fs) (Forest_md fs, Maybe md),ForestMD fs md,ICRep fs) =>
	FSTree fs
	-> (ForestFSThunkI fs (Maybe rep),ForestFSThunkI fs (Forest_md fs,Maybe md))
	-> ((rep,md) -> Manifest fs -> ForestO fs (Manifest fs))
	-> (rep -> FilePath -> ForestI fs md)
	-> Manifest fs -> ForestO fs (Manifest fs)
doManifestMaybe tree (rep_t,md_t) manifestContent defaultContent man = do
	rep_mb <- inside $ get rep_t
	(fmd,md_mb) <- inside $ get md_t
	path <- inside $ get_fullpath fmd
	case (rep_mb,md_mb) of
		(Just rep,Just md) -> do
			let testm = do
				status1 <- liftM (boolStatus ConflictingMdValidity) $ forestO $ sameValidity fmd md
				status2 <- liftM (boolStatus $ NonExistingPath path) $ latestTree >>= doesExistInTree path
				return $ status1 `mappend` status2
			let man1 = addTestToManifest testm man
			manifestContent (rep,md) man1 -- the path will be added recursively
		(Nothing,Nothing) -> do
			canpath <- forestM $ canonalizePathInTree path tree
			dskpath <- forestM $ pathInTree canpath tree
			let testm = do
				status1 <- liftM (boolStatus $ ConflictingMdValidity) $ forestO $ isValidMD fmd
				status2 <- liftM (boolStatus $ ExistingPath path) $ latestTree >>= liftM not . doesExistInTree path
				return $ status1 `mappend` status2
			let man1 = addTestToManifest testm man
			return $ removePathFromManifest canpath path man1 -- removes the path
		(Just rep,Nothing) -> do 
			md <- inside $ defaultContent rep "" --XXX: can we provide a better filepath?
			let testm = return (Invalid [ConflictingRepMd]) -- always invalid
			let man1 = addTestToManifest testm man
			manifestContent (rep,md) man1 -- the path will be added recursively
		(Nothing,Just md) -> do 
			canpath <- forestM $ canonalizePathInTree path tree
			dskpath <- forestM $ pathInTree canpath tree
			let testm = return (Invalid [ConflictingRepMd]) -- always invalid
			let man1 = addTestToManifest testm man
			return $ removePathFromManifest canpath path man1 -- removes the path

doManifestFocus :: (ForestMD fs md,Matching fs a) =>
	FilePath -> a -> FSTree fs -> (rep,md)
	-> ((rep,md) -> Manifest fs -> ForestO fs (Manifest fs))
	-> Manifest fs -> ForestO fs (Manifest fs)
doManifestFocus parentPath matching tree dta@(rep,md) manifestUnder man = do
	let testm = do
		fmd <- forestO $ get_fmd_header md
		path <- forestO $ get_fullpath fmd
		let name = makeRelative parentPath path
		isValid <- forestO $ isValidMD fmd
		testFocus parentPath name (\file tree -> return True) [name]
	manifestUnder dta $ addTestToManifest testm man

testFocus :: (FSRep fs,Matching fs a) => FilePath -> a -> (FileName -> FSTree fs -> ForestM fs Bool) -> [FileName] -> ForestM fs Status
testFocus root matching pred new_files = do
	tree <- latestTree
	files <- filterM (flip pred tree) =<< getMatchingFilesInTree root matching tree
	let testFile (file,new_file) = do
		canpath <- canonalizePathInTree (root </> file) tree
		new_canpath <- canonalizePathInTree (root </> new_file) tree
		return $ canpath == new_canpath
	same <- liftM and $ mapM testFile $ zip (List.sort new_files) (List.sort files)
	return $ boolStatus (ConflictingMatching root (show matching) new_files files) $ (length files == length new_files) && same

doManifestSimple :: (IncK (IncForest fs) imd',ForestMD fs imd',Matching fs a,md' ~ ForestFSThunkI fs imd') =>
	FilePath -> ForestI fs a -> FSTree fs -> (rep',md')
	-> ((rep',md') -> Manifest fs -> ForestO fs (Manifest fs))
	-> Manifest fs -> ForestO fs (Manifest fs)
doManifestSimple parentPath matching tree dta manifestUnder man = inside matching >>= \m -> doManifestFocus parentPath m tree dta manifestUnder man

doManifestSimpleWithConstraint :: (IncK (IncForest fs) Bool,IncK (IncForest fs) imd',ForestMD fs imd',Matching fs a,md' ~ ForestFSThunkI fs imd') =>
	FilePath -> ForestI fs a -> FSTree fs
	-> ((rep',md') -> ForestI fs Bool)
	-> (rep',(md',ForestICThunkI fs Bool))
	-> ((rep',md') -> Manifest fs -> ForestO fs (Manifest fs))
	-> Manifest fs -> ForestO fs (Manifest fs)
doManifestSimpleWithConstraint parentPath matching tree pred dta manifestUnder = doManifestConstraint tree pred dta $ \dta' man1 ->
	inside matching >>= \m -> doManifestFocus parentPath m tree dta' manifestUnder man1

-- to enforce consistency while allowing the list to change, we delete all files in the directory that do not match the values
doManifestCompound :: (ForestMD fs md',Matching fs a,imd ~ (md',ForestFSThunkI fs FileInfo)) =>
	FilePath -> ForestI fs a -> FSTree fs
	-> (container_rep -> [(FilePath,rep')]) -> (container_md -> [(FilePath,imd)])
	-> (container_rep,container_md)
	-> (FileName -> ForestFSThunkI fs FileInfo -> (rep',md') -> Manifest fs -> ForestO fs (Manifest fs))
	-> Manifest fs -> ForestO fs (Manifest fs)
doManifestCompound parentPath matchingM tree toListRep toListMd (c_rep,c_md) manifestUnder man = do
	matching <- inside matchingM
	old_files <- forestM $ getMatchingFilesInTree parentPath matching tree
	let reps' = map snd $ toListRep c_rep
	let (new_files,imds) = unzip $ toListMd c_md
	let (mds',fileinfos_t) = unzip imds
	let dtas' = zip reps' mds'
	
	let rem_files = old_files \\ new_files -- files to be removed
	man1 <- forestM $ foldr (\rem_path man0M -> canonalizePathInTree rem_path tree >>= \canpath -> liftM (removePathFromManifest canpath rem_path) man0M) (return man) $ map (parentPath </>) rem_files -- remove deprecated files
	
	let manifestEach ((n,info_t),dta') man0M = man0M >>= doManifestFocus parentPath n tree dta' (manifestUnder n info_t)
	foldr manifestEach (return man1) (zip (zip new_files fileinfos_t) dtas')

doManifestCompoundWithConstraint :: (IncK (IncForest fs) FileInfo,IncK (IncForest fs) Bool,ForestMD fs md',Matching fs a,imd ~ (md',(ForestFSThunkI fs FileInfo,ForestICThunkI fs Bool))) =>
	FilePath -> ForestI fs a -> FSTree fs
	-> (container_rep -> [(FilePath,rep')]) -> (container_md -> [(FilePath,imd)])
	-> (FileName -> ForestFSThunkI fs FileInfo -> ForestI fs Bool)
	-> (container_rep,container_md)
	-> (FileName -> ForestFSThunkI fs FileInfo -> (rep',md') -> Manifest fs -> ForestO fs (Manifest fs))
	-> Manifest fs -> ForestO fs (Manifest fs)
doManifestCompoundWithConstraint parentPath matchingM tree toListRep toListMd pred (c_rep,c_md) manifestUnder man = do
	matching <- inside matchingM
	old_files <- forestM $ getMatchingFilesInTree parentPath matching tree
	
	let reps' = map snd $ toListRep c_rep
	let (new_files,imds) = unzip $ toListMd c_md
	let (mds',fileinfos_t_preds_t) = unzip imds
--	let (fileinfos_t,preds_t) = unzip fileinfos_t_preds_t
	let dtas' = zip reps' mds'
	
	let old_files' = old_files \\ new_files -- old files that are not in the view
	old_metadatas' <- mapM (getRelForestMDInTree parentPath tree) old_files'
	-- we need to check which old files satisfy the predicate
	old_values' <- inside $ filterM (\(n,fmd) -> pred n (fileInfo fmd)) $ zip old_files' old_metadatas'
	let rem_files = map fst old_values'
	-- and delete them
	man1 <- forestM $ foldr (\rem_path man0M -> canonalizePathInTree rem_path tree >>= \canpath -> liftM (removePathFromManifest canpath rem_path) man0M) (return man) $ map (parentPath </>) rem_files -- remove deprecated files
	
	let manifestEach ((n,(info_t,pred_t)),(rep',md')) man0M = man0M >>= doManifestConstraint tree (\_ -> pred n info_t) (rep',(md',pred_t))
		(\dta' -> doManifestFocus parentPath n tree dta' (manifestUnder n info_t))
	foldr manifestEach (return man1) (zip (zip new_files fileinfos_t_preds_t) dtas')


