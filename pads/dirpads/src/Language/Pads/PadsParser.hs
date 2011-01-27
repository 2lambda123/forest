{-# LANGUAGE NamedFieldPuns #-}

module Language.Pads.PadsParser where

-- These are the combinators used to build PADS parsers

import qualified Language.Pads.Source as S
import Language.Pads.Errors
import Language.Pads.MetaData
import Language.Pads.RegExp
import Char

import Control.Monad

{- Parsing Monad -}

newtype PadsParser a = PadsParser { (#) :: S.Source -> Result (a,S.Source) }
type Result a = (a,Bool)

-- type PadsParserMD a = PadsParser (a, Base_md)


parseStringInput :: PadsParser a -> String -> (a,String)
parseStringInput pp cs = case pp #  (S.padsSourceFromString cs) of
                           ((r,rest),b) -> (r, S.padsSourceToString rest)  


-- parseByteStringInput :: PadsParser a -> ByteString -> a
parseByteStringInput pp cs = case pp #  (S.padsSourceFromByteString cs) of
                           ((r,rest),b) -> r


                        
instance Functor PadsParser where
  fmap f p = PadsParser $ \bs -> case p # bs of
                                   ((x,bs'),b) -> ((f x, bs'),b)

-- if any results on the way are bad, then the whole thing will be bad
instance Monad PadsParser where
  return r = PadsParser $ \bs -> ((r,bs), True)
  p >>= f  = PadsParser $ \bs -> let ((v,bs'),b)   = p # bs
                                     ((w,bs''),b') = f v # bs'
                                 in ((w,bs''), b && b')



badReturn  r = PadsParser $ \bs -> ((r,bs), False)
mdReturn (rep,md) = PadsParser $ 
    \bs -> (((rep,md),bs), numErrors (get_md_header md) == 0)

returnClean :: t -> PadsParser (t, Base_md)
returnClean x = return (x, cleanBasePD)

returnError :: t -> ErrMsg -> PadsParser (t, Base_md)
returnError x err = do loc <- getLoc
                       badReturn (x, mkErrBasePDfromLoc err loc)




--------------------------
-- Source manipulation functions


queryP :: (S.Source -> a) -> PadsParser a
queryP f = PadsParser $ \bs -> ((f bs,bs), True)

primPads :: (S.Source -> (a,S.Source)) -> PadsParser a
primPads f = PadsParser $ \bs -> ((f bs), True)

liftStoP :: (S.Source -> Maybe (a,S.Source)) -> a -> PadsParser a
liftStoP f def = PadsParser $ \bs -> 
                 case f bs of
                   Nothing      -> ((def,bs), False)
                   Just (v,bs') -> ((v,bs'), True)

replaceSource :: S.Source -> (Result (a,S.Source)) -> (Result (a,S.Source))
replaceSource bs ((v,_),b) = ((v,bs),b)


-------------------------
-------------------------

-- The monad is non-backtracking. The only choice point is at ChoiceP

choiceP :: [PadsParser a] -> PadsParser a
choiceP ps = foldr1 (<||>) ps

(<||>) :: PadsParser a -> PadsParser a -> PadsParser a
p <||> q = PadsParser $ \bs -> (p # bs) <++> (q # bs) 

(<++>) :: Result a -> Result a -> Result a
(r, True)    <++> _  = (r, True)
(r1, False)  <++> r2 = r2 -- A number of functions rely on this being r2




-------------------------

parseMaybe :: PadsMD md => PadsParser (rep,md) -> PadsParser (Maybe rep, (Base_md, Maybe md))
parseMaybe p = parseJust p <||> parseNothing

parseJust :: PadsMD md => PadsParser (rep,md) -> PadsParser (Maybe rep, (Base_md, Maybe md))
parseJust p = do
  (r,md) <- p
  return (Just r, (get_md_header md, Just md))

parseNothing :: PadsParser (Maybe t, (Base_md, Maybe s))
parseNothing = return (Nothing, (cleanBasePD, Nothing))
                        

-----------------------

parseTry :: PadsParser a -> PadsParser a
parseTry p = PadsParser $ \bs -> replaceSource bs (p # bs)


-------------

parseConstraint :: PadsMD md => PadsParser(rep,md) -> (rep -> md -> Bool) -> PadsParser(rep, (Base_md, md))
parseConstraint p pred = do 
  (rep,md) <- p
  return (rep, (constraintReport (pred rep md) md, md))
 
constraintReport isGood md = Base_md {numErrors = totErrors, errInfo = errors}
  where
    Base_md {numErrors, errInfo} = get_md_header md
    totErrors = if isGood then numErrors else numErrors + 1
    errors = if totErrors == 0 then Nothing else 
       Just(ErrInfo {msg = if isGood then FUnderlyingTypedefFail
                                     else FPredicateFailure,
                     position = join $ fmap position errInfo})

-------------------------------------------------


parseListNoTermNoSep :: PadsMD md => PadsParser (rep,md) -> PadsParser ([rep], (Base_md, [md]))
parseListNoTermNoSep p = listReport (parseMany p)

parseListNoTermSep :: (PadsMD md, PadsMD mdSep) => PadsParser (repSep,mdSep) -> PadsParser(rep, md) -> PadsParser ([rep], (Base_md, [md]))
parseListNoTermSep sep p = listReport (parseManySep sep p)

parseListTermLengthNoSep :: (PadsMD md) => Int -> PadsParser(rep, md) -> PadsParser ([rep], (Base_md, [md]))
parseListTermLengthNoSep i p = listReport (parseCount i p)

parseListTermLengthSep :: (PadsMD md, PadsMD mdSep) => Int -> PadsParser (repSep,mdSep) -> PadsParser(rep, md) -> PadsParser ([rep], (Base_md, [md]))
parseListTermLengthSep n sep p = listReport (parseCountSep n sep p)

parseListTermNoSep :: (PadsMD md, PadsMD mdTerm) => 
                     PadsParser (repTerm,mdTerm) -> PadsParser(rep, md) -> PadsParser ([rep], (Base_md, [md]))
parseListTermNoSep term p = listReport (parseManyTerm term p)

parseListTermSep :: (PadsMD md, PadsMD mdSep, PadsMD mdTerm) => 
                     PadsParser (repSep,mdSep) -> PadsParser (repTerm,mdTerm) -> PadsParser(rep, md) -> PadsParser ([rep], (Base_md, [md]))
parseListTermSep sep term p = listReport (parseManySepTerm sep term p)


listReport  :: (Monad m, PadsMD b) => m [(a, b)] -> m ([a], (Base_md, [b]))
listReport p = do 
  elems <- p
  let (reps, mds) = unzip elems
  let hmds = map get_md_header mds
  return (reps, (mergeBaseMDs hmds, mds))


-----------------------------------

parseMany :: PadsMD md => PadsParser (rep,md) -> PadsParser [(rep,md)]
parseMany p = do { (r,m) <- p
                 ; if (numErrors (get_md_header m) == 0)
                   then do { rms <- parseMany p
                           ; return ((r,m) : rms)}
                   else badReturn [] 
                 } 
            <||>
              return []


parseManySep :: (PadsMD md, PadsMD mdSep) => PadsParser (repSep,mdSep) -> PadsParser(rep, md) -> PadsParser [(rep,md)]
parseManySep sep p = do { rm <- p
                        ; rms <- parseManySep1 sep p
                        ; return (rm : rms)
                        }

parseManySep1 :: (PadsMD md, PadsMD mdSep) => PadsParser (repSep,mdSep) -> PadsParser(rep, md) -> PadsParser [(rep,md)]
parseManySep1 sep p = do { (r,m) <- sep
                         ; if (numErrors (get_md_header m) == 0)
                           then parseManySep sep p
                           else badReturn [] -- terminate the recursion if separator error found
                                             -- return would work too, as p will create the badness
                         } 
                      <||>
                        return []

-----------------------------------


parseCount :: (PadsMD md) => Int -> PadsParser(rep, md) -> PadsParser [(rep,md)]
parseCount n p  | n <= 0    = return []
                | otherwise = sequence (replicate n p)


parseCountSep :: (PadsMD md) => Int -> PadsParser rmdSep -> PadsParser(rep, md) -> PadsParser [(rep,md)]
parseCountSep n sep p  | n <= 0    = return []
parseCountSep n sep p = do { rm <- p
                           ; rms <- parseCountSep1 (n-1) sep p
                           ; return (rm:rms) }

parseCountSep1 n sep p  | n <= 0    = return []
parseCountSep1 n sep p = do { smd <- sep -- <||> scanForSep [] sep
                            ; parseCountSep n sep p  -- we lose the metadata for sep, which will detail any problems
                            }

-----------------------------------



parseManyTerm :: (PadsMD md, PadsMD mdTerm) =>  PadsParser (repTerm,mdTerm) -> PadsParser(rep, md) -> PadsParser [(rep,md)]
parseManyTerm term p = (term >> return [])
                  <||> (ifEOFP >> return [])
                  <||> do { rm <- p
                          ; rms <- parseManyTerm term p
                          ; return (rm:rms) }



parseManySepTerm :: (PadsMD md, PadsMD mdSep, PadsMD mdTerm) =>  
                     PadsParser (repSep,mdSep) -> PadsParser (repTerm,mdTerm) -> PadsParser(rep, md) -> PadsParser [(rep,md)]
parseManySepTerm sep term p = (term >> return [])
                         <||> (ifEOFP >> return [])
                         <||> scan
  where 
  scan = do (rep, md) <- p
            (terminated,junk) <- seekSep sep term
            if terminated then
              case junk of
                [] -> return [(rep,md)]
                _  -> do sepLoc <- getLoc
                         badReturn [(rep,junkReport md sepLoc junk)]

              else do
                rms <- scan 
                case junk of
                  [] -> return ((rep,md):rms)  
                  _  -> do sepLoc <- getLoc
                           badReturn ((rep,junkReport md sepLoc junk) : rms)


seekSep sep term = (term >> return (True, []))
              <||> (ifEOFP >> return (True, []))
              <||> (sep >> return (False, []))
              <||> recoverSep sep term

recoverSep sep term = do { b <- isEORP
                         ; if b then badReturn (False, []) else
                           do { c <- takeHeadP
                              ; (b,cs) <- seekSep sep term
                              ; badReturn (b, c:cs) 
                              }
                         }

junkReport md loc junk = replace_md_header md mergeMD 
  where
    mdSep   = mkErrBasePDfromLoc (ExtraStuffBeforeTy junk "seperator" ) loc
    mergeMD = mergeBaseMDs [get_md_header md, mdSep]



-------------------------------------------------



getLoc :: PadsParser S.Loc
getLoc = queryP S.getSrcLoc

isEOFP, isEORP :: PadsParser Bool 
isEOFP = queryP S.isEOF
isEORP = queryP S.isEOR

ifEOFP, ifEORP :: PadsParser () 
ifEOFP = do { b <- isEOFP; if b then return () else badReturn ()}
ifEORP = do { b <- isEORP; if b then return () else badReturn ()}


{- Is this what we should do if there isn't sufficient input? -}
takeP_new :: Int -> PadsParser String
takeP_new n = liftStoP (S.take' (fromInt n)) (take n def)
  where
    def = '0':def

takeP :: Integral a => a -> PadsParser String
takeP n = primPads (S.take (fromInt n))

fromInt :: (Integral a1, Num a) => a1 -> a
fromInt n = fromInteger $ toInteger n


-------------------------------------------------



peekHeadP :: PadsParser Char 
peekHeadP = queryP S.head

takeHeadP :: PadsParser Char
takeHeadP = primPads S.takeHead

takeHeadStrP :: String -> PadsParser Bool
takeHeadStrP str = primPads (S.takeHeadStr str)

-- Return string is junk before found string
scanStrP :: String -> PadsParser (Maybe String)
scanStrP str = primPads (S.scanStr str)


regexMatchP ::RE -> PadsParser (Maybe String)
regexMatchP re = primPads (S.regexMatch re)

regexStopP :: RE -> PadsParser (Maybe String)
regexStopP re = primPads (S.regexStop re)

scanP :: Char -> PadsParser Bool
scanP c = primPads (\s -> let (f,r,e) = S.scanTo c s in (f,r))

getAllP :: PadsParser String
getAllP = primPads S.drainSource

getAllBinP :: PadsParser S.RawStream
getAllBinP = primPads S.rawSource

satisfy p = primPads loop
 where loop s = if S.isEOF s || S.isEOR s then ([],s) else
          let c = S.head s in
          if p c then 
            let (xs,s') = loop (S.tail s) in
            (c:xs, s')
          else
            ([],s)

digitListToInt :: Bool -> [Char] -> Int
digitListToInt isNeg digits = let raw = foldl (\a d ->10*a + (Char.digitToInt d)) 0 digits
   in if isNeg then negate raw else raw


-------------------------

parseLine :: PadsMD md => PadsParser (r,md) -> PadsParser (r,md)
parseLine p =  do 
   (_,bmd) <- doLineBegin
   (r, md) <- p
   (_,emd) <- doLineEnd
   let new_hd = mergeBaseMDs [bmd, get_md_header md, emd]
   return (r, replace_md_header md new_hd)


doLineBegin :: PadsParser ((), Base_md)
doLineBegin = do
  rbegErr <- primPads S.srcLineBegin
  case rbegErr of
    Nothing -> returnClean ()
    Just err -> returnError () (LineError err)


doLineEnd :: PadsParser ((), Base_md)
doLineEnd = do
  rendErr <- primPads S.srcLineEnd
  case rendErr of
    Nothing -> returnClean ()
    Just err -> returnError () (LineError err)





