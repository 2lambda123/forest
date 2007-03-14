structure Hosts = struct

    val hostnames = [ "ac"
                    , "ad"
                    , "ae"
                    , "aero"
                    , "af"
                    , "ag"
                    , "ai"
                    , "al"
                    , "am"
                    , "an"
                    , "ao"
                    , "aq"
                    , "ar"
                    , "arpa"
                    , "as"
                    , "at"
                    , "au"
                    , "aw"
                    , "az"
                    , "ba"
                    , "bb"
                    , "bd"
                    , "be"
                    , "bf"
                    , "bg"
                    , "bh"
                    , "bi"
                    , "biz"
                    , "bj"
                    , "bm"
                    , "bn"
                    , "bo"
                    , "br"
                    , "bs"
                    , "bt"
                    , "bv"
                    , "bw"
                    , "by"
                    , "bz"
                    , "ca"
                    , "cc"
                    , "cf"
                    , "cg"
                    , "ch"
                    , "ci"
                    , "ck"
                    , "cl"
                    , "cm"
                    , "cn"
                    , "co"
                    , "com"
                    , "coop"
                    , "cr"
                    , "cs"
                    , "cu"
                    , "cv"
                    , "cx"
                    , "cy"
                    , "cz"
                    , "de"
                    , "dj"
                    , "dk"
                    , "dm"
                    , "do"
                    , "dz"
                    , "ec"
                    , "edu"
                    , "ee"
                    , "eg"
                    , "eh"
                    , "er"
                    , "es"
                    , "et"
                    , "eu"
                    , "fi"
                    , "firm"
                    , "fj"
                    , "fk"
                    , "fm"
                    , "fo"
                    , "fr"
                    , "fx"
                    , "ga"
                    , "gb"
                    , "gd"
                    , "ge"
                    , "gf"
                    , "gh"
                    , "gi"
                    , "gl"
                    , "gm"
                    , "gn"
                    , "gov"
                    , "gp"
                    , "gq"
                    , "gr"
                    , "gs"
                    , "gt"
                    , "gu"
                    , "gw"
                    , "gy"
                    , "hk"
                    , "hm"
                    , "hn"
                    , "hr"
                    , "ht"
                    , "hu"
                    , "id"
                    , "ie"
                    , "il"
                    , "in"
                    , "info"
                    , "int"
                    , "io"
                    , "iq"
                    , "ir"
                    , "is"
                    , "it"
                    , "jm"
                    , "jo"
                    , "jobs"
                    , "jp"
                    , "ke"
                    , "kg"
                    , "kh"
                    , "ki"
                    , "km"
                    , "kn"
                    , "kp"
                    , "kr"
                    , "kw"
                    , "ky"
                    , "kz"
                    , "la"
                    , "lb"
                    , "lc"
                    , "li"
                    , "lk"
                    , "lr"
                    , "ls"
                    , "lt"
                    , "lu"
                    , "lv"
                    , "ly"
                    , "ma"
                    , "mc"
                    , "md"
                    , "mg"
                    , "mh"
                    , "mil"
                    , "mk"
                    , "ml"
                    , "mm"
                    , "mn"
                    , "mo"
                    , "mp"
                    , "mq"
                    , "mr"
                    , "ms"
                    , "mt"
                    , "mu"
                    , "museum"
                    , "mv"
                    , "mw"
                    , "mx"
                    , "my"
                    , "mz"
                    , "na"
                    , "name"
                    , "nato"
                    , "nc"
                    , "ne"
                    , "net"
                    , "nf"
                    , "ng"
                    , "ni"
                    , "nl"
                    , "no"
                    , "nom"
                    , "np"
                    , "nr"
                    , "nt"
                    , "nu"
                    , "nz"
                    , "om"
                    , "org"
                    , "pa"
                    , "pe"
                    , "pf"
                    , "pg"
                    , "ph"
                    , "pk"
                    , "pl"
                    , "pm"
                    , "pn"
                    , "pr"
                    , "pro"
                    , "pt"
                    , "pw"
                    , "py"
                    , "qa"
                    , "re"
                    , "ro"
                    , "ru"
                    , "rw"
                    , "sa"
                    , "sb"
                    , "sc"
                    , "sd"
                    , "se"
                    , "sg"
                    , "sh"
                    , "si"
                    , "sj"
                    , "sk"
                    , "sl"
                    , "sm"
                    , "sn"
                    , "so"
                    , "sr"
                    , "st"
                    , "store"
                    , "su"
                    , "sv"
                    , "sy"
                    , "sz"
                    , "tc"
                    , "td"
                    , "tf"
                    , "tg"
                    , "th"
                    , "tj"
                    , "tk"
                    , "tm"
                    , "tn"
                    , "to"
                    , "tp"
                    , "tr"
                    , "travel"
                    , "tt"
                    , "tv"
                    , "tw"
                    , "tz"
                    , "ua"
                    , "ug"
                    , "uk"
                    , "um"
                    , "us"
                    , "uy"
                    , "va"
                    , "vc"
                    , "ve"
                    , "vg"
                    , "vi"
                    , "vn"
                    , "vu"
                    , "web"
                    , "wf"
                    , "ws"
                    , "ye"
                    , "yt"
                    , "yu"
                    , "za"
                    , "zm"
                    , "zr"
                    , "zw"
                    ]

    exception TooBig
    fun isDomainName ( s : string ) : bool =
        let fun search ( s : string ) ( low : int ) ( high : int ) ( n : int ) : bool =
            let val mid = low + ( ( high - low ) div 2 )
                val dom = List.nth ( hostnames, mid )
            in if n > 9
               then raise TooBig
               else if dom = s
                    then true
                    else if low >= high
                         then false
                         else if s < dom
                              then search s low ( mid - 1 ) ( n + 1 )
                              else search s ( mid + 1 ) high ( n + 1 )
            end
        in search s 0 ( length hostnames - 1 ) 0
        end

end
