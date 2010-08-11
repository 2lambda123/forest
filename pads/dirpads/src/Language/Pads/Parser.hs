module Language.Pads.Parser where 

import Data.Map as Map

import Language.Pads.Syntax as S

import Text.Parsec
import qualified Text.Parsec.String as PS
import Text.Parsec.Error
import Text.Parsec.Prim as PP
import qualified Text.Parsec.Token as PT
import Text.Parsec.Language
import Text.ParserCombinators.Parsec.Language 
import Text.ParserCombinators.Parsec.Pos
import Language.Haskell.Meta as LHM
import Language.Haskell.TH as TH

type Parser = PS.Parser

lexer :: PT.TokenParser ()
lexer = PT.makeTokenParser (haskellStyle { reservedOpNames = ["=", "(:", ":)", "<=>", "{", "}", "::", "<|", "|>", "|"],
                                           reservedNames   = ["Line", "Trans", "using", "where", "data"]})

whiteSpace    = PT.whiteSpace  lexer
identifier    = PT.identifier  lexer
reserved      = PT.reserved    lexer
reservedOp    = PT.reservedOp  lexer
charLiteral   = PT.charLiteral lexer
stringLiteral = PT.stringLiteral  lexer
commaSep1     = PT.commaSep1   lexer
parens        = PT.parens      lexer
braces        = PT.braces      lexer


replaceName :: String -> PadsTy -> PadsTy
replaceName str ty = case ty of
  Precord _ body -> Precord str body
  Punion  _ body -> Punion  str body
  otherwise -> ty

padsDecl :: Parser PadsDecl
padsDecl =   tyDecl
         <|> dataDecl


dataDecl :: Parser PadsDecl
dataDecl = do { reserved "data"
              ; id <- identifier
              ; pat <- param
              ; padsTy <- dataTy id
              ; return (PadsDecl(Id id, pat, padsTy))
              } <?> "Data Declaration"

tyDecl :: Parser PadsDecl
tyDecl = do { id <- identifier
            ; pat <- param
            ; ty <- padsTy
            ; return (PadsDecl(Id id, pat, replaceName id ty))
            } <?> "Type Declaration"

param :: Parser (Maybe TH.Pat)
param = do { str <- manyTill anyChar (reservedOp "=")
           ; pat <- case (Prelude.null str, LHM.parsePat str) of 
                            (True, _) -> return Nothing
                            (_, Left err) -> unexpected ("Failed to parse Haskell pattern: " ++ err)
                            (_, Right patTH) -> return (Just patTH)
           ; return pat                            
           }

dataTy :: String -> Parser PadsTy
dataTy str = unionTy str 


idTy   :: Parser PadsTy
idTy   = do { base <- identifier
            ; return (Pname base)
            } <?> "named type"

charlitTy :: Parser S.Lit
charlitTy = do { c <- charLiteral
               ; return (S.CharL c)
               } <?> "character literal type"

strlitTy :: Parser S.Lit
strlitTy = do { s <- stringLiteral
               ; return (S.StringL s)
               } <?> "string literal type"

litTy :: Parser PadsTy
litTy = do { lit <- charlitTy <|> strlitTy
           ; return (Plit lit)
           } <?> "literal type"

fnTy   :: Parser PadsTy
fnTy   =  idTy

fnAppTy :: Parser PadsTy
fnAppTy = do { ty <- fnTy
             ; reservedOp "(:"
             ; str <- manyTill anyChar (reservedOp ":)") 
             ; case LHM.parseExp str of
                 Left err    -> unexpected ("Failed to parse Haskell expression: " ++ err ++ " in Pads application")
                 Right expTH -> return (Papp ty expTH)
             } <?> "type function application"


lineTy :: Parser PadsTy
lineTy = do { reserved "Line"
              ; ty <- padsTy
              ; return (Pline ty)
              } <?> "line type"

tupleTy :: Parser PadsTy
tupleTy = do { tys <- parens padsTyList
             ; return (Ptuple tys)
             } <?> "tuple type"

