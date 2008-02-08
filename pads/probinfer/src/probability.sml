structure Probability = 
struct
    open Basetokens

    fun loadFile path = 
     let 
       val strm = TextIO.openIn path
	   val data : String.string = TextIO.inputAll strm
       fun isNewline c = c = #"\n" orelse c = #"\r"
       fun getLines(ss,l) = 
         if (Substring.isEmpty ss) then List.rev l
	     else let 
                val (ln, rest) = Substring.splitl (not o isNewline) ss
                val rest = (case Substring.getc rest
				    of NONE => rest
				    |  SOME(#"\n", rest) => rest (* UNIX EOR discipline *)
				    |  SOME(#"\r", rest) => 
					(case Substring.getc rest 
					 of SOME(#"\n", rest) => rest (* DOS EOR discipline *)
                                         |  _ => rest (* Mac OS EOR discipline *))
			            | _ => rest (* This case is impossible because of the def if isNewline *))
		       in
			     getLines(rest, (Substring.string ln)::l)
		       end
       val lines = getLines ( Substring.full data, [])
	   val () = TextIO.closeIn strm
     in
	   lines
     end

    fun tstringToBToken (s, str) : BToken =
      if String.isSubstring "int" s then PPint
      else if String.isSubstring "float" s then PPfloat
      else if String.isSubstring "time" s then PPtime
      else if String.isSubstring "date" s then PPdate
      else if String.isSubstring "ip" s then PPip
      else if String.isSubstring "hostname" s then PPhostname
      else if String.isSubstring "email" s then PPemail
      else if String.isSubstring "mac" s then PPmac
      else if String.isSubstring "path" s then PPpath
      else if String.isSubstring "urlbody" s then PPurlbody
      else if String.isSubstring "url" s then PPurl  (* although url is a substring of urlbody, if the above case is true, we won't branch here *)
      else if String.isSubstring "word" s then PPword
      else if String.isSubstring "id" s then PPid
      else if String.isSubstring "bXML" s then PPbXML
      else if String.isSubstring "eXML" s then PPeXML
      else if String.isSubstring "white" s then ((*if String.compare(" ", str)=EQUAL then print "white\n" else ();*)PPwhite)
      else if String.isSubstring "message" s then PPmessage
      else if String.isSubstring "permission" s then PPpermission      
      else if String.isSubstring "blob" s then PPblob
      else if String.isSubstring "punc" s then (if (String.size str)=1 then (PPpunc str) else PPblob)
      else if String.isSubstring "text" s then PPtext
      else if String.isSubstring "lit" s then (
        case s of 
            "," => PPpunc ","
          | "." => PPpunc "."
          | " " => PPwhite
          | _ => PPblob
      )
      else PPblob

    exception CPtagError

    fun extractLog path : (BToken*string) list list = 
      let
        val files : string list = loadFile "/n/fs/pads/pads/probinfer/training/log/log.list"
        fun loadOne (str, ret) = 
          if Char.compare(#"#", String.sub(str, 0))=EQUAL then ret
          else ret@(loadFile (path^str))
        val data : string list = List.foldl loadOne [] files
(*  val _ = List.app print data *)
        fun splitRec (d, l): string list list =
          case d of
            [] => List.take(l, (List.length l)-1)
           |hd::tl => if String.compare(hd, "EOR")=EQUAL then splitRec (tl, l@[[]])
                      else  
                        let
                          val wl = List.nth(l, (List.length l)-1) 
                        in
                          splitRec (tl, List.take(l, (List.length l)-1)@[(wl@[hd])])
                        end

        val splitd = splitRec(data, [[]])
(* val _ = List.app print (List.nth(splitd, 0)) *)
        fun constrOneRecord d : (BToken*string) list =
          let
            fun constrOneToken (t, (ret, cptagl)) =
            if (String.size t)=0 then (ret, cptagl)
            else (
              if String.compare(t, "CheckPoint")=EQUAL then (
                let
                  val thiscptag = List.hd cptagl
                in
                  if thiscptag<>0 then (ret, 1::cptagl)   (* nested checkpoint, need to create a new entry *) 
                  else (ret, [1])
                end 
                )
              else if String.compare(t, "Rollback")=EQUAL then (
                let
                  val thiscptag = List.hd cptagl
                  val nested = List.length cptagl
                in
                  if thiscptag<1 then raise CPtagError
                  else if thiscptag=1 then (
                    if nested=1 then (ret, [0])
                    else (ret, List.drop(cptagl, 1))
                  )
                  else ( 
                    if nested=1 then (List.drop(ret, thiscptag-1), [0])
                        else (
                          let
                            val subv = thiscptag-1
                            fun subOne i = i-thiscptag+1
                          in
                            (List.drop(ret, thiscptag-1), List.map subOne (List.drop(cptagl, 1)))
                          end)
                  )
                end
                )
              else if String.compare(t, "Commit")=EQUAL then (
                let
                  val thiscptag = List.hd cptagl
                  val nested = List.length cptagl
                in
                  if thiscptag<1 then raise CPtagError
                  else (
                    if nested=1 then (ret, [0])
                    else (ret, List.drop(cptagl, 1))
                  )
                end
                )
              else         
                let 
                  fun isColon c = c = #":"
                  val (junk1, dataString) = Substring.splitr (not o isColon) (Substring.full t)
                  val (tokenName, junk2) = Substring.splitl (not o isColon) (Substring.full t)
                in
                  if Substring.compare(dataString, Substring.full "Rollback")=EQUAL then (
                    let
                      val thiscptag = List.hd cptagl
                      val nested = List.length cptagl
                    in
                      if thiscptag<1 then raise CPtagError
                      else if thiscptag=1 then (
                        if nested=1 then (ret, [0])
                        else (ret, List.drop(cptagl, 1))
                      )
                      else (
                        if nested=1 then (List.drop(ret, thiscptag-1), [0])
                        else (
                          let
                            val subv = thiscptag-1
                            fun subOne i = i-thiscptag+1
                          in
                            (List.drop(ret, thiscptag-1), List.map subOne (List.drop(cptagl, 1)))
                          end)
                      )
                    end
                  )
                  else if Substring.compare(dataString, Substring.full "CheckPoint")=EQUAL then (
                    let
                      val thiscptag = List.hd cptagl
                    in
                      if thiscptag<>0 then (ret, 1::cptagl)
                      else (ret, [1])
                    end 
                    )
                  else ( (*print ((Substring.string tokenName)^"\n");*)
                    let
                      val thiscptag = List.hd cptagl
                      fun addOne i = i+1
                    (*  val _ = if ((Substring.size dataString)=0) then (print (Int.toString (String.size t));print t; raise CPtagError) else () *) 
                      val newdataString = 
                        if (Substring.size dataString)=0 then (
                          let val (s1, s2) = Substring.splitr (not o isColon) junk1 in (Substring.full ((Substring.string s2)^":")) end
                        )
                        else dataString
                    in
                      if (Substring.size newdataString)=0 then (ret, cptagl)
                      else (
                      if thiscptag>0 then  
                      ((tstringToBToken(Substring.string tokenName, Substring.string newdataString), 
                        Substring.string newdataString)::ret, List.map addOne cptagl)
                      else 
                      ((tstringToBToken(Substring.string tokenName, Substring.string newdataString), 
                        Substring.string newdataString)::ret, cptagl)
                      )
                    end
                    )
                end
              )  
(*
val (s1, s2) = List.nth ((List.foldl constrOneToken [] d), 0)
val _ = print s1 
*)
            val (revtable, retag) = List.foldl constrOneToken ([], [0]) d     
          in
            List.rev(revtable)
          end
      in
        List.map constrOneRecord splitd
      end

    fun BTokenPairComp ((t1a,t1b), (t2a,t2b)) = 
	let val r1 = compBToken (t1a, t2a)
	in
	    if  r1 = EQUAL then compBToken (t1b, t2b) else r1
	end

    structure BTokenPairTable = RedBlackMapFn(
                     struct type ord_key = BToken * BToken
			    val compare = BTokenPairComp
		     end) 

    structure BTokenTable = RedBlackMapFn(
                     struct type ord_key = BToken
			    val compare = compBToken
		     end)  

    fun compList (l1, l2) = 
      case Int.compare(List.length l1, List.length l2) of
          GREATER => GREATER
        | LESS => LESS
        | EQUAL => let
                     val len = List.length l1
                     val concat = l1@l2
                     fun comp (i, (rest, ord)) = 
                       case ord of
                           EQUAL => (List.drop(rest, 1), Int.compare(i, List.nth(rest, len)))
                         | GREATER => (rest, GREATER)
                         | LESS => (rest, LESS)
                     val (junk, order) = List.foldl comp (concat, EQUAL) l1 
                   in
                     order
                   end

    fun ListBTokenPairComp ((t1a,t1b), (t2a,t2b)) = 
	let val r1 = compBToken (t1b, t2b)
	in
	    if  r1 = EQUAL then compList (t1a, t2a) else r1
	end

    structure ListBTokenPairTable = RedBlackMapFn(
                     struct type ord_key = (int list)*BToken
			    val compare = ListBTokenPairComp
		     end)  

(* char-by-char HMM: there're 3 tables to construct.
   (t1, t2), (c vector, t), t
*)

    exception stringSizeError

    fun constrTokenTable l = 
      let
        fun countOne (tslist, btokentable) = 
          let
(*            val _ = if List.length tslist = 0 then print "Error\n" else () *)
            fun countOneToken ((btoken, str), btt) =
              let
                val num = String.size str
                val oldnum = BTokenTable.find(btt, btoken)
              in
                if num=0 then (print (BTokenToName btoken); raise stringSizeError)
                else (
                  case oldnum of
                      NONE => BTokenTable.insert(btt, btoken, num)
                    | SOME n => (
                        let
                          val (newtable, junk) = BTokenTable.remove(btt, btoken)
                        in
                          BTokenTable.insert(newtable, btoken, num+n)
                        end
                      )
                )
              end
          in
            List.foldl countOneToken btokentable tslist
          end
      in
        List.foldl countOne BTokenTable.empty l
      end

    fun constrTokenPairTable l = 
      let
        fun countOne (tslist, btokenpairtable) = 
          let
            fun countOneToken ((btoken, str), (pre, btt)) =
              let
                val length = String.size str
                val thistable = ref btt
              in
                ((
                case pre of
                    SOME pretoken => ( 
                      let
                        val firstoldn = BTokenPairTable.find(btt, (pretoken, btoken))
                        val _ = if length=0 then raise stringSizeError else ()
                      in 
                        thistable := (case firstoldn of
                                             NONE => BTokenPairTable.insert(btt, (pretoken, btoken), 1)
                                           | SOME n => (
                                               let
                                                 val (newtable, junk) = BTokenPairTable.remove(btt, (pretoken, btoken))
                                               in
                                                 BTokenPairTable.insert(newtable, (pretoken, btoken), n+1)
                                               end
                                             ))
                      end
                    )
                  | NONE => ());
                if length=1 then (SOME btoken, !thistable)
                else (
                  case BTokenPairTable.find(!thistable, (btoken, btoken)) of
                      NONE => (SOME btoken, BTokenPairTable.insert(!thistable, (btoken, btoken), length-1))
                    | SOME n => (
                        let
                          val (newtable, junk) = BTokenPairTable.remove(!thistable, (btoken, btoken))
                        in
                          (SOME btoken, BTokenPairTable.insert(newtable, (btoken, btoken), n+length-1))
                        end
                      )
                ))
              end
            val (junk, tableret) = List.foldl countOneToken (NONE, btokenpairtable) tslist
          in
            tableret
          end
      in
        List.foldl countOne BTokenPairTable.empty l
      end

    fun constrBeginTokenTable l = 
      let
        fun countOne (tslist, btokentable) = 
          let
(*            val _ = if List.length tslist = 0 then print "Error\n" else () *)
            val (first, str) = List.nth(tslist, 0)
            val pre = BTokenTable.find(btokentable, first)
          in
            case pre of
                NONE => BTokenTable.insert(btokentable, first, 1)
              | SOME n => (
                  let 
                    val (newtable, junk) = BTokenTable.remove(btokentable, first)
                  in
                    BTokenTable.insert(newtable, first, n+1)
                  end
                  )
          end
      in
        List.foldl countOne BTokenTable.empty l
      end

    fun constrEndTokenTable l = 
      let
        fun countOne (tslist, btokentable) = 
          let
            val (last, str) = List.nth(tslist, (List.length tslist)-1)
            val pre = BTokenTable.find(btokentable, last)
          in
            case pre of
                NONE => BTokenTable.insert(btokentable, last, 1)
              | SOME n => (
                  let 
                    val (newtable, junk) = BTokenTable.remove(btokentable, last)
                  in
                    BTokenTable.insert(newtable, last, n+1)
                  end
                  )
          end
      in
        List.foldl countOne BTokenTable.empty l
      end

(* feature vector: upper-case? lower-case? digit? punc? whitespace? "."? ","? """? *)
    fun charToList c : int list = 
      let
        val upper = if Char.isUpper c then [1] else [0]
        val lower = if Char.isLower c then 1::upper else 0::upper
        val digit = if Char.isDigit c then 1::lower else 0::lower
        val punct = if Char.isPunct c orelse Char.isSpace c then 1::digit else 0::digit
        val space = if Char.isSpace c then 1::punct else 0::punct
        val dot = if Char.compare(c, #".")=EQUAL then 1::space else 0::space
        val comma = if Char.compare(c, #",")=EQUAL then 1::dot else 0::dot
        val quest = if Char.compare(c, #"?")=EQUAL then 1::comma else 0::comma
        val quote = if Char.compare(c, #"\"")=EQUAL then 1::quest else 0::quest
      in
        List.rev quote
      end

    fun constrListTokenTable l = 
      let
        fun countOne (tslist, btokentable) = 
          let
            fun countOneToken ((btoken, str), btt) =
              let
                fun countOneChar (c, btt) =
                  let
                    val v = charToList c
                  in
                    case ListBTokenPairTable.find(btt, (v, btoken)) of
                        NONE => ListBTokenPairTable.insert(btt, (v, btoken), 1)
                      | SOME n => (
                          let
                            val (newtable, junk) = ListBTokenPairTable.remove(btt, (v, btoken))
                          in
                            ListBTokenPairTable.insert(btt, (v, btoken), n+1)
                          end
                        )
                  end
              in
                List.foldl countOneChar btt (String.explode str) 
              end
          in
            List.foldl countOneToken btokentable tslist
          end
      in
        List.foldl countOne ListBTokenPairTable.empty l
      end

    fun dumpCCHMM ( path : string ) : unit = 
        let 
          val _ = print ("Printing char-by-char HMM to files under "^path^"\n")
          val list = extractLog "/n/fs/pads/pads/probinfer/training/log/";
          val table1 = constrTokenTable list
(*          val _ = print "1\n" *)
          val table2 = constrTokenPairTable list
(*          val _ = print "2\n" *)
          val table3 = constrListTokenTable list
(*          val _ = print "3\n" *)
          val table4 = constrBeginTokenTable list
(*          val _ = print "4\n" *)
          val table5 = constrEndTokenTable list
(*          val _ = print "5\n" *)
          fun dumpToken t = 
            let
	          val strm = TextIO.openOut (path^"TokenCount")
              val outlist = BTokenTable.listItemsi table1
              fun output (bt, i) = TextIO.output(strm, (BTokenToName bt)^"="^(Int.toString i)^"\n")  
              val _ = List.map output outlist
            in
              TextIO.closeOut strm 
            end
          fun dumpTokenPair t = 
            let
	          val strm = TextIO.openOut (path^"TokenPairCount")
              val outlist = BTokenPairTable.listItemsi table2
              fun output ((bt1,bt2), i) = TextIO.output(strm, ((BTokenToName bt1)^" "^(BTokenToName bt2)^"="^(Int.toString i)^"\n"))  
              val _ = List.map output outlist
            in
              TextIO.closeOut strm 
            end
          fun dumpListToken t = 
            let
	          val strm = TextIO.openOut (path^"CharTokenCount")
              val outlist = ListBTokenPairTable.listItemsi table3
              fun listToString il = 
                let
                  fun foo (i, ret) = ret^(Int.toString i)
                in
                  List.foldl foo "" il
                end
              fun output ((l, bt), i) = TextIO.output(strm, (listToString l)^" "^(BTokenToName bt)^"="^(Int.toString i)^"\n")  
              val _ = List.map output outlist
            in
              TextIO.closeOut strm 
            end
          fun dumpBeginToken t = 
            let
	          val strm = TextIO.openOut (path^"BeginTokenCount")
              val outlist = BTokenTable.listItemsi table4
              fun output (bt, i) = TextIO.output(strm, (BTokenToName bt)^"="^(Int.toString i)^"\n")  
              val _ = List.map output outlist
            in
              TextIO.closeOut strm 
            end
          fun dumpEndToken t = 
            let
	          val strm = TextIO.openOut (path^"EndTokenCount")
              val outlist = BTokenTable.listItemsi table5
              fun output (bt, i) = TextIO.output(strm, (BTokenToName bt)^"="^(Int.toString i)^"\n")  
              val _ = List.map output outlist
            in
              TextIO.closeOut strm 
            end
          fun dumpInitProb t = 
            let
	          val strm = TextIO.openOut (path^"InitProb")
              val outlist = BTokenTable.listItemsi table4
              fun sumAll ((bt, i), ret) = ret+i
              val sum = List.foldl sumAll 0 outlist
              val wholelist = BTokenMapF.listItemsi btokentable
              fun output (bt, s) = 
                case BTokenTable.find(table4, bt) of
                    NONE => TextIO.output(strm, "0.0\n")
                  | SOME n => TextIO.output(strm, (Real.toString ((Real.fromInt n)/(Real.fromInt sum)))^"\n") 
              val _ = List.app output wholelist
            in
              TextIO.closeOut strm 
            end
          fun dumpTransProb t = 
            let
	          val strm = TextIO.openOut (path^"TransProb")
              val wholelist = BTokenMapF.listItemsi btokentable
              fun output (bt1, s1) = 
                let
                  fun outputin ((bt2, s2), ret) =
                    case BTokenPairTable.find(table2, (bt1, bt2)) of
                        NONE => ret^"0 "
                      | SOME n => ret^Real.toString((Real.fromInt n)/(Real.fromInt (Option.valOf(BTokenTable.find(table1, bt1)))))^" "
                  val outputstrm = List.foldl outputin "" wholelist
                in
                  TextIO.output(strm, outputstrm^"\n")
                end 
              val _ = List.app output wholelist
            in
              TextIO.closeOut strm 
            end
          fun dumpEmitProb t = 
            let
	          val strm = TextIO.openOut (path^"EmitProb")
              fun constrList i =
                let
                  val bit8 = if i-256>=0 then 1 else 0
                  val num8 = i-256*bit8
                  val bit7 = if num8-128>=0 then 1 else 0
                  val num7 = num8-128*bit7
                  val bit6 = if num7-64>=0 then 1 else 0
                  val num6 = num7-64*bit6
                  val bit5 = if num6-32>=0 then 1 else 0
                  val num5 = num6-32*bit5
                  val bit4 = if num5-16>=0 then 1 else 0
                  val num4 = num5-16*bit4
                  val bit3 = if num4-8>=0 then 1 else 0
                  val num3 = num4-8*bit3
                  val bit2 = if num3-4>=0 then 1 else 0
                  val num2 = num3-4*bit2
                  val bit1 = if num2-2>=0 then 1 else 0
                  val num1 = num2-2*bit1
                  val bit0 = if num1-1>=0 then 1 else 0
                in
                  if i=0 then [[0,0,0,0,0,0,0,0,0]]
                  else [bit8, bit7, bit6, bit5, bit4, bit3, bit2, bit1, bit0]::(constrList (i-1))
                end
              val wholelist1 = constrList 511
              val wholelist2 = BTokenMapF.listItemsi btokentable
              fun output l = 
                let
                  fun outputin ((bt, s), ret) =
                    case ListBTokenPairTable.find(table3, (l, bt)) of
                        NONE => ret^"0 "
                      | SOME n => ret^Real.toString((Real.fromInt n)/(Real.fromInt (Option.valOf(BTokenTable.find(table1, bt)))))^" "
                  val outputstrm = List.foldl outputin "" wholelist2
                in
                  TextIO.output(strm, outputstrm^"\n")
                end 
              val _ = List.app output wholelist1
            in
              TextIO.closeOut strm 
            end
          in
            (dumpToken table1; dumpTokenPair table2; dumpListToken table3; dumpBeginToken table4; dumpEndToken table5; dumpInitProb table4; dumpTransProb table2; dumpEmitProb table3)
          end 

    exception BadTable

    fun readTokenTable path =
      let
        val list = loadFile (path^"TokenCount")
        fun extractOne (t, table) =
          let
            fun isEqual c = c = #"="
            val (tokenj, counts) = Substring.splitr (not o isEqual) (Substring.full t)
            val token = Substring.trimr 1 tokenj 
          in 
            BTokenTable.insert(table, nameToBToken (Substring.string token), Option.valOf(Int.fromString (Substring.string counts)))
          end
      in
        List.foldl extractOne BTokenTable.empty list
      end

    val tokentable = readTokenTable "/n/fs/pads/pads/probinfer/training/"

    fun readBoundaryTokenTable path tag =
      let
        val list = 
          case tag of
              0 => loadFile (path^"BeginTokenCount")
            | 1 => loadFile (path^"EndTokenCount")
        fun extractOne (t, table) =
          let
            fun isEqual c = c = #"="
            val (tokenj, counts) = Substring.splitr (not o isEqual) (Substring.full t)
            val token = Substring.trimr 1 tokenj 
          in 
            BTokenTable.insert(table, nameToBToken (Substring.string token), Option.valOf(Int.fromString (Substring.string counts)))
          end
        val inittable = List.foldl extractOne BTokenTable.empty list
        val sumlist = BTokenTable.listItems inittable
        fun addAll (i, ret) = i+ret
        val sum = List.foldl addAll 0 sumlist
        val newlist = BTokenTable.listItemsi inittable
        fun createNew ((key, i), ret) = BTokenTable.insert(ret, key, (Real.fromInt i)/(Real.fromInt sum))
      in
        List.foldl createNew BTokenTable.empty newlist
      end

    val begintokentable = readBoundaryTokenTable "/n/fs/pads/pads/probinfer/training/" 0
    val endtokentable = readBoundaryTokenTable "/n/fs/pads/pads/probinfer/training/" 1

    fun readTokenPairTable path =
      let
        val list = loadFile (path^"TokenPairCount")
        fun extractOne (t, table) =
          let
            fun isComma c = c = #" "
            fun isEqual c = c = #"="
            val (token, counts) = Substring.splitr (not o isEqual) (Substring.full t) 
            val (token1j, token2) = Substring.splitr (not o isComma) (Substring.trimr 1 token)
            val token1 = Substring.trimr 1 token1j
            val key = (nameToBToken (Substring.string token1), nameToBToken (Substring.string token2))
          in 
            BTokenPairTable.insert(table, key, Option.valOf(Int.fromString (Substring.string counts)))
          end
      in
        List.foldl extractOne BTokenPairTable.empty list
      end

    val tokenpairtable = readTokenPairTable "/n/fs/pads/pads/probinfer/training/"

    fun readListTokenTable path =
      let
        val list = loadFile (path^"CharTokenCount")
        fun extractOne (t, table) =
          let
            fun isComma c = c = #" "
            fun isEqual c = c = #"="
            val (token, counts) = Substring.splitr (not o isEqual) (Substring.full t) 
            val (charvecj, token2) = Substring.splitr (not o isComma) (Substring.trimr 1 token)
            val charvec = Substring.trimr 1 charvecj
(*            fun charToInt c = Option.valOf(Int.fromString(Char.toString c)) *)
            fun charToInt c =
              case c of
                  #"0" => 0
                | #"1" => 1
                | _ => (print (Char.toString c); raise BadTable)
            fun stringToList l = List.map charToInt (Substring.explode l)
            val key = (stringToList charvec, nameToBToken (Substring.string token2))
          in 
            ListBTokenPairTable.insert(table, key, Option.valOf(Int.fromString (Substring.string counts)))
          end
      in
        List.foldl extractOne ListBTokenPairTable.empty list
      end

    val listtokentable = readListTokenTable "/n/fs/pads/pads/probinfer/training/"
    
    fun defaultVal v =
      case v of
          NONE => 0.5 (* a parameter to tune *)
        | SOME n => Real.fromInt n

    fun defaultRVal v =
      case v of
          NONE => 0.5 (* a parameter to tune *)
        | SOME n => n

    fun computeProb pathgraph : Seqset list = 
      let
        fun transProb tslist =
          let
            fun addOne (((t, s), l), (pre, ret)) = 
              let
                val first = 
                  case pre of
                      NONE => Math.ln(defaultRVal(BTokenTable.find(begintokentable, t)))
                    | SOME pret => Math.ln(defaultVal(BTokenPairTable.find(tokenpairtable, (pret, t))))
                val rest = (Real.fromInt ((String.size s)-1)) * (Math.ln(defaultVal(BTokenPairTable.find(tokenpairtable, (t, t)))))
              in
                (SOME t, first+rest+ret)
              end 
            val (lastt, most) = List.foldl addOne (NONE, 0.0) tslist
            val all = most + (Math.ln(defaultRVal(BTokenTable.find(endtokentable, Option.valOf(lastt)))))
          in
            all
          end 
        fun emitProb tslist =
          let
            fun addOne (((t,s),l), ret) = 
              let
                fun addOneChar (c, v) =
                  let
                    val value = defaultVal(ListBTokenPairTable.find(listtokentable, (charToList c, t)))
                  in
                    (Math.ln value) + v
                  end
              in
                List.foldl addOneChar ret (String.explode s)
              end
          in
            List.foldl addOne 0.0 tslist
          end
        fun doOneTList (tsllist, f) = (tsllist, (transProb tsllist) + (emitProb tsllist))
        fun doOneSeqset ss = List.map doOneTList ss
      in
        List.map doOneSeqset pathgraph
      end

end
