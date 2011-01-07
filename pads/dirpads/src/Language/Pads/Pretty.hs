{-# LANGUAGE NamedFieldPuns,RecordWildCards #-}
module Language.Pads.Pretty where
import Char (isPrint, ord)
import Numeric (showHex)

import Text.PrettyPrint.Mainland
import Language.Pads.Syntax
import Language.Pads.Errors
import Language.Pads.CoreBaseTypes
import Language.Pads.Source
import Language.Pads.MetaData
import Language.Pads.PadsParser

import qualified Data.Map as M


seplines :: Doc -> [Doc] -> Doc
seplines s = folddoc (\hd tl -> hd <> s </> tl)


whitesep = sep
field_ppr field_name ppr = text field_name   <+> equals <+> ppr
record_ppr str pprs  = namedty_ppr str (recordbody_ppr pprs)  
recordbody_ppr docs = 
       text "{" 
  <//> align (seplines comma docs) 
  <//> text "}"
tuple_ppr ds = (text "(" <//>
                    align (commasep ds ) <//>        
                text ")")

maybe_ppr d = case d of 
  Nothing -> text "Nothing"
  Just a -> ppr a




namedty_ppr str ph = hang 2 (text str <+/> ph)
-- host_t_ppr (Host_t h) = namedty_ppr "Host_t" (ppr h)

namedtuple_ppr :: String -> [Doc] -> Doc
namedtuple_ppr name pprls = group $ hang 2 (text name <+/> (tuple_ppr pprls))


list_ppr ds = (text "[---" <//>
                    align (seplines comma ds ) <//>        
                text "]")

--instance (Pretty a, Pretty b)  => Pretty (M.Map a b) where
--  ppr = map_ppr 
map_ppr d = list_ppr (map ppr (M.toList d))

string_ppr :: String -> Doc
string_ppr = ppr


namedlist_ppr :: String -> [Doc] -> Doc
namedlist_ppr name pprls = group $ hang 2 (text name <+/> (list_ppr pprls))




pint_ppr :: Pint -> Doc
pint_ppr (Pint x) = ppr x

instance Pretty Pint where
 ppr = pint_ppr 

pstring_ppr (Pstring s) = ppr s

instance Pretty Pstring where
 ppr = pstring_ppr

instance Pretty PstringME where
 ppr (PstringME s) = ppr s

instance Pretty PstringSE where
 ppr (PstringSE s) = ppr s

--instance Pretty String where
-- ppr = pstring_ppr

--instance Pretty a => Pretty (Maybe a) where
-- ppr = maybe_ppr










instance Pretty Lit where
   ppr (CharL c) | isPrint c   = text $ show c
                 | ord c == 0  = squotes $ text $ "\\0"
                 | otherwise   = squotes $ text $
                                 "\\x" ++ showHex (ord c) ""
   ppr (StringL s) = text $ show s


instance Pretty Loc where
 ppr (Loc{lineNumber,byteOffset}) = text "Line:" <+> ppr lineNumber <> text ", Offset:" <+> ppr byteOffset 

instance Pretty Pos where 
  ppr (Pos{begin,end}) = case end of
                                Nothing -> ppr begin
                                Just end_loc ->  text "from:" <+> ppr begin <+> text "to:" <+> ppr end_loc

instance Pretty Source where 
    ppr (Source{current, rest, ..}) = text "Current:" <+> text (show current)

instance Pretty ErrInfo where
  ppr (ErrInfo {msg,position}) = ppr msg <+> 
       case position of 
         Nothing -> empty
         Just pos -> (text "at:") <+>  ppr pos

instance Pretty Base_md where
  ppr = pprBaseMD

pprBaseMD Base_md {numErrors=num, errInfo = info} = text "Errors:" <+> ppr num <+> 
                                                    case info of Nothing -> empty
                                                                 Just e -> ppr e


instance Pretty PadsTy where
    ppr (Ptuple tys) = parens (commasep (map ppr tys))
    ppr (Plit l) = ppr l
    ppr (Pname s) = text s



instance Pretty PadsDecl where
    ppr (PadsDecl (name,pat,padsty)) = ppr name <+>  text (show pat) <+> text "=" <+> ppr padsty

instance Pretty Id where
    ppr (Id ident)  = text ident
    ppr (AntiId v)  = ppr "$id:" <> ppr v

instance Pretty a => Pretty (Result a) where
    ppr (Good r) = text "Good:" <+> ppr r
    ppr (Bad  r) = text "Bad:"  <+> ppr r


instance (Pretty a, Pretty b, Pretty c, Pretty d, Pretty e) => Pretty (a, b, c, d, e) where
    ppr (a, b, c, d, e) = parens $ commasep [ppr a, ppr b, ppr c, ppr d, ppr e]

instance (Pretty a, Pretty b, Pretty c, Pretty d, Pretty e, Pretty f) => Pretty (a, b, c, d, e, f) where
    ppr (a, b, c, d, e, f) = parens $ commasep [ppr a, ppr b, ppr c, ppr d, ppr e, ppr f]

instance (Pretty a, Pretty b, Pretty c, Pretty d, Pretty e, Pretty f, Pretty g) => Pretty (a, b, c, d, e, f,g) where
    ppr (a, b, c, d, e, f, g) = parens $ commasep [ppr a, ppr b, ppr c, ppr d, ppr e, ppr f, ppr g]


