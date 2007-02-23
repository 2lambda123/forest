structure Tokens = struct
    open Complexity
    open Distribution

    exception BadToken      (* For functions defined on some of the tokens *)
    exception XMLToken      (* Don't know how to handle these yet *)
    exception LargeIntToken (* Don't know how to handle these yet *)
    exception GroupToken    (* Don't know how to handle these yet *)
    exception ErrorToken    (* Don't know how to handle these yet *)

    type location = { lineNo: int, beginloc: int, endloc:int }

    (* Establish an order on locations *)
    fun compLocation (l1:location, l2:location):order =
        let val {lineNo = ln1, beginloc = b1, endloc = e1} = l1
            val {lineNo = ln2, beginloc = b2, endloc = e2} = l2
        in ( case Int.compare (ln1, ln2) of
                  LESS    => LESS
                | GREATER => GREATER
                | EQUAL   => ( case Int.compare (b1, b2) of
                                    LESS    => LESS
                                  | GREATER => GREATER
                                  | EQUAL   => Int.compare (e1, e2)
                             )
           )
        end

    (* Number of possible ASCII characters for string values, according
       to the definition in tokens.lex
     *)
    val numStringChars : int = 26 + 26 + 10 + 1 + 1
    val probStringChar : real = 1.0 / Real.fromInt numStringChars
    val numWhiteChars  : int = 2 (* Space and tab *)
    val probWhiteChar  : real = 1.0 / Real.fromInt numStringChars

    (* Raw token format, pass one over the data *)
    datatype Token = PbXML of string * string |
                     PeXML of string * string |
	             Ptime of string | 
		     Pmonth of string | 
		     Pip of string | 
                     Pint of LargeInt.int | 
		     Pstring of string | 
                     Pgroup of {left : LToken, body : LToken list, right : LToken} | 
	             Pwhite of string | 
		     Other of char | 
		     Pempty | 
		     Error
    withtype LToken = Token * location

    (*    Establish an order on Token using the following constraints:
          Ptime < Pmonth < Pip < PbXML < PeXML < Pint < Pstring < Pgroup <
          Pwhite < Other < Pempty < Error
     *)
    fun compToken (t1:Token, t2:Token):order = 
	case (t1,t2) of
           (Ptime i1, Ptime i2)           => EQUAL
        |  (Pmonth i1, Pmonth i2)         => EQUAL
        |  (Pip i1, Pip i2)               => EQUAL
        |  (PbXML (f1,s1), PbXML (f2,s2)) => String.compare(f1,f2)
        |  (PeXML (f1,s1), PeXML (f2,s2)) => String.compare(f1,f2)
        |  (Pint i1, Pint i2)             => EQUAL
        |  (Pstring s1, Pstring s2)       => EQUAL
        |  (Pwhite s1, Pwhite s2)         => EQUAL
        |  (Pgroup g1, Pgroup g2)         => compToken(#1(#left g1), (#1(#left g2)))
        |  (Other c1, Other c2)           => Char.compare (c1, c2)
        |  (Pempty, Pempty)               => EQUAL
        |  (Error, Error)                 => EQUAL
        |  (Ptime _, _)                   => LESS
        |  (Pmonth _, Ptime _)            => GREATER
        |  (Pmonth _, _)                  => LESS
        |  (Pip _, Ptime _)               => GREATER
        |  (Pip _, Pmonth _)              => GREATER
        |  (Pip _, _)                     => LESS
        |  (PbXML _, Ptime _ )            => GREATER
        |  (PbXML _, Pmonth _)            => GREATER
        |  (PbXML _, Pip _)               => GREATER
        |  (PbXML _,  _)                  => LESS
        |  (PeXML _, Ptime _ )            => GREATER
        |  (PeXML _, Pmonth _)            => GREATER
        |  (PeXML _, Pip _)               => GREATER
        |  (PeXML _, PbXML _)             => GREATER
        |  (PeXML _,  _)                  => LESS
        |  (Pint _, Ptime _)              => GREATER
        |  (Pint _, Pmonth _)             => GREATER
        |  (Pint _, Pip _)                => GREATER
        |  (Pint _, PbXML _)              => GREATER
        |  (Pint _, PeXML _)              => GREATER
        |  (Pint _, _)                    => LESS
        |  (Pstring _, Ptime _)           => GREATER
        |  (Pstring _, Pmonth _)          => GREATER
        |  (Pstring _, Pip _)             => GREATER
        |  (Pstring _, Pint _)            => GREATER
        |  (Pstring _, PbXML _)           => GREATER
        |  (Pstring _, PeXML _)           => GREATER
        |  (Pstring _,  _)                => LESS
        |  (Pgroup _, Ptime _)            => GREATER
        |  (Pgroup _, Pmonth _)           => GREATER
        |  (Pgroup _, Pip _)              => GREATER
        |  (Pgroup _, Pint _)             => GREATER
        |  (Pgroup _, Pstring _)          => GREATER
        |  (Pgroup _, PbXML _)            => GREATER
        |  (Pgroup _, PeXML _)            => GREATER
        |  (Pgroup _,  _)                 => LESS
        |  (Pwhite _, Ptime _)            => GREATER
        |  (Pwhite _, Pmonth _)           => GREATER
        |  (Pwhite _, Pip _)              => GREATER
        |  (Pwhite _, Pint _)             => GREATER
        |  (Pwhite _, Pstring _)          => GREATER
        |  (Pwhite _, Pgroup _)           => GREATER
        |  (Pwhite _, PbXML _)            => GREATER
        |  (Pwhite _, PeXML _)            => GREATER
        |  (Pwhite _, _)                  => LESS
        |  (Other _, Ptime _)             => GREATER
        |  (Other _, Pmonth _)            => GREATER
        |  (Other _, Pip _)               => GREATER
        |  (Other _, Pint _)              => GREATER
        |  (Other _, Pstring _)           => GREATER
        |  (Other _, Pgroup _)            => GREATER
        |  (Other _, Pwhite _)            => GREATER
        |  (Other _, PbXML _)             => GREATER
        |  (Other _, PeXML _)             => GREATER
        |  (Other _, _)                   => LESS
        |  (Pempty, Ptime _)              => GREATER
        |  (Pempty, Pmonth _)             => GREATER
        |  (Pempty, Pip _)                => GREATER
        |  (Pempty, Pint _)               => GREATER
        |  (Pempty, Pstring _)            => GREATER
        |  (Pempty, Pgroup _)             => GREATER
        |  (Pempty, Pwhite _)             => GREATER
        |  (Pempty, Other _)              => GREATER
        |  (Pempty, PbXML _)              => GREATER
        |  (Pempty, PeXML _)              => GREATER
        |  (Pempty, _)                    => LESS
        |  (Error, _)                     => GREATER

    (* Establish an order on LTokens based on the order on Tokens *)
    fun compLToken (ltok1:LToken, ltok2:LToken):order =
        let val (t1,l1) = ltok1
            val (t2,l2) = ltok2
        in ( case compToken (t1, t2) of
                    LESS    => LESS
                  | GREATER => GREATER
                  | EQUAL   => compLocation (l1, l2)
           )
        end

    (* Mapping having LTokens as a domain *)
    structure LTokenMap = RedBlackMapFn ( struct type ord_key = LToken
                                                 val  compare = compLToken
                                          end
                                        )
    (* Mapping from LTokens to frequency *)
    type LTokenFreq = int LTokenMap.map
    val emptyLTokenFreq : LTokenFreq = LTokenMap.empty
    fun addLTokenFreq (t:LToken, f:LTokenFreq):LTokenFreq =
        ( case LTokenMap.find (f,t) of
               NONE   => f
             | SOME n => LTokenMap.insert (f,t,n+1)
        )

    fun tokenOf (t:LToken):Token = #1 t
    fun tokenLength (t:Token):int =
        ( case t of
               PbXML (s1, s2) => raise XMLToken
             | PeXML (s1, s2) => raise XMLToken
             | Ptime s        => size s
             | Pmonth s       => size s
             | Pip s          => size s
             | Pint n         => raise LargeIntToken
             | Pstring s      => size s
             | Pgroup grp     => raise GroupToken
             | Pwhite s       => size s
             | Other c        => 1
             | Pempty         => 0
             | Error          => raise ErrorToken
        )

    fun lTokenLength (t:LToken):int = tokenLength (tokenOf t)

    (* Calculate the maximum token length
     * This number is probably garbage unless all the tokens in the
       list are of the same type.
     *)
    fun maxTokenLength ( ts : LToken list ) : int =
        foldl (fn (t:LToken,x:int) => Int.max (x, lTokenLength t)) 0 ts

    (* A record is a special kind of list of tokens *)
    type Record = Token list

    (* Distributions must consider a list of tokens, for example when
       dealing with a structure. The *clump* is our grouping concept
       for tokens.
     *)
    datatype Clump = EmptyClump
                   | BasicClump         of Token
                   | BoundedClump       of Token list * int
                   | UnboundedClump     of Token list
                   | SingletonMetaClump of Clump
                   | BoundedMetaClump   of Clump list * int
                   | UngoundedMetaClump of Clump list

    type Model = Clump Density
    fun junkModel ( c : Clump ) : Model =
       fn ( u : Clump ) => if u = c then 1.0 else 0.0

end
