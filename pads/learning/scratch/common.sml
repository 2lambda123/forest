(* Defines utility functions common to all modules *)
structure Common = struct
	open Types (* defined in types.sml *)

	fun idcompare (id1:Id, id2:Id):order =
            String.compare(Atom.toString(id1), Atom.toString(id2))

	structure LabelMap = SplayMapFn(struct
                 type ord_key = Id
                 val compare = idcompare
        end)
	structure LabelSet = SplaySetFn(struct
                 type ord_key = Id
                 val compare = idcompare
        end)
   	structure IntMap = RedBlackMapFn(
                 struct type ord_key = int
	    		val compare = Int.compare
		 end) 

	exception TyMismatch
	exception RecordNum

	(* defines an arbitrary order on tokens	to put it in maps *)
	(* it overrides some of the ordering in structure.sml *)
	fun compare(a : Token option,b:Token option) = case (a,b) of
			(SOME a', SOME b') => compared(a',b')
		|	(SOME a, _) => GREATER
		|	(NONE, SOME _) => LESS
		|	(NONE, NONE) => EQUAL
		and compared(a,b) = case (a, b) of
			(Pint (x, _), Pint (x', _)) => LargeInt.compare(x,x')
			| (Pfloat x, Pfloat x') => 
				(
				case (x, x') of 
				  ((a, b), (a', b')) => if a=a' then LargeInt.compare (b, b')
				  			else LargeInt.compare(a, a')
				)
			| (Pstring (s1), Pstring(s2)) => String.compare(s1, s2)
			| (Ptime(s1), Ptime(s2)) => String.compare(s1, s2)
			| (Pdate(s1), Pdate(s2)) => String.compare(s1, s2)
			| (Pip(s1), Pip(s2)) => String.compare(s1, s2)
			| (Phostname(s1), Phostname(s2)) => String.compare(s1, s2)
			| (Ppath(s1), Ppath(s2)) => String.compare(s1, s2)
			| (Purl(s1), Purl(s2)) => String.compare(s1, s2)
			| (Pwhite(s1), Pwhite(s2)) => String.compare(s1, s2)
			| (Other(c1), Other(c2)) => String.compare(Char.toString(c1), Char.toString(c2))
			| _ => Structure.compToken(a, b)
	
	structure BDSet = RedBlackSetFn(struct
                                              type ord_key = Token 
                                              val compare = compared
                                        end)
	
	(* ____ to string functions useful for debugging *)

	fun printTyList tylist =
		case tylist of
			ty::tail => (printTy ty; printTyList tail)
			| nil => print "--- end of TyList ---\n"

	(* function to transpose a table *)
        fun transpose( alistlist : 'a list list) : 'a list list =
                let
                        fun addtohead(alist, alistlist) = case (alist,alistlist) of
                          (h::t, h2::t2) => (h :: h2) :: addtohead(t,t2)
                        | (nil,nil) => nil
                        | _  => raise TyMismatch
                in
                        List.foldr addtohead (List.map (fn x => nil) 
				(List.hd alistlist)) alistlist
                end
	datatype constraint =
	  Length of int                (* constrains array lengths, string lengths, # of int digits *)
	| Ordered of ordered             (* constrains arrays to be in order *)
	| Unique of Token (* value is always the same when present, and is Token *)
	| Range of LargeInt.int * LargeInt.int (* constrains integers to fall in this range, inclusive *)
	| Switched of Id list * (Token option list * Token option) list (* a mapping between ids in id list, their values in the list of Token options, and the value of this node *)
	| Eq of (Id * Rat.rat) list * Rat.rat (* lin equation of Id list plus constant *)
	| EnumC of BDSet.set (* set of values it takes on *)
	and ordered = Ascend | Descend

	fun bdtos (d:Token):string = 
	  let fun pad x = if String.size x < 11 
		then pad (x ^ " ") else x 
	  in (pad (case d of
		PbXML(node, attrib) => "<" ^ node ^ attrib ^ ">"
	|	PeXML(node, attrib) => "</" ^ node ^ attrib ^ ">"
	|	Pint (i, s) => s
	|	Pfloat (a, b) => (LargeInt.toString a) ^"."^(LargeInt.toString b)
	|	Ptime(t) => t
	|	Pdate(t) => t
	|	Pip(t)  => t
	|	Phostname(t)  => t
	|	Ppath(t)  => t
	|	Purl(t)  => t
	|	Pstring(str)  => str
	|	Pwhite (str)  =>  "["^str^"]"  
	|	Other (c)  => Char.toString(c) 
	| 	Pempty => "[]" 
	|	_ => raise TyMismatch ))
	 end

	fun tokentorefine (d:Token):Refined =
		case d of
		PbXML(node, attrib) => StringConst(node ^ " + " ^ attrib) 
	|	PeXML(node, attrib) => StringConst(node ^ " + " ^ attrib) 
	|	Pint (i, _) => IntConst(i)
	(*TODO: should add float refine type *)
	|	Pfloat(t) => FloatConst(t)
	|	Ptime(t) => StringConst(t)
	|	Pdate(t) => StringConst(t)
	|	Pip(t)  => StringConst(t)
	|	Phostname(t)  => StringConst(t)
	|	Ppath(t)  => StringConst(t)
	|	Purl(t)  => StringConst(t)
	|	Pstring(str)  => StringConst(str)
	|	Pwhite (str)  =>  StringConst(str)  
	|	Other(c)  =>  StringConst(Char.toString(c))  
	| 	_ => StringConst("")

	fun bdoltos (x:Token option list): string = (case x of
		h :: nil => (case h of SOME a => bdtos a | NONE => "NONE      ")
	|	h :: t => (case h of SOME a => bdtos a | NONE => "NONE       ") 
				^ "" ^ (bdoltos t)
	|	nil => "()\n")

	fun idstostrs(idlist: Id list):string list =
            map (fn id => Atom.toString(id)) idlist
		
	(* link a list of labels with separators *)
	fun implode(slist : string list, seperator:string):string =
            case slist of
                 h :: nil => h
               | h :: t   => h ^ seperator ^ implode(t,seperator)
               | nil      => ""

	fun ctos(c:constraint):string = (case c of
		  Length x => "Length " ^ (Int.toString x)
		| Ordered x => (case x of Ascend => "Ascending" | Descend => "Decending")
		| Unique x => "Unique: " ^ (bdtos x)
		| EnumC bdset => "EnumC:\n" ^ ( implode(map bdtos (BDSet.listItems bdset),"\n") )
		| Range(l,h) => "Range [" ^ (LargeInt.toString l) ^ "," ^ 
				(LargeInt.toString h) ^ "]"
		| Eq(((lb,i) :: idlist), c) => "Equation " ^ (foldl (fn ((lb,i),str) => str ^ " + " ^ (Rat.toString i) ^ Atom.toString(lb)) ((Rat.toString i) ^ Atom.toString(lb)) idlist) ^ " + " ^ (Rat.toString c)
		| Eq(nil,c) => "Equation " ^ (Rat.toString c)
		| Switched (lablist, branches) => "Switched " ^ (
		let 
		val lab = implode(idstostrs(lablist),"\t") 
		val branches' = map (fn (bdolist,bdo) => "(" ^ bdoltos bdolist ^ ") -> " ^ bdoltos [bdo]) branches 
		val vals = implode(branches',"\n") 
		in 
		"(" ^ lab ^ ")\n" ^ vals 
		end)) ^ "\n"
	fun printConstMap (cmap:constraint list LabelMap.map):unit =
            LabelMap.appi (fn (lab,clist) => print (Atom.toString(lab) ^ ":\n" ^ (String.concat(map ctos clist))^ "\n")) cmap
	fun some(a : 'a option) : 'a = case a of SOME x => x | NONE => raise Size
	fun isIn(ch:char,str:string):bool =
            List.exists (fn x => x = ch) (String.explode str)
	fun escapeRegex(str:string):string =
            String.translate (fn x => if isIn(x ,"^$.[]|()*+?" )
                                      then "\\" ^ (String.str x) 
                                      else String.str x) str

	fun myand(a,b) = a andalso b
	fun myor(a,b) = a orelse b
	fun ltoken_equal((tk1, _):LToken, (tk2, _):LToken):bool =
	  case (tk1, tk2) of 
		    (PbXML(a,b), PbXML(a1, b1)) => (a=a1 andalso b = b1)
		  | (PeXML(a,b), PeXML(a1, b1)) =>  (a=a1 andalso b = b1) 
		  | (Ptime(a), Ptime(b)) => (a = b)
		  | (Pdate(a), Pdate(b)) => (a = b)
		  | (Pip(a), Pip(b)) => (a = b)
		  | (Phostname(a), Phostname(b)) => (a = b)
		  | (Ppath(a), Ppath(b)) => (a = b)
		  | (Purl(a), Purl(b)) => (a = b)
		  | (Pint(a, s1), Pint(b, s2)) => (a = b andalso s1 = s2)
		  | (Pfloat(a), Pfloat(b)) => (a = b)
		  | (Pstring(a), Pstring(b)) => (a = b)
		  | (Pwhite(a), Pwhite(b)) => (a = b)
		  | (Other(a), Other(b)) => (a = b)
		  | (Pempty, Pempty) => true
		  (* ignoring Pgroup for now *)
		  | _ => false
	fun ltoken_ty_equal ((tk1, _):LToken, (tk2, _):LToken):bool =
	  case (tk1, tk2) of 
		    (PbXML(a,b), PbXML(a1, b1)) => true
		  | (PeXML(a,b), PeXML(a1, b1)) => true 
		  | (Ptime(a), Ptime(b)) => true
		  | (Pdate(a), Pdate(b)) => true
		  | (Pip(a), Pip(b)) => true
		  | (Phostname(a), Phostname(b)) => true
		  | (Ppath(a), Ppath(b)) => true
		  | (Purl(a), Purl(b)) => true
		  | (Pint(_), Pint(_)) => true
		  | (Pfloat(a), Pfloat(b)) => true
		  | (Pstring(a), Pstring(b)) => true
		  | (Pwhite(a), Pwhite(b)) => true
		  | (Other(a), Other(b)) => true
		  | (Pempty, Pempty) => true
		  (* ignoring Pgroup for now *)
		  | _ => false

	(* the two refine types are exactly the same *)
	fun refine_equal (a:Refined, b:Refined):bool =
		case (a, b) of 
			(StringME(x), StringME(y)) => (x = y)
		       |(Int(x, y), Int(x1, y1)) => (x = x1 andalso y = y1)
		       |(IntConst(x), IntConst(y)) => (x = y)
		       |(StringConst(x), StringConst(y)) => (x = y)
		       |(Enum(l1), Enum(l2)) => foldr myand true 
				(ListPair.map refine_equal(l1, l2))
		       |(LabelRef(x), LabelRef(y)) => Atom.same(x, y)
		       | _ => false
	fun refine_equal_op (a:Refined option, b:Refined option):bool =
		case (a,b) of 
			(SOME a', SOME b') => refine_equal(a', b')
		|_ => false

	fun refine_equal_op1 (a:Refined option, b:Refined option):bool =
		case (a,b) of 
			(SOME a', SOME b') => refine_equal(a', b')
		| (NONE, NONE) => true
		|_ => false

	fun ltokenlToRefinedOp ltokenl=
		case ltokenl of
		  h::t =>
		  let 
			val not_equal = (List.exists (fn x => not (ltoken_equal(x, h))) t)
		  in
			if not_equal then NONE else SOME (tokentorefine (#1 (hd ltokenl)))
		  end
		  | nil => NONE


    (*function to merge AuxInfo a1 into a2*)
    fun mergeAux(a1, a2) =
	case (a1, a2) of 
	 ({coverage=c1, label=l1, tycomp=tc1},{coverage=c2, label=l2, tycomp=tc2}) =>
 	 	{coverage=c1+c2, label=l2, tycomp=tc2} (* ????? *)

    (*function that test if tylist1 in a struct can be described by tylist2 in another struct*)
    (* tylist1 is described by tylist2 if tylist1 is a sub-sequence of tylist2 and 
	all other elements in tylist2 can describe Pempty *)
    fun listDescribedBy (tylist1, tylist2) = 
      let
	 val (len1, len2) = (length(tylist1), length(tylist2))
      in
	(len1 <= len2) andalso
	let 
	   val head2 = List.take(tylist2, len1)
	   val tail2 = List.drop(tylist2, len1)
	   val emptyBase = Base(getAuxInfo(hd tylist1), [(Pempty, {lineNo=0, beginloc=0, endloc=0,recNo=0})])
	in
	   (
	   (foldr myand true (map describedBy (ListPair.zip (tylist1, head2)))) 
	   andalso (*the tail2 all describe Pempty *)
	   (foldr myand true (map (fn x => describedBy (emptyBase, x)) tail2)) 
	   )
	   orelse (describedBy(emptyBase, hd tylist2) andalso 
	   	listDescribedBy (tylist1, List.drop(tylist2, 1)))
	end
      end
    (*function that test if ty1 can be described by ty2 *)
    and describedBy(ty1, ty2) =
	let
	  val emptyBase = Base(getAuxInfo(ty1), [(Pempty, {lineNo=0, beginloc=0, endloc=0,recNo=0})])
	  val res =
	    case (ty1, ty2) of 
		(*assume no Pempty in the Pstruct as they have been cleared by remove_nils*)
		(Base(a1, tl1), Base(a2, tl2)) => ltoken_ty_equal(hd tl1, hd tl2)
		| (Base(a1, tl1), Pstruct(a2, tylist2)) => listDescribedBy ([Base(a1, tl1)], tylist2)
		(*below is not completely right, haven't considered the case of tylist1 is a subset
		  of tylist2 and the rest of tylist2 can describe Pempty *) 
		| (Pstruct(a1, tylist1), Pstruct(a2, tylist2)) => listDescribedBy(tylist1, tylist2)
		| (Punion(a1, tylist1), Punion(a2, tylist2)) =>
			foldr myand true (map 
				(fn ty => (foldr myor false (map (fn x => describedBy (ty, x)) tylist2))) 
				tylist1)
		| (ty1, Punion(a2, tylist2)) =>
			foldr myor false (map (fn x => describedBy (ty1, x)) tylist2)
		| (Poption(a1, ty), ty2) => describedBy (emptyBase, ty2) andalso describedBy (ty, ty2)
		| (ty1, Poption(a2, ty)) => describedBy (ty1, emptyBase) orelse describedBy (ty1, ty)
		(*
		| (Switch(a1, id1, rtylist1), Switch(a2, id2, rtylist2)) =>
			Atom.same(id1, id2) andalso 
			(foldr myand true (map (fn x => rtyexists (x,rtylist2)) rtylist1))
		*)
		| _ => false
(*
	    val _ = (print "Checking\n"; printTy(ty1); print "with ...\n"; printTy(ty2); 
			print "Answer is: "; (if res = true then print "true\n\n" else print "false\n\n"))
*)
	in res
	end

    
    (*merge a ty into a tylist in a union *)
    fun mergeUnion (ty, tylist, newlist) = 
      case tylist of 
	h::tail => if (describedBy (ty, h)) then newlist@[mergeTyInto(ty, h)]@tail
		   else (mergeUnion (ty, tail, newlist@[h]))
	| nil => newlist
    and describesEmpty tylist =
      case tylist of 
      nil => true
      | h::t =>
	let
	   val emptyBase = Base(getAuxInfo(hd tylist), [(Pempty, {lineNo=0, beginloc=0, endloc=0,recNo=0})])
	in
	   foldr myand true (map (fn x => describedBy (emptyBase, x)) tylist) 
	end handle Empty => false
    (*function to merge one list in struct to another list in struct*)
    and mergeListInto (tylist1, tylist2, headlist) =
	let 
	   val (len1, len2) = (length(tylist1), length(tylist2))
	   val head2 = List.take(tylist2, len1)
	   val tail2 = List.drop(tylist2, len1)
	in
	   if (describesEmpty headlist andalso 
	       foldr myand true (map describedBy (ListPair.zip (tylist1, head2))) andalso 
	       describesEmpty tail2) (*found the merging point*)
	   then
		let
	          (*here need to push a base with correct number of Pempty tokens into the head and tail lists
			note that the recNo of those "fake" tokens will be -1 and will not be used in
			table generation *)
		  fun genEmptyTokens 0 = nil
		  | genEmptyTokens numTokens =
			(Pempty, {lineNo=0, beginloc=0, endloc=0, recNo=(~1)})::(genEmptyTokens (numTokens-1))
	   	  val emptyBase = Base(getAuxInfo(hd tylist1), genEmptyTokens (getCoverage (hd tylist1)))
		  fun pushInto ty tylist = map (fn t => mergeTyInto (ty, t)) tylist
		in
		  (pushInto emptyBase headlist)@(map mergeTyInto (ListPair.zip (tylist1, head2)))@
		  (pushInto emptyBase tail2)	
		end
	   else mergeListInto (tylist1, List.drop(tylist2, 1), headlist@[hd tylist2])
	end
    (*function to merge ty1 and ty2 if ty1 is described by ty2 *)
    (*this function is used in refine_array rewriting rule, the recNo in ty1 
	is updated so that they are consistent with ty2 *)
    and mergeTyInto (ty1, ty2) =
		case (ty1, ty2) of 
		(Base(a1, tl1), Base(a2, tl2)) => Base(mergeAux(a1, a2), tl2@tl1) 
		| (Base(a1, tl1), Pstruct(a2, tylist2)) => Pstruct(mergeAux(a1, a2), 
			mergeListInto([Base(a1, tl1)], tylist2, nil))
		(*below is not completely right, haven't considered the case of tylist1 is a subset
		  of tylist2 and the rest of tylist2 can describe Pempty *) 
		| (Pstruct(a1, tylist1), Pstruct(a2, tylist2)) => 
			Pstruct(mergeAux(a1, a2), mergeListInto(tylist1, tylist2, nil))
		| (Punion(a1, tylist1), Punion(a2, tylist2)) => foldl mergeTyInto ty2 tylist1
		| (ty1, Punion(a2, tylist2)) => Punion(mergeAux(getAuxInfo(ty1), a2), mergeUnion(ty1, tylist2, nil))
		| (Poption (a1, ty), ty2) => 
			let
		  	  fun genEmptyTokens 0 = nil
		  	  | genEmptyTokens numTokens =
				(Pempty, {lineNo=0, beginloc=0, endloc=0, recNo=(~1)})::(genEmptyTokens (numTokens-1))
			  val emptyCoverage = getCoverage ty1 - getCoverage ty
			in
			  mergeTyInto (Base((mkTyAux emptyCoverage), 
						(genEmptyTokens emptyCoverage)), mergeTyInto (ty, ty2))
			end
		(*
		| (Switch(a1, id1, rtylist1), Switch(a2, id2, rtylist2)) =>
			Atom.same(id1, id2) andalso 
			(foldr myand true (map (fn x => rtyexists (x,rtylist2)) rtylist1))
		*)
		| _ => (print "mergeTyInto error!\n"; raise TyMismatch)


    (*function to merge two tys that are equal structurally*)
    (*assume ty1 is before ty2*)
    (*used by refine_array *)
    fun mergeTy (ty1, ty2) =
	case (ty1,ty2) of
		(Base(a1, tl1), Base (a2, tl2)) => Base (mergeAux(a1, a2), tl1@tl2)
		| (RefinedBase (a1, r1, tl1), RefinedBase(a2, r2, tl2)) => 
						RefinedBase(mergeAux(a1, a2), r1, tl1@tl2)
		| (TBD (a1, s1, cl1), TBD (a2, s2, cl2)) => TBD (mergeAux(a1, a2), s1, cl1@cl2)
		| (Bottom (a1, s1, cl1), Bottom (a2, s2, cl2)) => Bottom (mergeAux(a1, a2), s1, cl1@cl2)
		| (Punion(a1, tylist), Punion(a2, tylist2)) => Punion(mergeAux(a1, a2), 
				map mergeTy (ListPair.zip(tylist,tylist2)))
		| (Pstruct(a1, tylist), Pstruct(a2, tylist2)) => Pstruct(mergeAux(a1, a2),
				map mergeTy (ListPair.zip(tylist,tylist2)))
		| (Parray(a1, {tokens=t1, lengths=len1, first=f1, body=b1, last=l1}), 
		   Parray(a2, {tokens=t2, lengths=len2, first=f2, body=b2, last=l2})) => 
			Parray(mergeAux(a1, a2), {tokens = t1@t2, lengths = len1@len2, 
			first = mergeTy(f1, f2),
			body = mergeTy(b1, b2),
			last = mergeTy(l1, l2)})
		| (Switch (a1, id1, rtylist1), Switch(a2, id2, rtylist2)) =>
			let val (rl1, tylist1) = ListPair.unzip (rtylist1)
			    val (rl2, tylist2) = ListPair.unzip (rtylist2)
			in
			    if (Atom.same(id1, id2) andalso
					foldr myand true (ListPair.map refine_equal(rl1, rl2)) )
			    then
				Switch(mergeAux(a1, a2), id1, 
					ListPair.zip(rl1, map mergeTy (ListPair.zip(tylist1, tylist2))))
			    else raise TyMismatch
			end
		| (RArray(a1, sepop1, termop1, ty1, len1, l1), 
			RArray (a2, sepop2, termop2, ty2, len2, l2))
			=> RArray(mergeAux(a1, a2), sepop1, termop1, mergeTy(ty1, ty2), len1, (l1@l2)) 	
		| _ => raise TyMismatch

    (* function to attempt to merge ty1 into the leftmost part of the ty2*)

    (* function to test of two ty's are completely equal minus the labels *)
    (* if comparetype = 0, compare everything, otherwise compare down to 
	base modulo the token list and other meta data *)
    (* comparetype = 0 is currently not used and is not fully implemented *)
    fun ty_equal (comparetype:int, ty1:Ty, ty2:Ty):bool = 
	let
		fun check_list(l1:Ty list,l2: Ty list):bool = 
		let 
			val bools = ListPair.map (fn (t1, t2) => ty_equal(comparetype, t1, t2)) (l1, l2)
		in
			foldr myand true bools
		end
	in
		case (ty1,ty2) of
			(Base(_, tl1), Base (_, tl2)) => 
				if (comparetype = 0) then
				foldr myand true (ListPair.map ltoken_equal (tl1, tl2))
				else ltoken_ty_equal(hd tl1, hd tl2)
			| (TBD _, TBD _) => true
			| (Bottom _, Bottom _) => true
			| (Punion(_, tylist), Punion(_, tylist2)) => check_list(tylist,tylist2)
			| (Pstruct(_, tylist), Pstruct(_, tylist2)) => check_list(tylist,tylist2)
			| (Parray(_, a1), 
			   Parray(_, a2)) => ty_equal(comparetype, #first a1, #first a2) andalso 
				ty_equal(comparetype, #body a1, #body a2) andalso 
				ty_equal(comparetype, #last a1, #last a2) 
			| (RefinedBase (_, r1, tl1), RefinedBase(_, r2, tl2)) => 
				if (comparetype = 0) then
				(refine_equal(r1, r2) andalso 
				foldr myand true (ListPair.map ltoken_equal(tl1, tl2)))
				else refine_equal(r1, r2)
			| (Switch (_, id1, rtylist1), Switch(_, id2, rtylist2)) =>
				let val (rl1, tylist1) = ListPair.unzip (rtylist1)
				    val (rl2, tylist2) = ListPair.unzip (rtylist2)
				in
				        Atom.same(id1, id2) andalso 
					foldr myand true (ListPair.map refine_equal(rl1, rl2)) 
					andalso check_list (tylist1, tylist2)
				end
			| (RArray(_, sepop1, termop1, ty1, len1, _), 
				RArray (_, sepop2, termop2, ty2, len2, _))
				=> refine_equal_op1(sepop1, sepop2) andalso
				   refine_equal_op1(termop1, termop2) andalso
				   ty_equal (comparetype, ty1, ty2) andalso
				   refine_equal_op1(len1, len2)
			| _ => false 
		handle Size => (print "Size in ty_equal!\n" ; false)
	end

	(*this function reindex the recNo by collapsing them in every token of a given ty 
	and a start index and returns the updated ty *)
	fun reIndexRecNo ty startindex = 
	  let
(*
		val _ = print ("startindex = "^(Int.toString startindex)^" and The ty is\n")
		val _ = printTy ty
*)
		fun insertTListToMap tl intmap =
			case tl of
				nil => intmap
				| (t, {lineNo, beginloc, endloc, recNo}) :: ts => 
					insertTListToMap ts (IntMap.insert(intmap, recNo, 0))
		fun insertToMap ty intmap =
		  case ty of
			Base(_, tl)=> insertTListToMap tl intmap
			| RefinedBase (_, _, tl) => insertTListToMap tl intmap
			| TBD _  => intmap
			| Bottom _ => intmap
			| Punion(_, tylist)=> foldr (fn (x, m) => insertToMap x m) intmap tylist
			| Pstruct(_, tylist)=> foldr (fn (x, m) => insertToMap x m) intmap tylist
			| Parray(_, {tokens, lengths, first, body, last}) =>
				 foldr (fn (x, m) => insertToMap x m) intmap [first, body, last]
			| RArray(_, _, _, ty, _, lens) => insertToMap ty intmap 
			(*TODO: need to work on lens of RArray as well!!!*)
			| Switch (a, i, rtl) => foldr (fn ((r, ty), m) => insertToMap ty m) intmap rtl
			| Poption (a, ty) => insertToMap ty intmap

		fun updateMap intmap =
		  let
			val pairs = IntMap.listItemsi intmap
		    	fun insertPairs pairs index intmap =
			  case pairs of 
			    nil => intmap
			    | (oldRecNo, _)::rest => insertPairs rest (index+1) 
						(IntMap.insert(intmap, oldRecNo, index))
		  in
			insertPairs pairs startindex intmap
		  end
		fun updateTL(intmap, tl, newtl) =
			case tl of 
			  nil => newtl
			  | (t, {lineNo, beginloc, endloc, recNo})::ts => 
				let
				  val newRecop = IntMap.find(intmap, recNo)
				in
				  case newRecop of
					NONE => (print "One recNum not found!\n"; raise RecordNum)
					| _ => updateTL(intmap, ts, newtl@[(t, {lineNo=lineNo, beginloc=beginloc, 
							endloc=endloc, recNo=some(newRecop)})])
				end
		fun updateLens intmap lengths =
			case lengths of
			  nil => nil
			  | (l, r)::tail => 
				let
				  val newRecOp = IntMap.find (intmap, r)
				in
			  	  case newRecOp of
					NONE => (print "One recNum not found!\n"; raise RecordNum)
					| _ => (l, (some newRecOp))::(updateLens intmap tail)
				end
		fun updateTy intmap ty =
		  case ty of
			Base(a, tl)=> Base(a, updateTL(intmap, tl, nil))
			| RefinedBase (a, r, tl) => RefinedBase(a, r, updateTL(intmap, tl, nil))
			| Punion(a, tylist)=> Punion(a, map (updateTy intmap) tylist)
			| Pstruct(a, tylist)=> Pstruct(a, map (updateTy intmap) tylist)
			| Parray(a, {tokens, lengths, first, body, last}) => Parray(a, {tokens = tokens,
					lengths = (updateLens intmap lengths), first = updateTy intmap first, 
					body = updateTy intmap body, last = updateTy intmap last})
			| RArray(a, s, t, body, l, lens) => RArray(a, s, t, updateTy intmap body, l, 
					(updateLens intmap lens)) 
			| Switch (a, i, rtl) => Switch(a, i, map (fn (r, t) => (r, updateTy intmap ty)) rtl)
			| Poption(a, ty') => Poption(a, updateTy intmap ty')
			| _ => ty

		val recNoMap = insertToMap ty IntMap.empty

	  in
		updateTy (updateMap recNoMap) ty	
	  end
end
