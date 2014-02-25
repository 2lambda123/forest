structure TokenDefs =
struct
open Tokens
val tokenDefList =
        [ ( Pint (0, ""), "[-~]?([0-9]+)" )
        , ( Pfloat ("", ""), "([-~]?([0-9]+))|[-~]?([0-9]+)\\.([0-9]+)|[-~]?[1-9]\\.([0-9]+)(E|e)[-~]?([0-9]+)")
        , ( Ptime "", "([0-9][0-9]):([0-9][0-9]):([0-9][0-9])([ ]*(AM|PM))?([ \\t]+([+-][0-1][0-9]00))?") 
        , ( Pdate "", "((Jan|jan|Feb|feb|Mar|mar|Apr|apr|May|may|Jun|jun|Jul|jul|Aug|aug|Sep|sep|Oct|oct|Nov|nov|Dec|dec|January|February|March|April|May|June|July|August|September|October|November|December)|(0?[1-9]|1[0-2]))\\/([1-9]|[1-2][0-9]|0[1-9]|3[0-1])\\/([0-2][0-9][0-9][0-9])|([1-9]|[1-2][0-9]|0[1-9]|3[0-1])\\/((Jan|jan|Feb|feb|Mar|mar|Apr|apr|May|may|Jun|jun|Jul|jul|Aug|aug|Sep|sep|Oct|oct|Nov|nov|Dec|dec|January|February|March|April|May|June|July|August|September|October|November|December)|(0?[1-9]|1[0-2]))\\/([0-2][0-9][0-9][0-9])|([0-2][0-9][0-9][0-9])\\/((Jan|jan|Feb|feb|Mar|mar|Apr|apr|May|may|Jun|jun|Jul|jul|Aug|aug|Sep|sep|Oct|oct|Nov|nov|Dec|dec|January|February|March|April|May|June|July|August|September|October|November|December)|(0?[1-9]|1[0-2]))\\/([1-9]|[1-2][0-9]|0[1-9]|3[0-1])|((Jan|jan|Feb|feb|Mar|mar|Apr|apr|May|may|Jun|jun|Jul|jul|Aug|aug|Sep|sep|Oct|oct|Nov|nov|Dec|dec|January|February|March|April|May|June|July|August|September|October|November|December)|(0?[1-9]|1[0-2]))\\-([1-9]|[1-2][0-9]|0[1-9]|3[0-1])\\-([0-2][0-9][0-9][0-9])|([1-9]|[1-2][0-9]|0[1-9]|3[0-1])\\-((Jan|jan|Feb|feb|Mar|mar|Apr|apr|May|may|Jun|jun|Jul|jul|Aug|aug|Sep|sep|Oct|oct|Nov|nov|Dec|dec|January|February|March|April|May|June|July|August|September|October|November|December)|(0?[1-9]|1[0-2]))\\-([0-2][0-9][0-9][0-9])|([0-2][0-9][0-9][0-9])\\-((Jan|jan|Feb|feb|Mar|mar|Apr|apr|May|may|Jun|jun|Jul|jul|Aug|aug|Sep|sep|Oct|oct|Nov|nov|Dec|dec|January|February|March|April|May|June|July|August|September|October|November|December)|(0?[1-9]|1[0-2]))\\-([1-9]|[1-2][0-9]|0[1-9]|3[0-1])|((Jan|jan|Feb|feb|Mar|mar|Apr|apr|May|may|Jun|jun|Jul|jul|Aug|aug|Sep|sep|Oct|oct|Nov|nov|Dec|dec|January|February|March|April|May|June|July|August|September|October|November|December)|(0?[1-9]|1[0-2]))\\.([1-9]|[1-2][0-9]|0[1-9]|3[0-1])\\.([0-2][0-9][0-9][0-9])|([1-9]|[1-2][0-9]|0[1-9]|3[0-1])\\.((Jan|jan|Feb|feb|Mar|mar|Apr|apr|May|may|Jun|jun|Jul|jul|Aug|aug|Sep|sep|Oct|oct|Nov|nov|Dec|dec|January|February|March|April|May|June|July|August|September|October|November|December)|(0?[1-9]|1[0-2]))\\.([0-2][0-9][0-9][0-9])|([0-2][0-9][0-9][0-9])\\.((Jan|jan|Feb|feb|Mar|mar|Apr|apr|May|may|Jun|jun|Jul|jul|Aug|aug|Sep|sep|Oct|oct|Nov|nov|Dec|dec|January|February|March|April|May|June|July|August|September|October|November|December)|(0?[1-9]|1[0-2]))\\.([1-9]|[1-2][0-9]|0[1-9]|3[0-1])|((Mon|Monday|Tue|Tuesday|Wed|Wednesday|Thu|Thursday|Fri|Friday|Sat|Saturday|Sun|Sunday|mon|tue|wed|thu|fri|sat|sun),?[ \\t]+)?(Jan|jan|Feb|feb|Mar|mar|Apr|apr|May|may|Jun|jun|Jul|jul|Aug|aug|Sep|sep|Oct|oct|Nov|nov|Dec|dec|January|February|March|April|May|June|July|August|September|October|November|December)[ \\t]+([1-9]|[1-2][0-9]|0[1-9]|3[0-1])(,[ \\t]+([0-2][0-9][0-9][0-9]))?|((Mon|Monday|Tue|Tuesday|Wed|Wednesday|Thu|Thursday|Fri|Friday|Sat|Saturday|Sun|Sunday|mon|tue|wed|thu|fri|sat|sun),?[ \\t]+)?([1-9]|[1-2][0-9]|0[1-9]|3[0-1])[ \\t]+(Jan|jan|Feb|feb|Mar|mar|Apr|apr|May|may|Jun|jun|Jul|jul|Aug|aug|Sep|sep|Oct|oct|Nov|nov|Dec|dec|January|February|March|April|May|June|July|August|September|October|November|December)(,[ \\t]+([0-2][0-9][0-9][0-9]))?")  (* slow *) 
       , ( Pip "", "([0-9]+)\\.([0-9]+)\\.([0-9]+)\\.([0-9]+)")
       , ( Phostname "", "(([0-9A-Za-z_][A-Za-z0-9_\\-]*)+\\.(com|net|edu|org|gov|co|ac|mil|info|int)(\\.[a-zA-Z][a-zA-Z])?|(([0-9A-Za-z_][A-Za-z0-9_\\-]*)\\.)+[a-zA-Z][a-zA-Z]+)")
       , ( Pemail "", "([0-9a-zA-Z\\-_+][0-9a-zA-Z\\-_+.]*)@((([0-9A-Za-z_][A-Za-z0-9_\\-]*)\\.)+([0-9A-Za-z_][A-Za-z0-9_\\-]*))")
       , ( Pmac "", "(([0-9a-fA-F][0-9a-fA-F])(:|\\-))+([0-9a-fA-F][0-9a-fA-F])")
(*       , ( Ppath, "(\\/([^\\/\\\\?*:<>\"\\[\\] ]+))(\\/([^\\/\\\\?*:<>\"\\[\\] ]+))*\\/?|(([^\\/\\\\?*:<>\"\\[\\] ]+)\\/)(([^\\/\\\\?*:<>\"\\[\\] ]+)\\/)*([^\\/\\\\?*:<>\"\\[\\] ]+)?|\\\\?(\\\\([^\\/\\\\?*:<>\"\\[\\] ]+))(\\\\([^\\/\\\\?*:<>\"\\[\\] ]+))*\\\\?|(([^\\/\\\\?*:<>\"\\[\\] ]+)\\\\)(([^\\/\\\\?*:<>\"\\[\\] ]+)\\\\)*([^\\/\\\\?*:<>\"\\[\\] ]+)?|([^\\/\\\\?*:<>\"\\[\\] ]+)|\\/([^\\/\\\\?*:<>\"\\[\\] ]+)|\\\\([^\\/\\\\?*:<>\"\\[\\] ]+)|\\/|\\\\") (* slow *) *)

       , ( Ppath "", "\\/([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*)?\\/([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*)?(\\/([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*)?)*\\/?|([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*)\\/([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*)?\\/(([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*)?\\/)*([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*)?|\\\\([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*)?\\\\([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*)?(\\\\([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*)?)*\\\\?|([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*)\\\\([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*)?\\\\(([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*)?\\\\)*([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*)?|(http|ftp|https):\\/\\/(((([0-9A-Za-z_][A-Za-z0-9_\\-]*)\\.)+([0-9A-Za-z_][A-Za-z0-9_\\-]*))|([0-9A-Za-z_][A-Za-z0-9_\\-]*))(:([1-9][0-9]*))?\\/?([^<>{}|\\^\\[\\] \\t\\n\\r\"()'])*|(\\/([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*))+\\;([A-Za-z][A-Za-z0-9_\\-]*)=([A-Za-z][A-Za-z0-9_\\-]*)\\?([^<>{}|\\^\\[\\] \\t\\n\\r\"()'])*|(\\/([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*))+\\;([A-Za-z][A-Za-z0-9_\\-]*)=([A-Za-z][A-Za-z0-9_\\-]*)|(\\/([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*))+\\/?\\?([^<>{}|\\^\\[\\] \\t\\n\\r\"()'])*")

(*(*(*(*(*(*(* *)*)*)*)*)*)*)
       , ( Purl "", "(http|ftp|https):\\/\\/((([0-9A-Za-z_][A-Za-z0-9_\\-]*)\\.)+([0-9A-Za-z_][A-Za-z0-9_\\-]*))(:([1-9][0-9]*))?\\/?[^ \\t\\n\\r\"()']*|(\\/([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*))+\\;([A-Za-z][A-Za-z0-9_\\-]*)=([A-Za-z][A-Za-z0-9_\\-]*)\\?[^ \\t\\n\\r\"()']*|(\\/([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*))+\\;([A-Za-z][A-Za-z0-9_\\-]*)=([A-Za-z][A-Za-z0-9_\\-]*)|(\\/([0-9A-Za-z_.][A-Za-z0-9_\\-.*%'&]*))+\\?[^ \\t\\n\\r\"()']*")
(* extremely slow *) 
(*(*(*(*(*(*(* *)*)*)*)*)*)*)
(*       , ( PbXML, "\\<([a-zA-Z])+\\>")
       , ( PeXML, "\\<\\/[^>]+\\>") *) 
       , ( Pwhite "", "[ \\t\\r\\n]+") 
       , ( Ptext "", "([\"'])([A-Za-z0-9_,;. ]|(\\-))+([\"'])")
       , ( Pstring "", "[A-Za-z][A-Za-z0-9_\\-]*")
]

end

