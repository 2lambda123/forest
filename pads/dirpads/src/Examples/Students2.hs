{-# LANGUAGE TypeSynonymInstances, TemplateHaskell, QuasiQuotes, MultiParamTypeClasses, FlexibleInstances, DeriveDataTypeable, ScopedTypeVariables #-}

module Examples.Students where

import Language.Pads.Padsc
import Language.Forest.Forestc
import Language.Pads.GenPretty

import Data.Map
import System.IO.Unsafe (unsafePerformIO)



ws   = RE "[ \t]+"
ows  = RE "[ \t]*"
junk = RE ".*"
space = ' '
quote = '\''
comma = ','


[pads| 
  type Grade = Pre "[ABCD][+-]?|F|AUD|N|INC|P"

  data Course = 
    { sort         :: Pre "[dto]",           ws
    , departmental :: Pre "[.D]",            ws
    , passfail     :: Pre "[.p]",            ws
    , level        :: Pre "[1234]",          ws
    , department   :: Pre "[A-Z][A-Z][A-Z]", ws
    , number       :: Pint where <| 100 <= number && number < 600 |>, ws
    , grade        :: Grade,                 junk                               
    } 

  data Middle_name = {' ', middle :: Pre "[a-zA-Z]+[.]?" }           
 
  data Student_Name(myname::String) = 
    { lastname   :: Pre "[a-zA-Z]*"  where <| toString lastname ==  myname |>,  comma, ows     
    , firstname  :: Pre "[a-zA-Z]*" 
    , middlename :: Maybe Middle_name
    }

  data School = AB | BSE

  data Person (myname::String) =
    { fullname   :: Student_Name myname,    ws
    , school     :: School,                 ws, quote
    , year       :: Pre "[0-9][0-9]"
    }

  type Header  = [Line (Pre ".*")] with term length of 7 
  type Trailer = [Line (Pre ".*")] with term Eof 
  data Student (name::String) = 
    { person  :: Line (Person name)
    , Header  
    , courses :: [Line Course]
    , Trailer
    }
|]

transferRE  = RE "TRANSFER|Transfer"
leaveRE     = RE "LEAVE|Leave"
withdrawnRE = RE "WITHDRAWN|WITHDRAWAL|Withdrawn|Withdrawal|WITHDREW"

[forest|
  -- Directory containing all students in a particular major.
  type Major_d = Directory 
       { students is Map [ s :: File (Student <| getName s |>) 
                         | s <- matches (GL "*.txt") where <| not (template s) |> ] }

  -- Directory containing all students in a particular year
  type Class_d (year :: String) = Directory
    { bse is <|"BSE" ++ year|> :: Major_d
    , ab  is <|"AB"  ++ year|> :: Major_d   
    , transfer is  [ t :: Major_d | t <- matches transferRE  ]      
    , withdrawn is [ w :: Major_d | w <- matches withdrawnRE ]
    , leave is     [ l :: Major_d | l <- matches leaveRE     ] 
    }

  -- Directory for all graduated students
  type Grads_d = Directory 
    { classes is  Map [ aclass :: Class_d <| getYear aclass |>  
                      | aclass <- matches (RE "classof[0-9][0-9]") ] }

  -- Root of the hierarchy
  type PrincetonCS_d = Directory
    { classof10 :: Class_d  "10" 
    , classof11 :: Class_d  "11" 
    , graduates :: Grads_d
    }
|]


-- Auxiliary code
template s = or [ s == "SSSS.txt"
                , s == "SSS.txt"
                , s == "sxx.txt"
                , s == "sss.txt"
                , s == "ssss.txt" ]

splitExt s = let (dne, dotgeb) = Prelude.break (== '.') (reverse s) 
             in case dotgeb of 
                 [] -> (reverse dne, [])
                 '.':tser -> (reverse tser, reverse dne)
                 tser -> (reverse tser, reverse dne)

getName = fst . splitExt
getYear s = reverse (Prelude.take 2 (reverse s))




mkPrettyInstance ''PrincetonCS_d
mkPrettyInstance ''PrincetonCS_d_md

--cs_dir = "/Users/kfisher/pads/dirpads/src/Examples/data/facadm"
cs_dir = "Examples/data/facadm"
(cs_rep, cs_md) = unsafePerformIO $ princetonCS_d_load cs_dir

cd_md md f = f $ snd md  -- should this change the paths?
cd_rep rep f = f $ rep



doTar = tarFiles cs_md "CS.tar"

-- Find all files mentioned in cs
files = listFiles cs_md

grad09_dir = "/Users/kfisher/pads/dirpads/src/Examples/data/facadm/graduates/classof09"
(grad09_rep, grad09_md) = unsafePerformIO $ (class_d_load "09") grad09_dir

majorBSE09_dir = "/Users/kfisher/pads/dirpads/src/Examples/data/facadm/graduates/classof09/BSE09"
(bse09_rep, bse09_md) = unsafePerformIO $ major_d_load  majorBSE09_dir

Grads_d grads = graduates cs_rep
grads07 = grads ! "classof07" 
Major_d bse_grads07 = bse grads07

errs = fst cs_md

errsP = pretty 80 (ppr errs)


clark = bse_grads07 ! "clark.txt"
clark_doc = student_ppr clark
clark_output n = putStrLn (pretty n clark_doc)

ppBseGrads07 n = putStrLn (pretty n (major_d_ppr (bse grads07)))

student_input_file = "/Users/kfisher/pads/dirpads/src/Examples/data/facadm/classof10/AB10/APPS.txt"
student_result :: (Student, Student_md) = unsafePerformIO $ parseFile1 "APPS" student_input_file
-- (Student apps apps_courses, sfmd) = unsafePerformIO $ load1 "APPS" student_input_file

finger_input_file = "/Users/kfisher/pads/dirpads/src/Examples/data/facadm/classof11/WITHDREW/finger.txt"
finger_result :: (Student, Student_md) = unsafePerformIO $ parseFile1 "finger" finger_input_file

course_input = "d D . 3 JPN 238 INC"
course_result = course_parseS course_input

major_dir = "/Users/kfisher/pads/dirpads/src/Examples/data/facadm/classof11/AB11"
(major_rep, major_md) = unsafePerformIO $ major_d_load  major_dir

withdrawn_dir = "/Users/kfisher/pads/dirpads/src/Examples/data/facadm/classof11/WITHDREW"
(withdrawnt_rep, withdrawnt_md) = unsafePerformIO $ major_d_load  withdrawn_dir

class_dir = "/Users/kfisher/pads/dirpads/src/Examples/data/facadm/classof11"
(class_rep, class_md) = unsafePerformIO $ (class_d_load "11") class_dir

class07_dir = "/Users/kfisher/pads/dirpads/src/Examples/data/facadm/graduates/classof07"
(class07_rep, class07_md) = unsafePerformIO $ (class_d_load "07") class07_dir

class10_dir = "/Users/kfisher/pads/dirpads/src/Examples/data/facadm/classof10"
(class10_rep, class10_md) = unsafePerformIO $ (class_d_load "10") class10_dir

class11_dir = "/Users/kfisher/pads/dirpads/src/Examples/data/facadm/classof11"
(class11_rep, class11_md) = unsafePerformIO $ (class_d_load "11") class11_dir

grad_dir = "/Users/kfisher/pads/dirpads/src/Examples/data/facadm/graduates"
(grad_rep, grad_md) = unsafePerformIO $ grads_d_load grad_dir