padsTyList :: Parser [PadsTy]
padsTyList = commaSep1 padsTy

unionTy :: String -> Parser PadsTy
unionTy str = do { branches <- branchList
                 ; return (Punion str branches)
                 } <?> "data type"

branchList :: Parser [(Maybe String, PadsTy, Maybe TH.Exp)]
branchList = sepBy1  branch (reservedOp "|")

branch :: Parser (Maybe String, PadsTy, Maybe TH.Exp)
branch = do { id <- identifier
            ; ty  <- padsTy
            ; predM <- optionMaybe fieldPredicate
            ; return (Just id, ty, predM)
            }

recordTy :: Parser PadsTy
recordTy = do { fields <- braces fieldList
              ; return (Precord "" fields)   -- empty string is placeholder for record name, which will be filled in at decl level.
              } <?> "record type"

fieldList :: Parser [(Maybe String, PadsTy, Maybe TH.Exp)]
fieldList = commaSep1 field

{- Records 
[pads| Request = { i1 :: Pint, 
                         ',',
                   i2 :: Pint Pwhere <| i1 == i2 } |> |]
-}

field :: Parser (Maybe String, PadsTy, Maybe TH.Exp)
field = do { idM <- optionMaybe $ try fieldLabel
           ; ty  <- padsTy
           ; predM <- optionMaybe fieldPredicate
           ; return (idM, ty, predM)
           }
        

fieldLabel :: Parser String
fieldLabel = do { id <- identifier
                ; reservedOp "::"
                ; return id
                }

fieldPredicate :: Parser TH.Exp
fieldPredicate = do { reserved   "where"
                    ; reservedOp "<|"
                    ; str <- manyTill anyChar (reservedOp "|>")
                    ; case LHM.parseExp str of
                     Left err    -> unexpected ("Failed to parse Haskell expression: " ++ err ++ ".")
                     Right expTH -> return expTH
                    }


transformTy :: Parser PadsTy
transformTy = do { reserved "Trans"
                 ; reservedOp "{" 
                 ; srcTy <- padsTy
                 ; reservedOp "<=>" 
                 ; dstTy <- padsTy
                 ; reserved "using"
                 ; str <- manyTill anyChar (reservedOp "}")
                 ; case LHM.parseExp str of
                   Left err    -> unexpected ("Failed to parse Haskell expression: " ++ err ++ " in Trans.")
                   Right expTH -> return (Ptrans srcTy dstTy expTH)
                 } <?> "transform"

typedefTy :: Parser PadsTy
typedefTy = do { str1 <- manyTill anyChar (reservedOp "::")
               ; pat <- case LHM.parsePat str1 of
                             (Left err) -> unexpected ("Failed to parse Haskell pattern in where declaration: " ++ err)
                             (Right patTH) -> return patTH
               ; ty <- padsTy
               ; reserved "where"
               ; str2 <- manyTill anyChar eof
               ; case LHM.parseExp str2 of
                      Left err    -> unexpected ("Failed to parse Haskell expression: " ++ err ++ " in where declaration.")
                      Right expTH -> return (Ptypedef pat ty expTH)
               } <?> "where"

padsTy :: Parser PadsTy
padsTy = lineTy
     <|> transformTy 
     <|> tupleTy
     <|> recordTy
     <|> try fnAppTy
     <|> try typedefTy
     <|> litTy
     <|> idTy
     <?> "pads type"



runLex :: Show a => PS.Parser a -> String -> IO()
runLex p input 
  = parseTest (do { whiteSpace
                  ; x <- p
                  ; eof
                  ; return x
                  }) input



parse :: PS.Parser a -> SourceName -> Line -> Column -> String -> Either ParseError a
parse p fileName line column input 
  = PP.parse (do {  setPosition (newPos fileName line column)
                  ; whiteSpace
                  ; x <- p
                  ; eof
                  ; return x
                  }) fileName input



simple :: PS.Parser Char
simple = letter

result = parseTest simple " hello"

