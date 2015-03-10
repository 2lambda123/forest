(* 
Zach DeVito
Kenny Zhu
Reduce implements the refinement system for Tys
*)
structure Probreduce = struct
open Common
open Types
open Probmodel
exception TyMismatch
exception InvalidToken
exception Unexpected

(* a table to record which base types are Refinable*)
fun refineableBase (token, s) = 
  case token of 
	  PPbXML => true
	| PPeXML => true
	| PPint => true
    | PPfloat => true
	| PPwhite => true
	| PPblob => true
	| _ => false

fun enumerableBase (token, s) = 
  case token of 
	  PPbXML => true
	| PPeXML => true
	| PPint => true
(*
    | PPword => true
    | PPhstring => true
    | PPtext => true
    | PPpermission => true
    | PPid => true
    | PPfloat => true
	| PPblob => true
*)
	| _ => false
	
(* calculates the complexity of a datatype so that we can try to minimize it*)
fun cost const_map ty =
  let 
	fun is_base ty' = case ty' of 
		PPBase _ => true 
		| PPRefinedBase _ => true
		| _ => false
	fun const_cost isbase c =
  		case c of
		    NLength _ => if isbase then 1 else 0
		  | NOrdered _ => if isbase then 1 else 0
		  | NUnique _ => if isbase then 1 else 0
		  | NRange _ => if isbase then 1 else 0
		  | NSwitched (_,ops) => 5
		  | NEq _ => 1
		  | NEnumC set => if isbase then 1 else 0
	fun total_const_cost myty = 
	  let
		val id = getLabel(getNAuxInfo(myty))
	  	val entry = LabelMap.find(const_map, id)
		val isbase = is_base(myty)
	  	val e_cost = case entry of 
	  	    SOME x => foldr op+ 0 (map (const_cost isbase) x)
	  	  | NONE => 0
	  in
	  	e_cost 
	  end
	fun ty_cost (myty:NewTy) =
		case myty of 
		(* consts are cheaper than variables *)
		  PPRefinedBase (_, r, _) =>  (
			case r of 
				StringME _ => 1 
				| Int _ => 2
				| IntConst _ => 1
				| FloatConst _ => 1
				| StringConst _ => 1
				| Enum l => length(l)
				| LabelRef _ => 1
				| Blob _ => 1
			)
		| PPBase _ => 3 
		| PPTBD _ => 1
		| PPBottom _ => 1
		(* bigger datastructures are more complex than bases*)
		| PPstruct(a, tylist) => foldr op+ 0 (map (cost const_map) tylist) + 3 
		| PPunion (a, tylist) => foldr op+ 0 (map (cost const_map) tylist) + 3
		| PParray (a, {tokens, lengths, first, body, last}) => 
			(* first, body and last are potentially structs so plus 9*)
				foldr op+ 0 (map (cost const_map) [first, body, last])+9
		| PPSwitch (a, id, l) => foldr op+ 0 (map (fn (r, t) => 
			ty_cost (PPRefinedBase(a, r, nil))+cost const_map t) l)
		| PPRArray (a, sepop, termop, body, lenop, lens) => 
			(case sepop of SOME (sep) => 0 | NONE => 1) +
			(case termop of SOME (term) => 0 | NONE => 1) + 
			(cost const_map body)
		| PPoption (a, ty) => (cost const_map ty) + 3 
	in (ty_cost ty) + (total_const_cost ty) + 1 (* every constraint is counted towards cost *)
  end

