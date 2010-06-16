module Language.Pads.Errors where
import Text.PrettyPrint.Mainland as PP
import qualified Language.Pads.Source as S
import Data.Data

data ErrMsg = 
   FoundWhenExpecting String String
 | MissingLiteral String
 | ExtraBeforeLiteral String
 | RecordError String
 | Insufficient Int Int
 | RegexMatchFail String
   deriving (Typeable, Data, Eq)

instance Pretty ErrMsg where
  ppr (FoundWhenExpecting str1 str2) = text ("Encountered " ++ str1 ++ " when expecting " ++ str2 ++ ".")
  ppr (MissingLiteral s)     = text ("Missing Literal: " ++ s ++ ".")
  ppr (ExtraBeforeLiteral s) = text ("Extra bytes before literal: " ++ s ++ ".")
  ppr (Insufficient found expected) = text("Found " ++ (show found) ++ " bytes when looking for " ++ (show expected) ++ "bytes.")
  ppr (RegexMatchFail s) = text ("Failed to match regular expression: " ++ s ++ ".")
  ppr (RecordError s)        = text (s)

data ErrInfo = ErrInfo { msg      :: ErrMsg,
                         position :: S.Pos }
   deriving (Typeable, Data, Eq)

instance Pretty ErrInfo where
  ppr (ErrInfo {msg,position}) = ppr msg <+> (text "at:") <+>  ppr position