fun score ty =
	let
		val comps = getNComps (newmeasure ty)
		val rawcomp = combine (#tc comps) (#dc comps)
	in (toReal rawcomp)
end

type constraint_map = newconstraint list LabelMap.map

(* a rule takes an Ty and the constrant lookup table, returns a [possibly] new Ty *)

(* 	they are seperated into two types: pre and post constraint anaysis
	this allows for a reduction in complexity without worrying about labels
	changes due to major structural changes
*)
type pre_reduction_rule = NewTy -> NewTy
type post_reduction_rule = constraint_map -> NewTy -> constraint_map*NewTy

(* reduction rules *)
(* single member lists are removed*)
fun remove_degenerate_list ty =
case ty of
  PPunion(a, h :: nil) => h
| PPunion (a, nil) => PPBase(a, nil)
| PPstruct (a, h :: nil) => h
| PPstruct (a, nil) => PPBase(a, nil)
| PPSwitch(a, id, nil) => PPBase(a, nil)
| PParray(a, {tokens, lengths, first, body, last}) => 
	if lengths=nil then PPBase(a, nil) else ty 
| PPRArray(a, _, _, _, _, nil) => PPBase(a, nil) 
| _ => ty

fun remove_degenerate_list1 cmap ty =
case ty of
  PPunion(a, h :: nil) => (cmap, h)
| PPunion (a, nil) => (cmap, PPBase(a, nil))
| PPstruct (a, h :: nil) => (cmap, h)
| PPstruct (a, nil) => (cmap, PPBase(a, nil))
| PPSwitch(a, id, nil) => (cmap, PPBase(a, nil))
| PParray(a, {tokens, lengths, first, body, last}) => 
	if lengths=nil then (cmap, PPBase(a, nil)) else (cmap, ty) 
| PPRArray(a, _, _, _, _, nil) => (cmap, PPBase(a, nil)) 
| _ => (cmap, ty)


(* tuples inside tuples are removed*)
and unnest_tuples ty : NewTy =
case ty of 
  PPstruct (a, tylist) =>
  let
  	fun lift_tuple ty = 
  	case ty of
  	  PPstruct(_, tylist) => tylist
  	| _ => [ty]
  	val result = map lift_tuple tylist
  in
  	PPstruct(a, List.concat result )
  end
| _ => ty
(* sums inside sums are removed *)
and unnest_sums ty : NewTy = 
case ty of 
  PPunion(a, tylist) =>
  let
  	fun lift_sum ty = 
  	case ty of
  	  PPunion(_, tylist) => tylist
  	| _ => [ty]
  	val result = map lift_sum tylist
  in
  	PPunion(a, List.concat result )
  end
| _ => ty
(* remove nil items from struct*)
(* also removes Pemptys from struct*)
and remove_nils ty : NewTy = 
case ty of
  PPstruct (a, nil) => PPBase(a, nil)
  | PPstruct (a, tylist) =>
    let val tylist' =  List.filter (fn x => case x of
                        PPBase(_, nil) => false
                        | PPBase (_, (((PPempty, _), _)::_)) => false
                        | PPRefinedBase(_, _, nil) => false
                        | _ => true ) tylist
    in
        case tylist' of
          nil => hd tylist
        | _ => PPstruct(a, tylist')
    end
| _ => ty
(* removed unused branches of sums *)
and unused_branches ty =
case ty of 
  PPunion(aux, tylist) => 
  let
  	fun isUnused(ty) = ( 
  	  case ty of
	    PPBase(_, nil) => true
	    | PPRefinedBase(_, _, nil) => true
  	    | _ => false)
  	fun remove_unused() = 
  	let
  		val (unused,used) = List.partition isUnused tylist
  		val strs = map NewTyToString unused
  		(*val _ = app (fn x=> print ("unused:" ^ x)) strs*)
  	in
  		used
  	end
  in
  	PPunion (aux, remove_unused())
  end
| _ => ty
(* elements of a sum are check to see if they share a common prefix (ie tuples with
a common prefix, or a common postfix) these elements are then brought out of a sum
and a tuple is created *)
(* TODO: the token coverage in the aux info may not be correct after this operation *)
and prefix_postfix_sums ty : NewTy =
case ty of
  PPunion (a, tylist) =>
  let
  	fun conv_to_list ty' =
  	case ty' of
  	  PPstruct(_, tylist') => tylist'
  	| _ => [ty']
  	val underlings = map conv_to_list tylist (*list of tylists *)
	val auxlist = map getNAuxInfo tylist (* list of aux info *)
  	fun commonPrefix tylists = 
  	let
  		val elems = map hd tylists
  		val tails = map tl tylists
  	in
		case elems of
		  h :: t => 
		  let 
		  	val not_equal = (List.exists (fn x => not(newty_equal(1, x, h) )) t) 
		  in 
		  	if not_equal then nil else (foldr mergeNewTy h t) :: commonPrefix tails 
  	          end
		| nil => nil
  	end handle Empty => nil
  	val cpfx = commonPrefix underlings
  	val plen = length cpfx
  	val remaining = map (fn x => List.drop(x,plen) ) underlings
  	val remaining_rev = map List.rev remaining
  	val csfx_rev = commonPrefix remaining_rev
  	val slen = length csfx_rev
  	val remaining_rev = map (fn x => List.drop(x,slen) ) remaining_rev
  	val remaining = map List.rev remaining_rev
  	val csfx = List.rev csfx_rev
  	val rem_tups = map(fn (a, tys) => case tys of
				nil => genEmptyPPBase a (#coverage a)
				| t::nil => t
				| _ => PPstruct(a, tys)
			      ) (ListPair.zip(auxlist, remaining))
	val unionTys = case length rem_tups of
			0 => nil
			| 1 => rem_tups
			| _ => [union_to_optional (PPunion(a, rem_tups))]
  	val newty = case (cpfx, csfx) of
  	  (h::t, _) => PPstruct (mkTyAux (#coverage a), 
				cpfx @ unionTys @ csfx)
  	| (_,h::t) => PPstruct (mkTyAux (#coverage a), 
				cpfx @ unionTys @ csfx)
  	| (nil,nil) => PPunion (a, tylist)
  in newty
  end
| _ => ty
(* detect a table with a header and rewrite the struct with unions inside
(a1 + b1), (a2 + b2), (a3 + b3) = (a1, a2, a3) + (b1, b2, b3) 
where a and b are header and body rows of a table respectively *)
(*this rule cause the cost of the ty to go up so it's currently not used *)
and extract_table_header ty  =
 case ty of 
	PPstruct (a, tylist) =>
	  let
		fun getNewLabel x = SOME ( getLabel ( { coverage = x
                                                      , label=NONE
                                                      , tycomp = zeroComps
                                                      }
                                                    )
                                         )
		fun numUnions tylist =
			case tylist of
				h::tail => (case h of 
						PPunion(_, _) => 1+numUnions tail
						| _ => numUnions tail
					   )
				| nil => 0
		fun check_table tylist =
		  case tylist of
			h::tail => 
				(
				case h of 
				PPunion(a, [ty1, ty2]) =>
					let
						val c1 = getNCoverage(ty1)
						val c2 = getNCoverage(ty2)
					in
						if (c1=1 andalso c2 >1) orelse
						   (c1>1 andalso c2=1) then
							check_table tail
						else false	
					end
				| _ => check_table tail
				)
			| nil => true	 
		fun split_union ty =
			case ty of
				PPunion(a, [ty1, ty2]) => 
					let
						val c1 = getNCoverage(ty1)
						val c2 = getNCoverage(ty2)
					in
						if (c1=1) then (ty1, ty2) (* table header comes first *)
						else (ty2, ty1)
					end
				| ty => let
					val aux = getNAuxInfo(ty)
					val c   = #coverage aux
					val l   = #label aux
					val tc  = #tycomp aux
					val aux1 = {coverage=1, label=getNewLabel 1, tycomp=tc }
					val aux2 = {coverage=c-1, label=l, tycomp = tc }
					in
						(setNAuxInfo ty aux1, setNAuxInfo ty aux2)
					end
		val overallCoverage = getNCoverage(ty)
		val unions = numUnions tylist
	  in
		if unions>=2 andalso check_table tylist = true then
		  let
			val _ = print "Found a table!!! Rewriting!!!\n"
			val _ = printNewTy ty
			val (tys1, tys2) = ListPair.unzip (map split_union tylist)
			val a1 = {coverage=1, label=getNewLabel 1, tycomp = zeroComps }
			val a2 = {coverage=overallCoverage-1, 
				label=getNewLabel 1, tycomp = zeroComps }
			val newty = PPunion(a, [PPstruct(a1, tys1), PPstruct(a2, tys2)])
			val _ = (print "Cost for ty: "; print (Real.toString(score ty)))
			val _ = (print "\nCost for newty: "; print (Real.toString(score newty)))
		  in newty
		  end
		else ty
	  end
     	| _ => ty

(* adjacent constant strings are merged together *)
and adjacent_consts cmos ty = 
  case ty of PPstruct(a, tylist) => 
    let
	 fun mergetok (t1:BSLToken, t2:BSLToken) : BSLToken =
	    let
		fun combineloc (loc1:location, loc2:location) = 
		  {lineNo=(#lineNo loc1), beginloc=(#beginloc loc1), endloc=(#endloc loc2),
			recNo=(#recNo loc1)}
	    in
		case (t1, t2) of 
			(((PPwhite, s1), loc1), ((PPwhite, s2), loc2)) => 
			  	((PPwhite, s1 ^ s2), combineloc(loc1, loc2))
			| (((PPempty, s1), loc1), ((PPempty, s2), loc2)) => 
				((PPempty, ""), combineloc(loc1, loc2))
			| (((tk1, ts1), loc1), ((tk2, ts2), loc2)) =>
				((PPblob, (ts1^ts2)), 
				combineloc(loc1, loc2))
	    end
	 (*the two token lists are supposed to be of equal length*)
	 fun mergetoklist (tl1: BSLToken list, tl2: BSLToken list): BSLToken list =
			case tl2 of 
			nil => tl1
			| _ => ListPair.mapEq mergetok (tl1, tl2)
			handle UnequalLengths => (ListPair.map mergetok (tl1, tl2))

  	 fun for_const while_const t x tl = 
  	 let
       		val (clist,rest, resttl) = while_const(t)
     	 in
	  	(x :: clist, rest, mergetoklist(tl, resttl))
         end
  	 fun while_const tylist = case tylist of 
  		h::t => (case h of
  				  PPRefinedBase(_, StringConst(x), tl) => 
					for_const while_const t x tl
  				| _ => (nil,tylist, nil))
  	   	| nil => (nil, nil, nil)

  	 fun find_adj tylist = case tylist of
  	  	h::t => (case h of
			PPRefinedBase(aux, StringConst(x), l) => 
			let
  				val (clist, rest, tlists) = while_const(t)
    			in
    				PPRefinedBase(aux, StringConst(String.concat(x :: clist)), 
				 mergetoklist(l, tlists)) 
				:: find_adj rest
    			end
  	    		| _ => h :: find_adj t)
  		| nil => nil
  	val newtylist = find_adj tylist
    in
  	(cmos, PPstruct(a, newtylist))
    end
| _ => (cmos, ty)
(* rule to convert a normal Parray to a refined RArray *)
and refine_array ty = 
	case ty of 
	(* 1st case is looking at the Parray itself *)
	PParray(aux, {tokens, lengths, first, body, last}) =>
		let
(*
		val _ = (print "trying to refine array \n"; printTy (measure ty)) 
*)
		fun getlen (lens, x) = 
			case lens of 
			l::tail => if (l = x) then getlen(tail, x)
				   else NONE
			| nil => SOME(IntConst(Int.toLarge(x)))
		val lens = (#1 (ListPair.unzip(lengths)))		
		val lenop = getlen(lens, hd lens)
		fun isStruct ty = case ty of 
			(PPstruct(_)) => true 
			| PPoption (a, ty') => isStruct ty'
			| _ => false
		fun is_base ty' = case ty' of 
			PPBase _ => true 
			| PPRefinedBase _ => true
			| _ => false
		fun firstEle(ty) = 
		  case ty of 
		  PPstruct(aux, tylist) => List.hd tylist
		  | PPoption(_, ty') => firstEle ty'
		  | _ => raise TyMismatch
		fun lastEle(ty) = 
		  case ty of 
		  PPstruct(aux, tylist) => List.last tylist
		  | PPoption(_, ty') => lastEle ty'
		  | _ => raise TyMismatch
		fun droplast(ty) = 
		  case ty of 
		  PPstruct({label=SOME(id),... }, tylist) => 
			(case (length tylist) of 
			 0 => raise Size
			| 1 => PPBase(mkTyAux1(0, id), nil)
			| 2 => (hd tylist)
			| _ => let
				val newtylist = List.take(tylist, (length tylist) -1)	
			       in
				PPstruct(mkTyAux1(minNCoverage(newtylist), id), newtylist)
			       end
			)
		  | PPoption (a, ty') => PPoption (a, droplast ty')
		  | _ => raise TyMismatch
	  	fun findRefined ty =
		  (*funtion to find the first base or refine type and convert it to refined type *)
			case ty of
			  PPstruct(_, tylist) => findRefined (hd tylist)
			| PPoption (_, ty') => findRefined ty'
			| PPRefinedBase(_, refined, _) => SOME(refined)
			| PPBase(_, ltokens) => bsltokenlToRefinedOp ltokens
			| _ => NONE
(*
		fun combineRefined (ref1, ref2) =
			case (ref1, ref2) of
			(StringME(s), Int(_)) => SOME(StringME(substring(s, 0, size(s)-1)
						^"[0-9]*/"))
			| (StringME(s), IntConst(_)) => SOME(StringME(substring(s, 0, size(s)-1)^
							"[0-9]*/"))
			| (StringME(s), StringME(t)) => SOME(StringME(substring(s, 0, size(s)-1)^
						      substring(s, 1, size(s)-1)))
			| (StringConst(s), StringConst(t)) => SOME(StringConst(s^t))
			| (StringConst(s), Int(_)) => SOME(StringME("/"^ (String.toCString s) ^"[0-9]*/"))
			| (StringConst(s), IntConst(_)) => SOME(StringME("/"^ (String.toCString s) ^
								"[0-9]*/"))
			| (Enum(l1), Enum(l2)) => SOME(Enum(l1@l2))
			| _ => NONE
*)				
		fun getRefine(ty) = case ty of PPRefinedBase(_, r, _) => SOME(r) 
					| PPBase (_, tl) => bsltokenlToRefinedOp tl
					| _ => NONE
		fun isEmpty(ty) = case ty of 
					 PPBase(_, tkl) =>
						( 
						  case (hd tkl) of 
							((PPempty, _), _) => true
							| _ => false
						)
					| _=> false

		(* if the firsttail = body tail, then this is a possible separator.
		   if the stripped first is part of body and last is part of body, then
		   the separator is confirmed, and the first and last can be obsorbed
		   into the body. if either stripped first or the stripped last is part 
		   of the body, then the separator is confirmed and either the first or the
		   the last is absorbed into the body, and the other one is pushed out 
		   of the array.
		   if none of the first and the last is part of body, then no separator is
		   defined and both first and last are pushed out of the array. *)

		(*the separator should be a refinedbase ty in the last position
		 of the first and body tys, or no separator if the two elements are not
		 equal, or if the body is the same as the tail or the tail is empty *)
		fun getSepTerm(first, body, last)=
		let
			val bodyhd = getRefine(firstEle(body))	
			val bodytail = getRefine(lastEle(body))
			val firsttail = if (isStruct(first)) then getRefine(lastEle(first))
					else getRefine(first) (*assume it's a base itself*)
			val lasthd= if (isStruct(last)) then getRefine(firstEle(last))
					else getRefine(last)
		in
			if (isEmpty(last)) (*no sep and terminator is outside*)
			then if newdescribedBy(first, body) then
				  let
					val first' = newreIndexRecNo first (getNCoverage body)
				  in
					(NONE, NONE, NONE, SOME(mergeNewTyInto(first', body)), NONE)
				  end
				else
					(NONE, NONE, SOME first, SOME body, NONE)
			else (* with possible sep and possible term inside last *)
			     (* two cases: first = body or first != body *)
			  let
			     val firsteqbody = newdescribedBy(first, body)
			     val lasteqbody = newdescribedBy(last, droplast(body)) 
			     val withSep = refine_equal_op(firsttail, bodytail)
(*
			     val _ = (if firsteqbody then print "true " else print "false ";
				   	if lasteqbody then print "true " else print "false ";
				   	if withSep then print "true\n" else print "false\n")
*)
			  in
			     case (firsteqbody, lasteqbody, withSep) of 
				(true, true, true) => 
					let 
					  val first' = newreIndexRecNo (droplast first) (getNCoverage body)
					  val body' = mergeNewTyInto(first', droplast(body))
					  val last' = newreIndexRecNo last (getNCoverage body')
					  val body'' = mergeNewTyInto(last', body')
					in
					(bodytail, NONE, NONE, SOME(body''), NONE)
					end
				| (true, true, false) => 
					let
					  val first' = newreIndexRecNo (droplast first) (getNCoverage body)
					  val body' = mergeNewTyInto(first', (droplast body))
					  val last' = newreIndexRecNo last (getNCoverage body')
					in
					  (NONE, NONE, NONE, SOME(mergeNewTyInto(last', body')), NONE)
					end
				| (true, false, _) => (NONE, NONE, NONE, 
					SOME(mergeNewTyInto((newreIndexRecNo first (getNCoverage body)), body)), 
					SOME last)
				| (false, true, _) => (bodytail, NONE, SOME first,
					SOME(mergeNewTyInto((newreIndexRecNo last (getNCoverage body)), 
					droplast(body))), NONE)
				| (_, _, _) => (NONE, NONE, SOME first, SOME body, SOME last)
			  end
		end handle TyMismatch => (NONE, NONE, SOME first, SOME body, SOME last)
	in
		  let 
		    val (sepop, termop, firstop, bodyop, lastop) = getSepTerm(first, body, last)
		    val newty = 
			case (firstop, bodyop, lastop) of 
			 (NONE, SOME(body'), NONE) => 
				PPRArray(aux, sepop, termop, body', lenop, lengths)
			|(NONE, SOME(body'), SOME(last')) =>
			  	PPstruct(mkTyAux(#coverage aux), 
				[PPRArray(aux, sepop, termop, body', lenop, lengths), last'])
			|(SOME(first'), SOME(body'), NONE) =>
			  	PPstruct(mkTyAux(#coverage aux), 
				[first', PPRArray(aux, sepop, NONE, body', lenop, lengths)])
			|(SOME(first'), SOME(body'), SOME(last')) =>
			  	PPstruct(mkTyAux(#coverage aux), 
			    	[first', PPRArray(aux, sepop, termop, body', lenop, lengths), last'])
			| _ => ty
(*
		    val _ = (print "Done refining array to:\n"; printTy (measure newty))  
*)
		  in
		 	newty
		  end
	end 
	| PPstruct(a, tylist) =>
		let 
(*
		  val _ = (print "trying to refine array in struct \n"; printTy (measure ty))
*)
		  fun findRefined ty =
		  (*funtion to find the first base or refine type and convert it to refined type *)
			case ty of
			  PPstruct(_, tylist) => findRefined (hd tylist)
			| PPRefinedBase(_, refined, _) => SOME(refined)
			| PPBase(_, ltokens) => bsltokenlToRefinedOp ltokens
			| _ => NONE

		  fun updateTerm (arrayty, termop) =
			case (arrayty) of
				PPRArray(a, sep, term, body, len, lengths)=>
					PPRArray(a, sep, termop, body, len, lengths)
			| _ => raise TyMismatch
		  fun updateArray tylist newlist =
			case tylist of
			nil => newlist
			| t::tys =>
				case t of PPRArray (_, _, NONE, _, _, _) => 
				(
				  case tys of 
				  nil => newlist@[t]
				  | _ =>
				  	let
				  	val nextRefined= findRefined(hd tys)	
				  	val newArray = updateTerm(t, nextRefined)
					in newlist@[newArray]@tys
				  	end
				)
				| _ => updateArray tys (newlist@[t]) 

		  val tylist' = updateArray tylist nil
(*
		  val _ = (print "Done refining array in struct to:\n"; printTy (measure (Pstruct(a, tylist'))))
*)
		in PPstruct(a, tylist')
		end
	|_ => ty

and struct_to_array ty =
(*this rule converts a struct with repeated content to an fixed length RArray*)
(*TODO: it is possible to convert a subsequence of the tylist into an RArray
	but this could be expensive *)
  case ty of 
    PPstruct (a, tylist) =>
	if length tylist <3 then ty
	else
	  let
	    (*function to takes a tylist and divides it into 
		size n chunks and merges the chunks together, the resulting
		SOME tylist plus SOME sep is of size n or NONE if not possible to do that *)
(*
	    val _ = (print "Before:\n";printTy (measure ty))
*)
	    fun tylistEqual (tys1, tys2) =
		let
		  val pairs = ListPair.zipEq (tys1, tys2)
		  val equal = foldl myand true (map (fn (x, y) => newty_equal (1, x, y)) pairs)
		in
		  equal
		end handle UnequalLengths => false
		  	
	    fun getRefine(ty) = case ty of PPRefinedBase(_, r, _) => SOME(r) 
					| PPBase (_, tl) => bsltokenlToRefinedOp tl
					| _ => NONE
	    fun divMerge (tylist:NewTy list) (n : int) (newlist: NewTy list) = 
	      if ((length tylist) mod n)>0 andalso ((length tylist) mod n) < (n-1) 
	      then NONE
	      else
		(* last iteration possibly with a sep *)
		if (length tylist <>0) andalso (length tylist) = (length newlist)-1  
		then
		  let
			val refop = getRefine (List.last newlist)
			val body = List.take (newlist, n-1)
		  in
			case refop of
			NONE => NONE
			| SOME r => 
			  if tylistEqual (body, tylist) then 
			    SOME ((map mergeNewTyForArray (ListPair.zip (body, tylist))), SOME r)
			  else NONE
		  end
		else case tylist of 
		  nil => SOME (newlist, NONE)
		  | _ =>
		    let
		      val first = List.take (tylist, n)
		      val tail = List.drop (tylist, n)
		    in
		      case newlist of
			(*at the begining, the first chunk is reindexed at 0 *)
			nil => divMerge tail n (map (fn t => newreIndexRecNo t 0) first)
			| _ =>
		          if tylistEqual (newlist, first) then 
				divMerge tail n (map mergeNewTyForArray (ListPair.zip (newlist, first))) 
			  else NONE
		     end handle Subscript => NONE
	    fun try m n = 
		if (m>n) then NONE
	        else 
		let
		  val listop = divMerge tylist m nil 
		in
		  case listop of 
			NONE => try (m+1) n
			| _ => listop
		end
	    val tysop = try 1 ((length tylist) div 3)
	  in
	    case tysop of
		NONE => ty
		| SOME (tylist', NONE) => 
		  let
		    (* no sep *)
		    (* get the map of recNos *)
		    val recNoMap = newinsertToMap ty IntMap.empty
		    val len = (length tylist) div (length tylist')
		    val lens = map (fn (r, _) => (len, r)) (IntMap.listItemsi recNoMap)
		    val newty = PPRArray (a, NONE, NONE, PPstruct(mkTyAux (getNCoverage (hd tylist')), tylist'), 
			(SOME (IntConst (Int.toLarge len))), lens)
(*
	    	    val _ = (print "After:\n"; printTy newty)
*)
		  in newty 
		  end 
		| SOME (tylist', SOME r) => 
		  let
		    (* with sep *)
		    (* get the map of recNos *)
		    val recNoMap = newinsertToMap ty IntMap.empty
		    val len = (length tylist + 1) div ((length tylist') + 1)
		    val lens = map (fn (r, _) => (len, r)) (IntMap.listItemsi recNoMap)
		    val newty = PPRArray (a, SOME r, NONE, PPstruct(mkTyAux (getNCoverage (hd tylist')), 
			tylist'), 
			(SOME (IntConst (Int.toLarge len))), lens)
(*
	    	    val _ = (print "After:\n";printTy (measure newty))
*)
		  in newty 
		  end 
	  end
    | _ => ty

(* find negative number (both int and float)  rule (Phase one rule) *)
and find_neg_num ty =
	case ty of
	PPstruct (a, tylist) =>
	let
	  fun isPunctuation ty =
		case ty of
		  PPBase (_, (((PPpunc "-", "-"), _)::_)) => false
		| PPBase (_, (((PPpunc "+", "+"), _)::_)) => false
		| PPBase (_, (((PPpunc _, _), _)::_)) => true	
		| PPBase (_, (((PPwhite, _), _)::_)) => true	
		| _ => false
	  (*the tl1 represents a subset of records of tl2*)
	  fun mergetoklist (tl1: BSLToken list, tl2: BSLToken list): BSLToken list =
	  let
	    fun insertNumToMap (ltoken:BSLToken, recMap) = IntMap.insert (recMap, (#recNo (#2 ltoken)), ltoken)
	    fun insertSignToMap (((_, _), (loc:location)), recMap) =
		let
		  val tokOp = IntMap.find (recMap, (#recNo loc))
		in
		  case tokOp of
			SOME ((PPint, s), loc1) =>
				IntMap.insert (recMap, (#recNo loc), ((PPint, "-"^s), combLoc(loc, loc1)))
			| SOME ((PPfloat, s), loc1) =>
				IntMap.insert (recMap, (#recNo loc), ((PPfloat, "-"^s), combLoc(loc, loc1)))
			| _ => (print "RecNum doesn't match!" ; raise TyMismatch)
		end
	    val tokenmap= foldl insertNumToMap IntMap.empty tl2
	    val tokenmap = foldl insertSignToMap tokenmap tl1
	  in
	    IntMap.listItems tokenmap
	  end

	  fun combineTys (PPBase (a1, tl1), PPBase(a2, tl2)) = 
			PPBase (a2, mergetoklist (tl1, tl2))  
	     | combineTys (PPoption (_, PPBase(a1, tl1)), PPBase(a2, tl2)) =
			PPBase (a2, mergetoklist (tl1, tl2))
		
	  fun matchPattern (pre:NewTy list) (tys:NewTy list) =
		case tys of 
		   nil => pre
		  | (ty1 as PPBase(a1, ((PPpunc "-", "-"), _)::_))::((ty2 as PPBase(a2, ((PPint, _), _)::_)) :: post) => 
		     if (length pre = 0) then (matchPattern [combineTys (ty1, ty2)] post)
		     else if isPunctuation (List.last pre) then (matchPattern (pre@[combineTys (ty1, ty2)]) post)
		     else matchPattern (pre@[ty1, ty2]) post
		  | (ty1 as PPBase(a1, ((PPpunc "-", "-"), _)::_))::((ty2 as PPBase(a2, ((PPfloat, _), _)::_)) :: post) => 
		     if (length pre = 0) then (matchPattern [combineTys (ty1, ty2)] post)
		     else if isPunctuation (List.last pre) then (matchPattern (pre@[combineTys (ty1, ty2)]) post)
		     else matchPattern (pre@[ty1, ty2]) post
		  | (ty1 as PPoption(_, PPBase(a1, ((PPpunc "-", "-"), _)::_)))::
			((ty2 as PPBase(a2, ((PPint, _), _)::_))::post) => 
		     if (length pre = 0) then (matchPattern [combineTys (ty1, ty2)] post)
		     else if isPunctuation (List.last pre) then (matchPattern (pre@[combineTys (ty1, ty2)]) post)
		     else matchPattern (pre@[ty1, ty2]) post
		  | (ty1 as PPoption(_, PPBase(a1, ((PPpunc "-", "-"), _)::_)))::
			((ty2 as PPBase(a2, ((PPfloat, _), _)::_))::post) => 
		     if (length pre = 0) then (matchPattern [combineTys (ty1, ty2)] post)
		     else if isPunctuation (List.last pre) then (matchPattern (pre@[combineTys (ty1, ty2)]) post)
		     else matchPattern (pre@[ty1, ty2]) post
		  | x::rest => matchPattern (pre@[x]) rest
	in PPstruct(a, matchPattern nil tylist)
	end
	| _ => ty

(* int to float rule (Phase one rule)
several scenarios:
tys = Pint . Pint => Pfloat
tys = Pint  Poption (. Pint) => Pfloat
[not dot] tys [not dot]
Pint + Pfloat => Pfloat
*)
(*TODO: when checking no dot, we are assuming it's a base, it could be more complex than that,
  also, maybe the second case should rewrite to Pfloat + Pint, instead? *)
and to_float ty = 
	case ty of
	PPstruct (a, tylist) =>
	  let
(*
		val _ = (print "before:\n"; printTy (measure ty))
*)
		fun getFloatTokens (tokens1, tokens2) =
		  let
			fun insertIntToMap (ltok, intmap) =
				case ltok of
				((PPint, s), (loc:location)) => 
					IntMap.insert(intmap, (#recNo loc), ((PPfloat, s), loc)) 
				| _ => (print "Got a different token than Pint for int!"; raise TyMismatch)
			fun insertFracToMap (ltok, intmap) =
				case ltok of
				((PPint, s), loc) => 
				  let
					val tokOp = IntMap.find (intmap, (#recNo loc))
				  in
					case tokOp of
					  NONE => intmap
					  | SOME ((PPfloat, ipart), loc1) => 
						IntMap.insert(intmap, (#recNo loc), 
						((PPfloat, (ipart^"."^s)), combLoc(loc1, loc)))
					  | _ => raise TyMismatch
				  end
				| _ => (print "Got a different token than Pint for frac!"; raise TyMismatch)
			val tokenmap= foldl insertIntToMap IntMap.empty tokens1
			val tokenmap = foldl insertFracToMap tokenmap tokens2
		  in
			IntMap.listItems tokenmap
		  end
		fun combineTys tys =
		  case tys of
			[PPBase(a1, intTokList), PPBase(_, _), PPBase (_, intTokList1)]=> 
				PPBase(a1, getFloatTokens(intTokList, intTokList1))
		      |  [PPBase(a1, intTokList), PPoption(_, PPstruct(_, [(PPBase _), PPBase(a3, intTokList1)]))]=>
				PPBase(a1, getFloatTokens(intTokList, intTokList1))
		      | _ => raise TyMismatch
		fun matchPattern pre tys =
			case tys of 
			   nil => NONE
			  | (PPBase(a1, ((PPint, _), _)::_))::((PPBase(a2, ((PPpunc ".", "."), _)::_))::
				((PPBase(a3, ((PPint, _), _)::_)) :: post)) => 
				SOME (pre, List.take(tys, 3), post)
			  | (PPBase(a1, ((PPint, _), _)::_))::((PPoption(_, PPstruct(_,
				[PPBase(a2, ((PPpunc ".", "."), _)::_), PPBase(a3, ((PPpunc ".", "."), _)::_)]))):: post) => 
				SOME (pre, List.take(tys, 2), post)
			  | (PPBase(a1, ((PPpunc ".", "."), _)::_))::(x::rest) => 
				matchPattern (pre@(List.take(tys, 2))) rest
			  | x::rest => matchPattern (pre@[x]) rest
			
		(* there can be multiple floats in the same tylist, we are getting all of them *)	
		fun matchAll pre tys = 
		  let 		  
			val listOp = matchPattern nil tys
		  in
			case listOp of
			NONE => pre@tys
			| SOME (pre', tys', post) => matchAll (pre@pre'@[(combineTys tys')]) post
		  end
		val newtylist = matchAll nil tylist
		val newty = if (length newtylist) = 1 then hd newtylist
			    else PPstruct(a, newtylist)
(*
		val _ = (print "New Ty:\n"; printTy (measure newty))
*)
	  in
		newty
	  end
	| PPunion (a, [ty1, ty2]) =>
	  let
		fun toFloatTokens ltokens =
		  case ltokens of
		  nil => nil
		  | ((PPint, s), loc)::tail => ((PPfloat, s), loc)::(toFloatTokens tail)
		  | _ => raise TyMismatch
	  in
		case (ty1, ty2) of 
		   (PPBase(a1, toks1 as (((PPint, _), _)::_)), PPBase(a2, toks2 as (((PPfloat, _), _)::_))) => 
			PPBase(a, (toFloatTokens toks1)@toks2)
		  | (PPBase(a1, toks1 as (((PPfloat, _), _)::_)), PPBase(a2, toks2 as (((PPint, _), _)::_))) => 
			PPBase(a, toks1@(toFloatTokens toks2))
		  | _ => ty
	  end
	| _ => ty

(* this rule is used for only one case now: ty1 + Pemty ==> Poption ty1 *)
and union_to_optional ty =
	case ty of 
	PPunion (a, tys) =>
	    let 
		fun isNotPempty ty =
		case ty of
		  PPBase (_, ltokens) => 
		    (case (hd ltokens) of 
		     ((PPempty, _), _) => false
		     | _ => true)
		 | _ => true 

		val nonPemptyTys = List.filter isNotPempty tys
	     in
		if length nonPemptyTys = 0 
		  then genEmptyPPBase a (getNCoverage ty)
		else if length nonPemptyTys = 1 then PPoption(a, (hd nonPemptyTys))
	   	else ty
	     end	
	| _ => ty

(* post constraint rules, these require the cmap to be filled  and the 
data labeled *)

(* a unique Base type becomes a constant type *)
(* Notice that the unique constraint has not been taken away from the LabelMap *)
and uniqueness_to_const (cmos:constraint_map) ty =
case ty of
  PPBase({coverage, label=SOME id, ...}, tokens) => 
  if length tokens>0 andalso refineableBase (#1 (hd tokens)) then
    (case LabelMap.find(cmos, id) of  
      SOME consts => 
        let
      		fun find_unique clist newlist = case clist of
      	    		NUnique x :: t => (SOME(x), newlist @ t)
      	  		| h :: t => find_unique t (newlist@[h])
      	  		| nil => (NONE, newlist)
		val (somety, newconsts) = find_unique consts nil
		val (newcmos, _) = LabelMap.remove(cmos, id)
	    val newcmos = LabelMap.insert(newcmos, id, newconsts)
        in
       		case somety of 			
		  SOME((PPbXML, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPeXML, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
        | SOME((PPint, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				IntConst(Option.valOf(LargeInt.fromString x)), tokens)
			)
		| SOME((PPfloat, x)) => 
            let
              fun isDot c = c = #"."
              val (i, junk) = Substring.splitl (not o isDot) (Substring.full x)
              val (junk, r) = Substring.splitr (not o isDot) (Substring.full x)
              val ii = Substring.string i
              val rr = Substring.string r
              val floatret = if String.size ii = String.size x orelse String.size rr = String.size x then FloatConst(ii, "nan") else FloatConst(ii, rr)
            in
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				floatret, tokens)
			)
            end
		| SOME((PPblob, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPtime, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPdate, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPip, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPhostname, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPpath, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPurl, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPurlbody, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPemail, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPmac, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPwhite, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPword, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPhstring, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPid, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPmessage, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPtext, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
		| SOME((PPpermission, x)) => 
			(
				newcmos, 
				PPRefinedBase((mkTyAux1(coverage, id)), 
				StringConst(x), tokens)
			)
       		| _ => (cmos, ty)                                (* no punctuation *)
      	end
    | NONE => (cmos, ty)
    )
   else (cmos, ty)
| _ => (cmos, ty)

(* convert a sum into a switched type if a switch constraint is defined *)
(* a sum can only be determined by a base value that is the son of any of the sum's
   ancestors, for a start, we just look at the sum's siblings in a tuple *) 
and sum_to_switch cmos ty =
case ty of 
  PPstruct(aux, tylist) =>
  let	
	(* function to test if a base value with a specific id exists in a ty list*) 
	(* only int base or refined base as well as enum can be considered *)
	fun existsbase(tlist, id) = 
		case (tlist) of
			PPBase(a, ((PPint, _), l)::ts)::tail => if Atom.same(id, getLabel(a)) then true
							else existsbase(tail, id)
			| PPRefinedBase(a, (Int _), _)::tail => if Atom.same(id, getLabel(a)) then true
							else existsbase(tail, id)
(*			| PPRefinedBase(a, (Float _), _)::tail => if Atom.same(id, getLabel(a)) then true
							else existsbase(tail, id) *)
			| PPRefinedBase(a, (Enum _), _)::tail => if Atom.same(id, getLabel(a)) then true
							else existsbase(tail, id)
			| ty::tail => if (Atom.same(getLabel(getNAuxInfo(ty)), id)) then false
					else existsbase(tail, id)
			| nil => false
	
	(* test if a sum is a switched sum depending on some other id, test only the first n elements of tylist*)
	fun is_switch(cmos:constraint_map, id, n) = 
	  case LabelMap.find(cmos, id) of  
      		SOME consts => 
        	  let 
			fun cost_switch c =
				case c of
					NONE => some(Int.maxInt)
					| SOME(NSwitched (_, mappings)) => (length mappings)
					|_ => raise TyMismatch
			fun find_switch(clist, newclist, cur_cheapest) =
      	  			case clist of 
				  NSwitched (ids, mappings) :: t => 
				    (* we are only interested in 1-1 mapping in switched *)
				    (* we also use the "cheapest" switch of all the switches and
					delete all the more expensive 1-1 switches *)
				    if length(ids) = 1 andalso 
					length(#1 (hd mappings))=1 andalso existsbase(List.take(tylist, n), hd ids)
				    then 
					(
					if (cost_switch(SOME(NSwitched (ids, mappings)))< 
						cost_switch(cur_cheapest))
					then find_switch (t, newclist, SOME(NSwitched(ids, mappings)))
					else find_switch (t, newclist, cur_cheapest)
					)
				    else find_switch (t, (newclist@[NSwitched(ids, mappings)]), cur_cheapest)
      	  			  | h :: t => find_switch (t, (newclist@[h]), cur_cheapest)
      	  			  | nil => (case cur_cheapest of 
						SOME(NSwitched(ids, mappings)) => 
							(SOME(ids, mappings), newclist)
						| _ => (NONE, newclist)
					   )
			val (someidmappings, newconsts) = find_switch(consts, nil, NONE)
			val (newcmos, _) = LabelMap.remove(cmos, id)
	    		val newcmos = LabelMap.insert(newcmos, id, newconsts)
		  in
			(someidmappings, newcmos)
		  end 
    	 	| NONE => (NONE, cmos) 
			
	fun to_switch (ty, id, mappings)=
	(* convert a union ty to a Switch type if possible given an id 
	   from a switch variable and mappings of a list of tuples 
	  ([token option], token option) *)
	  case ty of
	    PPunion(aux, tlist) =>
	  	let
		    fun getrefine (index, mappings) = 
		    (*given an index, give a list of refined values that points to this index from the mapping*)
		      case mappings of 
			([SOME tok1], SOME((PPint, i)))::tail => 
				if ((Option.valOf(LargeInt.fromString i))=index) then bstokentorefine(tok1)::getrefine(index, tail)
				else getrefine (index, tail)
		      	| _::tail => getrefine(index, tail)
		      	| nil => nil
		    (*assume index starts from 1 for the tylist branches*)
		    fun   gen_ref_ty_list (_, nil, _) = nil
			| gen_ref_ty_list (mappings, head::tail, index) =
			(case getrefine(index, mappings) of
			    nil => nil(* returns immediately if no refine is found *)
			  | refined => if length(refined) = 1 then
						((hd refined), head):: gen_ref_ty_list(mappings, tail, index+1)
					else
						(Enum(refined), head):: gen_ref_ty_list(mappings, tail, index+1)
			)
		    fun reorder refTyList =
			let fun isDefault (re, switchedTy) =
				case re of 
				  StringConst "*" => true
				  | _ => false
			    fun isNotDefault (re, switchedTy) = not (isDefault (re, switchedTy))
			    val defaultpairs = List.filter isDefault refTyList
			    val others = List.filter isNotDefault refTyList
			in (others@defaultpairs)
			end
		    val refine_ty_list = reorder(gen_ref_ty_list (mappings, tlist, 1))
		in
		    if (length refine_ty_list = length tlist) 
		    then (PPSwitch (aux, id, refine_ty_list))
		    else ty
		end
	   | _ => ty

 	fun containsPempty tylist =
	  case tylist of
		nil => false
		| PPoption(_, _)::_ => true
		| PPBase(_, (((PPempty, _), _)::_))::_ => true
		| ty::tail => containsPempty tail

	fun rewrite_switch (cmos, tlist) =
	    case tlist of 
		h::rest => 
		(
		case h of 
		  PPunion(a, sumlist) => 
		    if (containsPempty sumlist) then
		    	let val (newcmos, rest')=rewrite_switch(cmos, rest)
		       	in (newcmos, h::rest')
			end
		    else
			  let 
			    val (c, newcmos)  = is_switch(cmos, some(#label a), (length tylist)-(length tlist)) 
			  in 
			    case c of 
				SOME ([id], mappings) =>
					(
					  let 
						val (newcmos, rest') = rewrite_switch(newcmos, rest)
					  in
						(newcmos, to_switch(h, id, mappings)::rest')
					  end
					)
				| _ =>    let val (newcmos, rest') = rewrite_switch(newcmos, rest)
					  in
					  	(newcmos, h::rest')
					  end
			  end
		  | _ => 	let val (newcmos, rest')=rewrite_switch(cmos, rest)
		       		in (newcmos, h::rest')
				end
		)
		| nil => (cmos, nil)

	val (newcmos, tylist') = rewrite_switch(cmos, tylist)
  in 
	(newcmos, PPstruct(aux, tylist'))
  end
  | _ => (cmos, ty)

(*convert an enum constraint to a Enum refined type or a range constraint to 
	a range refined type *)
and enum_range_to_refine cmos ty = 
  case ty of                  
    PPBase({coverage, label=SOME(id), ...}, b) => 
      if length b>0 andalso enumerableBase (#1 (hd b)) then
        (case LabelMap.find(cmos,id) of 
         SOME consts =>    
            let             
                fun check_enum list newconsts=  
                  case list of (NEnumC set) :: t =>
                      let
                        val items = NewBDSet.listItems set
                        val refs = map bstokentorefine items
                        val ty' = (if length(refs)=1 then 
				PPRefinedBase(mkTyAux1(coverage, id), hd refs, b)
				else
				(if (length(refs)=0) then ty
				 else if (allStringConsts refs) then
				  let
		                  (*funtion to sort the all string const refined types by 
				    the length of the strings from longest to shortest, 
				    this is so as to attemp the longer and more specific
		      		    strings first*)
		    			fun shorter (re1, re2) =
					  case (re1, re2) of
					  (StringConst x, StringConst y) => (size x < size y)
					  | _ => raise TyMismatch
					val sorted_res = ListMergeSort.sort shorter refs
				  in
					PPRefinedBase(mkTyAux1(coverage, id), Enum sorted_res, b)
				  end
				 else PPRefinedBase(mkTyAux1(coverage, id), Enum refs, b)
				)
				)
(*                     	val _ = print ("ENUM: " ^ (TyToString ty')^"\n") *)
                      in
                        (ty', newconsts@t)
                      end
		  | (NRange(min,max)):: t => (PPRefinedBase(mkTyAux1(coverage, id), 
				Int(min, max), b), newconsts@t)
                  | h :: t => check_enum t (newconsts@[h])
                  | nil => (ty, newconsts) 
		val (newty, newconsts) = check_enum consts nil
		val (newcmos, _) = LabelMap.remove(cmos, id)
	    	val newcmos = LabelMap.insert(newcmos, id, newconsts)
            in
		(newcmos, newty)
            end
        | NONE => (cmos, ty)
       )
     else (cmos, ty)
  | _ => (cmos, ty)


(* check if a ty is a blob by dividing the variance of this ty by the number of
   tokens per record associated with this ty *)

fun mergeAdjPPblobs (t1, l1)  (t2, l2) =
	if adjacent (t1, l1) (t2, l2) then
	  case (t1, t2) of
	    ((PPblob, s1), (PPblob, s2)) => ((PPblob, (s1 ^ s2)), combLoc (l1, l2))
	  | _ => raise InvalidToken
	else raise InvalidToken
fun merge_tls (tl1, tl2) =
(*
	let 
	  val _ = print ("TL1 : " ^ (LTokensToString tl1) ^ "\n")
	  val _ = print ("TL2 : " ^ (LTokensToString tl2) ^ "\n")
	in
*)
	  if tl1 = nil then tl2
	  else if tl2 = nil then tl1
	  else
	   (* we take one element from tl1 and check against
		every element in tl2 in order and find the
		element in tl2 whose location immediately precedes
		the element in tl1 and stick these two element together,
		if not found, put this element in tl2 *)
	   let fun appendto backl (t, outputl) =
		case List.find 
		  (fn t' => adjacent t t') backl of
		  SOME ltoken => outputl @ [mergeAdjPPblobs t ltoken]
		| NONE =>  (outputl @ [t])
	       fun prepend frontl (t, outputl) =
		case List.find 
		  (fn t' => adjacent t' t) frontl of
		  SOME ltoken => outputl @ [mergeAdjPPblobs ltoken t]
		| NONE =>  (outputl @ [t])
	   in	
	   if length tl2 >= length tl1 (* tl1 is subset of tl2*)
	   then	foldl (appendto tl1) [] tl2
	   else foldl (prepend tl2) [] tl1 
	   end
(*
	end
*)

(* merge all the tokens belonging to a ty to one single token list *)
(* invarants are that the token list are ordered by their line no and
   and the two corresponding tokens in lists are adjacent to each other*)
fun mergeTokens ty =
  let 
      fun mysort tl = 
	    let fun gt ((t1, l1), (t2, l2)) = (compLocation (l1, l2) = GREATER)
	    in
	    ListMergeSort.sort gt tl
	    end
      fun tos ((t : BSToken), l) = ((PPblob, (#2 t)), l)
      fun collapse (tl : BSLToken list) sep =
	let fun col_helper tl cur_tok newtl =
	  case tl of
	    nil => 
		(
		  case cur_tok of
		    NONE => newtl
		  | SOME t => newtl @ [t]
		)
	  | t :: tl => 
		(
		  case cur_tok of
		    NONE => col_helper tl (SOME t) newtl
		  | SOME (ct as ((PPblob, s), loc)) => 
			if adjacent ct t then 
			  col_helper tl (SOME (mergeAdjPPblobs ct t)) newtl
			else 
			  let val newloc = {lineNo = (#lineNo loc), beginloc = (#beginloc loc),
				endloc = (#endloc loc) + (size sep), recNo = (#recNo loc)} 
		  	      val ct_sep = ((PPblob, (s ^ sep)), newloc) 
		          in
			     col_helper (t :: tl) NONE (newtl @ [ct_sep])
			  end
		 | _ => raise InvalidToken
		)
	in col_helper tl NONE nil
	end

  in
    let val final_tl = 
      case ty of
	   PPBase (a, l) => 
		if isEmpty ty then nil else map tos (mysort l)
        |  PPTBD (a, _, l) => raise TyMismatch
        |  PPBottom (a, _, l) => raise TyMismatch
        |  PPstruct (a, tys) => 
		(* assume none of the tys are empty ty *)
		let val ltl_list = map mergeTokens tys
		in
		  foldl merge_tls nil ltl_list
		end
        |  PPunion (a, tys)       => 
		let val nonEmptyTys = List.filter (fn ty => not (isEmpty ty)) tys
		    val tls = map mergeTokens nonEmptyTys
		in mysort (List.concat tls) end
        |  PParray (a, {tokens=t, lengths=len, first=f, body=b, last=l}) => 
		raise TyMismatch
		(*
		merge_tls ((merge_tls ((mergeTokens f), (mergeTokens b))), (mergeTokens l))
		*)
        |  PPRefinedBase (aux, re, l) => map tos (mysort l)
        |  PPSwitch (a, id, retys) => 
		let val nonEmptyReTys = List.filter (fn (_, ty) => not (isEmpty ty)) retys
		    val tls = map (fn (_, ty) => mergeTokens ty) nonEmptyReTys
		in mysort (List.concat tls)
		end
        |  PPRArray (a,sep,term,body,len,lengths) => 
		let val tl = mergeTokens body
		val sepstr = case sep of 
			SOME (IntConst a) => LargeInt.toString a
			| SOME (FloatConst (a, b)) => a ^ "." ^ b
			| SOME (StringConst s) => s
			| _ => ""
		in
		   ((*print "Collapsing array:\n";
		   printTy ty; *)
		   collapse tl sepstr)
		end 
        |  PPoption (a, body)  => mergeTokens body
     in
       final_tl
     end
  end

fun isBlob ty =
  case ty of
    PPBase _ => false
  | PPRefinedBase _ => false
  | PPoption _ => false
  (* | PPstruct _ => false *)
  | _ =>
	let val avgNumTokensPerRec = (Real.fromInt (getNumTokens ty)) / 
			(Real.fromInt (getNCoverage ty)) 
	    val tyc = toReal (getNTypeComp ty)
	    val adc = toReal (getNAtomicComp ty) 
	    val var = newvariance ty
	    val ratio = var / avgNumTokensPerRec 
	    val ratio1 = tyc / adc
(*
	    val _ = print "For Ty .....\n"
	    val _ = printTy ty
	    val _ = print ("AvgNumTokensPerRec = " ^ (Real.toString avgNumTokensPerRec) ^ "\n")
	    val _ = print ("Variance = " ^ Real.toString var ^ "\n")
*)
	    val _ = print ((getLabelString (getNAuxInfo ty)) ^ ":\t")
	    val _ = print ("Ratio = " ^ Real.toString ratio ^ "\t")
	    val _ = print ("Comp Ratio = " ^ Real.toString ratio1 ^ "\n")
	in
	  ratio > 1.0 andalso (ratio + ratio1 > 4.0)
	end
(* TODO: augment this function to search for more patterns by merging
  all tokens in the ty and then do string matching *)
fun getStoppingPatt ty =
  case ty of
    PPRefinedBase (a, StringME regex, _) => (NONE, SOME regex)
  | PPRefinedBase (a, IntConst i, _) => (SOME (LargeInt.toString i), NONE)
  | PPRefinedBase (a, FloatConst (i, d), _) => (SOME (i ^ "." ^ d), NONE)
  | PPRefinedBase (a, StringConst s, _) => (SOME s, NONE)
  | _ => (NONE, NONE)

fun containString ltokens str =
	case ltokens of
	  nil => false
	| (t, loc)::rest => 
	  (
	    case t of
	      (PPblob, s) => if String.isSubstring str s then true
			 else containString rest str
	    | _ => raise InvalidToken
	  )
	
fun containPatt ltokens patt = true (* assume true for now as we don't have regex yet *)


(* update the current ty to a possible ty if the sibling contains legit stopping pattern *)	
(* NOTE: we don't go inside array for now *)	
fun updateWithBlobs s_opt ty =
(*
  let fun f tys =
    case tys of
	nil => nil
      | [ty] => [mkBlob NONE ty]
      | ty::(sib::x) => (mkBlob (SOME sib) ty):: (f (sib::x))
  in
*)
  let fun f tys s_opt = 
	case tys of
	  nil => nil
	| ty::tys => 
	    let val newty = updateWithBlobs s_opt ty 
	    in
		case newty of
		  PPRefinedBase (a, Blob _, _) => newty::(f tys NONE)
		| _ => newty::(f tys (SOME newty))
	    end
  fun mergeAdjBlobs curBlob tys newtys =
   let fun mergeBlobs b1 b2 = 
	case (b1, b2) of
	(PPRefinedBase (a1, Blob _, tl1), PPRefinedBase (a2, Blob x, tl2)) =>
	  PPRefinedBase (a1, Blob x, merge_tls (tl1, tl2))
	| _ => raise TyMismatch
   in
     case tys of
	(b as PPRefinedBase (a, Blob _, tl)) :: tys => 
		(
		case curBlob of
		  SOME cb =>
		    let val newb = mergeBlobs cb b in
		      mergeAdjBlobs (SOME newb) tys newtys
		    end
		| NONE => mergeAdjBlobs (SOME b) tys newtys
		)
	| t :: tys => 
		(
		case curBlob of 
		  SOME cb => mergeAdjBlobs NONE tys (newtys@[cb, t])
		| _ => mergeAdjBlobs NONE tys (newtys @ [t])
		)
	| nil => 
		(
		case curBlob of 
		  SOME cb => (newtys@[cb])
		| _ => newtys
		)
    end
  fun isBlobTy ty =
	case ty of
	  PPRefinedBase (_, Blob _, _) => true
	| _ => false
  in
  case ty of
	  PPstruct(a, tys) => 
	   let val newtys = List.rev (f (List.rev tys) s_opt)
(*
	       val _ = print "**** BEGIN ****************\n"
	       val _ = map printTy newtys
	       val _ = print "**** END ****************\n"
*)
	       in mkBlob s_opt (PPstruct (a, mergeAdjBlobs NONE newtys nil))
	   end
   	| PPunion(a, tys) =>
	    let val newtys = map (updateWithBlobs s_opt) tys 
	        val blobtys = List.filter isBlobTy newtys
		val newblob = List.foldl (fn (blob, l) =>
				case l of
				  nil => [blob]
				| [oldblob] => [mergeNewTy (oldblob, blob)]
				| _ => raise Unexpected) nil blobtys
		val nonblobtys = List.filter (fn x => not (isBlobTy x)) newtys
	    in
	      mkBlob s_opt (PPunion (a, (nonblobtys @ newblob)))
	    end
	| PPRArray (a, sep, term, body, fixed, lengths) =>
	   (
	    case (sep, term) of
	    (SOME s, SOME t) => 
		if refine_equal (s, t) then
		  (* use a dummy refinedbase type as righthand side sibling *)
		  let val sib_opt = SOME (PPRefinedBase (a, s, nil)) in
	    	    mkBlob s_opt (PPRArray(a, sep, term, updateWithBlobs sib_opt body, fixed, lengths))
		  end
		else mkBlob s_opt (PPRArray (a, sep, term, body, fixed, lengths))
	    | _ => mkBlob s_opt (PPRArray (a, sep, term, body, fixed, lengths))
	   )
	| PPSwitch(aux, id, retys) =>
	    let val newretys = map (fn (re, t) => (re, updateWithBlobs s_opt t)) retys in
	      mkBlob s_opt (PPSwitch(aux, id, newretys))
	    end
	| PPoption (aux, ty) => mkBlob s_opt (PPoption(aux, updateWithBlobs s_opt ty))
	| _ => ty
  end	

and mkBlob sibling_opt ty = 
  if isBlob (newmeasure ty) then
    let val ltokens = mergeTokens ty 
	(* val _ = printTy ty  *)
	(* val _ = print (LTokensToString ltokens)  *)
    in 
    case sibling_opt of
	  NONE => 
		let val newty = PPRefinedBase(getNAuxInfo ty, Blob(NONE, NONE), ltokens)
		    val _ = print "******* FOUND BLOB ABOVE ******\n"
		in newty 
(*
		if score newty < score ty then newty 
		else updateWithBlobs sibling_opt ty
*)
		end
	| SOME sibty =>
	  (
		let
		  (* val _ = print "Getting stopping patt\n" *)
		  val pair = getStoppingPatt sibty in
		case pair of 
		  (SOME str, NONE) => 
		    if containString ltokens str then ty
		    else 
			let val newty = PPRefinedBase(getNAuxInfo ty, Blob pair, ltokens)
		            val _ = print "******* FOUND BLOB ABOVE ******\n"
			in newty
	(*
			if score newty < score ty then newty 
			else updateWithBlobs sibling_opt ty
	*)
			end
		| (NONE, SOME str ) => 
		    if containPatt ltokens str then ty
		    else 
			let val newty = PPRefinedBase(getNAuxInfo ty, Blob pair , ltokens)
		            val _ = print "******* FOUND BLOB ABOVE ******\n"
			in newty
	(*
			if score newty < score ty then newty 
			else updateWithBlobs sibling_opt ty
	*)
			end
		| _ => ty
		end
	)
    end
  else ty

(* the actual reduce function can either take a SOME(const_map) or
NONE.  It will use the constraints that it can apply. *)
and reduce phase ty = 
let
  val phase_one_rules : pre_reduction_rule list = 
		[ 	
			remove_degenerate_list,
			unnest_tuples,
			unnest_sums,
			prefix_postfix_sums,
			remove_nils,
		  	unused_branches,
(*
			extract_table_header,
*)
			union_to_optional,
			struct_to_array,
			find_neg_num,
			to_float,
			refine_array
		]
  val phase_two_rules : post_reduction_rule list =
		[ 
		  uniqueness_to_const, 
		  adjacent_consts,
		  enum_range_to_refine,
		  sum_to_switch
		]
  val phase_three_rules : pre_reduction_rule list = 
		[ 	
			remove_degenerate_list,
			unnest_tuples,
			unnest_sums,
			prefix_postfix_sums,
			remove_nils,
		  	unused_branches,
			union_to_optional
(*
			, extract_table_header
*)
		]

  (* generate the list of rules *)
  val cmap = case phase of
	2 => Constraint.newconstrain' ty
	| _ => LabelMap.empty
(* Print the constraints 
  val _ = printConstMap cmap
*)
  (* returns a new cmap after reducing all the tys in the list and a new tylist *)
  fun mymap f phase cmap tylist newlist =
	case tylist of 
		ty::tail => let 
				val(cmap', ty') = f phase cmap ty
			    in	mymap f phase cmap' tail (newlist@[ty'])
			    end
		| nil => (cmap, newlist)

  (*reduce a ty and returns the new constraint map and the new ty *)
  (* phase = 0: pre_constraint; phase = 1: post_constraint *)
  fun reduce' phase cmap (ty:NewTy) =
    let 
      	(* go bottom up, calling reduce' on children values first *)
      	val (newcmap, reduced_ty) = 
			case ty of
			  PPstruct (a, tylist) => let 
				val (cmap', tylist') = mymap reduce' phase cmap tylist nil
				in (cmap', PPstruct (a, tylist'))
				end
			| PPunion (a, tylist) => let
				val (cmap', tylist') = mymap reduce' phase cmap tylist nil
				in (cmap', (newmeasure (PPunion(a, tylist'))))
				end
			| PParray (a, {tokens, lengths, first, body, last}) => 
				let
				val (cmap1, firstty) = reduce' phase cmap first
				val (cmap2, bodyty) = reduce' phase cmap1 body 
				val (cmap3, lastty) = reduce' phase cmap2 last 
				in
				(cmap3, PParray(a, {tokens=tokens, lengths=lengths, 
				first=firstty,
				body= bodyty,
				last=lastty}))
				end
			| PPBase b => (cmap, PPBase b)
			| PPTBD b => (cmap, PPTBD b)
			| PPBottom b => (cmap, PPBottom b)
			| PPRefinedBase b => (cmap, PPRefinedBase b)
                        | PPSwitch (a, id, pairs) =>  
                                let
                                val (refs, tylist) = ListPair.unzip(pairs)
                                val (cmap', tylist') = mymap reduce' phase cmap tylist nil
                                in (cmap', PPSwitch (a, id, ListPair.zip(refs, tylist')))
                                end
                        | PPRArray (a, sep, term, body, len, lengths) => 
                                let
                                val (cmap', body') = reduce' phase cmap body
                                in
                                (cmap', PPRArray (a, sep, term, body', len, lengths))
                                end
			| PPoption (a, body) => 
                                let
                                val (cmap', body') = reduce' phase cmap body
                                in
                                (cmap', PPoption(a, body'))
				end

	  fun iterate cmap (ty:NewTy) = 
	  let
	    (* calculate the current cost *)
	    (*
	    val _ = (print ("Old Ty: \n"); printTy (measure ty))
	    *)
	    val cur_cost = score ty
	    (* apply each rule to the ty *)
	    val cmap_ty_pairs = case phase of
			1 => map(fn x => (cmap, x ty)) phase_one_rules
		|	2 => map (fn x => x cmap ty) phase_two_rules
		|	3 => map(fn x => (cmap, x ty)) phase_three_rules
		| 	_ => (print "Wrong phase!\n"; raise TyMismatch)
	    (* find the costs for each one *)
	    val costs = map (fn (m, t)=> score t) cmap_ty_pairs 
	    val pairs = ListPair.zip(cmap_ty_pairs,costs)
	    (* we do greedy descent for now *)
	    fun min((a, b),(c, d)) = 
		if b < d then (a, b) else (c, d)
	    (* find the minimum cost out of the ones found *)
	    val ((newcmap, newTy), lowCost) = foldr min ((cmap, ty), cur_cost) pairs
	  in
	  	(* as long as the cost keeps going down, keep iterating *)
	  	if lowCost < cur_cost then 
		((*print "Old Ty:\n"; printTy (measure ty); 
		 print "New Ty:\n"; printTy (measure newTy);*) 
		 iterate newcmap newTy)
	  	else (newcmap, newTy) 
	  end
    in
 	(iterate newcmap reduced_ty) 
    end
(*val cbefore = cost cmap ty *)
  val (cmap', ty') = reduce' phase cmap ty 
(*  val cafter = cost cmap' ty'*)
(*  val _ = print ("Before:" ^ (Int.toString cbefore) ^ " After:" ^ (Int.toString cafter) ^ "\n") *)
in
  sortPPUnionBranches ty'
end 

end