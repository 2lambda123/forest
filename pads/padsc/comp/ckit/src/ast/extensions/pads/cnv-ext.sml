structure CnvExt : CNVEXT = struct
  structure PT   = ParseTree     (* the parse tree *)
  structure PX   = ParseTreeExt  (* Pads extensions *)
  structure P    = ParseTreeUtil (* Utility functions for manipulating the parse tree *)
  structure PE   = PError        (* Error reporting utilities *)
  structure PBTys = PBaseTys     (* Information about the pads base types *)
  structure PL   = PLib          (* Information about values/functions available from pads library *)
  structure PTSub= ParseTreeSubst(* Function for subtituting an expression for a string in an expression *)
  structure PPL  = PPLib
  structure BU   = BuildUtils

  structure TU   = TypeUtil      (* Ckit module: type utility functions *)
  structure SYM  = Symbol
  structure B    = Bindings
  structure G :> GENGALAX = GenGalax
  structure PN = PNames
  
  open PNames

  type coreConversionFuns = 
	{
	 stateFuns : State.stateFuns,
	 mungeTyDecr: (Ast.ctype*ParseTree.declarator ->Ast.ctype * string option),

	 cnvType : bool*ParseTree.decltype -> Ast.ctype*Ast.storageClass,
	 cnvExpression: ParseTree.expression -> Ast.ctype * Ast.expression,
	 cnvStatement : ParseTree.statement -> Ast.statement,
	 cnvExternalDecl: ParseTree.externalDecl -> Ast.externalDecl list,

	 wrapEXPR: (Ast.ctype*Ast.coreExpression -> Ast.ctype*Ast.expression),
	 wrapSTMT: Ast.coreStatement -> Ast.statement,
	 wrapDECL: Ast.coreExternalDecl -> Ast.externalDecl,
	 evalExpr: ParseTree.expression -> 
	              (IntInf.int option * Ast.ctype * Ast.expression * bool) (* PADS *)
	 }

  type expressionExt = (ParseTree.specifier, ParseTree.declarator, ParseTree.ctype, ParseTree.decltype,
			ParseTree.operator, ParseTree.expression, ParseTree.statement)
                       ParseTreeExt.expressionExt

  type statementExt = (ParseTree.specifier, ParseTree.declarator, ParseTree.ctype, ParseTree.decltype,
		       ParseTree.operator, ParseTree.expression, ParseTree.statement)
	              ParseTreeExt.statementExt

  type externalDeclExt = (ParseTree.specifier, ParseTree.declarator, ParseTree.ctype, ParseTree.decltype,
		          ParseTree.operator, ParseTree.expression, ParseTree.statement)
	                 ParseTreeExt.externalDeclExt 

  type specifierExt = (ParseTree.specifier, ParseTree.declarator, ParseTree.ctype, ParseTree.decltype,
		       ParseTree.operator, ParseTree.expression, ParseTree.statement)
	              ParseTreeExt.specifierExt

  type declaratorExt = (ParseTree.specifier, ParseTree.declarator, ParseTree.ctype, ParseTree.decltype,
		        ParseTree.operator, ParseTree.expression, ParseTree.statement)
	               ParseTreeExt.declaratorExt

  type declarationExt = (ParseTree.specifier, ParseTree.declarator, ParseTree.ctype, ParseTree.decltype,
		        ParseTree.operator, ParseTree.expression, ParseTree.statement)
	               ParseTreeExt.declarationExt

  type extensionFuns = 
      {CNVExp: expressionExt -> Ast.ctype * Ast.expression,
       CNVStat: statementExt -> Ast.statement,
       CNVBinop: {binop: ParseTreeExt.operatorExt, arg1Expr: ParseTree.expression, arg2Expr: ParseTree.expression}
                 -> Ast.ctype * Ast.expression,
       CNVUnop: {unop: ParseTreeExt.operatorExt, argExpr: ParseTree.expression}
                 -> Ast.ctype * Ast.expression,
       CNVExternalDecl: externalDeclExt -> Ast.externalDecl list,
       CNVSpecifier: {isShadow: bool, rest : ParseTree.specifier list} 
                 -> specifierExt
                 -> Ast.ctype,
       CNVDeclarator: Ast.ctype * declaratorExt 
                 -> Ast.ctype * string option,
       CNVDeclaration: declarationExt -> Ast.declaration list}

  (****************** Abbreviations ******************************)
  type pty = PX.Pty

  type pcty = ParseTree.ctype
  type pdty = ParseTree.decltype
  type pcexp = ParseTree.expression
  type pcstmt = ParseTree.statement
  type pcdecr = ParseTree.declarator


  type acty = Ast.ctype
  type aexp = Ast.expression

  datatype litType = PChar | PString | PRegExp
  fun getLitSize (x, e) = 
      case (x, e) of 
        (PChar, _) => TyProps.mkSize(1,0)
      | (PString, PT.String s) => TyProps.mkSize(String.size s,0)
      | (_, _) => TyProps.Variable

  fun isSuffix s2 s1 = 
      let val l1 = String.size s1
	  val l2 = String.size s2
      in
	  if l1 < l2 then false
	  else String.extract(s1, l1 - l2, NONE) = s2
      end

  (****************** Conversion Functions ***********************)

  exception CnvExt of string

  fun CNVStat _ = raise (CnvExt "No proper extensions to statements")

  fun CNVBinop _ = raise (CnvExt "No proper extensions to binops")

  fun CNVUnop _ =  raise (CnvExt "No proper extensions to unnops")

  fun CNVSpecifier _ _ = raise (CnvExt "No proper extensions to specifiers")

  fun CNVDeclarator _ = raise (CnvExt "No proper extensions to declarators")

  fun CNVDeclaration _ = raise (CnvExt "No proper extensions to declarations")

  fun makeExtensionFuns ( {stateFuns,
			   mungeTyDecr,
			   cnvType,
			   cnvExpression,
			   cnvStatement,
			   cnvExternalDecl,
			   wrapEXPR,
			   wrapSTMT,
			   wrapDECL,
			   evalExpr}:coreConversionFuns) = 
      let 

	(* Imported Values ***********************************************************)
    val {locFuns =
	 {pushLoc, popLoc, getLoc, error, warn},
	 tidsFuns =
	 {pushTids, resetTids},
	 envFuns =
	 {topLevel, pushLocalEnv, popLocalEnv, lookSym, bindSym,
	  lookSymGlobal, bindSymGlobal, lookLocalScope, getGlobalEnv},
	 uidTabFuns =
	 {bindAid, lookAid=lookAid0, bindTid, lookTid, bindPaid, lookPaid},
	 funFuns =
	 {newFunction, getReturnTy, checkLabels, addLabel, addGoto}, 
	 switchFuns =
	 {pushSwitchLabels, popSwitchLabels, addSwitchLabel, addDefaultLabel},
	 ...}
	= stateFuns
    val ttab = (#ttab (#uidTables (#globalState stateFuns)))

(* Parse tree utility********************************************************)
    fun PTisConstExp e = 
	case e of 
	    PT.EmptyExpr => (PE.bug "EmptyExpression passed to PTisConstExp")
          |  PT.RealConst _ => true   (*XXX- ksf: generalize this to constant real expressions. *)
          | _ => (case evalExpr e of
		     (SOME _, _, _, false) => true
		   | _ => false)

(* Utility functions ********************************************************)

(* old version*)
    fun formatComment s = 
	let val s = " "^s^" "
	    val len = String.size s
	    val line = 50
	    val space = (line-len-4)
	    val prefix = Int.div(space,2)
	    val filler = #"*" 	
	    fun padLeft s = StringCvt.padLeft filler (prefix+len) s
	    fun padRight s = StringCvt.padRight filler (space+len) s
	in
(*	    if space<0 then ("\n"^s^"\n")
	    else  *)
	    padRight (padLeft s)
	end
    fun formatComment s = s


    fun extractString e = 
	case e
	of PT.EmptyExpr => NONE
        |  PT.IntConst i => (SOME ( String.str(Char.chr (IntInf.toInt i))) handle _ => NONE)
        |  PT.RealConst r => NONE
	|  PT.String s => SOME s
	|  PT.MARKexpression (loc,e) => extractString e
	|  _ => NONE

    fun getString (e,labelOpt) = 
	case labelOpt of SOME s => labelOpt 
        | _ => extractString e


    fun CTtoString (ct:Ast.ctype) =  
	let val underscore = !PPL.suppressTidUnderscores
	    val          _ =  PPL.suppressTidUnderscores := true
	    val        str =  PPL.ppToString (PPAst.ppCtype () ttab) ct
	    val          _ =  PPL.suppressTidUnderscores := underscore
	in 
	    str 
	end

    fun CExptoString (acexp: Ast.expression) =
	let val underscore = !PPL.suppressTidUnderscores
	    val          _ =  PPL.suppressTidUnderscores := true
	    val        str =  PPL.ppToString (PPAst.ppExpression () ttab) acexp
	    val          _ =  PPL.suppressTidUnderscores := underscore
            val        len = String.size str
	in 
	     String.extract (str, 0, SOME (len -1))
	end

    fun CisStatic(acty: acty) = 
     case acty 
      of Ast.Qual (_, ty) => CisStatic ty
       | Ast.Numeric _ => true
       | Ast.Pointer _ => false
       | Ast.Array(SOME _, ty)  => CisStatic ty
       | Ast.Array(NONE, _) => false
       | Ast.EnumRef _ => true 
       | Ast.TypeRef _ => CisStatic (TU.getCoreType ttab acty)
       | Ast.Function _ => false (* although a function can be viewed as a pointer *)
       | Ast.StructRef tid => 		
	  (case lookTid tid of
	       SOME {ntype = SOME(B.Struct(_, bl)),...} => 
		   let fun f(cty, _, _, _) = CisStatic cty
		   in
		       List.all f bl
		   end
	     | _ => false)
       | Ast.UnionRef tid => 
	  (case lookTid tid of
	       SOME {ntype = SOME(B.Union(_, bl)),...} => 
		   let fun f(cty, _, _) = CisStatic cty
		   in
		       List.all f bl
		   end
	     | _ => false)
       | Ast.Ellipses => false  (* can't occur *)
       | Ast.Void => false
       | Ast.Error => false

    fun getRE e = case e of (PT.ExprExt (PX.Pregexp e')) => SOME e' 
	          | PT.MARKexpression (l,e) => getRE e
                  | _ => NONE

    fun isEmptyString e = case e of PT.String s => String.size s = 0
	                  | _ => false
    fun unMark (PT.MARKexpression (l, e)) = e
      | unMark e = e

   fun isCId s = 
       let val chars = String.explode s
	   fun isUnder c = (c = #"_")
	   fun validFirst c = (isUnder c) orelse (Char.isAlpha c)
	   fun valid c =      (isUnder c) orelse (Char.isAlphaNum c)
       in
	   case chars of [] => false
           | c::cs => (validFirst c) andalso List.all valid cs
       end

    fun enumConstDefined enumConst = 
	let val sym = SYM.enumConst enumConst
	in
	    Option.isSome (lookLocalScope sym)
	end

    fun tyNameDefined tyName = 
	let val sym = SYM.typedef tyName
	in
	    Option.isSome (lookLocalScope sym)
	end

(* Error Reporting  **********************************************************)

	(* Setup the error reporting. *)
    val errorState = #errorState (#globalState stateFuns)
    val _ = (PE.setup errorState
	     (#error (#locFuns (stateFuns))) 
	     (#warn  (#locFuns (stateFuns))))

    fun unbound sym = (case lookSym sym of
			   SOME _ => PE.fail ("Redeclaration of " ^ 
					   (Symbol.name sym))
			 | NONE   => ())


    val bug = Error.bug errorState
    val seenDone : bool ref = ref false
    val nextId : int ref = ref 0
    fun padsID s = 
	let val res = s^"_"^(Int.toString (!nextId))
	in
	    nextId := !nextId + 1;
	    res
	end

(* AST help functions ********************************************************)

    val isFunction          = TU.isFunction          ttab
    val isStructOrUnion     = TU.isStructOrUnion     ttab
    val getCoreType         = TU.getCoreType         ttab
    val equalType           = TU.equalType           ttab
    val compatible          = TU.compatible          ttab

    fun sizeof ty = 
      LargeInt.fromInt (#bytes (Sizeof.byteSizeOf {sizes=Sizes.defaultSizes, err=error, warn=warn, bug=bug} ttab ty))

    fun isAssignable (t1, t2, rhsOpt) = 
	let val isRhs0 = 
	    case rhsOpt of
		SOME (Ast.EXPR (Ast.IntConst i, _, _)) => i = IntInf.fromInt 0
	      | _ => false
	in
	    (TU.isAssignable ttab {lhs = t1, rhs = t2, rhsExpr0 = isRhs0 })
	end


    fun ASTid(sym:SYM.symbol,
	      ct:Ast.ctype,
	      isGlobal:bool,
	      status : Ast.declStatus) : Ast.id =
	{name = sym,
	 uid = Pid.new (),
	 location = getLoc (),
	 ctype = ct,
	 stClass = if isGlobal then Ast.STATIC else Ast.DEFAULT,
	 status = status, 
	 global = isGlobal,
	 kind = (if (isFunction ct) then 
		     (Ast.FUNCTION {hasFunctionDef = false})
		 else Ast.NONFUN)
	 }

    fun ASTlocalId (s, ct) = ASTid(s, ct, false, Ast.DEFINED)


    fun localInitVar (id:string, ct:Ast.ctype) : SYM.symbol * Ast.id =
	let val sym = Symbol.object id
	    val id = ASTlocalId(sym, ct)
	in
	    bindSym (sym, B.ID id);
	    (sym, id)
	end

    fun declTid tid = 
	wrapDECL (Ast.ExternalDecl (Ast.TypeDecl {shadow=NONE,
						  tid=tid})) 

    fun insTempVar (id, pcty:pcty) = 
        let val (acty, sc) = cnvType (false, P.pctToPDT pcty)
	in
	    localInitVar(id, acty)
	end

    fun getBindings ns = List.map (fn (x, y, z) => (x, z)) ns
    fun getTypeContent ns = List.map (fn (x, y, z) => (x, y)) ns
    fun augTyEnv ns = ignore(List.map insTempVar (getTypeContent ns))

    (* Typedefs name to be ct.  Returns the related tid. Guarantees
     that this name is not previously typedef'd *)
    fun ASTtypedefGen bSym (name:string, ct:Ast.ctype): Tid.uid =
	let val sym = Symbol.typedef name
	    val _ = unbound sym
	    val tid = Tid.new ()
	    val symBinding = {name     = sym,
			      uid      = Pid.new (),
			      location = getLoc (),
			      ctype    = Ast.TypeRef tid }
	    val tidBinding = {name     = SOME name,
			      ntype    = SOME (B.Typedef(tid, ct)),
			      location = getLoc (),
			      global   = true } (*  XXX - should always be global? *)
	in
	    bSym (sym, B.TYPEDEF symBinding);
	    bindTid (tid, tidBinding);
	    tid
	end

    val ASTtypedef =ASTtypedefGen bindSym

    fun ASTmkEDeclComment s = 
	wrapDECL(Ast.ExternalDeclExt(AstExt.EComment s))

(* Ctype *********************************************************************)

    val CTint = Ast.Numeric (Ast.NONSATURATE, Ast.WHOLENUM, Ast.SIGNED, Ast.INT,
			     Ast.SIGNDECLARED)
    val CTuint = Ast.Numeric (Ast.NONSATURATE, Ast.WHOLENUM, Ast.UNSIGNED, Ast.INT,
			     Ast.SIGNDECLARED)
    val CTshort = Ast.Numeric (Ast.NONSATURATE, Ast.WHOLENUM, Ast.SIGNED, Ast.SHORT,
			     Ast.SIGNDECLARED)
    val CTushort = Ast.Numeric (Ast.NONSATURATE, Ast.WHOLENUM, Ast.UNSIGNED, Ast.SHORT,
			     Ast.SIGNDECLARED)
    val CTchar = Ast.Numeric (Ast.NONSATURATE, Ast.WHOLENUM, Ast.SIGNED, Ast.CHAR,
			     Ast.SIGNASSUMED)
    val CTuchar = Ast.Numeric (Ast.NONSATURATE, Ast.WHOLENUM, Ast.UNSIGNED, Ast.CHAR,
			     Ast.SIGNASSUMED)
    val CTintTys = [CTint, CTuint, CTshort, CTushort, CTchar, CTuchar]
    val CTints   = [CTint, CTuint]

    val CTstring = Ast.Pointer CTuchar

    fun CTcnvType (ct : PT.ctype) : (acty * Ast.storageClass) 
	= cnvType(false, P.pctToPDT ct)

    fun CTisSigned cty = 
        case cty of Ast.Numeric (_, _, Ast.UNSIGNED, _, _) => true
        | _ => false

    datatype CTsign = Signed | Unsigned | Any
    type CTnum =  Ast.intKind * CTsign

    fun CTgetNum ct =
	(case getCoreType ct of
	     Ast.Numeric(_, _, s', ik', _) => SOME (ik', s')
	   | _ => NONE)

    fun CTisNum (ik, s) ty =
	(case getCoreType ty of
	     Ast.Numeric(_, _, s', ik', _) => 
		 (if ik' = ik then
		     (case (s, s') of 
			  (Any     , _           ) => true
			| (Signed  , Ast.SIGNED  ) => true
			| (Unsigned, Ast.UNSIGNED) => true
			| _ => false)
		  else false)
	   | _ => false)
	
    val CTisChar  = CTisNum (Ast.CHAR, Any)
    val CTisSChar = CTisNum (Ast.CHAR, Signed)
    val CTisUChar = CTisNum (Ast.CHAR, Unsigned)

    val CTisInt  = CTisNum (Ast.INT, Any)
    val CTisSInt = CTisNum (Ast.INT, Signed)
    val CTisUInt = CTisNum (Ast.INT, Unsigned)

    val CTisShort  = CTisNum (Ast.SHORT, Any)

    fun CTisIntorChar cty = (CTisInt cty) orelse (CTisChar cty) orelse CTisShort cty

    val CTisPointer = TU.isPointer ttab

    fun CTisString ty = 
        let val coreTy = getCoreType ty
            val isPointer = CTisPointer coreTy
            fun getBase coreTy =
                let val derefTyOpt = TU.deref ttab coreTy
                in
		    case derefTyOpt
		    of SOME(baseTy) => baseTy
                    | _ => PE.bug "Impossible: must be able to dereference a pointer\n"
                end
        in
            isPointer andalso (CTisChar (getBase coreTy))
        end

    fun CTisStruct ty = 
	case isStructOrUnion ty
	    of SOME tid => 
		(case lookTid tid of
		     SOME {ntype = SOME(B.Struct(_)),...} => true
		   | _ => false)
	  | NONE => false

    (* Type-utils implements but does not export an essentially identical
     function!!! *)
    fun CTreduce ct = 
	(case ct of 
	     Ast.TypeRef tid =>
		 (case lookTid tid of
		      SOME {ntype = SOME (B.Typedef (_, ct)),...} => 
			  (CTreduce ct)
		    | NONE => PE.bug "Ill-formed type table"
		    | _ => ct)
	   | _ => ct)

    fun CTgetTyName ct = 
	(case ct of 
	     Ast.TypeRef tid =>
		 (case lookTid tid of
		      SOME {name, ntype = SOME (B.Typedef (_, ct)),...} => name
		    | NONE => (PE.bug "Ill-formed type table"; SOME "bogus")
		    | _ => NONE)
	   | _ => NONE)

    fun PTgetTyName pt = 
	let val ct = #1(CTcnvType pt)
	in
	(case ct of 
	     Ast.TypeRef tid =>
		 (case lookTid tid of
		      SOME {name, ntype = SOME (B.Typedef (_, ct)),...} => name
		    | NONE => (PE.bug "Ill-formed type table"; SOME "bogus")
		    | _ => NONE)
	   | _ => NONE)
	end

    fun CTgetPtrBase ct = 
	case CTreduce ct
          of Ast.Qual(_, ty) => CTgetPtrBase ty
           | Ast.Pointer cty => SOME cty
           | _ => NONE 

    fun CTisEnum ty = 
        case CTreduce ty
          of Ast.Qual (_, ty) => CTisEnum ty
           | (Ast.EnumRef tid) => SOME tid
           | _ => NONE

    fun expEqualTy(expPT, CTtys, genErrMsg) = 
	let val (expTy, expAst) = cnvExpression expPT
	in
            if List.exists (fn cty => equalType(cty, expTy)) CTtys
	    then ()
	    else PE.error (genErrMsg (CTtoString expTy)) 
	end

    fun getExpEqualTy(expPT, CTtys, genErrMsg) = 
	let val (expTy, expAst) = cnvExpression expPT
	in
           if List.exists (fn cty => equalType(cty, expTy)) CTtys
	   then (true, expTy)
	   else (PE.error (genErrMsg (CTtoString expTy));
                 (false, expTy))
	end

    fun expAssignTy(expPT, CTtys, genErrMsg) = 
	let val (expTy, expAst) = cnvExpression expPT
	in
            if List.exists (fn cty => isAssignable(cty, expTy, NONE)) CTtys
	    then ()
	    else PE.error (genErrMsg (CTtoString expTy)) 
	end

    fun CTcnvType (ct : PT.ctype) : (acty * Ast.storageClass) 
	= cnvType(false, P.pctToPDT ct)

    fun CTcnvDecr(ct, d) : Ast.ctype * string option = 
	let val (ct', sc) = CTcnvType ct  	(* check storage class okay*)
	in                                 	(* XXX - missing piece *)
	    mungeTyDecr(ct', d)
	end

    fun unzip8' [] = ([],[],[],[],[],[],[],[])
      | unzip8' ((b,c,d,e,f,g,h,i)::rest) = 
	let val (bs,cs,ds,es,fs,gs,hs,is) = unzip8' rest
	in
	    (b@bs, c@cs, d@ds, e@es, f@fs, g@gs, h@hs, i@is)
	end

    fun zip8 ([], [], [],[], [], [],[],[]) = []
      | zip8 (b::bs, c::cs, d::ds, e::es, f::fs, g::gs, h::hs, i::is) = (b, c, d,e,f,g,h,i) :: (zip8 (bs, cs, ds,es,fs,gs,hs,is))
      | zip8 _ = raise Fail "Zipping unequal length lists"

    fun cnvDeclaration(dt, del: (ParseTree.declarator * pcexp) list ) = 
	let val (ct', sc) = cnvType(false, dt)
	    val (ds, es) = ListPair.unzip del
	    val (cts, nameOpts) = ListPair.unzip(List.map (fn d => mungeTyDecr(ct', d)) ds)
            fun zip3 ([], [], []) = []
	      | zip3 (b::bs, c::cs, d::ds) = (b, c, d) :: (zip3 (bs, cs, ds))
              | zip3 (_, _, _) = raise Fail "Zipping unequal length lists"
	in
	    zip3 (cts, nameOpts, es)
	end

(*    fun tyNameToPCT name = 
	case name of "int" => P.makePCT [PT.Int]
           | "char"        => P.makePCT [PT.Char]
           | "short"       => P.makePCT [PT.Short]
           | "long"        => P.makePCT [PT.Long]
           | "float"       => P.makePCT [PT.Float]
           | "double"      => P.makePCT [PT.Double]
           | _ => P.makeTypedefPCT name  (* XXX: this will not work for C's built in types *) *)

     fun tyNameToPCT tyname = tyname

    (* The following function "decompiles" a ctype.  *)
    fun CTtoPTct (ct:acty) : PT.ctype =
	(case ct of
	     Ast.Void => P.void
	   | Ast.Ellipses => P.makePCT [PT.Ellipses]
	   | Ast.Qual (q, ct') => 
		 let val q' = (case q of 
				   Ast.CONST => PT.CONST 
				 | _ => PT.VOLATILE)
		     val {qualifiers=q'', specifiers = s''} = CTtoPTct ct'
		 in
		     { qualifiers = q' :: q'',
		       specifiers = s''
		       }
		 end		     
	   | Ast.Numeric(s, f, sgn, intk, sgntag) => 
		 let val sat = (case s of 
				    Ast.SATURATE => PT.Saturate 
				  | _ => PT.Nonsaturate)
		     val frac = (case f of 
				     Ast.FRACTIONAL => PT.Fractional
				   | Ast.WHOLENUM => PT.Wholenum)
		     fun cnvSgn Ast.SIGNED = [PT.Signed]
		       | cnvSgn Ast.UNSIGNED = [PT.Unsigned]
		     val sgn = (case sgntag of
				            Ast.SIGNASSUMED => []
     				          | Ast.SIGNDECLARED => cnvSgn sgn)
		     val ik = (case intk of
				   Ast.CHAR => [PT.Char]
				 | Ast.SHORT => [PT.Short]
				 | Ast.INT => [PT.Int]
				 | Ast.LONG => [PT.Long]
				 | Ast.LONGLONG => [PT.Long, PT.Long]
				 | Ast.FLOAT => [PT.Float]
				 | Ast.DOUBLE => [PT.Double]
				 | Ast.LONGDOUBLE => [PT.Long, PT.Double])
		     val specs = sat :: frac :: sgn @ ik
		 in
		     P.makePCT specs
		 end
	   | Ast.Array (iopt, ct') =>
		 let val e = (case iopt of 
				  NONE => PT.EmptyExpr
				| SOME (i, _) => PT.IntConst i) (* XXX: should get expression but it is an AST expression. *)
		     val ct'' = CTtoPTct ct'
		 in
		     P.makePCT [PT.Array(e, ct'')]
		 end
	   | Ast.Pointer ct' => P.makePCT [PT.Pointer (CTtoPTct ct')]
	   | Ast.Function (ct', cts) =>
		 let val ct'' = CTtoPTct ct'
		     fun f ct = (P.pctToPDT (CTtoPTct ct), PT.EmptyDecr)
		 in
		     P.makePCT [ PT.Function { retType = ct'',
					      params = (List.map f cts)
					      } ]
		 end
	   | Ast.StructRef t => 
		 let fun procMem (ct, mopt : Ast.member option, iopt, commentOpt) =
		     let val ct' = CTtoPTct ct 
			 val dr = 
			     case mopt of
				 NONE => PT.EmptyDecr
			       | SOME {name,...} => PT.VarDecr (SYM.name name)
			 val e = 
			     case iopt of
				 NONE => PT.EmptyExpr
			       | SOME i => PT.IntConst i
		     in
			 (ct', [(dr, e)], commentOpt)
		     end
		 in case lookTid t of
(*		     SOME {name=SOME n, ntype=NONE,...} =>
			 P.makePCT [PT.StructTag {isStruct=true, name=n }] *)
		     SOME {name=SOME n,...} =>
			 P.makePCT [PT.StructTag {isStruct=true, name=n }] 
		   | SOME {name=nopt, ntype=SOME (B.Struct (_, ms)), ...} =>
			 P.makePCT [PT.Struct {isStruct=true,
					      tagOpt=nopt,
					      members=List.map procMem ms}]
		   
		   | _ => PE.bug "Ill-formed type table (struct)"
		 end
	   | Ast.UnionRef t => 
		 let fun procMem (ct, m:Ast.member, s) =
		     let val ct' = CTtoPTct ct
			 val dr = PT.VarDecr (SYM.name (#name m))
		     in
			 (ct', [(dr, PT.EmptyExpr)], NONE)
		     end
		 in case lookTid t of
		     SOME {name=SOME n, ntype=NONE,...} => 
			 P.makePCT [PT.StructTag {isStruct=false, name=n}]
		   | SOME {name=nopt, ntype=SOME (B.Union (_, ms)),...} =>
			 P.makePCT [PT.Struct {isStruct = false,
					      tagOpt = nopt,
					      members = List.map procMem ms}
				    ]			 
		   | _ => PE.bug "Ill-formed type table (union)"
		 end
	   | Ast.EnumRef t =>
		 let fun procMem ({name,...}:Ast.member, i, commentOpt) = 
		     (SYM.name name, PT.IntConst i, commentOpt)
		 in case lookTid t of
		     SOME {name=SOME n, ntype=NONE,...} => 
			 P.makePCT [PT.EnumTag n]
		   | SOME {name=nopt, ntype=SOME (B.Enum (_, ms)),...} =>
			 P.makePCT [PT.Enum {tagOpt = nopt,
					    enumerators = List.map procMem ms,
					    trailingComma = false}]
		   | _ => PE.bug "Ill-formed type table (enum)"
		 end
	   | Ast.TypeRef t =>
		 let in case lookTid t of
		     SOME {name= SOME n,...} => P.makePCT [PT.TypedefName n]
		   | _ => PE.bug "Ill-formed type table (typedef)"
		 end
	   | Ast.Error => PE.fail "Error type found"
	     )


(* Conversions ***************************************************************)
      fun pcnvExternalDecl decl = 
	  let (* Some useful names / name functions *)
		
	      fun tmpName (nm) = nm^"_Ptmp_"
	      fun tmpId (nm) = PT.Id(tmpName(nm))
	      fun pcgenName (nm) = nm^"_PCGEN_"
	      fun pcgenId (nm) = PT.Id(pcgenName(nm))


              val nerrPCGEN = pcgenName("nerr")
	      val tmpBufCursor = pcgenName("buf_cursor")
	      val tmpFn     = pcgenName("fn")
	      val tmpLength = pcgenName("length")
	      val tlen      = pcgenName("tlen")
	      val tdelim    = pcgenName("tdelim")
	      val trequestedOut = pcgenName("trequestedOut")

	      (* Some useful functions *)
		
	      val ioDiscX =  P.arrowX(P.arrowX(PT.Id pads, PT.Id PL.disc), PT.Id PL.io_disc)
	      val d_endianX =  P.arrowX(P.arrowX(PT.Id pads, PT.Id PL.disc), PT.Id PL.d_endian)
	      val m_endianX =  P.arrowX(PT.Id pads, PT.Id PL.m_endian)
	      val locX'     =  P.fieldX(pd, loc)
	      val locX      =  P.addrX(locX')
              val locS      =  PL.getLocS(PT.Id pads, P.fieldX(pd, loc))
	      val locBS     =  PL.getLocBeginS(PT.Id pads, P.fieldX(pd, loc))
	      val locES2    =  PL.getLocEndMinus2S(PT.Id pads, P.fieldX(pd, loc))
	      val locES1    =  PL.getLocEndMinus1S(PT.Id pads, P.fieldX(pd, loc)) 
	      val locES0    =  PL.getLocEndS(PT.Id pads, P.fieldX(pd, loc))


	      fun getDynamicFunctions (name, memChar) = 
		  case memChar of TyProps.Static => (NONE, NONE, NONE, NONE)
		| TyProps.Dynamic => (SOME (initSuf name),
				      SOME (cleanupSuf name),
				      SOME ((initSuf o pdSuf) name),
				      SOME ((cleanupSuf o pdSuf) name))

              fun buildTyProps (name, kind, diskSize, compoundDiskSize, memChar, endian, isRecord, 
				containsRecord, largeHeuristic, isSource, pdTid, numArgs) = 
     		  let val (repInit, repClean, pdInit, pdClean) = getDynamicFunctions (name, memChar)
		  in
		      {kind     = kind,
		       diskSize = diskSize,
		       compoundDiskSize = compoundDiskSize,
	 	       memChar  = memChar,
		       endian   = endian, 
		       isRecord = isRecord,
		       containsRecord = containsRecord,
                       largeHeuristic = largeHeuristic, 
		       isSource   = isSource,
		       numArgs  = numArgs,
		       repName  = name, 
		       repInit  = repInit,
		       repRead  = readSuf name, 
		       repClean = repClean,
		       pdName   = pdSuf name,
		       pdTid    = pdTid,
		       pdInit   = pdInit,
		       pdClean  = pdClean,
		       accName  = accSuf name,
		       accInit  = (initSuf o accSuf) name,
		       accAdd   = (addSuf o accSuf) name,
		       accReport= (reportSuf o accSuf) name,
		       accClean = (cleanupSuf o accSuf) name}
		  end


              fun lookupScan(ty:pty) = 
		  case ty
                  of PX.Name s => ( case PBTys.find(PBTys.baseInfo, Atom.atom s)
				    of NONE => NONE
                                    |  SOME(b:PBTys.baseInfoTy) => #scanname b)

              fun lookupAcc(ty:pty) = 
		  case ty
                  of PX.Name s => ( case PBTys.find(PBTys.baseInfo, Atom.atom s)
				    of NONE => SOME(accSuf s)  (* non-base type; acc constructed from type name*)
                                    |  SOME(b:PBTys.baseInfoTy) => Option.map Atom.toString (#accname b))
	      fun lookupAcc'(ty:pty) = 
		  valOf (lookupAcc ty) handle x => (PE.error ("Failed to find accumulator:" ^(P.tyName ty)); "missing_accumulator")

              fun lookupPred(ty:pty) = 
		  case ty
                  of PX.Name s => ( case PBTys.find(PBTys.baseInfo, Atom.atom s)
				    of NONE => SOME(isPref s)  (* non-base type; acc constructed from type name*)
                                    |  SOME(b:PBTys.baseInfoTy) => Option.map Atom.toString (#predname b))

              fun lookupWrite(ty:pty) = 
		  case ty
                  of PX.Name s => ( case PBTys.find(PBTys.baseInfo, Atom.atom s)
				    of NONE => s  (* non-base type; acc constructed from type name*)
                                    |  SOME(b:PBTys.baseInfoTy) => s)


	      fun lookupLitWrite s = (bufSuf o writeSuf) s

              fun reverseLookup(cty:Ast.ctype) : PX.Pty option = 
		  let val entries : (Atom.atom * PBTys.baseInfoTy) list = PBTys.listItemsi(PBTys.baseInfo)
		      fun find f [] = NONE
                        | find f (x::xs) = case (f x) of NONE => find f xs | r => r
		      fun chkOne(a, b:PBTys.baseInfoTy) = 
			  let val n = #repname b
			      val accPCT = P.makeTypedefPCT (Atom.toString n)
			      val (accCT, sc) = CTcnvType accPCT
			  in
			      if equalType(cty, accCT) then SOME (PX.Name (Atom.toString a))
			      else NONE
			  end
		   in
		      find chkOne entries
		  end

              fun lookupMemFun(ty:pty) = 
		  case ty
                  of PX.Name s => ( case PBTys.find(PBTys.baseInfo, Atom.atom s)
				    of NONE => s  (* non-base type; mem constructed from rep name*)
                                    |  SOME(b:PBTys.baseInfoTy) => Atom.toString (#repname b))

              fun lookupMemChar (ty:pty) = 
                  case ty 
                  of PX.Name s => ( case PBTys.find(PBTys.baseInfo, Atom.atom s)
				    of NONE => (case PTys.find(Atom.atom s)
						of NONE => TyProps.Dynamic
						| SOME (b:PTys.pTyInfo) => (#memChar b)
						    (* end nested case *))
                                    |  SOME(b:PBTys.baseInfoTy) => (#memChar b))

              fun lookupDiskSize (ty:pty) = 
                  case ty 
                  of PX.Name s => ( case PBTys.find(PBTys.baseInfo, Atom.atom s)
				    of NONE => (case PTys.find(Atom.atom s)
						of NONE => TyProps.Variable
						| SOME (b:PTys.pTyInfo) => #diskSize b
						    (* end nested case *))
                                    |  SOME(b:PBTys.baseInfoTy) =>  #diskSize b)

              fun lookupEndian (ty:pty) = 
                  case ty 
                  of PX.Name s => ( case PBTys.find(PBTys.baseInfo, Atom.atom s)
				    of NONE => (case PTys.find(Atom.atom s)
						of NONE => false
						| SOME (b:PTys.pTyInfo) => (#endian b)
						    (* end nested case *))
                                    |  SOME(b:PBTys.baseInfoTy) => (#endian b))

             fun lookupContainsRecord (ty:pty) = 
                  case ty 
                  of PX.Name s => ( case PBTys.find(PBTys.baseInfo, Atom.atom s)
				    of NONE => (case PTys.find(Atom.atom s)
						of NONE => false
						| SOME (b:PTys.pTyInfo) => (#isRecord b orelse #containsRecord b)
						    (* end nested case *))
                                    |  SOME(b:PBTys.baseInfoTy) => false)


	      fun lookupHeuristic (ty:pty) =
		  case ty
		  of PX.Name s => ( case PBTys.find(PBTys.baseInfo, Atom.atom s)
                                    of NONE => (case PTys.find(Atom.atom s)
                                                of NONE => false
                                                | SOME (b:PTys.pTyInfo) => (#largeHeuristic b)
                                                    (* end nested case *)) 
                                    |  SOME(b:PBTys.baseInfoTy) => false)(* ???? *)

              fun lookupPadsx(ty:pty) = BU.lookupTy(ty,padsxSuf,#padsxname)

	      fun lookupCompoundDiskSize (ty:pty) =
		  case ty
		  of PX.Name s => ( case PBTys.find(PBTys.baseInfo, Atom.atom s)
                                    of SOME(b:PBTys.baseInfoTy) => TyProps.Base(#diskSize b)
		                    |  NONE => (case PTys.find(Atom.atom s)
                                                of NONE => raise Fail ("Type "^s^" not defined")
                                                |  SOME (b:PTys.pTyInfo) => (#compoundDiskSize b)
                                                    (* end nested case *))) 

              fun getPadsName (pcty:pcty) : pty = 
  		  case PTgetTyName pcty 
		  of SOME n => (case PBTys.find(PBTys.baseInfo, Atom.atom n)
				of SOME b => PX.Name n
			        |  NONE => (case PTys.find(Atom.atom n)
					    of NONE => (PE.bug "expected PADS type name"; PX.Name "bogus")
					    | SOME b => PX.Name n))
                   | NONE => (PE.bug "expected PADS type name"; PX.Name "bogus")

              fun isPadsTy tyname = 
		  case PTgetTyName tyname
                  of SOME n => (case PBTys.find(PBTys.baseInfo, Atom.atom n)
				of SOME b => PTys.BaseTy b
				|  NONE => (case PTys.find(Atom.atom n)
					    of NONE => PTys.CTy
					    | SOME b => PTys.CompoundTy b))
                   | NONE => PTys.CTy
 

	      fun reduceArgList(args, (params, bodies):TyProps.argList)=
		  let val subList = ListPair.zip(params, args)
		      val results = List.map (PTSub.substExps subList) bodies
		  in
		      results
		  end

              fun reduceArrayParts(subList, args, sizeSpec, arrayPreds) = 
		  let val doSub = PTSub.substExps subList
		      val modArgs = List.map doSub args
                      fun doSizeSpec NONE = NONE
                        | doSizeSpec (SOME (PX.SizeInfo {min, max, maxTight})) = 
			    SOME (PX.SizeInfo {min = Option.map doSub min,
					       max = Option.map doSub max,
					       maxTight=maxTight})
		      val modSizeSpec = doSizeSpec sizeSpec

		      fun doParseCond e = 
			  case e 
			  of PX.General e => PX.General (doSub e)
			  |  PX.ParseCheck e => PX.ParseCheck (doSub e)

		      fun doArrayConstraint ac = 
			  case ac 
                          of PX.Sep e => PX.Sep (doSub e)
                          |  PX.Term PX.noSep => PX.Term PX.noSep
                          |  PX.Term (PX.Expr e) => PX.Term (PX.Expr e)
			  |  PX.Last es  => PX.Last  (List.map doParseCond es)
			  |  PX.Ended es => PX.Ended (List.map doParseCond es)
			  |  PX.Skip es  => PX.Skip  (List.map doParseCond es)
			  |  PX.Longest =>  PX.Ended (List.map doParseCond PL.longestX)
		      val modArrayPreds = List.map doArrayConstraint arrayPreds
		  in
		      (modArgs, modSizeSpec, modArrayPreds)
		  end

              fun evalExprNoErrs e = 
		  let val () = (Error.warningsEnabled errorState false;
				Error.errorsEnabled errorState false)
		      val result = #1(evalExpr e)
		      val () = (Error.warningsEnabled errorState true;
				Error.errorsEnabled errorState true)
		  in
		      result
		  end
	      
	      fun evalArgList(args) : IntInf.int list =
		  let fun doOne e = 
		        let val resOpt = evalExprNoErrs e
			in
			    case resOpt of NONE => raise Fail "Expected a closed expression" | SOME res => res
			end
		  in
		      List.map doOne args
		  end

              fun reduceSizeSpec (cFormals, args, sizeSpec) = 
		  let fun g (formals, exp, recExp) = 
			  let val subList = ListPair.zip(formals, args)
			      val rExp = PTSub.substExps subList exp
			      val rrecExp = PTSub.substExps subList recExp
			      val boundVars = "strlen" :: cFormals
			  in
      			      if  (PTSub.expIsClosed(boundVars, rExp)) andalso (PTSub.expIsClosed(boundVars, rrecExp)) then
				  let val cval = evalExprNoErrs rExp
				      val crecval = evalExprNoErrs rrecExp
				  in
				      case (cval, crecval)
			              of (NONE, NONE) => TyProps.Param(cFormals, NONE, rExp, rrecExp)
			              | (NONE, SOME e) => TyProps.Param(cFormals, NONE, rExp, PT.IntConst e)
				      | (SOME e, NONE) => TyProps.Param(cFormals, NONE, PT.IntConst e, rrecExp)
				      | (SOME e1, SOME e2) => 
					   TyProps.Size(e1, e2)
				  end
			      else TyProps.Variable  (* must have a dependency on an earlier portion of data *)
			  end
		  in
		      case sizeSpec 
		      of TyProps.Param(formals, _, exp, recExp) => g (formals, exp, recExp)
                      |  x => x
		  end

	      fun reduceCDSize(args, sizeSpec) = reduceSizeSpec([], args, sizeSpec)

	      fun computeDiskSize(cName, cFormals, pty, args) =
		  let val sizeSpec = lookupDiskSize pty
		      val () = case sizeSpec of TyProps.Param(formals, _, _, _) =>
			          if not (List.length formals = List.length args) then
				     PE.error ("Number of arguments does not match "^
					       "specified number of args in type: "^cName^"\n")
				  else ()
			       | _ => ()
		  in
		      reduceSizeSpec(cFormals, args, sizeSpec)
		  end

	      fun coreArraySize (elemSize, sepSize, rep) = 
		  TyProps.scale(TyProps.add(elemSize, sepSize), rep)

              fun mungeParam(pcty:pcty, decr:pcdecr) : string * pcty = 
		  let val (act, nOpt) = CTcnvDecr(pcty, decr)
                      (* convert pads name to c name, if a pads typedef *)
                      val pct = case CTgetTyName act
			        of NONE => CTtoPTct act
                                | SOME tyName => 
				    P.makeTypedefPCT(BU.lookupTy(PX.Name tyName, repSuf, #repname))

                      val name = case nOpt
			         of NONE => (PE.error "Parameters to PADS data types must have names\n"; 
					     "bogus")
				 | SOME n => n
		  in
                      (name, pct)
		  end



	      fun reportStructErrorSs (code, shouldGetLoc, locX) = 
		  let val setLocSs = if shouldGetLoc 
				     then [PL.getLocEndMinus1S(PT.Id pads, locX)]
				     else []
		  in
		  [PT.IfThen(
		     P.eqX(P.zero, P.fieldX(pd, nerr)), 
		     PT.Compound(
		      [P.assignS(P.fieldX(pd, errCode), code)]
		      @ setLocSs
		      @ [P.assignS(P.fieldX(pd, loc), locX)])),
		   P.plusAssignS(P.fieldX(pd, nerr), P.intX 1)]
		  end

	      fun reportBaseErrorSs (code, shouldGetLoc, locX) = 
		  [P.assignS(P.fieldX(pd, errCode), code),
		   P.assignS(P.fieldX(pd, loc), locX)]

	      fun reportUnionErrorSs (code, shouldGetLoc, locX) = 
                 [PT.IfThen(
		   P.eqX(PT.Id result, PL.P_OK), (* only report scanning error if correctly read field*)
		   PT.Compound
		    [PT.IfThen(
		      P.eqX(P.zero, P.fieldX(pd, nerr)), 
		      PT.Compound 
		       [P.assignS(P.fieldX(pd, errCode), code),
		        P.assignS(P.fieldX(pd, loc), locX)]),
		     P.plusAssignS(P.fieldX(pd, nerr), P.intX 1)])]



              fun genReadEOR (readName, reportErrorSs, esRetX) () = 
		  [P.mkCommentS ("Read to EOR"),
		    PT.Compound[
			   P.varDeclS'(PL.base_pdPCT, tpd),
			   P.varDeclS'(PL.sizePCT, "bytes_skipped"),
			   PL.getLocBeginS(PT.Id pads, P.dotX(PT.Id tpd, PT.Id loc)),
                           PT.IfThenElse(
			      P.eqX(PL.P_OK, 
				    PL.IOReadNextRecX(PT.Id pads, P.addrX (PT.Id "bytes_skipped"))),
			      PT.Compound
			       [PT.IfThen(
				 PT.Id "bytes_skipped",
				 PT.Compound
                                  [P.mkCommentS "in genReadEOR1",
				   PL.getLocEndMinus1S(PT.Id pads, P.dotX(PT.Id tpd, PT.Id loc)),
				   PT.IfThenElse(
				     PL.testNotPanicX(PT.Id pd),
				     PT.Compound(
				       [PL.userErrorS(PT.Id pads, 
						      P.addrX(P.dotX(PT.Id tpd, PT.Id loc)),
						      PL.P_EXTRA_BEFORE_EOR,
						      readName, PT.String "Unexpected data before EOR",
						      [])]
				       @ reportErrorSs(PL.P_EXTRA_BEFORE_EOR, true, P.dotX(PT.Id tpd, PT.Id loc))),
				     PT.Compound
					[PL.getLocEndMinus1S(PT.Id pads, P.dotX(PT.Id tpd, PT.Id loc)),
					 PL.userInfoS(PT.Id pads, 
						       P.addrX(P.dotX(PT.Id tpd, PT.Id loc)),
						       readName,
						       PT.String "Resynching at EOR", 
						       [])]),
				   PL.endSpec pads esRetX]),
				PL.unsetPanicS(PT.Id pd)],
			      PT.Compound
			       [P.mkCommentS "in genReadEOR2",
				PL.unsetPanicS(PT.Id pd),
				PL.getLocEndMinus1S(PT.Id pads, P.dotX(PT.Id tpd, PT.Id loc)),
				PL.userErrorS(PT.Id pads, 
					      P.addrX(P.dotX(PT.Id tpd, PT.Id loc)),
					      PL.P_AT_EOR,
					      readName,
					      PT.String "Found EOF when searching for EOR", 
					      []),
				PL.endSpec pads	esRetX]) ]  ]


	      fun genReadFun (readName, cParams:(string * pcty)list, 
			      mPCT, pdPCT, canonicalPCT, mFirstPCT, doInit, bodySs) = 
		  let val (cNames, cTys) = ListPair.unzip cParams
                      val paramTys = [P.ptrPCT PL.toolStatePCT, P.ptrPCT mPCT, P.ptrPCT pdPCT, P.ptrPCT canonicalPCT]
			             @ cTys

                      val paramNames = [pads, m, pd, rep]@ cNames
                      val formalParams = List.map P.mkParam (ListPair.zip (paramTys, paramNames))
		      val innerInits = (if doInit
					then [PT.Expr(PT.Call(PT.Id "PD_COMMON_INIT_NO_ERR", [PT.Id pd])),
					      PT.Expr(PT.Call(PT.Id "PD_COMMON_READ_INIT", [PT.Id pads,PT.Id pd]))]
					else [])
		      val returnTy =  PL.toolErrPCT
		      val checkParamsSs = [PL.IODiscChecks3P(PT.String readName, PT.Id m, PT.Id pd, PT.Id rep)]
		      val innerBody = checkParamsSs @ innerInits @ bodySs
		      val readFunED = 
			  P.mkFunctionEDecl(readName, formalParams, PT.Compound innerBody, returnTy)
		  in
		      [readFunED]
		  end

(*
ssize_t test_write2io (P_t *pads, Sfio_t *io, <test_params>, test_pd *pd, test *rep);
ssize_t test_write2buf(P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, <test_params>, test_pd *pd, test *rep)
ssize_t test_write_xml_2io (P_t *pads, Sfio_t *io, <test_params>, test_pd *pd, test *rep, const char *tag, int indent);
ssize_t test_write_xml_2buf(P_t *pads, Pbyte *buf, size_t buf_len, int *buf_full, <test_params>, test_pd *pd, test *rep, const char *tag, int indent)
*)

	      fun modTagSs (newTag) = 
		  [PT.IfThen(P.notX(PT.Id tag),
		             P.assignS(PT.Id tag, PT.String newTag))]

	      fun writeAdjustLenSs shouldAdjustBuffer = 
		[PT.Expr(PT.Call(PT.Id(if shouldAdjustBuffer then "PCGEN_TLEN_UPDATES" else "PCGEN_FINAL_TLEN_UPDATES"), []))]

	      fun writeFieldSs (fname, argXs, adjustLengths) = 
		  [P.assignS(PT.Id tlen, 
			     PT.Call(PT.Id fname,
				     ([PT.Id pads, PT.Id tmpBufCursor, PT.Id bufLen, PT.Id bufFull]
				      @ argXs)))]
		  @ (writeAdjustLenSs adjustLengths)

              fun fmtCall(fname, argXs) = PT.Call(PT.Id fname, 
					  [PT.Id pads, PT.Id tmpBufCursor, PT.Id bufLen, PT.Id bufFull, P.addrX(PT.Id trequestedOut), PT.Id tdelim]
					  @ argXs)

	      fun fmtFieldSs (fname, argXs) = 
		      [PL.fmtStruct(PT.String fname, fmtCall(fname, argXs))]

	      fun fmtBranchSs (fname, argXs, tagX) = 
		      [PL.fmtUnion(PT.String fname, fmtCall(fname, argXs), tagX)]

              fun fmtTypedefSs(fname, argXs) =  [PL.fmtTypedef(fmtCall(fname, argXs))]

	      fun writeXMLFieldSs (fname, argXs, tagArg, adjustLengths, bumpIndent, cArgs) = 
		  [P.assignS(PT.Id tlen, 
			     PT.Call(PT.Id fname,
				     ([PT.Id pads, PT.Id tmpBufCursor, PT.Id bufLen, PT.Id bufFull]
				      @ argXs @ [tagArg, if bumpIndent then P.plusX(PT.Id indent, P.intX 2) else PT.Id indent] @ cArgs)))]
		  @ (writeAdjustLenSs adjustLengths)

	      fun genWriteFuns (name, standardOrEnum, writeName, writeXMLName, fmtName, isRecord, isSource, cParams:(string * pcty)list, 
		 		mPCT, pdPCT, canonicalPCT, iBodySs, iXMLBodySs, iFmtFinalBodySs) = 
		  let val writeIOName = ioSuf writeName
		      val writeBufName = bufSuf writeName
		      val writeXMLIOName = ioSuf writeXMLName
		      val writeXMLBufName = bufSuf writeXMLName
                      val fmtIOName  = ioSuf fmtName			
		      val fmtBufName = bufSuf fmtName
		      val fmtBufFinalName = bufFinalSuf fmtName
		      val (cNames, cTys) = ListPair.unzip cParams
		      val cNamesAsIds = List.map PT.Id cNames
		      val commonTys =   [P.ptrPCT pdPCT, P.ptrPCT canonicalPCT]
		      val commonNames = [pd, rep]
		      val IOcommonTys = [P.ptrPCT PL.toolStatePCT, PL.sfioPCT]
		      val IOcommonNames = [pads, io]
		      val BufcommonTys = [P.ptrPCT PL.toolStatePCT, P.ptrPCT PL.bytePCT, PL.sizePCT, P.intPtr]
		      val BufcommonNames =[pads, buf, bufLen, bufFull] 
		      val FmtcommonTys = [P.intPtr, P.ccharPtr,  P.ptrPCT mPCT]
		      val FmtcommonNames = [requestedOut, delims, m]

                      val IOparamTys =   IOcommonTys @ commonTys @ cTys 
                      val IOparamNames = IOcommonNames @ commonNames @ cNames 
                      val IOformalParams = List.map P.mkParam (ListPair.zip (IOparamTys, IOparamNames))

		      val BufParamTys =   BufcommonTys @ commonTys @ cTys 
		      val BufParamNames =  BufcommonNames @ commonNames @ cNames 
		      val BufFormalParams = List.map P.mkParam (ListPair.zip (BufParamTys, BufParamNames))
			  
		      val FmtIOParamTys =   IOcommonTys @ FmtcommonTys @ commonTys @ cTys 
		      val FmtIOParamNames = IOcommonNames @ FmtcommonNames @ commonNames @ cNames
		      val FmtIOformalParams = List.map P.mkParam (ListPair.zip (FmtIOParamTys, FmtIOParamNames))

		      val FmtBufParamTys = BufcommonTys @ FmtcommonTys @ commonTys @ cTys 
		      val FmtBufParamNames = BufcommonNames @ FmtcommonNames @ commonNames @ cNames 
		      val FmtBufFormalParams = List.map P.mkParam (ListPair.zip (FmtBufParamTys, FmtBufParamNames))

                      val IOXMLparamTys = IOcommonTys @ commonTys @ [P.ccharPtr, P.int] @ cTys
                      val IOXMLparamNames = IOcommonNames @ commonNames @ [tag, indent] @ cNames
		      val BufXMLParamTys =    BufcommonTys   @ commonTys   @ [P.ccharPtr, P.int] @ cTys 
		      val BufXMLParamNames =  BufcommonNames @ commonNames @ [tag, indent]       @ cNames 
                      val IOXMLformalParams = List.map P.mkParam (ListPair.zip (IOXMLparamTys, IOXMLparamNames))
		      val BufXMLFormalParams = List.map P.mkParam (ListPair.zip (BufXMLParamTys, BufXMLParamNames))

		      val returnTy =  PL.ssizePCT
                      
                      (* -- write2buf *)
		      val bufDeclSs = [P.varDeclS(P.ptrPCT PL.bytePCT, tmpBufCursor, PT.Id buf),
				        P.varDeclS(PL.ssizePCT, tmpLength, P.zero),
				        P.varDeclS'(PL.ssizePCT, tlen)]
		      val bufCheckParamsSs = [PL.IODiscChecksSizeRet3P(PT.String writeBufName, 
								       PT.Id buf, PT.Id bufFull, PT.Id rep)]
		      val bufIntroSs = [P.assignS(P.starX (PT.Id bufFull), P.zero)]
		      val (bufRecordIntroSs, bufRecordCloseSs)  = 
                           if isRecord then
			       (([P.assignS(PT.Id tlen, 
					    PL.recOpenBufWrite(PT.Id pads, PT.Id tmpBufCursor, 
							       PT.Id bufLen, PT.Id bufFull, PT.String writeBufName))]
				  @ (writeAdjustLenSs true)),
				[P.assignS(PT.Id tlen,
					   PL.recCloseBufWrite(PT.Id pads, PT.Id tmpBufCursor,
							       PT.Id bufLen, PT.Id bufFull, 
							       PT.Id buf, PT.Id tmpLength, PT.String writeBufName))]
				  @  (writeAdjustLenSs false))
			   else ([], [])
		      val bufCloseSs = [PT.Return (PT.Id tmpLength)]
		      val bufBodySs  = bufDeclSs @ bufCheckParamsSs @ bufIntroSs @ bufRecordIntroSs @ iBodySs 
			                @ bufRecordCloseSs @ bufCloseSs
		      val writeBufFunED = 
			  P.mkFunctionEDecl(writeBufName, BufFormalParams, PT.Compound bufBodySs, returnTy)

                      (* -- fmt2buf *)
		      val fmtbufDeclSs = bufDeclSs @
			                 [P.varDeclS'(P.ccharPtr, tdelim),
					  P.varDeclS (P.int, trequestedOut, P.falseX)]

		      val fmtBufFinalCloseSs = 
			  (if isRecord then [PL.fmtRecord (PT.String fmtBufFinalName)] else [])
			  @ [PT.Return (PT.Id tmpLength)]
		      val fmtBufFinalBodySs  = fmtbufDeclSs @ iFmtFinalBodySs @ fmtBufFinalCloseSs
		      val fmtBufFinalFunED = 
			  P.mkFunctionEDecl(fmtBufFinalName, FmtBufFormalParams, PT.Compound fmtBufFinalBodySs, returnTy)

		      (* fmt2buf body is standard for all types *)
		      val fmtBufArgs = [PT.Id pads, PT.Id buf, PT.Id bufLen, PT.Id bufFull,
					PT.Id requestedOut, PT.Id delims, PT.Id m, PT.Id pd, PT.Id rep] @ cNamesAsIds
		      val fmtBufFnAssignX = P.assignX(PT.Id tmpFn, PL.fmtfnLookupX(name))
		      val fmtBufFnInvokeX = PL.fmtfnInvokeX(tmpFn, fmtBufArgs)
		      val fmtBufBodySs = [
			  P.varDeclS'(PL.fmtfnPCT, tmpFn),
			  PL.fmtInitStandardOrEnum(standardOrEnum, PT.String fmtBufName, fmtBufFnAssignX, fmtBufFnInvokeX),
			  PT.Return(PT.Call(PT.Id fmtBufFinalName, fmtBufArgs)) ]
		      val fmtBufFunED =
			  P.mkFunctionEDecl(fmtBufName, FmtBufFormalParams, PT.Compound fmtBufBodySs, returnTy)

                      (* -- write_xml_2buf *)
		      val (sourceTagBeginSs,sourceTagEndSs) = 
			  if isSource then 
			      let val full =  OS.Path.file (!(PadsState.padsName))
(*				  val name = case PTyUtils.mungeFileName(full, "p", "xsd") of NONE => "" 
			                     | SOME n => n *)
				  in
				      ([PT.Expr(PT.Call(PT.Id "PCGEN_SOURCE_XML_OUT_BEGIN", [PT.String full]))],
				       [PT.Expr(PT.Call(PT.Id "PCGEN_SOURCE_XML_OUT_END",[]))])
			      end
			      else ([],[])
		      val bufXMLCheckParamsSs = [PL.IODiscChecksSizeRet3P(PT.String writeXMLBufName, 
								          PT.Id buf, PT.Id bufFull, PT.Id rep)]
		      val bufXMLBodySs  = bufDeclSs @ bufXMLCheckParamsSs @ bufIntroSs @ 
			                  sourceTagBeginSs @ iXMLBodySs @ sourceTagEndSs @ bufCloseSs
		      val writeXMLBufFunED = 
			  P.mkFunctionEDecl(writeXMLBufName, BufXMLFormalParams, PT.Compound bufXMLBodySs, returnTy)

                      (* -- write2io  and  write_xml_2io *)
 		      val introSs = [P.varDeclS'(P.ptrPCT PL.bytePCT, buf),
 				     P.varDeclS'(P.int, bufFull),
 				     P.varDeclS'(PL.sizePCT, bufLen) ]
		      fun doWriteS (wBufName, extraArgs, lastArgs) =
			  PT.Call(PT.Id wBufName,
				  [PT.Id pads, PT.Id buf, PT.Id bufLen,
				   P.addrX (PT.Id bufFull)]
				  @ extraArgs
				  @ (List.map PT.Id [pd, rep]) @ lastArgs @ (List.map PT.Id cNames))
		      fun mkWriteFunED (wIOName, fParams, wBufName, extraArgs, lastArgs) =
			  P.mkFunctionEDecl(wIOName, fParams,
					    PT.Compound ( introSs @
							  [PT.Expr(PT.Call(PT.Id "PCGEN_WRITE2IO_USE_WRITE2BUF",
									   [PT.String(wIOName),
									    doWriteS(wBufName, extraArgs, lastArgs)])),
							   PT.Return(P.intX ~1)]),
					    returnTy)
		      val writeIOFunED    = mkWriteFunED(writeIOName,    IOformalParams,    writeBufName,    [], [])
		      val fmtIOFunED      = mkWriteFunED(fmtIOName,      FmtIOformalParams, fmtBufName,      [PT.Id requestedOut, PT.Id delims, PT.Id m], [])
		      val writeXMLIOFunED = mkWriteFunED(writeXMLIOName, IOXMLformalParams, writeXMLBufName, [], [PT.Id tag, PT.Id indent])
		  in
		      ([writeBufFunED, writeIOFunED, writeXMLBufFunED, writeXMLIOFunED], [fmtBufFinalFunED, fmtBufFunED, fmtIOFunED])
		  end


              (* Perror_t foo_init/foo_clear(P_t* pads, foo *r) *)
              fun genInitFun(funName, argName, argPCT, bodySs, noParamChecks) = 
		  let val paramTys = [P.ptrPCT PL.toolStatePCT, 
				      P.ptrPCT argPCT]
		      val paramNames = [pads, argName]
		      val formalParams = List.map P.mkParam (ListPair.zip (paramTys, paramNames))
		      val chkTSSs = if noParamChecks then [] 
				    else [PT.Expr(PT.Call(PT.Id "PDCI_DISC_1P_CHECKS",
							  [PT.String funName, PT.Id argName]))]
		      val bodySs = chkTSSs @ bodySs
		      val returnTy =  PL.toolErrPCT
		      val initFunED = 
			  P.mkFunctionEDecl(funName, formalParams, 
					    PT.Compound bodySs, returnTy)
		  in
		      initFunED
		  end

	      fun genMaskInitFun(funName, maskPCT) = 
		  let val mask = "mask"
		      val baseMask = "baseMask"
		      val paramTys = [P.ptrPCT PL.toolStatePCT, P.ptrPCT maskPCT, PL.base_mPCT]
		      val paramNames = [pads, mask, baseMask]  
		      val formalParams = List.map P.mkParam (ListPair.zip(paramTys, paramNames))
		      val bodySs = [PL.fillMaskS(PT.Id mask, PT.Id baseMask, maskPCT)]
		      val returnTy =  P.void
		      val maskInitFunED = 
			  P.mkFunctionEDecl(funName, formalParams, 
					    PT.Compound bodySs, returnTy)
		  in
		      [maskInitFunED]
		  end

              (* Perror_t foo_copy(P_t* pads, foo *dst, foo* src) *)
              fun genCopyFun(funName, dst, src, argPCT, bodySs, noParamChecks) = 
		  let val paramTys = [P.ptrPCT PL.toolStatePCT, 
				      P.ptrPCT argPCT,
				      P.ptrPCT argPCT]
		      val paramNames = [pads, dst, src]
		      val formalParams = List.map P.mkParam (ListPair.zip (paramTys, paramNames))
		      val chkTSSs = if noParamChecks then []
				    else [PT.Expr(PT.Call(PT.Id "PDCI_DISC_2P_CHECKS",
							  [PT.String funName, PT.Id src, PT.Id dst]))]
		      val bodySs = chkTSSs @ bodySs
		      val returnTy =  PL.toolErrPCT
		      val copyFunED = 
			  P.mkFunctionEDecl(funName, formalParams, 
					    PT.Compound bodySs, returnTy)
		  in
		      copyFunED
		  end

              (* int is_foo(foo *rep) *)
              fun genIsFun(funName, cParams:(string *pcty) list, rep, argPCT, bodySs) = 
		  let val (cNames, cTys) = ListPair.unzip cParams
		      val paramTys = [P.ptrPCT argPCT] @ cTys
		      val paramNames = [rep] @ cNames
		      val formalParams = List.map P.mkParam (ListPair.zip (paramTys, paramNames))
		      val returnTy =  P.int
		      val isFunED = 
			  P.mkFunctionEDecl(funName, formalParams, PT.Compound bodySs, returnTy)
		  in
		      isFunED
		  end



	      fun genTrivReportFuns (reportName, whatStr, baseWhatStr, accPCT, repioCallX) = 
		  let fun genParamTys extraPCTs =
		          [P.ptrPCT PL.toolStatePCT] 
			 @ extraPCTs
			 @ [P.ccharPtr,
			    P.ccharPtr,
			    P.int,
			    P.ptrPCT accPCT]
                      fun genParamNames extraNames = [pads] @ extraNames @ [ prefix, what, nst, acc]
                      val intlParamNames = genParamNames [outstr]
                      val extlFormalParams = List.map P.mkParam (ListPair.zip (genParamTys [], genParamNames []))
		      val intlFormalParams = List.map P.mkParam 
			                        (ListPair.zip (genParamTys [PL.sfioPCT], intlParamNames))
		      val macroCallS =
			  case baseWhatStr of
			      NONE   => PT.Expr(PT.Call(PT.Id "PCGEN_ENUM_ACC_REP2IO", [PT.String whatStr, repioCallX]))
			    | SOME b => PT.Expr(PT.Call(PT.Id "PCGEN_TYPEDEF_ACC_REP2IO", [PT.String whatStr, b, repioCallX]))
		      val XXXsetWhatS = PT.IfThen(P.notX(PT.Id what),
						 PT.Compound[P.assignS(PT.Id what, PT.String whatStr)])
		      val XXXbodySs = PT.Compound([XXXsetWhatS, PT.Return(repioCallX)])
		      val bodySs = PT.Compound([macroCallS])
		      val returnTy = PL.toolErrPCT
		      val toioReportFunED = P.mkFunctionEDecl(ioSuf reportName, intlFormalParams, bodySs, returnTy)
		      val externalReportFunED = BU.genExternalReportFun(reportName, intlParamNames, extlFormalParams, acc)
		  in
		      [toioReportFunED, externalReportFunED]
		  end

              (* const char * name2str(enumPCT which) *)
              fun genEnumToStringFun(name, enumPCT, members) = 
  		  let val cnvName = toStringSuf name
		      val which = "which"
		      val paramNames = [which]
		      val paramTys = [enumPCT]
		      val formalParams = List.map P.mkParam(ListPair.zip(paramTys, paramNames))
		      fun cnvOneBranch (ename, dname,  _, _) =
			  P.mkCase(PT.Id ename, SOME [PT.Return (PT.String dname)])
		      val defBranch =
			  P.mkDefCase(SOME [PT.Return (PT.String "*unknown_tag*")])
		      val branches = (List.concat(List.map cnvOneBranch members)) @ defBranch
		      val bodySs = [PT.Switch ((PT.Id which), PT.Compound branches)]
		      val returnTy = P.ccharPtr
		      val cnvFunED = 
			  P.mkFunctionEDecl(cnvName, formalParams, PT.Compound bodySs, returnTy)
		  in
		      cnvFunED
		  end


	      fun callIntPrint (reportName, prefixX, whatX, nstX, fieldX) = 
		  PT.Call(PT.Id reportName, 
			  [PT.Id pads, PT.Id outstr, prefixX, whatX, nstX, fieldX])



	      fun checkParamTys (fieldName, functionName, extraargs, numBefore, numAfter) = 
		  let val (eaty, _) = cnvExpression (PT.Id functionName)
		      val fargtysOpt = case eaty
			  of Ast.Pointer(Ast.Function (retTy, argTys)) => (
			      (SOME (List.take(List.drop(argTys, numBefore), 
			                  (List.length argTys) - numAfter - numBefore)))
				  handle Subscript => NONE)
			| _ =>   NONE (* error, to be reported later *)
		      val aargtys = #1( ListPair.unzip (List.map cnvExpression extraargs))
		      fun match([], []) = true
			| match(fty::ftys, aty::atys) = 
			  isAssignable(fty, aty, NONE) andalso
			  match(ftys, atys)
			| match _ = false
		      val errMsg = "Actual argument(s) for field "^
			  fieldName ^" did not have expected type(s)"
		  in
		      case fargtysOpt
			  of NONE => (PE.error errMsg)
			| SOME fargtys => (
					   if not (match(fargtys, aargtys))
					       then (PE.error errMsg)
					   else ()
		  (* end case *))
		  end
                                      


              (* handles problem if first element of an initializer is an enumerated type *)
              fun getFirstEMPCT emFields = 
		  case emFields
		  of [] => NONE
		  | ((_, ty, _)::fs) => 
		      let val aty = #1 (CTcnvType ty)
		      in
			  if Option.isSome(CTisEnum aty) 
			      then SOME ty else NONE
		      end

	      (* Given a manifest field description, calculate shared properties *)
	      fun genTyPropsMan {tyname, name, args, isVirtual, expr, pred, comment} =
		  let val (ct, _) = CTcnvType tyname
		      val isStatic = CisStatic ct
		      val () = if not isStatic then 
			  PE.error ("Representation of manifest field "^name
				    ^" contains a pointer")
			       else ()
		      val tyStr = CTtoString ct
		  in
		      [{diskSize = TyProps.mkSize (0,0), 
			memChar = if isStatic then TyProps.Static else TyProps.Dynamic,
			endian = false, isRecord = false, 
                        containsRecord = false, largeHeuristic = false, 
			labels = [SOME (name, tyStr, ([], []), isVirtual, comment )]}]
		  end


              fun unionDotBranchX (base, name) = P.dotX(P.dotX(base, PT.Id(PNames.unionVal)), PT.Id name)
              fun getUnionDotBranchX (base, name) = P.addrX(unionDotBranchX(base, name))
	      fun unionRepX (base, name, isVirt, isLMatch) =
		  if isVirt
		  then tmpId(name)
		  else ( if isLMatch
			 then unionDotBranchX(pcgenId("trep"), name)
			 else P.unionBranchX(base, name) )
	      fun unionPdX (pd, name, isVirt, isLMatch) =
		  if isLMatch
		  then unionDotBranchX(pcgenId("tpd"), name)
		  else P.unionBranchX(pd, name)
	      fun structRepX (base, name, isVirt) =
		  if isVirt then tmpId(name) else P.fieldX(rep, name)

	      fun genFreshName testFn base suff = 
		  let val name0 = base^suff
		  in
		      if not (testFn name0) then name0
		      else let fun getname base next suff = 
			  let val n = base^"_"^(Int.toString next)^suff
			  in
			      if not (testFn n) then n
			      else getname base (next + 1) suff
			  end
			   in
			       getname base 0 suff
			   end
		  end




	      (* Does some checks, produces tuple with 4 lists:                                                *)
	      (*     1. A list of all of the field names in order that they occur                              *)
	      (*     2. A list of just the names of the virtual fields                                         *)
	      (*     3. A list of pairs (name, type) of local vars to use for Pomit fields                     *)
              (*           where tmpNames are used for temp union fields                                       *)
	      (*     4. A list of substitution pairs for field constraints, of 5 kinds:                        *)
	      (*           (name, P.dotX(pcgenName("trep"), PT.Id name))     -- for struct longestMatch field  *)
	      (*           (name, P.fieldX(rep, name))                         -- for struct field               *)
	      (*           (name, unionDotBranchX(pcgenName("trep"), name))  -- for union longestMatch field   *)
	      (*           (name, P.unionBranchX(rep, name))                   -- for union field                *)
	      (*           (name, PT.Id tmpName)                             -- for omitted field              *)
              (*     5. a list of substitution pairs for pd references within Parse check constraints,         *)
              (*        of the same forms as the field constraints above.                                      *)
	      (*     6. A list of substitution pairs for post-read (Pwhere, is fn) constraint                  *)
	      (*        same as above except longestMatch is ignored, uses rep for all non-omitted cases       *)
	      (*     7. A list of types                                                                        *)
	      (*     8. A list of type names                                                                   *)

	      fun checkStructUnionFields (structOrUnion, structOrUnionName, isLongestMatch, fields) =
		  let fun readMapping (name) =
			  if structOrUnion = "Pstruct"
			  then ( if isLongestMatch
				 then (PE.error ("Unexpected Plongest modifier on Pstruct"^structOrUnionName^".") ; 
				       [(name, P.dotX(pcgenId("trep"), PT.Id name))])
				 else [(name, P.fieldX(rep, name))] )
			  else [(name, unionRepX(rep, name, false, isLongestMatch))]
		      fun pdMapping (name) =
			  if structOrUnion = "Pstruct"
			  then ( if isLongestMatch
				 then  [(pdSuf name, P.dotX(pcgenId("tpd"), PT.Id name))]
				 else [(pdSuf name, P.fieldX(pd, name))] )
			  else [(pdSuf name, unionPdX(pd,name,false,isLongestMatch))]
		      fun postReadMapping (name) =
			  if structOrUnion = "Pstruct"
			  then [(name, P.fieldX(rep, name))]
			  else [(name, P.unionBranchX(rep, name))]
		      fun tmpMapping (name) = [(name, tmpId(name))]
                      (* gen functions produce [( [name], [name(if omit)|empty],
						  [var-pair(if omit)|empty], [empty(if omit)|mapping], [empty(if omit)|mapping] )] *)
		      fun genLocFull ({pty: PX.Pty, args: pcexp list, name: string, isVirtual: bool, 
				      isEndian: bool, isRecord, containsRecord, largeHeuristic: bool,
				      pred, comment: string option, size,optDecl, arrayDecl,...}:BU.pfieldty) = 
			  ( if  name = PNames.pd orelse name = PNames.identifier orelse (structOrUnion = "Pstruct" andalso name = PNames.structLevel)
				orelse isSuffix "_pd" name 
			    then PE.error (structOrUnion^" "^structOrUnionName^" contains field with reserved name '"^name^"'\n")
			    else ();
			    let val tyName = BU.lookupTy (pty, repSuf, #repname)
				val ty = P.makeTypedefPCT(BU.lookupTy (pty, repSuf, #repname))
				val () = ( CTcnvType ty  (* ensure that the type has been defined *) ; () )
				val (ty,tyName) = if arrayDecl orelse optDecl then 
				                    let val tyName = name^"_t"
							val tyName = genFreshName tyNameDefined name "_t"
						    in (P.makeTypedefPCT tyName, tyName) 
						    end 
						  else (ty,tyName)
			    in
				if isVirtual
				then [( [name], [name], [(tmpName(name), ty)], tmpMapping(name),  [],             tmpMapping(name),      [ty], [tyName] )]
				else [( [name], [],     [],                    readMapping(name), pdMapping name, postReadMapping(name), [ty], [tyName] )]
			    end
			  )
		      fun genLocBrief (r as (e,labelOpt)) = 
			  if structOrUnion = "Pstruct" then []
                          else let val nameOpt = getString r  (* still need to handle regular expressions *)
			       in
				   case nameOpt 
                                   of NONE => (PE.error (structOrUnion^" "^structOrUnionName^
							" contains an ill-formed literal "^(P.expToString e)^" \n"); [])
				   | SOME s => 
				       if not (isCId s) then
					   (PE.error (structOrUnion^" "^structOrUnionName^
							" contains an invalid literal "^s^" \n"); [])
				       else
					   []
				   
			       end
		      fun genLocMan {tyname, name, args, isVirtual, expr, pred, comment} = 
			 let val () = if name = PNames.pd orelse name = PNames.identifier orelse (structOrUnion = "Pstruct" andalso name = PNames.structLevel)
				       then PE.error (structOrUnion^" "^structOrUnionName^" contains field with reserved name '"^name^"'\n")
				       else () 
			      val () = (case expr 
					 of PT.EmptyExpr => PE.error "Manifest fields must have an initializing expression"
			                  | _ => ())
			 in
			     case isPadsTy tyname
			      of PTys.CTy =>
				 if isVirtual
				 then [( [name], [name], [(tmpName(name),tyname)], tmpMapping(name),  [],             tmpMapping(name),      [tyname], ["bogus"] )]
				 else [( [name], [],     [],                       readMapping(name), pdMapping name, postReadMapping(name), [tyname], ["bogus"] )]
			       | _        => 
				 let val tyName = BU.lookupTy ((getPadsName tyname), repSuf, #repname)
				     val ty = P.makeTypedefPCT(tyName)
				     val () = ( CTcnvType ty  (* ensure that the type has been defined *) ;
						if lookupContainsRecord(getPadsName tyname)
						then PE.error ("Pcomputed field "^name^" has a PADS type that contains a record")
						else () )
				 in
				     if isVirtual
				     then [( [name], [name], [(tmpName(name),ty)], tmpMapping(name),  [],             tmpMapping(name),      [ty], [tyName] )]
				     else [( [name], [],     [],                   readMapping(name), pdMapping name, postReadMapping(name), [ty], [tyName] )]
				 end
			 end
		      val resall = P.mungeFields genLocFull genLocBrief genLocMan fields
		      fun analyzePred NONE = false
                        | analyzePred (SOME pred:pcexp PX.PPostCond list option) = 
			  let fun f [] = false
			        | f ((PX.General x)::ls) = f ls
			        | f ((PX.ParseCheck x) ::ls) = true
			  in
			      f pred
			  end
		      fun predInfoFull ({pty: PX.Pty, args: pcexp list, name: string, isVirtual: bool, 
				      isEndian: bool, isRecord, containsRecord, largeHeuristic: bool,
				      pred, comment: string option, size,optDecl, arrayDecl,...}:BU.pfieldty) = [analyzePred pred]
		      fun predInfoBrief _ = [false]
		      fun predInfoMan {tyname, name, args, isVirtual, expr, pred, comment} = [analyzePred pred]
		      val hasParseCheck = List.exists (fn x=>x) (P.mungeFields predInfoFull predInfoBrief predInfoMan fields)
		  in
		     (hasParseCheck, unzip8' resall)
		  end

	      (* For an omitted field, generate init call if cty is a dynamic PADS type *)
	      fun initOmitVar (name, cty) =
		  case isPadsTy cty
		   of PTys.CTy => [] 
		    |  _       => let val pty = getPadsName cty
				  in if TyProps.Dynamic = lookupMemChar pty
				     then
					 [PT.Expr(PT.Call(PT.Id(initSuf(lookupMemFun(pty))),
							  [PT.Id pads, P.addrX(PT.Id(name))]))]
				     else []
				  end

	      fun omitVarDecls (omitVars) =
		  List.map (P.varDeclS' o (fn(x, y) => (y, x))) omitVars

	      fun omitVarInits (omitVars) =
		  List.concat (List.map initOmitVar omitVars)

	      fun nameLoc name (x::xs) = (if name = x then 1 else 1 + (nameLoc name xs))
		| nameLoc name [] = 0 (* not needed? *)

              (* see if any names after curName are free in expr *)

	      fun checkStructFieldScope (structName, curName, names, expr, inParseCheck) =
		  let val loc1 = nameLoc curName names
		      fun checkOneField (checkName, loc2) =
			  let val () = if curName = checkName then ()
				       else if PTSub.isFreeInExp([checkName], expr) andalso (loc1 < loc2)
				       then (PE.error("Illegal field reference in Pstruct "^structName^
						      ":\n\t\tcontraint for field "^curName^" refers to later field "^checkName))
				       else ()
			  in
			      let val pdFree = PTSub.isFreeInExp([pdSuf checkName], expr)
			      in
				  if not inParseCheck andalso pdFree 
				      then (PE.error("Illegal parse descriptor reference in Pstruct "^structName^
						     ":\n\t\tnon-parsecheck contraint for field "^curName^" refers to parse descriptor "^(pdSuf checkName)^"."))
				  else if pdFree andalso (loc1 < loc2)
					   then (PE.error("Illegal parse descriptor reference in Pstruct "^structName^
							  ":\n\t\tcontraint for field "^curName^" refers to later parse descriptor "^(pdSuf checkName)))
				  else ()
			      end
			  end
		      val nmap = List.map (fn(x) => (x, nameLoc x names)) names
		  in
		      (List.map checkOneField nmap; ())
		  end

	      fun checkUnionFieldScope (unionName, curName, names, expr, inParseCheck) =
		  let fun checkOneField checkName =
		          let val _ = if curName = checkName then ()
				      else if PTSub.isFreeInExp([checkName], expr)
				      then (PE.error("Illegal branch reference in Punion "^unionName^
						     ":\n\t\tcontraint for branch "^curName^" refers to value of branch  "^checkName))
				      else ()
			  in
			   if PTSub.isFreeInExp([pdSuf checkName], expr) 
			    then
			        if inParseCheck andalso curName = checkName then ()
			        else if inParseCheck
			        then (PE.error("Illegal parse descriptor reference in Punion "^unionName^
					       ":\n\t\tcontraint for field "^curName^" refers to parse descriptor "^(pdSuf checkName)^"."))
				else
				        (PE.error("Illegal parse descriptor reference in Punion "^unionName^
						  ":\n\t\tnon-parsecheck contraint for field "^curName^" refers to parse descriptor "^(pdSuf checkName)^"."))

			   else()
			  end
		  in
		      (List.map checkOneField names; ())
		  end


	      fun modStructPred (structName, curName, names, pred, subList) =
		  case pred of NONE =>  NONE
			     | SOME predList =>
	                       let fun doOne subList exp = 
				       let val (exp,inParseCheck) = case exp of PX.General e => (e,false) | PX.ParseCheck e => (e,true)
					   val ()     = checkStructFieldScope(structName, curName, names, exp,inParseCheck)
					   val modExp = PTSub.substExps subList exp
					   val ()     = expEqualTy(modExp, CTintTys,
							   (fn(s) => ("Pstruct "^structName^": constraint for field '"^
								      curName ^ "' has type " ^ s ^ ", expected type int")))
				       in
					   modExp
				       end
			       in
				   SOME (P.andBools(List.map (doOne subList) predList))
			       end

	      fun modUnionPred (unionName, curName, names, pred, subList) =
		  case pred of NONE => NONE
			     | SOME predList =>
	                       let fun doOne subList exp = 
				      let val (exp,inParseCheck) = case exp of  PX.General e => (e,false) | PX.ParseCheck e => (e,true)
					  val ()     = checkUnionFieldScope(unionName, curName, names, exp,inParseCheck)
					  val modExp = PTSub.substExps subList exp
					  val ()     = expEqualTy(modExp, CTintTys,
							   (fn(s) => ("Punion "^unionName^": constraint for branch '"^
								      curName ^ "' has type " ^ s ^ ", expected type int")))
				      in 
					  modExp
				      end
			       in
				   SOME (P.andBools(List.map (doOne subList) predList))
			       end

	      fun chkManArgs (structOrUnion, structOrUnionName, tyname, name, args, subList) =
		  case isPadsTy tyname
		   of PTys.CTy => if not (List.length args = 0) then
			              PE.error ("In "^structOrUnion^" "^structOrUnionName^", Pcompute field "^name^ " has C type; hence can have no parameters")
				  else ()
		    | _ => (let val modArgs = List.map (PTSub.substExps subList) args
			    in
				checkParamTys(name, (BU.lookupTy(getPadsName tyname, readSuf, #readname)), modArgs, 4, 0)
			    end)



	      (* Given a manifest field description, generate canonical representation *)
	      fun genRepMan {tyname, name, args, isVirtual, expr, pred, comment} = 
		  if isVirtual then [] else
		  let val fullCommentOpt = BU.manComment(name, comment, expr, pred)
		      val ty = case isPadsTy tyname
			       of PTys.CTy => tyname
                               | _ => P.makeTypedefPCT(BU.lookupTy(getPadsName tyname, repSuf, #repname))
		  in
		      [(name, ty, fullCommentOpt)]
		  end


              (* Given manifest field, use f to generate field declaration from pads pty *)
              fun genMan x =  BuildUtils.genMan (isPadsTy, getPadsName) x
              
	      
	      (* Given representation of manifest field, generate accumulator representation. *)
	      fun genAccMan m =  genMan (lookupAcc', NONE, false, m)

	      (* Given representation of manifest field, generate parse descriptor representation. *)
	      fun genEDMan m = 
		  let fun f pty = BU.lookupTy(pty, pdSuf, #pdname)
		  in
		      genMan (f, (SOME PL.base_pdPCT), true, m)
		  end


              fun genAssignMan(tyname, name, repX, exp) = 
		  let val pct = tyNameToPCT tyname
		      val (cty, _) = CTcnvType pct
		      fun assignS exp = 
		      case exp 
			  of PT.MARKexpression(loc, exp) => assignS exp
			| PT.EmptyExpr => P.assignS(repX, P.zero)
			| PT.InitList l => 
			      PT.Compound[P.varDeclS(pct, name, exp),
					  P.assignS(repX, PT.Id name)]
			| exp =>
			      (expAssignTy(exp, [cty], 
					   fn s=> ("Value for field "^
						   name ^ " " ^
						   "has type "^s^", expected type "^
						   (CTtoString cty)^"\n"));
			       P.assignS(repX, exp))
		  in
		      assignS exp
		  end

	      (* Given manifest representation, generate accumulator functions(init, reset, cleanup) *)
	      fun genAccTheMan theSuf m = 
		      BU.genFunMan (isPadsTy, getPadsName) (lookupAcc', theSuf, acc, [], m)


	      (* Given manifest representation, generate report function *)
	      fun cnvPtyForReport(reportSuf, ioSuf, pty, name, fieldOrBranch) = 
		  case lookupAcc(pty)
		   of NONE =>
		      [P.mkCommentS(fieldOrBranch^" '"^name^"': no acc function, cannot accumulate")]
		| SOME a =>
		  (let val reportName = reportSuf a
		       fun gfieldX base = P.getFieldX(base, name)
		   in
		       BU.genPrintPiece(ioSuf reportName, name, P.zero, gfieldX acc, [])
		   end)

	      fun genAccReportMan (reportSuf, ioSuf, fieldOrBranch) {tyname, name, args, isVirtual, expr, pred, comment} =
		  if isVirtual 
		  then [P.mkCommentS("Pomit "^fieldOrBranch^": cannot accumulate")]
		  else case isPadsTy tyname 
			of PTys.CTy => [P.mkCommentS("C type "^fieldOrBranch^": cannot accumulate")]
			 | _ => (cnvPtyForReport(reportSuf, ioSuf, getPadsName tyname, name, fieldOrBranch))

	      fun emit (condition, eds) = 
		  if condition then 
		      List.concat(List.map cnvExternalDecl eds)
		  else []

              fun emitAccum eds = emit (!(#outputAccum(PInput.inputs)), eds)
              fun emitRead  eds = emit (!(#outputRead(PInput.inputs)), eds)
              fun emitWrite eds = emit (!(#outputWrite(PInput.inputs)), eds)
              fun emitExperiment eds = emit (!(#outputExper(PInput.inputs)), eds)
              fun emitXML   eds = emit (!(#outputXML(PInput.inputs)), eds)
              fun emitHist  eds = emit (!(#outputHist(PInput.inputs)), eds)
              fun emitCluster eds = emit (!(#outputCluster(PInput.inputs)), eds)
	      fun emitPred  eds = emitRead eds

              fun isGalax () = (!(#outputXML(PInput.inputs)))

              fun cnvCTy ctyED = 
		  let val astdecls = cnvExternalDecl ctyED
		  in
		    (if not (List.length astdecls = 1) then (PE.bug "Expected no more than one external declaration") 
                                                       else ();
		     case List.hd astdecls 
                      of Ast.DECL(Ast.ExternalDecl (Ast.TypeDecl {shadow, tid}), aid, paid, loc) => (astdecls, tid)
                      | _ => (PE.error "Expected ast declaration"; (astdecls, Tid.new())))
		  end

              fun cnvRep (canonicalED, padsInfo) = 
		  case cnvCTy canonicalED 
		  of (Ast.DECL(coreDecl, aid, paid, loc)::xs, tid) =>
                       (Ast.DECL(coreDecl, aid, bindPaid padsInfo, loc) ::xs, tid)
                  | _ => (PE.bug "Expected ast declaration"; ([], Tid.new()))


              (*  Typedef case *)
	      fun cnvPTypedef ({name : string, params: (pcty * pcdecr) list, isRecord, containsRecord, 
			        largeHeuristic,	isSource : bool, baseTy: PX.Pty, args: pcexp list, 
				pred : pcexp PX.PPredicate option})=
(*			        predTy: PX.Pty option, thisVar: string option, pred: pcexp option}) =  *)
		  let val base = "base"
		      val baseTyName = BU.lookupTy(baseTy, repSuf, #padsname)		
		      val baseTypeName = BU.lookupTy(baseTy, repSuf, #repname)		
		      val cParams : (string * pcty) list = List.map mungeParam params
		      val paramNames = #1(ListPair.unzip cParams)

                      (* Generate CheckSet mask typedef case*)
		      val baseMPCT = P.makeTypedefPCT(BU.lookupTy(baseTy, mSuf, #mname))
                      val mFields  = [(base, baseMPCT,          SOME "Base mask"),
				      (user, PL.base_mPCT,      SOME "Typedef mask")]
		      val mED      = P.makeTyDefStructEDecl (mFields, mSuf name)
		      val mDecls   = cnvExternalDecl mED
                      val mPCT     = P.makeTypedefPCT (mSuf name)		

                      (* Generate parse description: typedef to base pd *)
		      val pdEDPCT = P.makeTypedefPCT(BU.lookupTy(baseTy, pdSuf, #pdname))
		      val pdED = P.makeTyDefEDecl (pdEDPCT, pdSuf name)
		      val (pdDecls, pdTid)  = cnvCTy pdED
                      val pdPCT = P.makeTypedefPCT (pdSuf name)

		      (* Generate accumulator type *)
		      val PX.Name baseName = baseTy
		      val baseAccPCT = case PBTys.find(PBTys.baseInfo, Atom.atom baseName) 
			               of NONE => P.makeTypedefPCT (accSuf baseName)  (* must have been generated *)
                                       | SOME(b:PBTys.baseInfoTy) => 
					   (case (#accname b) 
					    of NONE => P.voidPtr   (* accumulation not defined for this base type *)
 			                    | SOME acc => (P.makeTypedefPCT (Atom.toString acc)))
		      val accED     = P.makeTyDefEDecl (baseAccPCT, accSuf name)
		      val accPCT    = P.makeTypedefPCT (accSuf name)		

		      (* Insert type properties into type table *)
                      val ds = computeDiskSize(name, paramNames, baseTy, args)
                      val mc = lookupMemChar baseTy
                      val endian = lookupEndian baseTy
                      val contR = lookupContainsRecord baseTy
 		      val lH = lookupHeuristic baseTy
		      val numArgs = List.length params
		      val typedefProps = buildTyProps(name, PTys.Typedef, ds, TyProps.Typedef (ds, baseName, (paramNames, args)), mc, endian, 
						      isRecord, contR, lH, isSource, pdTid, numArgs)
                      val () = PTys.insert(Atom.atom name, typedefProps)

		      (* Generate canonical representation: typedef to base representation *)
		      val baseTyPCT = P.makeTypedefPCT(BU.lookupTy(baseTy, repSuf, #repname))
		      val canonicalED = P.makeTyDefEDecl (baseTyPCT, repSuf name)
		      val (canonicalDecls, canonicalTid) = cnvRep(canonicalED, valOf (PTys.find (Atom.atom name)))
                      val canonicalPCT = P.makeTypedefPCT (repSuf name)

                      (* Generate Init function (typedef case) *)
		      val baseFunName = lookupMemFun (PX.Name baseTyName)
		      val initFunName = lookupMemFun (PX.Name name)
                      fun genInitEDs (suf, argName, aPCT) = case #memChar typedefProps
                          of TyProps.Static => 
				  [genInitFun(suf initFunName, argName, aPCT, [PT.Return PL.P_OK], true)]
                           | TyProps.Dynamic =>
			      let val bodySs = [PL.bzeroS(PT.Id argName, P.sizeofX(aPCT)),PT.Return PL.P_OK]
			      in
				  [genInitFun(suf initFunName, argName, aPCT, bodySs, false)]
			      end
                      val initRepEDs = genInitEDs (initSuf, rep, canonicalPCT)
                      val initPDEDs  = genInitEDs ((initSuf o pdSuf), pd, pdPCT)
                      fun genCleanupEDs (suf, argName, aPCT) = case #memChar typedefProps
                          of TyProps.Static => 
				  [genInitFun(suf initFunName, argName, aPCT, [PT.Return PL.P_OK], true)]
                           | TyProps.Dynamic =>
			      let val argX = PT.Id argName
				  val bodySs = 
				  [PT.Return(PT.Call(PT.Id(suf baseFunName),
						     [PT.Id pads, argX]))]
			      in
				  [genInitFun(suf initFunName, argName, aPCT, bodySs, false)]
			      end
                      val cleanupRepEDs = genCleanupEDs (cleanupSuf, rep, canonicalPCT)
                      val cleanupPDEDs  = genCleanupEDs ((cleanupSuf o pdSuf), pd, pdPCT)

                      (* Generate Copy Function typedef case *)
                      fun genCopyEDs(suf, which, aPCT) = 
			  let val copyFunName = suf initFunName
			      val dst = dstSuf which
			      val src = srcSuf which
			      val nestedCopyFunName = suf baseFunName
			      val bodySs = 
				  case #memChar typedefProps
				   of TyProps.Static => [PL.memcpyS(PT.Id dst, PT.Id src, P.sizeofX aPCT),
							 PT.Return PL.P_OK]
				   | _ => [PT.Return (PT.Call(PT.Id nestedCopyFunName, 
							      [PT.Id pads, PT.Id dst, PT.Id src]))]
			  in
			      [genCopyFun(copyFunName, dst, src, aPCT, bodySs, true)]
			  end
		      val copyRepEDs = genCopyEDs(copySuf o repSuf, rep, canonicalPCT)
		      val copyPDEDs  = genCopyEDs(copySuf o pdSuf,  pd,  pdPCT)

                      (* Generate m_init function typedef case *)
                      val maskInitName = maskInitSuf name 
                      val maskFunEDs = genMaskInitFun(maskInitName, mPCT)

                      (* Generate read function *)
                      (* -- Some helper functions *)
		      val readName = readSuf name
                      val baseReadFun = BU.lookupTy(baseTy, readSuf, #readname)
		      val modPredXOpt = case pred of NONE => NONE
			             | SOME {predTy, thisVar, pred} => SOME (PTSub.substExp (thisVar, P.starX(PT.Id rep), pred))
		      fun chk () = 
			  (checkParamTys(name, baseReadFun, args, 4, 0);
			   case modPredXOpt of NONE => ()
                           | SOME modPredX => 
			       expEqualTy(modPredX, CTintTys, 				
					  fn s=> (" constraint for typedef "^
						  name ^ " has type " ^ s ^
						  ", expected type int")))

                      fun genReadBody () = 
			  let val readBaseX = 
				  PL.readFunX(baseReadFun, 
					      PT.Id pads, 
					      P.addrX (P.fieldX(m, base)),
					      args,
					      PT.Id pd,
					      PT.Id rep)
			      val callMacroS =
				  case modPredXOpt of NONE =>
					if isRecord then 
					  PT.Expr(PT.Call(PT.Id "PCGEN_TYPEDEF_READ_REC", [PT.String(readName), readBaseX]))
					else
					  PT.Expr(PT.Call(PT.Id "PCGEN_TYPEDEF_READ", [PT.String(readName), readBaseX]))
				  | SOME modPredX => 
					if isRecord then 
					  PT.Expr(PT.Call(PT.Id "PCGEN_TYPEDEF_READ_CHECK_REC", [PT.String(readName), readBaseX, modPredX]))
					else
					  PT.Expr(PT.Call(PT.Id "PCGEN_TYPEDEF_READ_CHECK", [PT.String(readName), readBaseX, modPredX]))

		      in
			  [callMacroS, BU.stdReturnS]
		      end

                      (* -- Assemble read function typedef case *)
		      val _ = pushLocalEnv()                                        (* create new scope *)
		      val () = ignore (insTempVar(rep, P.ptrPCT canonicalPCT))      (* add rep to scope *)
                      val () = ignore (List.map insTempVar cParams)                 (* add params for type checking *)
		      val () = chk()
		      val readBody = genReadBody ()                               (* does type checking *)
		      val _ = popLocalEnv()                                         (* remove scope *)
		      val readFunEDs = genReadFun(readName, cParams, mPCT, pdPCT, canonicalPCT, 
						  NONE, false, readBody)

                      val readEDs = initRepEDs @ initPDEDs @ cleanupRepEDs @ cleanupPDEDs
			          @ copyRepEDs @ copyPDEDs @ maskFunEDs @ readFunEDs

                      (* -- generate is function (typedef case) *)
		      val isName = isPref name
		      val predX  = case (lookupPred baseTy, modPredXOpt) of 
			             (NONE, NONE) => P.trueX
				   | (SOME basePred, NONE) => PT.Call(PT.Id basePred, [PT.Id rep] @ args)
				   | (NONE, SOME modPredX) => modPredX
			           | (SOME basePred, SOME modPredX) => P.andX(PT.Call(PT.Id basePred, [PT.Id rep] @ args), modPredX)
		      val bodySs = [PT.Return predX]
		      val isFunEDs = [genIsFun(isName, cParams, rep, canonicalPCT, bodySs) ]

                      (* -- generate accumulator init, reset, and cleanup functions (typedef case) *)
		      fun genResetInitCleanup theSuf = 
			  let val theFun = (theSuf o accSuf) name
			  in case lookupAcc baseTy 
			      of NONE => (BU.gen3PFun(theFun, [accPCT], [acc],
						   [P.mkCommentS ("Accumulation not defined for base type of ptypedef"),
						    PT.Return PL.P_OK])
			                                     (* end NONE *))
				| SOME a => (
				   let val theBodyE = PT.Call(PT.Id(theSuf a), 
							      [PT.Id pads, PT.Id acc])
				       val theReturnS = PT.Return theBodyE
				       val theFunED = BU.gen3PFun(theFun, [accPCT], [acc],[theReturnS])
				   in
				      theFunED
				   end
				       (* end SOME *))
			  end
		      val initFunED = genResetInitCleanup initSuf
		      val resetFunED = genResetInitCleanup resetSuf
                      val cleanupFunED = genResetInitCleanup cleanupSuf

                      (* -- generate accumulator function *)
                      (*  Perror_t T_acc_add (P_t* , T_acc* , T_pd*, T* ) *)
		      val addFun = (addSuf o accSuf) name
		      fun genAdd NONE = BU.genAddFun(addFun, acc, accPCT, pdPCT, canonicalPCT, 
						  [P.mkCommentS ("Accumulation not defined for base type of ptypedef"),
						   PT.Return PL.P_OK])
                        | genAdd (SOME a) =
                           let val addX = PT.Call(PT.Id(addSuf  a), 
						  [PT.Id pads, PT.Id acc, PT.Id pd, PT.Id rep])
			       val addReturnS = PT.Return addX
			       val addBodySs =  [addReturnS]
			   in
			       BU.genAddFun(addFun, acc,accPCT, pdPCT, canonicalPCT, addBodySs)
			   end

                          (* end SOME case *)
                      val addFunED = genAdd (lookupAcc baseTy)

                      (* -- generate report function ptypedef *)
                      (*  Perror_t T_acc_report (P_t* , T_acc* , const char* prefix) *)
		      val reportFun = (reportSuf o accSuf) name
		      val repioCallX =
			  case lookupAcc(baseTy)
			   of NONE => PL.P_OK
			    | SOME a => PT.Call(PT.Id((ioSuf o reportSuf) a),
						[PT.Id pads, PT.Id outstr, PT.Id prefix, PT.Id what, PT.Id nst, PT.Id acc])
                      val reportFunEDs = genTrivReportFuns(reportFun, "typedef "^name, SOME(PT.String baseTyName), accPCT, repioCallX)
		      val accumEDs = accED :: initFunED :: resetFunED :: cleanupFunED :: addFunED :: reportFunEDs

	              (* Generate Hist functions typedef case *)
	              val histEDs = Hist.genTypedef (name, baseTy, canonicalPCT, pdPCT)

	              (* Generate Cluster functions typedef case *)
	              val clusterEDs = Cluster.genTypedef (name, baseTy, canonicalPCT, pdPCT)

                      (* Generate Write function typedef case *)
		      val writeName = writeSuf name
		      val fmtName = fmtSuf name
		      val writeXMLName = writeXMLSuf name
		      val writeBaseName = (bufSuf o writeSuf) (lookupWrite baseTy) 
		      val fmtBaseName = (bufSuf o fmtSuf) (lookupWrite baseTy) 
		      val writeXMLBaseName = (bufSuf o writeXMLSuf) (lookupWrite baseTy) 
		      val bodySs = writeFieldSs(writeBaseName, [PT.Id pd, PT.Id rep] @ args, isRecord)
		      val bodyXMLSs = modTagSs(name) @ writeXMLFieldSs(writeXMLBaseName, [PT.Id pd, PT.Id rep], PT.Id tag, false, false, args)
		      val fmtNameFinalBuf = bufFinalSuf fmtName
		      val bodyFmtFinalSs = (PL.fmtFinalInitTypedef (PT.String fmtNameFinalBuf)) ::(fmtTypedefSs(fmtBaseName, [P.getFieldX(m,base),PT.Id pd, PT.Id rep]@args))
                      val (writeFunEDs, fmtFunEDs)  = genWriteFuns(name, "STANDARD", writeName, writeXMLName, fmtName, isRecord, isSource, 
								   cParams, mPCT, pdPCT, canonicalPCT, bodySs, bodyXMLSs, bodyFmtFinalSs)

	              (***** typedef PADS-Galax *****)

		      val basePXTypeName = lookupPadsx(baseTy)
											 
		      fun genGalaxTypedefKthChildFun(name,baseTypeName) =		
			  let val nodeRepTy = PL.nodeT
			      val returnTy = P.ptrPCT nodeRepTy
                              val cnvName = PNames.nodeKCSuf name 
			      val paramTys = [P.ptrPCT nodeRepTy, PL.childIndexT]
                              val paramNames = [G.self,G.idx]
                              val formalParams =  List.map P.mkParam (ListPair.zip(paramTys, paramNames))
		              val bodySs = G.makeInvisibleDecls([name,baseTypeName],nil)
					   @ [G.macroTypKC(name,baseTypeName),
					      P.returnS (G.macroTypKCRet())]
			  in   
                              P.mkFunctionEDecl(cnvName, formalParams, PT.Compound bodySs, returnTy)
			  end


		      fun genGalaxTypedefKthChildNamedFun(name) =		
			  let val nodeRepTy = PL.nodeT
			      val returnTy = P.ptrPCT nodeRepTy
                              val cnvName = PNames.nodeKCNSuf name 
			      val paramTys = [P.ptrPCT nodeRepTy, PL.childIndexT, P.ccharPtr]
                              val paramNames = [G.self,G.idx,G.childName]
                              val formalParams =  List.map P.mkParam (ListPair.zip(paramTys, paramNames))
						  
		              val bodySs = [G.macroTypKCN()] 
					   @ [P.returnS (G.macroTypKCNRet())] 
			  in   
                              P.mkFunctionEDecl(cnvName, formalParams, PT.Compound bodySs, returnTy)
			  end
			 
	              val galaxEDs = 
			  [G.makeNodeNewFun(name),
			   G.makeCNInitFun(name,P.intX 2),
			   genGalaxTypedefKthChildFun(name,basePXTypeName),
			   genGalaxTypedefKthChildNamedFun(name),
			   G.makeCNKCFun(name,P.intX 2),
			   G.makeSNDInitFun(name),				      
			   G.makeTypedefSNDKthChildFun(name,basePXTypeName), 
			   G.makeTypedefPathWalkFun(name,basePXTypeName), 
			   G.makeNodeVtable(name),
			   G.makeCachedNodeVtable(name),
			   G.makeSNDNodeVtable(name)]


		  in
		        canonicalDecls
                      @ mDecls
                      @ pdDecls
		      @ (emitRead readEDs)
		      @ (emitPred isFunEDs)
                      @ (emitAccum accumEDs)
                      @ (emitHist histEDs)
                      @ (emitCluster clusterEDs)
                      @ (emitWrite writeFunEDs)
                      @ (emitWrite fmtFunEDs)
  		      @ (emitXML galaxEDs )
		  end


             fun cnvPArray {name:string, params : (pcty * pcdecr) list, isRecord, containsRecord, 
                            largeHeuristic, isSource : bool, args : pcexp list, baseTy:PX.Pty, 
			    sizeSpec:pcexp PX.PSize option, constraints: pcexp PX.PConstraint list,
			    postCond : pcexp PX.PArrayPostCond list} =
	     let 
		 val cParams : (string * pcty) list = List.map mungeParam params
		 val paramNames = #1(ListPair.unzip cParams)
		 val length = PNames.arrayLen
                 val elts = PNames.arrayElts
		 val numRead = "numRead"
		 val consumeFlag = PNames.consume
                 val internal = "_internal"
		 val element = "element"
		 val elt = "elt"
                 val array = PNames.arrayLevel
                 val arrayDetail = "arrayDetail"
                 val neerr = "neerr"
                 val firstError = "firstError"
		 val violated = "violated"
                 val elemRepPCT = P.makeTypedefPCT(BU.lookupTy(baseTy, repSuf, #repname))
                 val elemEdPCT  = P.makeTypedefPCT(BU.lookupTy(baseTy, pdSuf, #pdname))
                 val elemMPCT  = P.makeTypedefPCT(BU.lookupTy(baseTy, mSuf, #mname))
                 val elemReadName = BU.lookupTy(baseTy, readSuf, #readname)
		 val tLocX      =  PT.Id locPtr
 		 val tLocBX     =  P.arrowX(tLocX, PT.Id "b")
		 val tLocEX     =  P.arrowX(tLocX, PT.Id "e")				  
		 val tlocES1    =  PL.getLocEndMinus1S(PT.Id pads, P.starX(tLocX)) 
		 val tlocES0    =  PL.getLocEndS(PT.Id pads, P.starX(tLocX)) 

                 (* Some useful functions *)

  
                 fun amCheckingBasicE(SOME testE) = 
                     P.andX(PL.mTestSynCheckX(P.fieldX(m, array)), testE)
                   | amCheckingBasicE(NONE) = PL.mTestSynCheckX(P.fieldX(m, array))

                 fun amCheckingUserE(SOME testE) = 
                     P.andX(PL.mTestSemCheckX(P.fieldX(m, array)), testE)
                   | amCheckingUserE(NONE) = PL.mTestSemCheckX(P.fieldX(m, array))


                 (* Calculate bounds on array, generate statements for checking values *)
                 (* used in read function, defined below *)
		 val readName = readSuf name
		 val roDriverName = readName (* roDriverSuf name *)
		 val roInitName = roInitSuf name
		 val readOneName = readOneSuf name
		 val rereadOneName = rereadOneSuf name
		 val fcName      = finalChecksSuf name
		 val pdRBufferX   = P.fieldX(pd, internal)
		 val resRBufferX  = P.fieldX(rep, internal)

                 (* Array: error checking *)
                 val _ = CTcnvType elemRepPCT 

                 (* add local variables, ie, parameters,  to scope *)
		 val _ = pushLocalEnv()                                        (* create new scope *)
		 val cParams : (string * pcty) list = List.map mungeParam params
		 val () = ignore (List.map insTempVar cParams)  (* add params for type checking *)
		 (* scope is removed at end of cnvPArray *)

                 
                 (* -- Check size specification for array. 
		       Parameter esRetX is the return code passed to
		       recordArrayErrorS. 
		  *)
		 fun chkSizeSpecs esRetX = 
                     let fun allocBuffs  countX = 
			 let val zeroCanonical = 
			     case lookupMemChar baseTy
			     of TyProps.Dynamic => true | _ => false
			 in
                               PL.chkNewRBufS(readName, resRBufferX, zeroCanonical, PT.Id pads)
			     @ PL.chkNewRBufS(readName, pdRBufferX, true, PT.Id pads)
			 end
			 fun checkSizeTy (boundX, which) = 
			      expEqualTy(boundX, CTintTys, fn s=> (which ^" size specification "^
							    "for array " ^ name ^ " has type " ^ s ^
							    ", expected type unsigned int"))
			 fun chkSize(boundX, which) = 
			     let val () = checkSizeTy(boundX, which)
				 val (boundConstOpt, cty, _, _) = evalExpr boundX
				 val isUnsigned = CTisSigned cty
			     in
				 case boundConstOpt of NONE => NONE
                                 | SOME cVal => (
				     if IntInf.<(cVal, IntInf.fromInt 0)
				     then (PE.error("Mininum value for the size of array "^
						    name ^ " (" ^ (IntInf.toString cVal) ^")"^
						    " must be greater than zero"))
                                     else ();
				     SOME (cVal, isUnsigned)
                                 (* end SOME cVal *))
			     end
			 fun genPosMinCheckSs (minConstOpt, minX) = 
			     case minConstOpt of NONE => []
                             | SOME(_, isUnsigned) => 
			       if isUnsigned then []
			       else [PT.IfThen( (* if (minX<0) *)
					     amCheckingBasicE(SOME (P.ltX(minX, P.zero))),
					     BU.recordArrayErrorS([tlocES1], tLocX,
							       PL.P_ARRAY_MIN_NEGATIVE, true,
							       readName,
							       "Minimum value for the size of array "^
							       name ^  "(%d) " ^
							       "is negative", [minX], false, SOME(esRetX)))]

			 fun genPosMaxCheckSs (maxConstOpt, maxX) = 
			     case maxConstOpt of NONE => []
                             | SOME(_,isUnsigned) => 
				 if isUnsigned then []
				 else [PT.IfThen( (* if (maxX<0) *)
					     amCheckingBasicE(SOME(P.ltX(maxX, P.zero))),
					     BU.recordArrayErrorS([tlocES1], tLocX,
							       PL.P_ARRAY_MAX_NEGATIVE, true, readName,
							       "Maximum value for the size of array "^
							       name ^  "(%d) " ^
							       "is negative", [maxX], true, SOME(esRetX)))]

		     in
                     (case sizeSpec 
                      of NONE => (NONE, NONE, NONE, NONE, allocBuffs P.zero)
                      |  SOME (PX.SizeInfo {min, max, maxTight}) => (
                           case (min, max) 
                           of (NONE, NONE) => (NONE, NONE, NONE, NONE, allocBuffs P.zero)
                           |  (SOME minX, SOME maxX) => (
				let val minConstOpt = chkSize(minX, "Minimum")
				    val maxConstOpt = chkSize(maxX, "Maximum")
				    val staticBounds = (Option.isSome minConstOpt) andalso (Option.isSome maxConstOpt)
				    val minMaxCheckSs = 
					   if staticBounds 
                                             then if IntInf.> (#1(valOf minConstOpt), (#1(valOf maxConstOpt))) 
					          then (PE.error("Mininum value for the size of array "^
								name ^ " " ^
								" is greater than its maximum size");
							[])
                                                  else [] (* no static error, no need for dynamic checks*)
					     else ([PT.IfThen( (* if (minX > maxX) *)
						     amCheckingBasicE(SOME(P.gtX(minX, maxX))), 
						      BU.recordArrayErrorS([tlocES1], tLocX,
									PL.P_ARRAY_MIN_BIGGER_THAN_MAX_ERR,
                                                                        true, readName,
									      "Mininum value for "^
									      "the size of array "^
									      name ^ "(%d) " ^
									      "is greater than "^
									      "its maximum size (%d)",
									 [minX, maxX], false,SOME(esRetX))
						      )])

				    val dynBoundsCheckSs =  minMaxCheckSs 
					                  @ genPosMinCheckSs(minConstOpt, minX) 
					                  @ genPosMaxCheckSs(maxConstOpt, maxX)
				    val fixedSize =  (#1(valOf minConstOpt)) = (#1(valOf maxConstOpt))
							 handle Option => false
				    val sizeAllocSs = 
					if fixedSize 
                                        then allocBuffs (P.intX (IntInf.toInt(#1(valOf maxConstOpt))))
					else allocBuffs (P.zero)
					             
				in
				   (SOME minX, SOME maxX, minConstOpt, maxConstOpt,
				      dynBoundsCheckSs @ sizeAllocSs)
				end
                              (* end Some minX, Some maxX*))
                           | (SOME minX, NONE) => (
				let val minConstOpt = chkSize(minX, "Minumum")
				    val posMinCheckSs = genPosMinCheckSs(minConstOpt, minX)
				    val allocSizeX = P.intX (IntInf.toInt(valOf (#1(evalExpr minX))))
						     handle Option => P.zero
				in
				   (SOME minX, NONE, minConstOpt, NONE, posMinCheckSs @ allocBuffs(allocSizeX))
				end
                              (* end SOME minX, NONE *))
                           | (NONE, SOME maxX) => (
                                let val maxConstOpt = chkSize(maxX, "Maximum")
				    val posMaxCheckSs = genPosMaxCheckSs(maxConstOpt, maxX)
				    val allocSizeX = P.intX (IntInf.toInt(valOf (#1(evalExpr maxX))))
						     handle Option => P.zero
				    val (minXOpt, minConstOpt) = if maxTight then (SOME maxX, maxConstOpt)
						                 else (NONE, NONE)
				in
				   (minXOpt, SOME maxX, minConstOpt, maxConstOpt, 
				    posMaxCheckSs @ allocBuffs(allocSizeX))
				end
                              (* end NONE, SOME maxX *))
                           (* end case (min, max) *))
                         (* END size case *))
		     end

                 val (minOpt, maxOpt, minConstOpt, maxConstOpt, chkBoundsSs) = chkSizeSpecs PL.P_ERROR

		 val () = popLocalEnv()  (* remove scope with parameters used for type checking
					  size specifications *)

	         (* Generate CheckSet mask *)
		 val mFields = [(element, P.makeTypedefPCT(BU.lookupTy(baseTy, mSuf, #mname)), SOME "per-element"),
				 (array,   PL.base_mPCT, SOME "entire array")]
		 val mStructED = P.makeTyDefStructEDecl (mFields, mSuf name)
		 val mStructDecls = cnvExternalDecl mStructED 
		 val mPCT = P.makeTypedefPCT (mSuf name)			  

	         (* Generate parse description *)
                 val pdFields = [(pstate, PL.flags_t, NONE), 
				 (nerr, PL.uint32PCT,    SOME "Number of array errors"),
				 (errCode, PL.errCodePCT, NONE),
				 (loc, PL.locPCT, NONE)]
				@ (if isGalax() then [(identifier, PL.idPCT, SOME "Identifier tag for Galax")] else [])
				@ [(neerr, PL.uint32PCT,   SOME "Number of element errors"),
				   (firstError, PL.uint32PCT, 
				    SOME "if errCode == ARRAY_ELEM_ERR, index of first error"),
				   (numRead, PL.uint32PCT, SOME "Number of elements read"),
				   (length, PL.uint32PCT, SOME "Number of elements in memory")] 
				@ [(elts, P.ptrPCT(elemEdPCT), NONE),
				   (internal, P.ptrPCT PL.rbufferPCT, NONE)] 
		 val pdStructED = P.makeTyDefStructEDecl (pdFields, pdSuf name)
		 val (pdStructDecls, pdTid) = cnvCTy pdStructED 
		 val pdPCT = P.makeTypedefPCT (pdSuf name)			  

		 (* Generate accumulator type (array case) *)
                 val numElemsToTrack = case maxConstOpt of NONE => 10
		                       | SOME(x,y) => Int.min(10, IntInf.toInt x)
		 val baseFields = 
		     case lookupAcc baseTy of NONE => [] 
		     | SOME acc => 
			 [(array, P.makeTypedefPCT acc, SOME "Accumulator for all array elements"),
			  (arrayDetail, P.arrayPCT (P.intX numElemsToTrack, P.makeTypedefPCT acc), 
			   SOME ("Accumulator for first "^(Int.toString numElemsToTrack)^" array elements"))]
		 val accFields = (length, PL.uint32AccPCT, SOME "Accumulator for array length")::baseFields
		 val accED = P.makeTyDefStructEDecl (accFields, accSuf name)
		 val accPCT = P.makeTypedefPCT (accSuf name)			

          
                 (* -- process constraints *)
                 fun chkForallConstraintSs (r as {index, range, body}) = 
		     let val subList = [(PNames.arrayLen,   P.fieldX(rep, length)), 
					(name,              P.fieldX(rep, elts)),
					(PNames.arrayElts,  P.fieldX(rep, elts))]
			 val (lower, upper) = 
			     (case range 
			      of PX.ArrayName n => (
				 (if n = name orelse n = elts then ()
				  else PE.error ("Array name in bound expression ("^
						 n^") does not match the name "^
						 "of the array (must use '"^ name ^ "' or 'elts')")
				      ); (P.zero, P.minusX(PT.Id length, P.intX 1)))
			      | PX.Bounds(lower, upper) => (lower, upper))
			 val modBodyX  = PTSub.substExps subList body
			 val modLowerX = PTSub.substExps subList lower
			 val modUpperX = PTSub.substExps subList upper
			 fun errMsg which = (fn s => 
					     (which^" bound for forall expression for array "^
					      name ^" has type "^s^", expected type int"))
		     in
			 pushLocalEnv();
			 ignore(insTempVar(index,             P.int));
			 ignore(insTempVar(length,            PL.uint32PCT));
			 ignore(insTempVar(name,              P.ptrPCT elemRepPCT)); 
			 ignore(insTempVar(elts,              P.ptrPCT elemRepPCT)); 
			 expEqualTy(lower, CTintTys, errMsg "Lower");
			 expEqualTy(lower, CTintTys, errMsg "Upper");
			 expEqualTy(body, CTintTys, fn s=>("Pforall expression for array "^
							   name ^" has type "^s^", expected type int"));
			 popLocalEnv();
			 (false, PX.Forall {index=index, range = PX.Bounds(modLowerX, modUpperX), body=modBodyX})
		     end

                 fun chkGeneralConstraintSs (exp) = 
		     let val subList = [(PNames.arrayLen,   P.fieldX(rep, length)), 
					(name,              P.fieldX(rep, elts)),
					(PNames.arrayElts,  P.fieldX(rep, elts))]
			 val modExpX = PTSub.substExps subList exp
		     in
			 pushLocalEnv();
			 ignore(insTempVar(length,            PL.uint32PCT));
			 ignore(insTempVar(name,              P.ptrPCT elemRepPCT)); 
			 ignore(insTempVar(elts,              P.ptrPCT elemRepPCT)); 
			 expEqualTy(exp, CTintTys, fn s=>("Pwhere constraint for array "^
							 name ^" has type "^s^", expected type int"));
			 popLocalEnv();
                         (false, PX.AGeneral modExpX)
		     end

		 fun chkParseChkConstraintSs (exp) = 
		     let val genVars    = [(PNames.arrayLen,   PL.uint32PCT,        P.fieldX(rep, length)), 
					   (name,              P.ptrPCT elemRepPCT, P.fieldX(rep, elts)),
					   (PNames.arrayElts,  P.ptrPCT elemRepPCT, P.fieldX(rep, elts)),
					   (PNames.pdElts,     P.ptrPCT elemEdPCT,  P.fieldX(pd, elts))]
			 val parseVars  = [(PNames.arrayBegin, PL.posPCT,           tLocBX), 
					   (PNames.arrayEnd,   PL.posPCT,           tLocEX)]
			 val vars = genVars @ parseVars
			 val subList = getBindings (vars)
			 val modExp = PTSub.substExps subList exp
			 val needEndLoc =  PTSub.isFreeInExp([PNames.arrayEnd], exp) 
		     in
			 pushLocalEnv();
			 augTyEnv vars;
			 expEqualTy(exp, CTintTys, fn s=>("Pparsecheck constraint for array "^
							 name ^" has type "^s^", expected type int"));
			 popLocalEnv();
                         (needEndLoc, PX.AParseCheck modExp)
		     end

                 fun chkPostCondClause c = 
		     case c of 
		       PX.Forall r      => chkForallConstraintSs    r
		     | PX.AGeneral exp  => chkGeneralConstraintSs  exp
                     | PX.AParseCheck p => chkParseChkConstraintSs p
			   
		 fun chkWhereClauses cs = 
		     let val r = List.map chkPostCondClause cs
			 val (needEnds, modClauses) = ListPair.unzip r
			 val needEnd = List.exists (fn x => x) needEnds
		     in
			 (needEnd, modClauses)
		     end

                 fun chkPredConstraint (which, constraints : pcexp PX.PPostCond list) = 
		     let val curX = P.minusX(P.fieldX(rep, length), P.intX 1)
			 val genVars = [(PNames.arrayLen,   PL.uint32PCT,        P.fieldX(rep, length)), 
					(name,              P.ptrPCT elemRepPCT, P.fieldX(rep, elts)),
					(PNames.arrayElts,  P.ptrPCT elemRepPCT, P.fieldX(rep, elts)),
					(PNames.arrayCur,   PL.uint32PCT,        curX), 
					(PNames.curElt,     elemRepPCT,          P.subX(P.fieldX(rep, elts), curX))]
			               @ (if which = "Pended"
					  then [(PNames.consume, P.int,              PT.Id consumeFlag)]
				          else [])
			 val parsVars =[(PNames.pdElts,     P.ptrPCT elemEdPCT,  P.fieldX(pd, elts)),
					(PNames.curPd,      elemEdPCT,           P.subX(P.fieldX(pd, elts),  curX)),
					(PNames.numRead,    PL.uint32PCT,        P.fieldX(pd, numRead)), 
					(PNames.arrayBegin, PL.posPCT,           tLocBX), 
					(PNames.elemBegin,  PL.posPCT,           P.dotX(P.fieldX(pd,"loc"), PT.Id "b")), 
					(PNames.elemEnd,    PL.posPCT,           P.dotX(P.fieldX(pd,"loc"), PT.Id "e"))] 
			 val allVars      = genVars @ parsVars
			 val genSubList   = getBindings genVars
                         val parseSubList = getBindings allVars
			 val errMsg = fn s => (which ^" expression for array "^
					       name ^" has type"^s^", expected type int")
			 fun checkConstraint (PX.General exp) = 
                             let val modExpX = PTSub.substExps genSubList exp
			     in
				 pushLocalEnv();
				 augTyEnv genVars;
				 expEqualTy(exp, CTintTys, errMsg);
				 popLocalEnv();
				 (false, modExpX, SOME exp)  (* general expressions don't have location references *)
			     end
                           | checkConstraint (PX.ParseCheck exp) = 
                             let val needEndLoc = PTSub.isFreeInExp([PNames.elemEnd], exp)
				 val modExpX = PTSub.substExps parseSubList exp
			     in
				 pushLocalEnv();
				 augTyEnv allVars;
				 expEqualTy(exp, CTintTys, errMsg);
				 popLocalEnv();
				 (needEndLoc, modExpX, NONE)    (* parse expressions aren't included in is predicates *)
			     end
			 val modConstraints = List.map checkConstraint constraints
                         fun merge ((b,cX,iXs: pcexp option), (ba, cXa, iXa:pcexp option)) = (b orelse ba, P.andX(cX,cXa), 
			       case (iXs, iXa) 
				 of (NONE,NONE)   => NONE
                                  | (SOME cX, NONE) => SOME cX
                                  | (NONE, SOME aX) => SOME aX
				  | (SOME iX, SOME aX) => SOME (P.andX(iX, aX)))
			 val result as (needEndLoc, constraintPredX, isPredX:pcexp option) = 
			     case modConstraints
			     of [] => (false, P.trueX, NONE)
			     |  [x] => x
                             |  (x::xs) => foldr merge x xs
		     in
			 result
		     end

                 (* new scope needed for analysis of array constraints*)
		 val _ = pushLocalEnv()                                        (* create new scope *)
		 val () = ignore (List.map insTempVar cParams)  (* add params for type checking *)
		 fun mergeOpt which (o1, o2) = 
		     case (o1, o2) 
		     of   (NONE, NONE) => NONE
		       |  (NONE, SOME q) => SOME q
		       |  (SOME p, NONE) => SOME p
		       |  (SOME p, SOME q) => (PE.error("Multiple "^which^" clauses"); SOME p)

                 val (sepXOpt, termXOpt, noSepIsTerm, lastXOpt, endedXOpt, skipXOpt,
		      sepTermDynamicCheck, scan2Opt, stdeclSs, stparams, stinitInfo, stcloseSsFun) = 
                      let fun getFuns (which, exp) =
			   let val (okay, expTy) = getExpEqualTy(exp, CTstring :: CTintTys,
								fn s=>(which ^ " expression for array "^
								       name ^" has type "^s^", expected type char or char*"));
			       val reOpt = getRE exp
			       val pExp = unMark exp
			       val () = if isEmptyString pExp 
					then PE.warn (which ^ " expression for array "^ name ^" is the empty string")
					else ()
			       val isString = okay andalso equalType(expTy, CTstring)
			   in
			       if Option.isSome reOpt then
                                    (isEmptyString (unMark(Option.valOf reOpt));
			            (pExp, pExp, NONE, PRegExp, PL.reMatch, PL.reScan1, NONE))
			       else if isString then
			            (pExp, pExp, #1(evalExpr exp), PString, PL.cstrlitMatch, PL.cstrlitScan1, SOME PL.cstrlitWriteBuf)
			       else (pExp, pExp, #1(evalExpr exp), PChar,   PL.charlitMatch, PL.charlitScan1, SOME PL.charlitWriteBuf)
			   end
			       
			  fun doOne (constr:pcexp PX.PConstraint) = 
                              case constr 
                              of PX.Sep   exp => (SOME (getFuns("Separator", exp)), NONE, NONE, NONE, NONE, NONE)
                              |  PX.Term  (PX.Expr exp) =>(NONE, SOME( getFuns("Terminator", exp)), NONE, NONE, NONE, NONE)
                              |  PX.Term  PX.noSep => (NONE, NONE, SOME (), NONE, NONE, NONE)
                              |  PX.Last  exp => (NONE, NONE, NONE, SOME exp, NONE, NONE)
                              |  PX.Ended exp => (NONE, NONE, NONE, NONE, SOME exp, NONE)
                              |  PX.Skip  exp => (NONE, NONE, NONE, NONE, NONE, SOME exp)
			      |  PX.Longest   => (NONE, NONE, NONE, NONE, SOME PL.longestX, NONE)
			  val constrs = List.map doOne constraints
                          fun mergeAll ((a, b, c, d, e, f), (ra, rb, rc, rd, re, rf)) = 
			      (mergeOpt "Psep"  (a, ra), mergeOpt "Pterm" (b, rb), 
			       mergeOpt "Pterm == Pnosep" (c, rc), 
			       mergeOpt "Plast" (d, rd), mergeOpt "Pended" (e, re), mergeOpt "Pskip" (f, rf))
			  val (sepXOpt, termXOpt, termNoSepXOpt, lastXOpt, endedXOpt, skipXOpt ) = 
			           List.foldr mergeAll (NONE, NONE, NONE, NONE, NONE, NONE) constrs

			  val () = case (termXOpt, termNoSepXOpt) of 
			             (SOME _, SOME _) => PE.error ("Multiple Pterm clauses in array "^name)
				   | _ => ()
			  val () = case (sepXOpt, termNoSepXOpt) of
			              (NONE, SOME _) => PE.error ("Array "^name^" must have a separator"^
								  " for Pterm == Pnosep to be valid")
				   | _ => ()
			  val () = case (lastXOpt, endedXOpt) of
			             (SOME _, SOME _) => PE.error ("Array "^name^" cannot have both Plast and Pended clauses")
				   | _ => ()

                          fun compRegExp (which, endLabel, e) = 
			      let val regName = which^"_regexp"
				  val regArgX = P.addrX(PT.Id regName)
			          val ptrName = which^"_regexp_ptr"
				  val ptrArgX = PT.Id ptrName
			      in
			        ([PL.regexpDeclNullS(regName), 
				  PL.regexpPtrDeclS(ptrName, regArgX)],
				 [(P.ptrPCT PL.regexpPCT, ptrName)],
			         [((PL.regexpPCT,regName,SOME(PT.InitList[P.zero]),
				    SOME(P.ptrPCT PL.regexpPCT, ptrName,fn reX => P.addrX reX)),
				   PT.IfThen(P.eqX(PL.P_ERROR, PL.regexpCompileCStrX(PT.Id pads, e, ptrArgX, 
										    PT.String ("Array "^which), PT.String readName)),
					    PT.Compound([P.assignS(P.fieldX(pd, errCode), PL.P_INVALID_REGEXP),
							 P.plusAssignS(P.fieldX(pd, nerr), P.intX 1),
						         PL.setPanicS(PT.Id pd),
						         PT.Goto endLabel] )))],
				 ptrArgX,
				 [PL.regexpCleanupS(PT.Id pads, ptrArgX)])
			      end
			  fun strToRegExp(which, endLabel, e) =
                              compRegExp(which, endLabel, PL.regexpLitFromCStrX(PT.Id pads, e)) 
			  fun charToRegExp(which, endLabel, e) =
                              compRegExp(which, endLabel, PL.regexpLitFromCharX(PT.Id pads, e)) 

                          fun charToString(which, e) = 
			      let val strName = which^"_str"
				  val strArgX = PT.Id strName
			      in
				  ([P.varDeclS'(P.arrayPCT(P.intX 2, P.char), strName)], 
				   [(P.charPtr, strName)], 
				   [((P.charPtr,strName,NONE,NONE),
					PT.Compound [P.assignS(P.subX(PT.Id strName, P.zero), e),
						     P.assignS(P.subX(PT.Id strName, P.intX 1), P.zero)]) ], 
				   strArgX, [])
			      end	  
			      			
			  val (sepXOpt, termXOpt, declSs, params, initSs, closeSsFun, scan2Opt) = 
			      let val endLabel = name^"_end"
				  fun emptyFun _ = []
				  fun makeCloseFun closeSs inclLabel =
				      if inclLabel 
				      then [PT.Labeled(endLabel, PT.Compound closeSs)]
				      else closeSs
			      in
			      case (sepXOpt, termXOpt) of
                                (NONE, NONE) => (NONE, NONE, [], [], [], emptyFun, NONE)
                              | (SOME (e, e2, v, PRegExp, match, scan, write), NONE) => 
				    let val (declSs, params, initSs, expr, closeS) = compRegExp("separator", endLabel, e)
					val wCloseFun = makeCloseFun closeS
				    in
					(SOME(expr, expr, v, PRegExp, match, scan, write), termXOpt, declSs, 
					 params, initSs, wCloseFun, NONE)
				    end
                              | (SOME s, NONE) => (sepXOpt, termXOpt, [], [], [], emptyFun, NONE)
                              | (NONE, SOME(e, e2, v, PRegExp, match, scan, write)) =>
				    let val (declSs, params, initSs, expr, closeS) = compRegExp("terminator", endLabel, e)
					val wCloseFun = makeCloseFun closeS
				    in
					(SOME(expr, expr, v, PRegExp, match, scan, write), termXOpt, declSs, params, 
					 initSs, wCloseFun, NONE)
				    end
                              | (NONE, SOME t) => (sepXOpt, termXOpt, [], [], [], emptyFun, NONE) 
                              | (SOME(es, es2, vs, PChar, matchs, scans, writes), SOME(et, et2, vt, PChar, matcht, scant, writet)) =>
				      (SOME(es, es2, vs, PChar, matchs, scans, writes), 
				       SOME(et, et2, vt, PChar, matcht, scant, writet), [], [], [], emptyFun,
				       SOME PL.charlitScan2)
                              | (SOME(es, es2, vs, PString, matchs, scans, writes), SOME(et, et2, vt, PString, matcht, scant, writet)) =>
				      (SOME(es, es2, vs, PString, matchs, scans, writes), 
				       SOME(et, et2, vt, PString, matcht, scant, writet), [], [], [], emptyFun,
				       SOME PL.cstrlitScan2)
                              | (SOME(es, es2, vs, PRegExp, matchs, scans, writes), SOME(et, et2, vt, PRegExp, matcht, scant, writet)) =>
				    let val (declSss, paramss, initSss, exprs, closeSs) = compRegExp("separator", endLabel, es)
					val (declSst, paramst, initSst, exprt, closeSt) = compRegExp("terminator", endLabel, et)
					val wCloseFun = makeCloseFun (closeSs @ closeSt)
				    in
					(SOME(exprs, exprs, vs, PRegExp, matchs, scans, writes), 
					 SOME(exprt, exprt, vt, PRegExp, matcht, scant, writet), 
					 declSss @ declSst, paramss @ paramst, initSss @ initSst, wCloseFun, SOME PL.reScan2)
				    end
                              | (SOME(es, es2, vs, PRegExp, matchs, scans, writes), SOME(et, et2, vt, PString, matcht, scant, writet)) =>
				    let val (declSss, paramss, initSss, exprs, closeSs) = compRegExp("separator", endLabel, es)
					val (declSst, paramst, initSst, exprt, closeSt) = strToRegExp("terminator", endLabel, et)
					val wCloseFun = makeCloseFun (closeSs @ closeSt)
				    in
					(SOME(exprs, exprs, vs, PRegExp, matchs, scans, writes), 
					 SOME(et, exprt, vt, PString, matcht, scant, writet), 
					 declSss @ declSst, paramss @ paramst, initSss @ initSst, wCloseFun, SOME PL.reScan2)
				    end
                              | (SOME(es, es2, vs, PString, matchs, scans, writes), SOME(et, et2, vt, PRegExp, matcht, scant, writet)) =>
				    let val (declSss, paramss, initSss, exprs, closeSs) = strToRegExp("separator", endLabel, es)
					val (declSst, paramst, initSst, exprt, closeSt) = compRegExp("terminator", endLabel, et)
					val wCloseFun = makeCloseFun (closeSs @ closeSt)
				    in
					(SOME(es, exprs, vs, PRegExp, matchs, scans, writes), 
					 SOME(exprt, exprt, vt, PString, matcht, scant, writet), 
					 declSss @ declSst, paramss @ paramst, initSss @ initSst, wCloseFun, SOME PL.reScan2)
				    end
                              | (SOME(es, es2, vs, PRegExp, matchs, scans, writes), SOME(et, et2, vt, PChar, matcht, scant, writet)) =>
				    let val (declSss, paramss, initSss, exprs, closeSs) = compRegExp("separator", endLabel, es)
					val (declSst, paramst, initSst, exprt, closeSt) = charToRegExp("terminator", endLabel, et)
					val wCloseFun = makeCloseFun (closeSs @ closeSt)
				    in
					(SOME(exprs, exprs, vs, PRegExp, matchs, scans, writes), 
					 SOME(et, exprt, vt, PChar, matcht, scant, writet), 
					 declSss @ declSst, paramss @ paramst, initSss @ initSst, wCloseFun, SOME PL.reScan2)
				    end
                              | (SOME(es, es2, vs, PChar, matchs, scans, writes), SOME(et, et2, vt, PRegExp, matcht, scant, writet)) =>
				    let val (declSss, paramss, initSss, exprs, closeSs) = charToRegExp("separator", endLabel, es)
					val (declSst, paramst, initSst, exprt, closeSt) = compRegExp("terminator", endLabel, et)
					val wCloseFun = makeCloseFun (closeSs @ closeSt)
				    in
					(SOME(es, exprs, vs, PChar, matchs, scans, writes), 
					 SOME(exprt, exprt, vt, PRegExp, matcht, scant, writet), 
					 declSss @ declSst, paramss @ paramst, initSss @ initSst, wCloseFun, SOME PL.reScan2)
				    end
                              | (SOME(es, es2, vs, PString, matchs, scans, writes), SOME(et, et2, vt, PChar, matcht, scant, writet)) =>
				    let val (declSst, paramst, initSst, exprt, closeSt) = charToString("terminator", et)
				    in
				      (SOME(es, es2, vs, PString, matchs, scans, writes), 
				       SOME(et, exprt, vt, PChar, matcht, scant, writet), declSst, paramst, initSst, fn _ => closeSt,
				       SOME PL.cstrlitScan2)
				    end
                              | (SOME(es, es2, vs, PChar, matchs, scans, writes), SOME(et, et2, vt, PString, matcht, scant, writet)) =>
				    let val (declSss, paramss, initSss, exprs, closeSs) = charToString("separator", es)
				    in
				      (SOME(es, exprs, vs, PChar, matchs, scans, writes), 
				       SOME(et, et2, vt, PString, matcht, scant, writet), declSss, paramss, initSss, fn _ => closeSs,
				       SOME PL.cstrlitScan2)
				    end
			      end

			  val sepTermDynamicCheck = 
			      let val sepTermEqErrorMsg  = "Pterm and Psep expressions for Parray "^ name^
							   " have the same value"
				  val sepTermPreErrorMsg = "Pterm expressions for Parray "^ name^
							   " is a prefix of Psep expression"
				  fun intInftoStringRep i = Char.toString(Char.chr(IntInf.toInt i))
 			      in
			      case (sepXOpt, termXOpt) 
			      of (SOME(sepX, _, SOME i, _, _, _, _), SOME(termX, _, SOME j, _, _, _, _)) => 
				  if i = j then (PE.error (sepTermEqErrorMsg); []) else []
			      | (SOME(sepX, _, _, sepTyp, _, _, _), SOME(termX, _, _, termTyp, _, _, _)) => 
				      (case (sepX, termX) of
				          (PT.String s, PT.String t) => (if String.isPrefix t s 
									 then (PE.error (sepTermPreErrorMsg)) else (); [])
                                        | (PT.IntConst s, PT.IntConst t) => (if s = t
									     then (PE.error (sepTermEqErrorMsg)) else ();[])
                                        | (PT.String s, PT.IntConst t) => (if String.isPrefix (intInftoStringRep t) s
									   then (PE.error (sepTermPreErrorMsg)) else (); 
									       print ("Terminator: "^(IntInf.toString t));[])
                                        | (PT.IntConst s, PT.String t) => (if (intInftoStringRep s) = t 
									   then (PE.error (sepTermEqErrorMsg)) else ();[])
					| _ => (
					    let fun strCharCmp(sX, cX) = P.condX(P.eqX(PL.strLen(sX), P.intX 1),
										P.eqX(P.subX(sX, P.zero), cX), P.falseX)
						fun mkTest testX = 				      
						    [PT.IfThen(testX,
							       PL.userErrorS(PT.Id pads, locX, 
									     PL.P_ARRAY_SEP_TERM_SAME_ERR, readName, 
									     PT.String (sepTermEqErrorMsg^": %c"), [sepX]))]
						val testSs = 
                                                      case (sepTyp, termTyp) of
					                (PChar, PChar) => mkTest (P.eqX(sepX, termX))
                                                      | (PString, PString) => mkTest(P.eqX(P.zero, PL.strCmp(sepX, termX)))
                                                      | (PChar, PString) => mkTest(strCharCmp(termX, sepX))
						      | (PString, PChar) => mkTest(strCharCmp(sepX,  termX))
                                                      | _ => []
					    in
						testSs
					    end)) 
			      |  (_, _) => []
			      end
		      in
			  (sepXOpt, termXOpt, isSome termNoSepXOpt, lastXOpt, endedXOpt, skipXOpt,
			   sepTermDynamicCheck, scan2Opt, declSs, params, initSs, closeSsFun)
                      end
		 val _ = popLocalEnv()

	         (* Calculate and insert type properties into type table *)
                 val baseMemChar = lookupMemChar baseTy
		 val arrayMemChar = TyProps.Dynamic (* at the moment, all arrays are dynamically allocated. *)
                 val baseDiskSize = computeDiskSize(name, paramNames, baseTy, args)
                 val arrayRep = case sizeSpec 
		                     of NONE => TyProps.Variable  (* unbounded array *)
				     |  SOME (PX.SizeInfo{min, max, maxTight}) => 
					  if not maxTight then TyProps.Variable  (* lower and upper bounds differ *)
					  else (case (maxConstOpt, minConstOpt)
					        of (SOME (min,_), SOME( max,_)) =>  (* constant size given: maxTight => min = max *)
						     TyProps.Size(max, IntInf.fromInt 0)
					        | _ => TyProps.Param(paramNames, NONE, valOf max, P.zero)(* case max *))
                 fun getSize Xopt = case Xopt of NONE => TyProps.mkSize(0,0) | SOME (e, _, _, typ, _, _, _) => getLitSize(typ, e)
		 val sepSize  = getSize sepXOpt
		 val termSize  = getSize termXOpt
		 val arrayDiskSize = TyProps.add(coreArraySize(baseDiskSize, sepSize, arrayRep), termSize)
		 val contR = lookupContainsRecord baseTy 
		 val lH = contR orelse (lookupHeuristic baseTy)
                 val numArgs = List.length params
		 val PX.Name baseTyName = baseTy
		 val compoundArrayDiskSize = TyProps.Array {baseTy=baseTyName, args=(paramNames, args),
							    elem=baseDiskSize, sep = sepSize,
							    term=termSize, length = arrayRep}
                 val arrayProps = buildTyProps(name, PTys.Array, arrayDiskSize, compoundArrayDiskSize,
					       arrayMemChar, false, isRecord, contR, lH, isSource, pdTid, numArgs)
                 val () = PTys.insert(Atom.atom name, arrayProps)

		 (* array: Generate canonical representation *)
		 val canonicalFields = [(length, PL.uint32PCT, NONE), 
				        (elts, P.ptrPCT elemRepPCT, NONE),
					(internal, P.ptrPCT PL.rbufferPCT, NONE) ]
		 val canonicalStructED = P.makeTyDefStructEDecl (canonicalFields, repSuf name)
		 val (canonicalDecls, canonicalTid) = cnvRep(canonicalStructED, valOf (PTys.find (Atom.atom name)))
		 val canonicalPCT = P.makeTypedefPCT (repSuf name)			 

		 val _ = pushLocalEnv()
		 val () = ignore(List.map insTempVar cParams)
		 val (needArrayEndExp, postCond) = chkWhereClauses postCond
		 val skipXOpt  = case skipXOpt  of NONE => NONE | SOME r => SOME (chkPredConstraint  ("Pskip",  r))
                 val lastXOpt  = case lastXOpt  of NONE => NONE | SOME r => SOME (chkPredConstraint  ("Plast",  r))
                 val endedXOpt = case endedXOpt of NONE => NONE | SOME r => SOME (chkPredConstraint  ("Pended",  r))
		 val _ = popLocalEnv()

		 (* Generate init function, array case *)
		 fun genInitEDs(suf, base, aPCT) = 
		   case #memChar arrayProps
		   of TyProps.Static => [genInitFun(suf name, base, aPCT, [PT.Return PL.P_OK], true)]
		   |  TyProps.Dynamic => 
			 let val bodySs =  [PL.bzeroS(PT.Id base, P.sizeofX(aPCT)),PT.Return PL.P_OK]
			 in
			     [genInitFun(suf name, base, aPCT, bodySs, false)]
			 end
		 val initRepEDs = genInitEDs(initSuf, rep, canonicalPCT)
		 val initPDEDs = genInitEDs(initSuf o pdSuf, pd, pdPCT)


		 (* Generate cleanup function, array case *)
		 fun genCleanupEDs(suf, base, aPCT) = 
		     let val cleanupFunName = suf name
			 val cleanupEltFun = PT.Id(suf(lookupMemFun(baseTy)))
			 val arrayStat = (if arrayMemChar = TyProps.Static then "_AR_STAT" else "_AR_DYN")
			 val eltStat = (if baseMemChar = TyProps.Static then "_ELT_STAT" else "_ELT_DYN")
			 val xArgs = (if baseMemChar = TyProps.Static then [] else [cleanupEltFun])
			 val bodySs = [PT.Compound[P.varDeclS(PL.uint32PCT, nerrPCGEN, P.zero),
						   PT.Expr(PT.Call(PT.Id("PCGEN_ARRAY_CLEANUP"^arrayStat^eltStat),
								   [PT.String(cleanupFunName), PT.Id base] @ xArgs)),
						   BU.genReturnChk(PT.Id nerrPCGEN)]]
		     in 
			 [genInitFun(cleanupFunName, base, aPCT, bodySs, false)]
		     end
		 val cleanupRepEDs = genCleanupEDs(cleanupSuf, rep, canonicalPCT)
		 val cleanupPDEDs = genCleanupEDs(cleanupSuf o pdSuf, pd, pdPCT)

		 (* Generate copy function, array case *)
		 fun genCopyEDs(suf, csuf, base, aPCT, elemPCT) =
		     let val copyFunName = suf name
			 val copyEltFun = PT.Id(suf(lookupMemFun(baseTy)))
			 val cleanupEltFun = PT.Id(csuf(lookupMemFun(baseTy)))
			 val arrayStat = (if arrayMemChar = TyProps.Static then "_AR_STAT" else "_AR_DYN")
			 val eltStat = (if baseMemChar = TyProps.Static then "_ELT_STAT" else "_ELT_DYN")
			 val dst = dstSuf base
			 val src = srcSuf base
			 val xArgs = (if baseMemChar = TyProps.Static then [] else [copyEltFun, cleanupEltFun])
			 val bodySs = [PT.Compound[P.varDeclS(PL.uint32PCT, nerrPCGEN, P.zero),
						   PT.Expr(PT.Call(PT.Id("PCGEN_ARRAY_COPY"^arrayStat^eltStat),
								   [PT.String(copyFunName), PT.Id(src), PT.Id(dst)] @ xArgs)),
						   BU.genReturnChk(PT.Id nerrPCGEN)]]
		     in
			 [genCopyFun(copyFunName, dst, src, aPCT, bodySs, false)]
		     end

		 val copyRepEDs = genCopyEDs(copySuf o repSuf, cleanupSuf o repSuf, rep, canonicalPCT, elemRepPCT)
		 val copyPDEDs = genCopyEDs(copySuf o pdSuf, cleanupSuf o pdSuf, pd, pdPCT, elemEdPCT)

                 (* Generate m_init function array case *)
                 val maskInitName = maskInitSuf name 
                 val maskFunEDs = genMaskInitFun(maskInitName, mPCT)

		 (* Array: Generate read function *)
		 val _ = pushLocalEnv()                                        (* create new scope *)
		 val () = ignore (List.map insTempVar cParams)  (* add params for type checking *)

                 (* -- Some useful names *)
                 val readName = readName (* defined above *)
                 val foundTerm    = "foundTerm"
		 val lastSet      = "lastSet"
		 val endedSet     = "endedSet"
		 val omitresult   = "Pomitresult"
		 val reachedLimit = "reachedLimit"

		 val resBufferX   = P.fieldX(rep, elts)
		 val indexX       = P.minusX(P.fieldX(rep, length), P.intX 1)
		 val resNext      = P.subX(resBufferX, indexX)

		 val edBufferX    = P.fieldX(pd, elts)
 		 val edNext       = P.subX(edBufferX, indexX)

		 val eltPd        = PN.elt_pd
		 val eltRep       = PN.elt_rep
		 val notFirstElt  = "notFirstElt"				    

                 (* -- Check parameters to base type read function *)
		 val () = checkParamTys(name, elemReadName, args, 4, 0)
                 (* -- Declare top-level variables and initialize them *)
                 val initDecSs =   stdeclSs
			      @ [P.varDeclS'(PL.locPCT, tloc),
				 P.varDeclS(P.ptrPCT PL.locPCT, locPtr, P.addrX(PT.Id tloc)),
				 P.varDeclS'(P.int, result)] 
                              @ (if Option.isSome termXOpt then             (* int foundTerm = false *)
                                   [P.varDeclS(P.int, foundTerm, P.falseX)] 
                                 else [])
                              @ (if Option.isSome lastXOpt then             (* int lastSet = false *)
                                   [P.varDeclS(P.int, lastSet, P.falseX)] 
                                 else [])
                              @ (if Option.isSome endedXOpt then             (* int endedSet = false *)
                                   [P.varDeclS(P.int, endedSet, P.falseX),
				    P.varDeclS(P.int, consumeFlag,  P.falseX)]   (* default is to return last read element *)
                                 else [])
                              @ (if Option.isSome skipXOpt then               
				   [P.varDeclS(P.int, omitresult, P.falseX)]
				 else [])
                              @ (if Option.isSome maxOpt then               (* int reachedLimit = false *)
				   [P.varDeclS(P.int, reachedLimit, P.falseX)]
			        else [])
		 val (stRPInfo,stinitSs) = ListPair.unzip stinitInfo
                 val initAssignSs = [ P.assignS(P.fieldX(rep, length), P.zero),
				  P.assignS(P.fieldX(pd, neerr), P.zero),
				  P.assignS(P.fieldX(pd, firstError), P.zero),
				  P.assignS(P.fieldX(pd, numRead), P.zero)]		              
				@ stinitSs
		 val initGetLocSs = [ PL.getLocBeginS(PT.Id pads, P.starX(tLocX))]

		 val initSs = initDecSs @ initAssignSs @ initGetLocSs 

                 (* -- fragments for while loop for reading input *)

                 (* -- code for checking if terminator is next in input *)

                 (* -- Code for checking termination conditions *)
                 fun genBreakCheckX (termOpt, sizeOpt, lastOpt, endedOpt) = 
		     let val isEofX = PL.isEofX(PT.Id pads)
			 val isEorX = PL.isEorX(PT.Id pads)
			 val termFoundX = PT.Id foundTerm
			 val lastSetX = PT.Id lastSet
			 val endedSetX = PT.Id endedSet
			 val limitReachedX = PT.Id reachedLimit
		     in
                        case (termOpt, sizeOpt, lastOpt, endedOpt, isRecord)
			of (NONE,   NONE,  NONE,  NONE,   _)     => P.orX(isEofX, isEorX)
                        |  (NONE,   NONE,  NONE,  SOME _, _)     => P.orX(P.orX(isEofX, isEorX), endedSetX)
                        |  (NONE,   NONE,  SOME _, NONE,   _)     => P.orX(P.orX(isEofX, isEorX), lastSetX)
                        |  (NONE,   NONE,  SOME _, SOME _, _)     => P.orX(P.orX(P.orX(isEofX, isEorX), lastSetX), endedSetX)
                        |  (NONE,   SOME _, NONE,  NONE,   false) => P.orX(isEofX, limitReachedX)
                        |  (NONE,   SOME _, NONE,  SOME _, false) => P.orX(P.orX(isEofX, limitReachedX), endedSetX)
                        |  (NONE,   SOME _, SOME _, NONE,   false) => P.orX(P.orX(isEofX, limitReachedX), lastSetX)
                        |  (NONE,   SOME _, SOME _, SOME _, false) => P.orX(P.orX(P.orX(isEofX, limitReachedX), lastSetX), endedSetX)
                        |  (NONE,   SOME _, NONE,  NONE,   true)  => P.orX(isEofX, P.orX(isEorX, limitReachedX))
                        |  (NONE,   SOME _, NONE,  SOME _, true)  => P.orX(P.orX(isEofX, P.orX(isEorX, limitReachedX)), endedSetX)
                        |  (NONE,   SOME _, SOME _, NONE,   true)  => P.orX(P.orX(isEofX, P.orX(isEorX, limitReachedX)), lastSetX)
                        |  (NONE,   SOME _, SOME _, SOME _, true)  => P.orX(P.orX(P.orX(isEofX, 
								    P.orX(isEorX, limitReachedX)), lastSetX), endedSetX)
                        |  (SOME _, NONE,  NONE,  NONE,   false) => P.orX(isEofX, termFoundX)
                        |  (SOME _, NONE,  NONE,  SOME _, false) => P.orX(P.orX(isEofX, termFoundX), endedSetX)
                        |  (SOME _, NONE,  SOME _, NONE,   false) => P.orX(P.orX(isEofX, termFoundX), lastSetX)
                        |  (SOME _, NONE,  SOME _, SOME _, false) => P.orX(P.orX(P.orX(isEofX, termFoundX), lastSetX), endedSetX)
                        |  (SOME _, NONE,  NONE,  NONE,   true)  => P.orX(isEofX, P.orX(isEorX, termFoundX))
                        |  (SOME _, NONE,  NONE,  SOME _, true)  => P.orX(P.orX(isEofX, P.orX(isEorX, termFoundX)), endedSetX)
                        |  (SOME _, NONE,  SOME _, NONE,   true)  => P.orX(P.orX(isEofX, P.orX(isEorX, termFoundX)), lastSetX)
                        |  (SOME _, NONE,  SOME _, SOME _, true)  => P.orX(P.orX(P.orX(isEofX, 
								    P.orX(isEorX, termFoundX)), lastSetX), endedSetX)
                        |  (SOME _, SOME _, NONE,  NONE,   false) => P.orX(isEofX, 
						                    P.orX(termFoundX, limitReachedX))
                        |  (SOME _, SOME _, NONE,  SOME _, false) => P.orX(P.orX(isEofX, 
								    P.orX(termFoundX, limitReachedX)), endedSetX)
                        |  (SOME _, SOME _, SOME _, NONE,   false) => P.orX(P.orX(isEofX, 
							            P.orX(termFoundX, limitReachedX)), lastSetX)
                        |  (SOME _, SOME _, SOME _, SOME _, false) => P.orX(P.orX(P.orX(isEofX, 
							            P.orX(termFoundX, limitReachedX)), lastSetX), endedSetX)
                        |  (SOME _, SOME _, NONE,  NONE,   true)  => P.orX(isEofX, P.orX(isEorX,
							            P.orX(termFoundX, limitReachedX)))
                        |  (SOME _, SOME _, NONE,  SOME _, true)  => P.orX(P.orX(isEofX, P.orX(isEorX,
							            P.orX(termFoundX, limitReachedX))), endedSetX)
                        |  (SOME _, SOME _, SOME _, NONE,   true)  => P.orX(P.orX(isEofX, P.orX(isEorX,
						                    P.orX(termFoundX, limitReachedX))), lastSetX)
                        |  (SOME _, SOME _, SOME _, SOME _, true)  => P.orX(P.orX(P.orX(isEofX, P.orX(isEorX,
						                    P.orX(termFoundX, limitReachedX))), lastSetX), endedSetX)
		     end

                 fun genBreakCheckSs (term, size, last, ended, breakSs) = 
		     [P.mkCommentS("Have we finished reading array?"),
		      PT.IfThen(genBreakCheckX(term, size, last, ended), PT.Compound breakSs)]
		     
                 (* -- Check that we found separator on last loop.
		       Parameter esRetX is the return code passed to
		       recordArrayErrorS. 
		  *)
                 fun genSepCheck' useChkPts (NONE, breakSs, esRetX) = []
                   | genSepCheck' useChkPts (SOME (sepX, scan2SepX, cSepX, typ, matchSep, scan1Sep, writeSep), breakSs, esRetX) = 
		      case (termXOpt, noSepIsTerm) of 
                        (NONE, true) => 
                        [P.mkCommentS("Checking for separator"),
			 PT.IfThen(P.eqX(PL.P_ERROR, PL.matchFunX(matchSep, PT.Id pads, sepX, P.trueX (* eatlit *))),
				   PT.Compound(
				       P.mkCommentS("No separator, therefore array is finished")::
				       breakSs))]
                      | (NONE, false) => 
                        [P.mkCommentS("Array not finished; reading separator"),
			 PT.Compound([
			  P.varDeclS'(PL.sizePCT, "offset")]
			  @ (if (Option.isSome endedXOpt) andalso useChkPts then PL.chkPtS'(PT.Id pads, readName) else [])
			  @ [locBS,
		          PT.IfThenElse(
			    P.eqX(PL.P_OK,
				  PL.scan1FunX(scan1Sep, PT.Id pads, sepX,
					       P.trueX, (* eatlit *) P.falseX, (* panic *) P.addrX (PT.Id "offset"))),
                            PT.Compound[
			     PT.IfThen(amCheckingBasicE NONE, 
			      PT.Compound[(* if am checking *)
			        PT.IfThen(PT.Id "offset",
				    BU.recordArrayErrorS([locES2], locX, PL.P_ARRAY_EXTRA_BEFORE_SEP, true, 
						      readName,"", [], false, 
						      case endedXOpt of SOME(_) => NONE
								      | NONE => SOME(esRetX)))])],
                            PT.Compound([ (* else error in reading separator *)
			     P.mkCommentS("Error reading separator")]
			     @(if (Option.isSome endedXOpt)  andalso useChkPts then (PL.commitS(PT.Id pads, readName)) else [])
			     @(BU.recordArrayErrorS([locES1], locX, PL.P_ARRAY_SEP_ERR, true, readName, 
						 "Missing separator", [], true, SOME(esRetX)) ::
			        breakSs)))])]
		      | (SOME(termX, scan2TermX, _, _, _, _, _), _) => 
                       [P.mkCommentS("Array not finished; read separator with recovery to terminator"),
                         PT.Compound([
			 P.varDeclS'(P.int, "f_found"),
			 P.varDeclS'(PL.sizePCT, "offset")]
		      @ (if (Option.isSome endedXOpt)  andalso useChkPts then PL.chkPtS'(PT.Id pads, readName) else [])
		      @ [locBS,
		         PT.IfThenElse(
			    P.eqX(PL.P_OK,
				  PL.scan2FunX(valOf scan2Opt, PT.Id pads, 
					       scan2SepX, scan2TermX, P.trueX, P.falseX,
					       P.falseX, (* panic=0 *)
					       P.addrX (PT.Id "f_found"),
					       P.addrX (PT.Id "offset"))),
			    PT.Compound[
			      PT.IfThen(P.notX(PT.Id "f_found"),
					PT.Compound([P.assignS(PT.Id foundTerm, P.trueX)]
						    @ (if Option.isSome endedXOpt  andalso useChkPts  
							   then (PL.chkPtS'(PT.Id pads, readName)) else []))),
								  
                              PT.IfThen(amCheckingBasicE NONE, 
	  		       PT.Compound[ (* if am checking *)
			         PT.IfThenElse(P.andX(PT.Id "f_found", PT.Id "offset"),
				    BU.recordArrayErrorS([locES2], locX, PL.P_ARRAY_EXTRA_BEFORE_SEP, true, readName,"", [], 
						      false,case endedXOpt of SOME(_) => NONE
									    | NONE => SOME(esRetX)),
                                    PT.Compound [PT.IfThen(P.notX(PT.Id "f_found"),
					                   PT.Compound(BU.recordArrayErrorS([locES1], locX,
											 PL.P_ARRAY_EXTRA_BEFORE_TERM, true,
											 readName,"", [], false,SOME(esRetX)) ::
								       breakSs))] )])],
			    PT.Compound( (* else error in reading separator *)
			      [P.mkCommentS("Error reading separator")]
			      @ (if Option.isSome endedXOpt andalso useChkPts 
				     then (PL.chkPtS'(PT.Id pads, readName)) else [])
			      @ (BU.recordArrayErrorS([locES1], locX, PL.P_ARRAY_SEP_ERR, 
						    true, readName, "Missing separator", [], true,SOME(esRetX)) ::
			         breakSs)
			      ))])]

		 val genSepCheck = genSepCheck' true

                 (* -- read next element *)
		 val (chkLenSs, bufSugX) = case maxOpt of NONE => ([], P.zero)
	             | SOME sizeX => 
		        ([P.assignS(PT.Id reachedLimit, P.gteX(P.fieldX(rep, length), Option.valOf maxOpt))],
			 sizeX)

		 val sourceAdvanceCheckSs = 
		     let fun getBloc offset = P.dotX(P.subX(edBufferX, offset), PT.Id "loc")
			 fun getBpos offset = P.dotX(getBloc offset, PT.Id "b") 
			 val prevOffsetX = P.minusX(P.fieldX(rep,length), P.intX 1)
			 val curOffsetX = P.fieldX(rep,length)
		     in
			 [PL.alwaysGetLocBeginS(PT.Id pads, getBloc curOffsetX),
			  PT.IfThen(P.gtX(P.fieldX(rep,length), P.intX 1),
			  PT.Compound
			    [PT.IfThen(PL.PosEq(getBpos prevOffsetX, getBpos curOffsetX),
				       PT.Compound
				         [P.mkCommentS "array termination from lack of progress",
					  P.minusAssignS(P.fieldX(rep,length), P.intX 2),
					  PT.Break])])]
		     end

                 val readElementSs = 
                       [P.postIncS(P.fieldX(rep, length))]
                     @ chkLenSs
		     @ (PL.chkReserveSs(PT.Id pads,  readName, resRBufferX, 
				     P.addrX resBufferX, P.sizeofX elemRepPCT,
				     P.fieldX(rep, length), bufSugX))
		     @ (PL.chkReserveSs(PT.Id pads, readName, pdRBufferX, 
				     P.addrX edBufferX, P.sizeofX elemEdPCT,
				     P.fieldX(rep, length), bufSugX))
		     @ sourceAdvanceCheckSs
		     (* checkpoint here if have ended predicate in play 
                        and this is the first read. *)
		     @ (if Option.isSome endedXOpt  
			then [PT.IfThen(P.eqX(P.fieldX(pd,numRead),P.zero),
				       PT.Compound (PL.chkPtS'(PT.Id pads, readName)))]
			else [])
                      @ [P.assignS(PT.Id result, PL.readFunX(elemReadName, PT.Id pads, P.addrX(P.fieldX(m, element)),
							    args, P.addrX(edNext), P.addrX(resNext))),
			 PT.Expr(P.postIncX (P.fieldX(pd, numRead)))]

		 val markErrorSs = 
		     let val baseX = P.eqX(PT.Id result, PL.P_ERROR) 
			 val etestX = case endedXOpt of 
			               NONE   => baseX
				     | SOME _ => P.andX(baseX, P.notX(PT.Id endedSet))
			 val testX = case skipXOpt of
			               NONE => etestX
				     | SOME _ => P.andX(etestX, P.notX(PT.Id omitresult))
		     in
			 [PT.IfThen(testX,
			   PT.Compound[P.mkCommentS "in markErrorSs", 
				 PT.IfThen(PL.mTestNotIgnoreX(P.fieldX(m, array)),
			         PT.Compound[
				    P.postIncS(P.fieldX(pd, neerr)),
                                    PT.IfThen(P.notX(P.fieldX(pd, nerr)),
                                       PT.Compound (
	 			           (BU.reportErrorSs([locES1], locX, true, PL.P_ARRAY_ELEM_ERR, false, readName, "", []))
                                         @ [P.mkCommentS("Index of first element with an error"),
				            P.assignS(P.fieldX(pd, firstError), P.minusX(P.fieldX(rep, length), P.intX 1))])),
                                            PL.endSpec pads PL.P_ERROR])])]
		     end

                 (* -- panic recovery code *)
		 fun genPanicRecoveryS (sepXOpt, termXOpt, maxOpt, breakSs) = 
                     let val panicSs = PL.setPanicS(PT.Id pd) :: breakSs
                         val recoveryFailedSs = P.mkCommentS("Recovery failed") :: panicSs
			 val noRecoverySs = P.mkCommentS("No recovery possible") :: panicSs
			 fun scan1ToRecoverSs(which, scan, forX, eatForX) = [
			          P.varDeclS'(PL.sizePCT, "offset"),
				  P.mkCommentS("Try to recover to " ^ which),
				  PT.IfThenElse(P.eqX(PL.P_OK,
						   PL.scan1FunX(scan, PT.Id pads, forX, eatForX,
							        P.trueX, (* panic=1 *) P.addrX (PT.Id "offset"))),
                                    PT.Compound[
				     P.mkCommentS("We recovered; restored invariant")],
				    PT.Compound(recoveryFailedSs)
                                 )]
			 fun scan2ToRecoverSs (which, forX, stopX, eatForX, eatStopX) = [
			          P.varDeclS'(P.int, "f_found"),
			          P.varDeclS'(PL.sizePCT, "offset"),
				  P.mkCommentS("Try to recover to " ^ which),
				  PT.IfThenElse(P.eqX(PL.P_OK,
						   PL.scan2FunX(valOf scan2Opt, PT.Id pads, 
							        forX, stopX, eatForX, eatStopX,
							        P.trueX, (* panic=1 *)
							        P.addrX (PT.Id "f_found"),
					                        P.addrX (PT.Id "offset"))),
                                    PT.Compound[
				     P.mkCommentS("We recovered; restored invariant")],
				    PT.Compound(recoveryFailedSs)
                                 )] 
			 val recoverSs = 
			 case (sepXOpt, termXOpt, maxOpt) 
                         of (NONE,                               NONE,  _) => noRecoverySs
                         |  (SOME (sepX, _, _, _, _, sepScan1, _), NONE, NONE) => 
			        scan1ToRecoverSs("separator", sepScan1, sepX, P.trueX)
                         |  (SOME (sepX, _, _, _, _, sepScan1, _), NONE, SOME _) => 
			       [PT.IfThenElse(PT.Id reachedLimit,
				 PT.Compound(noRecoverySs), 
				 PT.Compound(scan1ToRecoverSs ("separator", sepScan1, sepX, P.trueX)))]
                         |  (NONE, SOME(termX, _, _, _, _, termScan1, _), _ ) => 
				scan1ToRecoverSs ("terminator", termScan1, termX, P.trueX)
                         |  (SOME (_, scan2SepX, _, _, _, _,  _), SOME(_, scan2TermX, _, _, _, _, _), _ ) =>
 			        scan2ToRecoverSs("separator and/or terminator", scan2SepX, scan2TermX, P.trueX, P.falseX)
		     in
			 PT.Compound recoverSs
		     end

		 (*P.addrX(edNext)*)
                 fun genPanicRecoverySs (pdPtrX, endedXOpt, skipXOpt, breakSs) = 
		     let val predX = case endedXOpt of NONE => PL.testPanicX(pdPtrX)
			             | _ => P.andX(P.notX (PT.Id endedSet), PL.testPanicX(pdPtrX))
			 val predX = case skipXOpt of NONE => predX
			             | _ => P.andX(predX, P.notX (PT.Id omitresult))
		     in
			 [PT.IfThen(predX, PT.Compound[genPanicRecoveryS(sepXOpt, termXOpt, maxOpt,breakSs)])]
		     end

                 (* -- while loop for reading input *)
		 (* executes body (when once is given) on failure to find terminator. *)
		 fun readTerm (termRead, termX, bdyOpt) = 
		     let val rhsX = PL.matchFunX(termRead, PT.Id pads, termX, P.falseX(*do not eat lit"*))
			 val bodyS = case bdyOpt of NONE => 
			                  PT.IfThen(P.eqX(PL.P_OK, rhsX),
						    PT.Compound[P.assignS(PT.Id foundTerm, P.trueX)])
		                     | SOME bdyS => 
			                  PT.IfThenElse(P.eqX(PL.P_OK, rhsX),
							PT.Compound[P.assignS(PT.Id foundTerm, P.trueX)],
							PT.Compound[bdyS])
		     in
			 PT.Compound [bodyS]
		     end
		 (* executes doneS on succesful match of terminator *)
		 fun readTerm' (termRead, termX, doneS) = 
		     let val rhsX = PL.matchFunX(termRead, PT.Id pads, termX, P.falseX(*do not eat lit"*))
		     in
			 PT.IfThen(P.eqX(PL.P_OK, rhsX),
				   PT.Compound[P.assignS(PT.Id foundTerm, P.trueX),
					       doneS])
		     end

                 fun genTermCheck NONE = []
                   | genTermCheck (SOME (exp, compExp, cExp, typ, readFun, scan1Fun, writeFun)) = 
                      [P.mkCommentS("Looking for terminator"), 
		       readTerm (readFun, exp, NONE)]

                 fun genLastCheck (NONE,_) = []
                   | genLastCheck (SOME (_, exp, _), skipXOpt) = 
                      let val predX = case skipXOpt of NONE => exp   
				      | _ => P.andX(P.notX (PT.Id omitresult), exp)
		      in
			[P.mkCommentS("Checking Plast predicate"),
		         PT.IfThen(predX, PT.Compound[P.assignS(PT.Id lastSet, P.trueX)])]
		      end

                 fun genEndedLocCalcSs (l, e) =
                     let fun f(NONE) = [] 
                           | f(SOME(true, _, _)) = [locES0]
			   | f(SOME(false, _, _)) = []
			 val last = f l
			 val ended = case last of nil => f e | _ => last
		     in
			 ended
		     end

                 fun genEndedCheck exp = 
                      [P.mkCommentS("Checking Pended predicate"),
                       PT.Compound[
			  P.varDeclS(P.int, "Ppredresult", exp),
		          PT.IfThenElse(P.notX (PT.Id "Ppredresult"),
			     PT.Compound(PL.commitS(PT.Id pads, readName)),
			     PT.Compound([P.assignS(PT.Id endedSet, P.trueX), 
					  PT.IfThenElse(PT.Id consumeFlag,
					     PT.Compound(PL.commitS(PT.Id pads, readName)),
			                     PT.Compound(PL.restoreS(PT.Id pads, readName)
							 @ [P.postDecS(P.fieldX(rep, length)),
							    P.postDecS(P.fieldX(pd, numRead))]))]))
		      ]]

                 fun genEndedSkipCheck (NONE, NONE) = []
                   | genEndedSkipCheck (SOME (_,exp,_), NONE) = genEndedCheck exp
                   | genEndedSkipCheck (NONE, SOME (_,omitX,_)) = 
		        [P.mkCommentS "Checking Pomit predicate",
                         P.assignS(PT.Id omitresult, omitX),
			 PT.IfThen(PT.Id omitresult,
				   PT.Compound([P.postDecS(P.fieldX(rep, length))]))]
                   | genEndedSkipCheck (SOME (_,ended,_), SOME (_,omitX,_)) = 
		        [P.mkCommentS("Checking Pomit predicate"),
                         P.assignS(PT.Id omitresult, omitX),
			 PT.IfThenElse(PT.Id omitresult,
				       PT.Compound(
					      PL.commitS(PT.Id pads, readName)
					    @ [P.postDecS(P.fieldX(rep, length))]),
				       PT.Compound (genEndedCheck ended))]

                 fun genRREndedCheck exp = 
                      [P.mkCommentS("Checking Pended predicate"),
                       PT.Compound[
			  P.varDeclS'(P.int, consumeFlag),
			  P.varDeclS(P.int, "Ppredresult", exp),
		          PT.IfThen(P.andX(PT.Id "Ppredresult",P.notX (PT.Id consumeFlag)),
				    P.returnS(PL.P_READ_OK_NO_DATA))]]

                 fun genRREndedSkipCheck (NONE, NONE) = []
                   | genRREndedSkipCheck (SOME (_,exp,_), NONE) = genRREndedCheck exp
                   | genRREndedSkipCheck (NONE, SOME (_,omitX,_)) = 
		        [P.mkCommentS "Checking Pomit predicate",
                         P.assignS(PT.Id omitresult, omitX),
			 PT.IfThen(PT.Id omitresult,
				   P.returnS(PL.P_READ_OK_NO_DATA))]
                   | genRREndedSkipCheck (SOME (_,ended,_), SOME (_,omitX,_)) = 
		        [P.mkCommentS("Checking Pomit predicate"),
                         P.assignS(PT.Id omitresult, omitX),
			 PT.IfThen(PT.Id omitresult,
				       P.returnS(PL.P_READ_OK_NO_DATA)),
			 PT.Compound (genRREndedCheck ended)]

                 val whileSs = 
		     let fun insLengthChk bdyS = 
			    case (maxOpt, maxConstOpt) 
                            of (SOME maxX, NONE) => (
				PT.IfThenElse(
                                 P.gteX(P.fieldX(rep, length), maxX),
				 PT.Compound[P.assignS(PT.Id reachedLimit, P.trueX)],
                                 PT.Compound[bdyS])
			      (* end case *))
			    | (_, _) => bdyS

			 fun insTermChk bdyS =
			     case termXOpt of 
				 NONE => PT.Compound[bdyS]
		               | SOME (termX, _, _, _, termRead, _, _) => (readTerm (termRead, termX, SOME bdyS))

			 val breakSs = [PT.Break]

			 val bdyS = 
			     PT.Compound[
			      locBS,
			      PT.While(P.trueX,  
                                 PT.Compound(
				   [P.mkCommentS("Ready to read next element")]
				   @ readElementSs 
                                   @ (genEndedLocCalcSs (lastXOpt, endedXOpt))
                                   @ (genEndedSkipCheck (endedXOpt, skipXOpt))
				   @ markErrorSs
				   @ (genPanicRecoverySs (P.addrX(edNext),endedXOpt,skipXOpt,breakSs))
                                   @ (genLastCheck  (lastXOpt, skipXOpt))
                                   @ (genTermCheck  termXOpt)
				   @ genBreakCheckSs (termXOpt, maxOpt, lastXOpt, endedXOpt,breakSs)
                                   @ (genSepCheck (sepXOpt,breakSs,PL.P_ERROR))
				   ))]
			 val termCondX = if isRecord then 
			                   P.andX(P.notX(PL.isEofX(PT.Id pads)),
						  P.notX(PL.isEorX(PT.Id pads)))
					 else
			                   P.notX(PL.isEofX(PT.Id pads))
			 val lengthChkBdyS = insLengthChk bdyS
			 val termChkBdyS = insTermChk lengthChkBdyS
			 val allChkS = PT.IfThen(P.andX(PL.testNotPanicX(PT.Id pd), termCondX), termChkBdyS)

		     in 
			 [P.mkCommentS("Read input until we reach a termination condition"),
                          allChkS]
		     end

                 (* -- Check if there was junk before trailing terminator *)
	         val trailingJunkChkSs = 
		     let val esRetX = PL.P_ERROR				      
		     in case termXOpt of 
			 NONE => []
		         | SOME (termX, _, _, _, _, termScan1, _) => 
			 [P.mkCommentS("End of loop. Read trailing terminator if there was trailing junk"),
			  PT.IfThen(P.andX(PL.testNotPanicX(PT.Id pd), P.notX(PT.Id foundTerm)),
			   PT.Compound[
			   P.varDeclS'(PL.sizePCT, "offset"),
			   locBS,
		           PT.IfThenElse(
			     P.eqX(PL.P_OK,
				  PL.scan1FunX(termScan1, PT.Id pads, 
					       termX, P.falseX,
					       P.falseX, (* panic=0 *)
					       P.addrX (PT.Id "offset"))),
                             PT.Compound[
			      PT.IfThen(amCheckingBasicE NONE, 
			        PT.Compound[
				 BU.recordArrayErrorS([locES1], locX, PL.P_ARRAY_EXTRA_BEFORE_TERM,
						   true, readName,"", [], false,SOME(esRetX)),
				 P.assignS(PT.Id foundTerm, P.trueX)])],
			     BU.recordArrayErrorS([locES1], locX, PL.P_ARRAY_TERM_ERR, true, readName,
					       "Missing terminator", [], true,SOME(esRetX)))
			 ])]
		     end

		 fun readEORSs esRetX = if isRecord then genReadEOR (readName, reportStructErrorSs, esRetX) () else []
                 (* -- Set data fields in canonical rep and ed from growable buffers *)
                 val setDataFieldsSs = 
                     [
		      P.assignS(P.fieldX(pd, length), P.fieldX(rep, length))
                     ]

                 (* -- Check array-level constraints *)
                 (* -- -- Check that the user's forall array constraint is satisfied. *)
                 fun genLoop {index:string, range, body:PT.expression}  = 
		     let val (lower, upper) = case range of PX.Bounds(lower, upper) => (lower, upper)
			                      | _ => (PE.bug "unexpected array name"; (P.zero, P.zero)  (* not possible *))
			 val supper = pcgenName "supper"
			 val slength = pcgenName "slength"
		     in
			 [PT.Compound
			 [P.varDeclS'(P.int, index),
			  P.varDeclS(PL.ssizePCT, supper, PT.Cast(PL.ssizePCT, upper)),
			  P.varDeclS(PL.ssizePCT, slength, PT.Cast(PL.ssizePCT, P.fieldX(rep, length))),
			  PT.IfThen(P.notX(P.andX(P.lteX(P.zero, lower),
						  P.ltX(PT.Id supper, PT.Id slength))),
				    PT.Compound[P.assignS(PT.Id violated, P.trueX)]),
			  PT.For(P.assignX(PT.Id index, lower),
				 P.andX(P.notX(PT.Id violated), 
					P.andX(P.gteX(PT.Id supper, P.zero),
					       P.lteX(PT.Id index, upper))), 
				 P.postIncX(PT.Id index),
				 PT.Compound[
                                   PT.IfThen(P.notX(body),
				             PT.Compound[P.assignS(PT.Id violated, P.trueX)] (* end if *))
					     ] (* end for *))]]
		     end
		           
                 fun genArrayConstraintsSs esRetX = 
		     let 
			 (* -- -- Check that we read at least min elements, if min specified *)
			 fun genMinReachedConstraintSs minX =  
			     let val lengthTestX = P.ltX(P.fieldX(rep, length), minX)
				 val testX = if Option.isSome maxOpt 
					     then P.andX(P.notX(PT.Id reachedLimit), lengthTestX)
					     else lengthTestX
			     in
			      [P.mkCommentS("Checking that we read enough elements"),
			       PT.IfThen(testX,
				  BU.recordArrayErrorS([tlocES1], tLocX, PL.P_ARRAY_SIZE_ERR, true, readName,
				    ("Read %d element(s) for array "^name^"; required %d"),
				    [P.fieldX(rep, length), minX], false,SOME(esRetX)))]
			     end

			 fun genForallConstraintSs forall  = 
				[P.mkCommentS "Checking Pforall constraint",
				 PT.Compound(
				  [P.varDeclS(P.int, "violated", P.falseX)]
				  @ genLoop forall
				  @ [PT.IfThen(PT.Id "violated",
					       BU.recordArrayErrorS([tlocES1], tLocX, PL.P_ARRAY_USER_CONSTRAINT_ERR, 
								 true, readName,("Pforall constraint for array "^name^" violated"), 
								 [], false,SOME(esRetX)))])]


			 (* -- -- Check that the user's general array constraint is satisfied. *)
			 fun genGeneralConstraintSs exp = 
				[PT.Compound(
				   [P.mkCommentS "Checking PWhere constraint"]
				   @ [PT.IfThen(P.notX exp,
					   BU.recordArrayErrorS([tlocES1], tLocX, PL.P_ARRAY_USER_CONSTRAINT_ERR, true, readName,
							     ("Pwhere constraint for array "^name^" violated"), [], false,SOME(esRetX)))])]

			 (* -- -- Check that the user's parse check predicate is satisfied *)
			 fun genParseCheckConstraintSs exp = 
				[PT.Compound(
				   [P.mkCommentS "Checking Pparsecheck constraint"]
				   @ (if needArrayEndExp then [tlocES0] else [])
				   @ [PT.IfThen(P.notX exp,
					   BU.recordArrayErrorS([tlocES1], tLocX, PL.P_ARRAY_USER_CONSTRAINT_ERR, true, readName,
							     ("Pparsecheck constraint for array "^name^" violated"), 
							     [], false,SOME(esRetX)))])]
			 fun genWhereClause c = 
			     case c of
			       PX.Forall r      => genForallConstraintSs     r
			     | PX.AGeneral exp  => genGeneralConstraintSs    exp
			     | PX.AParseCheck p => genParseCheckConstraintSs p


			 val semanticConstraintSs = List.concat (List.map genWhereClause postCond)

			 fun condWrapBase bdySs = 
			 [P.mkCommentS "Checking basic array constraints",
			  PT.IfThen(amCheckingBasicE(SOME(PL.testNotPanicX(PT.Id pd))),
				    PT.Compound bdySs)]
                         fun condWrapUser bdySs = 
			 [P.mkCommentS "Checking user-defined array constraints",
			  PT.IfThen(amCheckingUserE(SOME(PL.testNotPanicX(PT.Id pd))),
				    PT.Compound bdySs)]
                         fun condWrapBoth (bdySs1, bdySs2) = 
			 [PT.IfThen(PL.testNotPanicX(PT.Id pd),
				PT.Compound[P.mkCommentS "Checking basic array constraints",
				            PT.IfThen(amCheckingBasicE NONE, PT.Compound bdySs1),
				            P.mkCommentS "Checking user-defined array constraints",
				            PT.IfThen(amCheckingUserE NONE, PT.Compound bdySs2)])]
		     in
		       case (minOpt, semanticConstraintSs) of 
                         (NONE,      []) => []
                       | (SOME minX, []) => condWrapBase(genMinReachedConstraintSs minX)
                       | (NONE,      ss) => condWrapUser ss
                       | (SOME minX, ss) =>
			   condWrapBoth(genMinReachedConstraintSs minX, ss)
		     end

                 (* -- return value *)
                 val returnS = P.returnS (
				      P.condX(P.eqX(P.arrowX(PT.Id pd, PT.Id nerr), P.zero),
				      PL.P_OK, PL.P_ERROR))
	         (* -- Assemble read function array case *)
		 val bodySs =   [PT.Compound (
				  initSs 
                                @ sepTermDynamicCheck
                                @ chkBoundsSs
                                @ whileSs
				@ trailingJunkChkSs
				@ (readEORSs PL.P_ERROR)
				@ setDataFieldsSs
				@ (genArrayConstraintsSs PL.P_ERROR)
				@ (stcloseSsFun true)
                                @ [returnS])]
                 val readFunEDs = genReadFun(readName ^ "_old", cParams, mPCT, pdPCT, canonicalPCT, 
					     NONE, true, bodySs)
				  

		 (************* read_one functions *****************)


		 (* 
		 val roArgsFields = [(tloc,PL.locPCT, NONE),
				        (elts, P.ptrPCT elemRepPCT, NONE),
					(internal, P.ptrPCT PL.rbufferPCT, NONE) ]
		 val roArgsStructED = P.makeTyDefStructEDecl (canonicalFields, roArgsSuf name)
		 val (canonicalDecls, canonicalTid) = cnvRep(canonicalStructED, valOf (PTys.find (Atom.atom name)))
		 val roArgsPCT = P.makeTypedefPCT (repSuf name)			 
		  *)

				  
		 (* Macros used in read-one generated code *)

		 val macroDoFinalChecks = PT.Expr (PT.Call(PT.Id "PCGEN_ARRAY_DO_FINAL_CHECKS",[]))

		 fun chkAlreadyDone () =  PT.Expr (PT.Call(PT.Id "PCGEN_ARRAY_TEST_ALREADY_DONE",[]))

		 val macroReadOneDecs = PT.Expr (PT.Call(PT.Id "PCGEN_ARRAY_RO_DECS",[]))
					   
		 val macroGetBeginLoc = PT.Expr (PT.Call(PT.Id "PCGEN_ARRAY_GET_BEGIN_LOC",[]))

		 fun macroReserveSpaceX name elemName elemPdName bufSugX = 
		     PT.Call(PT.Id "PCGEN_ARRAY_RESERVE_SPACE",[PT.Id name, PT.Id elemName, 
								PT.Id elemPdName, bufSugX])

		 fun macroCheckpoint(name) = PT.Expr (PT.Call(PT.Id "PCGEN_ARRAY_CHECKPOINT",[PT.Id name]))

		 fun macroReadElem(readCall) = PT.Expr (PT.Call(PT.Id "PCGEN_ARRAY_READ_ELEM",[readCall]))
		 fun macroReadElemHD(readCall) = PT.Expr (PT.Call(PT.Id "PCGEN_ARRAY_READ_ELEM_HD",[readCall, PT.Id haveData]))

		 fun macroReReadElemX(readCall) = PT.Call(PT.Id "PCGEN_ARRAY_REREAD_ELEM",[readCall])
		 fun macroReReadElemBody(readCall) = PT.Expr (PT.Call(PT.Id "PCGEN_ARRAY_REREAD_ELEM_BODY",[readCall]))
		 val macroReReadElemRet = PT.Call(PT.Id "PCGEN_ARRAY_REREAD_ELEM_RET",[])

		 fun macroTestReadErr(eTestX,oTestX) = PT.Expr(PT.Call(PT.Id "PCGEN_ARRAY_TEST_READ_ERR",[eTestX,oTestX]))

		 val macroSourceAdvanceCheck  = PT.Expr (PT.Call (PT.Id "PCGEN_ARRAY_TEST_FC_SOURCE_ADVANCE2",[]))

		 fun macroRetOngoing keepX = PT.Call(PT.Id "PCGEN_ARRAY_RET_ONGOING",[keepX])

		 val macroLblFinalChecks = PT.Expr (PT.Call(PT.Id "PCGEN_ARRAY_LBL_FINAL_CHECKS",[]))
		 val macroRetFinalChecks = PT.Call(PT.Id "PCGEN_ARRAY_RET_FINAL_CHECKS",[])

		 fun macroTestTrailingJunk(name,termX,termScan1,termType) = 
		     PT.Expr(PT.Call(PT.Id ("PCGEN_ARRAY_TEST_TRAILING_JUNK_" ^ termType),
				     [PT.Id name,PT.Id termScan1,termX]))
		 val macroSetPartial = PT.Expr (PT.Call(PT.Id "PCGEN_ARRAY_SET_PARTIAL",[]))
		 val macroUnsetPartial = PT.Expr (PT.Call(PT.Id "PCGEN_ARRAY_UNSET_PARTIAL",[]))

		 fun macroRetDone keepX = PT.Call(PT.Id "PCGEN_ARRAY_RET_DONE",[keepX])

		 fun macroReadAll allocCall readCall incX = 
		     PT.Expr (PT.Call(PT.Id "PCGEN_ARRAY_READ_ALL",[allocCall, readCall, incX, PT.String roDriverName]))

		 val macroStdReturn = PT.Call(PT.Id "PCGEN_ARRAY_STD_RETURN",[])

                 val roReadElementSs = if Option.isSome endedXOpt
				       then [macroReadElem(PL.readFunX(elemReadName, PT.Id pads, P.addrX(P.fieldX(m, element)),
								       args, PT.Id eltPd, PT.Id eltRep))]
				       else [macroReadElemHD(PL.readFunX(elemReadName, PT.Id pads, P.addrX(P.fieldX(m, element)),
								       args, PT.Id eltPd, PT.Id eltRep))]
		      
                 val rroReadElementSs = 
		     [macroReReadElemBody(PL.readFunX(elemReadName, PT.Id pads, P.addrX(P.fieldX(m, element)),
						  args, PT.Id eltPd, PT.Id eltRep)),
		      P.returnS(macroReReadElemRet)]

		      
		 (* Generate extra read params structure  *)
		 fun genRPStructED(name,cParams,stRPInfo) =
		     let fun mungeInfo (ty,f,_,NONE) = [(f,ty,NONE)] (* swap order of type and field name *)
			   | mungeInfo (ty,f,_,SOME(pty,pf,_)) = [(f,ty,NONE),(pf,pty,SOME("pointer to " ^ f))]

			 val rpFields = [(beginLoc, PL.locPCT,SOME("location of array beginning"))]
					@ List.concat (List.map mungeInfo stRPInfo) 
					@ List.map (fn (f,ty) => (f,ty,NONE)) cParams
		     in
			 P.makeTyDefStructEDecl (rpFields, roParamsSuf name)
		     end

		 fun genRPInitFun(name,cParams,stRPInfo) =
		   let val ropTy = P.ptrPCT (P.makeTypedefPCT (roParamsSuf name))
		       val returnTy = P.void
		       val cnvName = PN.roParamsInitSuf name
		       val allParams = [P.mkParam (ropTy,paramsVar)]
		       val formalParams =  allParams
					   @ List.map (fn (s,ty) => P.mkParam (ty,s)) cParams

		       (* params->p = p *)
		       fun initp p = P.assignS(P.fieldX(paramsVar,p),PT.Id p)

		       (* params->p = expression *)
		       fun mungeST (_,p,NONE,_) = nil
			 | mungeST (ty,p,SOME(X),NONE) = [(P.varDeclS(ty,p,X),[initp p])]
			 | mungeST (ty,p,SOME(X),SOME(pty,pp,pfun)) = 
			   [(P.varDeclS(ty,p,X),[initp p, 
						 P.assignS(P.fieldX(paramsVar,pp),
							   P.addrX(P.fieldX(paramsVar,p))
							   )])]

		       val (decls,initSTParamsSs) = ListPair.unzip
						(List.concat (List.map mungeST stRPInfo))

		       fun initcp (p,_) = initp p
		       val initCParamsSs = List.map initcp cParams
					   
		       val bodySs = decls @ (List.concat initSTParamsSs) @ initCParamsSs
		   in   
		       [P.mkFunctionEDecl(cnvName, formalParams, PT.Compound bodySs, returnTy)]
		   end

		 fun genROInitFun (initName, cParams:(string * pcty)list, 
				   mPCT, pdPCT, canonicalPCT,
				   bodySs) = 
		     let val (cNames, cTys) = ListPair.unzip cParams
			 val paramTys = [P.ptrPCT PL.toolStatePCT, P.ptrPCT mPCT,P.ptrPCT pdPCT, P.ptrPCT canonicalPCT, P.ptrPCT PL.locPCT]
			 val paramNames = [pads, m,pd, rep, locPtr]

			 val formalParams = List.map P.mkParam 
						     ((ListPair.zip (paramTys, paramNames)) @ 
						      stparams @ 
						      (ListPair.zip (cTys, cNames )))
			 val innerInits = ([PT.Expr(PT.Call(PT.Id "PD_COMMON_INIT_NO_ERR", [PT.Id pd])),
					    PT.Expr(PT.Call(PT.Id "PD_COMMON_READ_INIT", [PT.Id pads,PT.Id pd]))])

			 val returnTy =  PL.readResPCT

			 val checkParamsSs = [PL.IODiscChecks3P(PT.String initName, PT.Id m, PT.Id pd, PT.Id rep)]
			 val innerBody = checkParamsSs 
					 @ innerInits @ bodySs
			 val readFunED = 
			     P.mkFunctionEDecl(initName, formalParams, PT.Compound innerBody, returnTy)
		     in
			 [readFunED]
		     end
			 
		 fun genReadOneFun (readName, cParams:(string * pcty)list, 
				    mPCT, pdPCT, canonicalPCT, elemPdPCT, elemCanonicalPCT,
				    bodySs) = 
		     let val (cNames, cTys) = ListPair.unzip cParams
			 val paramTys = [P.ptrPCT PL.toolStatePCT, P.ptrPCT mPCT,
					 P.ptrPCT pdPCT, P.ptrPCT canonicalPCT, P.ptrPCT PL.locPCT,
					 P.ptrPCT elemPdPCT, P.ptrPCT elemCanonicalPCT]

			 val paramNames = [pads, m, pd, rep, locPtr, elt_pd, elt_rep]

			 val formalParams = List.map P.mkParam ( (ListPair.zip (paramTys, paramNames)) @
								stparams @ 
								(ListPair.zip (cTys, cNames)))

			 val returnTy =  PL.readResPCT
			 val checkParamsSs = [PL.IODiscChecks3P(PT.String readName, PT.Id m, PT.Id pd, PT.Id rep),
					      PL.IODiscChecks2P(PT.String readName, PT.Id elt_pd, PT.Id elt_rep)]
			 val innerBody = checkParamsSs @ bodySs
			 val readFunED = 
			     P.mkFunctionEDecl(readName, formalParams, PT.Compound innerBody, returnTy)
		     in
			 [readFunED]
		     end

		 fun genReReadOneFun (rereadName, cParams:(string * pcty)list, 
				    mPCT, pdPCT, canonicalPCT, elemPdPCT, elemCanonicalPCT,
				    bodySs) = 
		     let val (cNames, cTys) = ListPair.unzip cParams
			 val paramTys = [P.ptrPCT PL.toolStatePCT, P.ptrPCT mPCT, 
					 P.ptrPCT pdPCT, P.ptrPCT canonicalPCT, P.ptrPCT PL.locPCT,
					 P.ptrPCT elemPdPCT, P.ptrPCT elemCanonicalPCT, P.int]
					@ cTys

			 val paramNames = [pads, m, pd, rep, locPtr, 
					   elt_pd, elt_rep, notFirstElt]
					  @ cNames 


			 val formalParams = List.map P.mkParam (stparams @ (ListPair.zip (paramTys, paramNames)))
			 val returnTy =  PL.readResPCT
			 val checkParamsSs = [PL.IODiscChecks3P(PT.String rereadName, PT.Id m, PT.Id pd, PT.Id rep),
					      PL.IODiscChecks2P(PT.String rereadName, PT.Id elt_pd, PT.Id elt_rep)]
			 val innerBody = checkParamsSs @ bodySs
			 val rereadFunED = 
			     P.mkFunctionEDecl(rereadName, formalParams, PT.Compound innerBody, returnTy)
		     in
			 [rereadFunED]
		     end

		 fun genFinalChecksFun (fcName, cParams:(string * pcty)list, 
					mPCT, pdPCT, canonicalPCT,
					bodySs) = 
		     let val (cNames, cTys) = ListPair.unzip cParams
			 val paramTys   = [P.ptrPCT PL.toolStatePCT, P.ptrPCT mPCT, P.ptrPCT pdPCT, P.ptrPCT canonicalPCT, P.ptrPCT PL.locPCT]
			 val paramNames = [pads,                     m,             pd,             rep,                   locPtr]
					   					   
			 val paramsTerm = if Option.isSome termXOpt 
					  then [(P.int,foundTerm)]
					  else []
					       
			 val paramsMax = if Option.isSome maxOpt 
					 then [(P.int, reachedLimit)]
					 else []
					      
			 val formalParams = List.map P.mkParam 
						     ((ListPair.zip (paramTys,paramNames))
						      @ stparams
						      @ paramsTerm 
						      @ paramsMax
						      @ [(P.int, consumeFlag)]
						      @ (ListPair.zip(cTys, cNames)))
			 val returnTy =  PL.readResPCT
			 val checkParamsSs = [PL.IODiscChecks3P(PT.String fcName, PT.Id m, PT.Id pd, PT.Id rep)]
			 val innerBody = G.makeInvisibleDecls([name],nil) @ checkParamsSs 
					 @ bodySs
			 val readFunED = 
			     P.mkFunctionEDecl(fcName, formalParams, PT.Compound innerBody, returnTy)
		     in
			 [readFunED]
		     end

		 fun callROInit(cParams) =
		     let val (cNames, _) = ListPair.unzip cParams
			 val (_,stNames) = ListPair.unzip stparams
				 
			 val paramNames = [pads, m] 
					@ [pd, rep, locPtr]
					@ stNames
					@ cNames

		     in
			 PT.Call(PT.Id roInitName, List.map PT.Id paramNames)
		     end
			 
		 fun callReadOne(cParams,eltPdX,eltRepX) =
		     let val (cNames, _) = ListPair.unzip cParams
			 val (_,stNames) = ListPair.unzip stparams
				 
			 val params = (List.map PT.Id 
						([pads, m, pd, rep, locPtr]))
				      @ [eltPdX,eltRepX]
				      @ (List.map PT.Id stNames)
			              @ (List.map PT.Id cNames)
		     in
			 PT.Call(PT.Id readOneName,  params)
		     end
			 
		 fun callFinalChecks(cParams, consumeX) =
		     let val (cNames, _) = ListPair.unzip cParams
			 val (_,stNames) = ListPair.unzip stparams
				 
			 val paramNames  = [pads, m,pd, rep, locPtr]
					   @ stNames
					   @ (if Option.isSome termXOpt
					      then [foundTerm]
					      else [])
					   @ (if Option.isSome maxOpt 
					      then [reachedLimit]
					      else [])		
			 val params1 = List.map PT.Id paramNames
			 val params2 = (List.map PT.Id cNames)
			 val params = params1 @ [consumeX] @ params2
	     in
			 PT.Call(PT.Id fcName, params)
		     end
			 
				       
                 (* -- return value *)
		 val markErrorSs' = 
		     let val macroNotEnded = P.notX(PT.Id endedSet)
			 val macroNoOmit   = P.notX(PT.Id omitresult)
			 val eTestX = case endedXOpt of 
			               NONE   => P.trueX
				     | SOME _ => macroNotEnded
			 val oTestX = case skipXOpt of
			               NONE => P.trueX
				     | SOME _ => macroNoOmit
		     in
			 [macroTestReadErr(eTestX,oTestX)]
		     end

                 (* -- Check if there was junk before trailing terminator *)
		 fun trailingJunkChkSs'(name) = 
		     case termXOpt of
			 NONE => []
		       | SOME (termX, _, _, PChar, _, termScan1, _) => 
			 [macroTestTrailingJunk(name,termX,termScan1,"C")]
		       | SOME (termX, _, _, _, _, termScan1, _) => 
			 [macroTestTrailingJunk(name,termX,termScan1,"P")]

		 (* Assemble read_one driver function *)
		 fun roDriverBodySs(name) =
		     let val elemName = BU.lookupTy(baseTy, repSuf, #repname)
			 val elemPdName  = BU.lookupTy(baseTy, pdSuf, #pdname)

			 val initDecSs =   
			     stdeclSs
			     @ [P.varDeclS'(PL.locPCT, tloc),
				P.varDeclS(P.ptrPCT PL.locPCT, locPtr, 
					   P.addrX(PT.Id tloc)),
				P.varDeclS(P.int, "i", P.zero),
				P.varDeclS'(P.int, result)] 
			     @ G.makeInvisibleDecls([name, elemName, elemPdName],[])

			 val indexX  = PT.Id "i"

			 val pdsX    = P.fieldX(pd, elts)
 			 val pdNext  = P.subX(pdsX, indexX)

			 val repsX   = P.fieldX(rep, elts)
			 (* incremement loop variable here *)
			 val repNext = P.subX(repsX, indexX)

			 val advanceX = P.assignX(indexX, P.fieldX(rep,length))

			 val bodySs = [PT.Expr (callROInit (cParams)),
				      macroReadAll (macroReserveSpaceX name elemName elemPdName bufSugX)
						   (callReadOne(cParams,P.addrX pdNext,P.addrX repNext))
						   (advanceX),
				      P.returnS(macroStdReturn)]
		     in
			 [PT.Compound(initDecSs @ bodySs)]
		     end
		     
		 (* Assemble read_one_init function *)
		 val roInitBodySs = 
		     let fun genPanicEndChkS doneS =
			     let val endCondX = 
				     if isRecord then 
					 P.orX(PL.isEofX(PT.Id pads),
						PL.isEorX(PT.Id pads))
				     else
			                 PL.isEofX(PT.Id pads)
			     in
				 PT.IfThen(P.orX(PL.testPanicX(PT.Id pd), endCondX), 
					   doneS)
			     end

			 fun genTermChkSs doneS =
			     case termXOpt of 
				 NONE => []
		               | SOME (termX, _, _, _, termRead, _, _) => 
				 [readTerm' (termRead, termX, doneS)]

			 fun genLengthChkSs doneS = 
			    case (maxOpt, maxConstOpt) 
                            of (SOME maxX, NONE) => (
				[PT.IfThen(
                                 P.gteX(P.fieldX(rep, length), maxX),
				 PT.Compound[P.assignS(PT.Id reachedLimit, P.trueX),
					     doneS])]
			      (* end case *))
			    | (_, _) => []

			 val doneS = macroDoFinalChecks

			 val decls = 
			     (if Option.isSome termXOpt then             (* int foundTerm = false *)
				  [P.varDeclS(P.int, foundTerm, P.falseX)] 
                              else [])
			     @ (if Option.isSome maxOpt then               (* int reachedLimit = false *)
				    [P.varDeclS(P.int, reachedLimit, P.falseX)]
			        else [])

			 val stEndSs = 
			     let val s = stcloseSsFun true 
			     in
				 if List.null s
				 then []
				 else (s @ [macroUnsetPartial] @ [P.returnS(PL.P_READ_ERR)])
			     end

			 val bdySs =
			       initAssignSs 
			     @ initGetLocSs
			     @ sepTermDynamicCheck
			     @ chkBoundsSs
			     @ [genPanicEndChkS doneS]
			     @ genTermChkSs doneS
			     @ genLengthChkSs doneS
			     @ [locBS,macroSetPartial]
			       (* There has been no read, so keepElt param of macro is false*)
			     @ [P.returnS (macroRetOngoing (P.falseX))]
			     @ [macroLblFinalChecks,
				P.returnS 
			       (* There has been no read, so consumeX param is false*)
				(callFinalChecks(cParams,P.falseX))]
			     @ stEndSs
		     in
			 [PT.Compound(decls @ bdySs)]
		     end

	         (* -- Assemble read_one function *)
                 val readOneBodySs = 
		     let val breakSs = [macroDoFinalChecks]
				
			 val initDecSs = 
			     (if Option.isSome termXOpt then             (* int foundTerm = false *)
                                    [P.varDeclS(P.int, foundTerm, P.falseX)] 
                                else [])
                             @ (if Option.isSome lastXOpt then             (* int lastSet = false *)
                                    [P.varDeclS(P.int, lastSet, P.falseX)] 
                                else [])
                             @ (if Option.isSome endedXOpt then             (* int endedSet = false *)
                                    [P.varDeclS(P.int, endedSet, P.falseX),
				     P.varDeclS(P.int, consumeFlag,  P.falseX)]   (* default is to return last element *)
                                else [P.varDeclS(P.int, haveData,  P.falseX)])  (* default is no data read, 
										 until changed in read macro. *)
                             @ (if Option.isSome skipXOpt then               
				    [P.varDeclS(P.int, omitresult, P.falseX)]
				else [])
                             @ (if Option.isSome maxOpt then               (* int reachedLimit = false *)
				    [P.varDeclS(P.int, reachedLimit, P.falseX)]
			        else [])
					   

			 fun insNotFirstChk bodySs =
			     [PT.IfThen(P.gtX(P.fieldX(pd, numRead),P.zero),
					PT.Compound bodySs)]

			 val bdyS = 
			       initDecSs
			     @ [macroReadOneDecs,
				chkAlreadyDone(),
			        macroGetBeginLoc,
				P.mkCommentS("Ready to read next element")]
			     @ (if Option.isSome endedXOpt  (* checkpoint if have ended predicate in play *)
				then [PT.Compound (G.makeInvisibleDecls([name],nil) @ [macroCheckpoint(name)])] 
				else [])
			     @ insNotFirstChk (genSepCheck' false (sepXOpt, breakSs,PL.P_READ_ERR))
			     @ roReadElementSs 
			     @ (genEndedLocCalcSs (lastXOpt, endedXOpt))
			     @ (genEndedSkipCheck (endedXOpt, skipXOpt))
			     @ markErrorSs'
			     @ (genPanicRecoverySs (PT.Id elt_pd, endedXOpt,skipXOpt, breakSs))
			     @ (genLastCheck  (lastXOpt, skipXOpt))
			     @ (genTermCheck  termXOpt)
			     @ chkLenSs
			     @ genBreakCheckSs (termXOpt, maxOpt, lastXOpt, endedXOpt, breakSs)
			     @ [macroSourceAdvanceCheck]
		             @ [P.returnS (macroRetOngoing (if Option.isSome skipXOpt 
							    then P.notX (PT.Id omitresult)
							    else P.trueX))]
			     @ [macroLblFinalChecks,
				P.returnS 
				    (callFinalChecks(cParams,
						     if Option.isSome endedXOpt 
						     then PT.Id consumeFlag
						     else PT.Id haveData))]
		     in
			 [PT.Compound(bdyS)]
		     end

	         (* -- Assemble reread_one function *)
                 val rereadOneBodySs = 
		     let val breakS = P.returnS(PL.P_READ_ERR)
				
			 val initDecSs = 
			     (if Option.isSome skipXOpt then               
				  [P.varDeclS(P.int, omitresult, P.falseX)]
			      else [])
					   

			 fun insNotFirstChk nil = nil
			   | insNotFirstChk bodySs =
			     [PT.IfThen(PT.Id notFirstElt,
					PT.Compound bodySs)]

			 fun genSepCheck (NONE) = []
			   | genSepCheck (SOME (sepX, scan2SepX, cSepX, typ, matchSep, scan1Sep, writeSep)) = 
			      (case (termXOpt, noSepIsTerm) of 
				(NONE, true) => 
				[P.mkCommentS("Checking for separator"),
				 PT.IfThen(P.eqX(PL.P_ERROR, PL.matchFunX(matchSep, PT.Id pads, sepX, P.trueX (* eatlit *))),
					   PT.Compound(
					       [P.mkCommentS("No separator, therefore array is finished"),
					       breakS]))]
			      | (NONE, false) => 
				[P.mkCommentS("Array not finished; reading separator"),
				 PT.Compound([P.varDeclS'(PL.sizePCT, "offset")]
					     @ [PT.IfThen(P.eqX(PL.P_ERROR,
						     PL.scan1FunX(scan1Sep, PT.Id pads, sepX,
								  P.trueX, (* eatlit *) P.falseX, (* panic *) 
								  P.addrX (PT.Id "offset"))),
					       breakS)])]
			      | (SOME(termX, scan2TermX, _, _, _, _, _), _) => 
			       [P.mkCommentS("Array not finished; read separator with recovery to terminator"),
				PT.Compound([P.varDeclS'(P.int, "f_found"),
					     P.varDeclS'(PL.sizePCT, "offset")]
					    @ [PT.IfThen(P.eqX(PL.P_ERROR,
							       PL.scan2FunX(valOf scan2Opt, PT.Id pads, 
									    scan2SepX, scan2TermX, P.trueX, P.falseX,
									    P.falseX, (* panic=0 *)
									    P.addrX (PT.Id "f_found"),
									    P.addrX (PT.Id "offset"))),
							 breakS)])]
			       )

			 val bdyS = 
			       (* initDecSs
			     @ *)
			     [P.mkCommentS("Ready to read element")]
			     @ insNotFirstChk (genSepCheck (sepXOpt))
		             @ rroReadElementSs
		     in
			 [PT.Compound(bdyS)]
		     end


		 val returnDoneS = 
		     P.returnS
			 (macroRetDone(PT.Id consumeFlag))

		 (* Assemble final_checks function*)
		 val finalChecksBodySs = [PT.Compound (
				  [macroUnsetPartial]
				@ trailingJunkChkSs'(name)
				@ (readEORSs PL.P_READ_ERR)
				@ setDataFieldsSs
				@ (genArrayConstraintsSs PL.P_READ_ERR)
				@ (stcloseSsFun false)
                                @ [returnDoneS])]

                 val readOneFunEDs = genRPInitFun(name,cParams,stRPInfo)
				     @ genFinalChecksFun(fcName, cParams, mPCT, pdPCT, canonicalPCT, 
						       finalChecksBodySs)
				     @ genROInitFun(roInitName, cParams, mPCT, pdPCT, canonicalPCT, 
						    roInitBodySs)
				     @ genReadOneFun(readOneName, cParams, mPCT, pdPCT, canonicalPCT, 
						     elemEdPCT,elemRepPCT,
						     readOneBodySs)				  
				     @ genReadFun(roDriverName, cParams, mPCT, pdPCT, canonicalPCT, 
						  NONE, true, roDriverBodySs(name))
				     @ genReReadOneFun(rereadOneName,cParams, mPCT, pdPCT, canonicalPCT, 
						     elemEdPCT,elemRepPCT,
						     rereadOneBodySs)
				     
                 val _ = popLocalEnv()


		 val (roParamsStructDecls,_) = cnvCTy (genRPStructED(name,cParams,stRPInfo))
								  
                 val readEDs = initRepEDs @ initPDEDs @ cleanupRepEDs @ cleanupPDEDs
			     @ copyRepEDs @ copyPDEDs @ maskFunEDs @ (* readFunEDs @ *)readOneFunEDs

                 (***** array PADS-Galax *****)
			 
    	         (* PDCI_node_t* fooArray_kthChild(PDCI_node_t *self, PDCI_childIndex_t idx) *)
		 fun genGalaxArrayKthChildFun(name) =		
		     let val nodeRepTy = PL.nodeT
			 val returnTy = P.ptrPCT nodeRepTy
                         val cnvName = PNames.nodeKCSuf name 
			 val paramTys = [P.ptrPCT nodeRepTy, PL.childIndexT]
                         val paramNames = [G.self,G.idx]
                         val formalParams =  List.map P.mkParam (ListPair.zip(paramTys, paramNames))
			 val elemName = lookupPadsx(baseTy)
		         val bodySs = G.makeInvisibleDecls([name,elemName],nil)
				      @ [G.macroArrKC(name,elemName),
					 P.returnS (G.macroArrKCRet())]
                     in   
                         P.mkFunctionEDecl(cnvName, formalParams, PT.Compound bodySs, returnTy)
                     end


		 fun genGalaxArrayKthChildNamedFun(name) =		
		     let val nodeRepTy = PL.nodeT
			 val returnTy = P.ptrPCT nodeRepTy
                         val cnvName = PNames.nodeKCNSuf name 
			 val paramTys = [P.ptrPCT nodeRepTy, PL.childIndexT, P.ccharPtr]
                         val paramNames = [G.self,G.idx,G.childName]
                         val formalParams =  List.map P.mkParam (ListPair.zip(paramTys, paramNames))
		         val bodySs = G.makeInvisibleDecls([name],nil)
				      @ [G.macroArrKCN(name)]
				      @ [P.returnS (G.macroArrKCNRet())]
		     in   
                         P.mkFunctionEDecl(cnvName, formalParams, PT.Compound bodySs, returnTy)
		     end
			 
		 fun makeGalaxEDs(name) = 
		     let val elemName = lookupPadsx(baseTy)
			 val pdName = BU.lookupTy(baseTy, pdSuf, #pdname)
			 val mName = BU.lookupTy(baseTy, mSuf, #mname)
		     in 
			 [G.makeNodeNewFun(name),
			  G.makeCNInitFun(name,G.macroArrLength(name)),
			  genGalaxArrayKthChildFun(name),
			  genGalaxArrayKthChildNamedFun(name),
			  G.makeCNKCFun(name,G.macroArrLength(name)),
			  G.makeSNDInitFun(name),				      
			  G.makeArrSNDKthChildFun(name,elemName),
			  G.makeArrPathWalkFun(name,elemName),
			  G.makeNodeVtable(name),
			  G.makeCachedNodeVtable(name),
			  G.makeSNDNodeVtable(name)]
			  @ (if (lookupContainsRecord baseTy)
			    then G.SmartNode.makeAllEDs(name,elemName,pdName,mName,cParams,stparams)
			    else [])
		     end
				  			 
	         val galaxEDs = makeGalaxEDs(name)
				

		 (* Generate Write function array case *)
		 val writeName = writeSuf name
		 val writeXMLName = writeXMLSuf name
		 val fmtName = fmtSuf name
		 val fmtBaseName = (bufSuf o fmtSuf) (lookupWrite baseTy) 
		 val writeBaseName = (bufSuf o writeSuf) (lookupWrite baseTy) 
		 val writeXMLBaseName = (bufSuf o writeXMLSuf) (lookupWrite baseTy) 
		 val lengthX = P.arrowX(PT.Id rep, PT.Id length)
		 fun elemX base = P.addrX(P.subX(P.arrowX(PT.Id base, PT.Id elts), PT.Id "i"))
                 val writeBaseSs = writeFieldSs(writeBaseName, [elemX pd, elemX rep] @ args, true)
		 val fmtBaseX = fmtCall(fmtBaseName, [P.getFieldX(m, element),elemX pd, elemX rep] @ args)
                 val writeXMLBaseSs = writeXMLFieldSs(writeXMLBaseName, [elemX pd, elemX rep], PT.String "elt", true, true, args)
		 val writeLastBaseSs =  [PT.IfThen(P.neqX(lengthX, P.zero), PT.Compound(writeBaseSs))]
		 fun writeLitSs litXOpt = 
		     case litXOpt of NONE => [] 
		     | SOME(e, _, _, _, _, _, SOME writeSep) => writeFieldSs(writeSep, [e], true)
                     | SOME _ => [P.mkCommentS "Don't currently support writing regular expressions"]
		 val writeSepSs = writeLitSs sepXOpt
		 val writeArraySs = [PT.Compound (
				     [P.varDeclS(P.int, "i", P.zero),
				      PT.IfThen(P.gtX(lengthX, P.intX 1),
						PT.Compound[
					           PT.For(P.assignX(PT.Id "i", P.zero),
							  P.ltX(PT.Id "i", P.minusX(lengthX, P.intX 1)),
							  P.postIncX (PT.Id "i"),
							  PT.Compound (writeBaseSs @ writeSepSs))])]
                                     @ writeLastBaseSs)]
		 val writeXMLArraySs = [PT.Compound (
				     [P.varDeclS(P.int, "i", P.zero),
				      PT.For(P.assignX(PT.Id "i", P.zero),
						  P.ltX(PT.Id "i", lengthX),
						  P.postIncX (PT.Id "i"),
						  PT.Compound (writeXMLBaseSs))])]
		 val writeTermSs = writeLitSs termXOpt
		 val bodySs = writeArraySs @ writeTermSs
		 val bodyXMLSs = [PT.Expr(PT.Call(PT.Id "PCGEN_ARRAY_OPEN_XML_OUT", []))]
				 @ writeXMLArraySs
				 @ [PT.Expr(PT.Call(PT.Id "PCGEN_XML_VALUE_OUT", [PT.String("length"), lengthX]))]
				 @ [PT.Expr(PT.Call(PT.Id "PCGEN_ARRAY_PD_XML_OUT", []))]
				 @ [PT.Expr(PT.Call(PT.Id "PCGEN_ARRAY_CLOSE_XML_OUT", []))]
		 val fmtBufFinalName = bufFinalSuf fmtName
		 val bodyFmtFinalSs = [P.varDeclS(P.int, "i", P.zero),
				       PL.fmtFinalInitStruct (PT.String fmtBufFinalName) ] @ [PL.fmtArray(PT.String fmtBufFinalName, fmtBaseX)] @ [PL.fmtFixLast()]
		 val (writeFunEDs, fmtFunEDs) = genWriteFuns(name, "STANDARD", writeName, writeXMLName, fmtName, isRecord, isSource, cParams, 
								  mPCT, pdPCT, canonicalPCT, bodySs, bodyXMLSs, bodyFmtFinalSs)

                 (* Generate is function array case *)
                 val isName = PNames.isPref name
                 fun genElemChecks () = 
		     let val index = "i"
			 val indexX = PT.Id index
			 val upperX = P.fieldX(rep, length)
			 val elemX = P.subX(P.fieldX(rep,elts), indexX)
			 val elemCXs = 
                             case lookupPred baseTy of NONE => [] 
		             | SOME elemPred => [PT.Call(PT.Id elemPred, [P.addrX elemX] @ args)]

			 val needsConsume = case endedXOpt of SOME(_,_,SOME isPredX) =>
			                          PTSub.isFreeInExp([PNames.consume], isPredX)
					    | _ => false
			 val genVars = [(PNames.arrayLen,   PL.uint32PCT,        P.fieldX(rep, length)), 
					(name,              P.ptrPCT elemRepPCT, P.fieldX(rep, elts)),
					(PNames.arrayElts,  P.ptrPCT elemRepPCT, P.fieldX(rep, elts)),
					(PNames.arrayCur,   PL.uint32PCT,        indexX), 
					(PNames.curElt,     elemRepPCT,          P.subX(P.fieldX(rep, elts), indexX))]
			               @ (if needsConsume then
    			                     [(PNames.consume,    P.int,               PT.Id consumeFlag)]
					  else [])
			 val omitCXs = 
			     case skipXOpt of NONE => []
				  | SOME (_,_, NONE) => []
				  | SOME (_, _, SOME isPredX) => 
				      let val modIsPredX = PTSub.substExps (getBindings genVars) isPredX
				      in
					  [P.notX modIsPredX] (* if would have skipped,shouldn't be in-memory representation *)
				      end
			 val lastCXs = 
			     case lastXOpt of NONE => []
				  | SOME (_,_, NONE) => []
				  | SOME (_, _, SOME isPredX) => 
				      let val modIsPredX = PTSub.substExps (getBindings genVars) isPredX
				      in
					  (* if last predicate, then should be no more elements in array *)
					  [P.condX(modIsPredX, P.eqX(P.fieldX(rep, length), P.plusX(indexX,P.intX 1)), P.trueX)] 
				      end
			 val endedCXs = 
			     case endedXOpt of NONE => []
				  | SOME (_,_, NONE) => []
				  | SOME (_, _, SOME isPredX) => 
				      let val modIsPredX = PTSub.substExps (getBindings genVars) isPredX
				      in
					  (* if ended predicate, then should be no more elements in array *)
					  [P.condX(modIsPredX, 						   
						   if needsConsume then 
						       P.condX(PT.Id consumeFlag, 
							       P.eqX(P.fieldX(rep, length), P.plusX(indexX, P.intX 1)),
							       P.eqX(P.fieldX(rep, length), indexX))
						   else P.eqX(P.fieldX(rep, length), indexX),
						   P.trueX)] 
				      end
			 val condXs = (elemCXs @ omitCXs @ lastCXs @ endedCXs)
			 val elemCondX = P.andBools condXs
		     in
		       case condXs of [] => []
                       | _ => 
			 [PT.Compound(
			   [P.varDeclS'(P.int, index)]
 		         @ (if needsConsume then [P.varDeclS(P.int, consumeFlag, P.falseX)] else [])
			 @ [PT.For(P.assignX(PT.Id index, P.zero),
				 P.andX(P.notX(PT.Id violated), P.ltX(PT.Id index, upperX)), 
				 P.postIncX(PT.Id index),
				 PT.Compound[
                                   PT.IfThen(P.notX(elemCondX),
				             PT.Compound[P.assignS(PT.Id violated, P.trueX)] (* end if *))
					     ] (* end for *))])]
		     end

		 fun genPredClause c = 
		     case c of 
                       PX.Forall      r   => genLoop r
		     | PX.AGeneral    exp => [PT.IfThen(P.notX exp, PT.Compound[P.assignS(PT.Id violated, P.trueX)])]
                     | PX.AParseCheck exp => []
		 val clausesSs = List.concat(List.map genPredClause postCond)
		 val bodySs = [P.varDeclS(P.int, violated, P.falseX)]
		             @ (genElemChecks ())
		             @  clausesSs
                             @ [PT.Return (P.notX(PT.Id violated))]
                 val isFunEDs = [genIsFun(isName, cParams, rep, canonicalPCT, bodySs)]

                 (* Generate accumulator functions array case *) 
  	         (* -- generate accumulator reset, init, and cleanup function *)
                 fun genResetInitCleanup theSuf = 
		     let val theFun = (theSuf o accSuf) name
                         val doElems = 
			     case lookupAcc baseTy of NONE => []
			   | SOME a => (
			       let val elemFunName = theSuf a
				   fun doOne eX = BU.chk3Pfun (elemFunName, [eX])
				   val fieldX = P.addrX(P.subX(P.arrowX(PT.Id acc, PT.Id arrayDetail), PT.Id "i"))
				   val doArrayDetailSs = [
					PT.Compound
					 [P.varDeclS'(P.int, "i"),
					  PT.For(P.assignX(PT.Id "i", P.zero),
						 P.ltX(PT.Id "i", P.intX numElemsToTrack),
						 P.postIncX (PT.Id "i"),
						 PT.Compound (doOne fieldX)
						 )]]
				   val arrayX = P.addrX(P.arrowX(PT.Id acc, PT.Id array))
				   val doArraySs = doOne arrayX
			       in
				   doArraySs @ doArrayDetailSs
			       end(* end SOME acc case *))
			 val lengthX = P.addrX(P.arrowX(PT.Id acc, PT.Id length))
			 val doLength = BU.chk3Pfun(theSuf PL.uint32Act, [lengthX])
			 val theDeclSs = [P.varDeclS(PL.uint32PCT, nerr, P.zero)]
			 val theReturnS = BU.genReturnChk (PT.Id nerr)
			 val theBodySs = theDeclSs @ doLength @ doElems @ [theReturnS]
			 val theFunED = BU.gen3PFun(theFun, [accPCT], [acc], theBodySs)
		     in
			 theFunED
		     end

  	         (* -- generate accumulator add function *)
                 fun genAdd () = 
		     let val theSuf = addSuf
			 val theFun = (theSuf o accSuf) name
			 val theDeclSs = [P.varDeclS(PL.uint32PCT, nerr, P.zero), P.varDeclS'(PL.base_pdPCT, tpd)]
			 val initTpdSs = [P.assignS(P.dotX(PT.Id tpd, PT.Id errCode), 
						    P.arrowX(PT.Id pd, PT.Id errCode))]
                         val doElems = 
			     case lookupAcc baseTy of NONE => []
			   | SOME a => (
			       let val elemFunName = theSuf a
				   fun getArrayFieldX (base, field) = 
					P.addrX(P.subX(P.arrowX(PT.Id base, PT.Id field), PT.Id "i"))
				   fun doOne (accX, pdX, repX) = BU.chkAddFun (elemFunName, accX, pdX, repX)
				   val doArrayDetailSs = [
					PT.Compound
					 [P.varDeclS'(P.int, "i"),
					  PT.For(P.assignX(PT.Id "i", P.zero),
						 P.ltX(PT.Id "i", P.arrowX(PT.Id rep, PT.Id length)),
						 P.postIncX (PT.Id "i"),
						 PT.Compound ([PT.IfThen(P.ltX(PT.Id "i", P.intX numElemsToTrack),
							       PT.Compound (doOne (getArrayFieldX(acc, arrayDetail), 
										   getArrayFieldX(pd, elts), 
										   getArrayFieldX(rep, elts))))]
							      @ (doOne (P.getFieldX(acc, array), 
								        getArrayFieldX(pd, elts), 
									getArrayFieldX(rep, elts))))
						 )]]
			       in
				   doArrayDetailSs
			       end(* end SOME acc case *))
			 val doLength = BU.chkAddFun(theSuf PL.uint32Act, P.getFieldX(acc, length), P.addrX(PT.Id tpd), 
						  P.getFieldX(rep, length))
			 val theReturnS = BU.genReturnChk (PT.Id nerr)
			 val theBodySs = theDeclSs @ initTpdSs @ BU.ifNotPanicSkippedSs(doLength @ doElems) @ [theReturnS]
			 val theFunED = BU.genAddFun(theFun, acc, accPCT, pdPCT, canonicalPCT, theBodySs)
		     in
			 theFunED
		     end

		 val initFunED = genResetInitCleanup  initSuf
		 val resetFunED = genResetInitCleanup resetSuf
		 val cleanupFunED = genResetInitCleanup cleanupSuf
                 val addFunED = genAdd()

		 (* -- generate accumulator report function array *)
		 (*  Perror_t T_acc_report (P_t* , T_acc* , const char* prefix  ) *)
                 fun genReport () = 
		     let val reportFun = (reportSuf o accSuf) name
			 val lengthX = P.arrowX(PT.Id acc, PT.Id length)
			 val doLengthSs = [BU.chkPrint(
					     callIntPrint((ioSuf o reportSuf) PL.uint32Act, PT.String "Array lengths", 
						 	 PT.String "array length", P.intX ~1, P.addrX lengthX)) ]
			 val maxX = P.dotX(lengthX, PT.Id "max")
			 val limitX = PT.QuestionColon(P.ltX(maxX, P.intX 10), maxX, P.intX 10)
						 
                         val doElems = 
			     case lookupAcc baseTy of NONE => []
			   | SOME a => (
			       let val elemFunName = reportSuf a
				   fun doOne (descriptor, prefixX, eX, extraArgXs) = 
					BU.genPrintPiece (ioSuf elemFunName, descriptor, prefixX, eX, extraArgXs)
				   val fieldX = P.addrX(P.subX(P.arrowX(PT.Id acc, PT.Id arrayDetail), PT.Id "i"))
				   val doArrayDetailSs = [
					PT.Compound
					 [P.varDeclS'(P.int, "i"),
					  PT.For(P.assignX(PT.Id "i", P.zero),
						 P.ltX(PT.Id "i", limitX),
						 P.postIncX (PT.Id "i"),
						 PT.Compound (doOne (arrayDetail^"[%d]", PT.String "array element", 
								     fieldX, [PT.Id "i"]))
						 )]]
				   val arrayX = P.addrX(P.arrowX(PT.Id acc, PT.Id array))
				   val doArraySs = doOne ("allArrayElts", PT.String "all array element", arrayX, [])
			       in
				   doArraySs @ doArrayDetailSs
			       end(* end SOME acc case *))
			 val checkNoValsSs = [PT.Expr(PT.Call(PT.Id "PCGEN_ARRAY_ACC_REP_NOVALS", []))]
			 val theBodySs = checkNoValsSs @ doLengthSs @ doElems 
			 val baseTyStr = case baseTy of PX.Name n => n
			 val theFunEDs = BU.genReportFuns(reportFun, "array "^ name ^" of "^baseTyStr, accPCT, acc, theBodySs)
		     in
			 theFunEDs
		     end
                 val reportFunEDs = genReport()

      		 val accumEDs = accED :: initFunED :: resetFunED :: cleanupFunED :: addFunED :: reportFunEDs

		 (* Generate histogram declarations, array case *)
		 val histEDs = Hist.genArray (name, baseTy, canonicalPCT, pdPCT)

		 (* Generate cluster declarations, array case *)
		 val clusterEDs = Cluster.genArray (name, baseTy, canonicalPCT, pdPCT)


		 val galaxStructDecls = 
		     if !(#outputXML(PInput.inputs)) andalso (lookupContainsRecord baseTy)
		     then #1(cnvCTy (G.SmartNode.makeArrayInfoStructED(name)))
		     else []

	     in
		   canonicalDecls
		 @ mStructDecls
                 @ pdStructDecls
		 @ roParamsStructDecls
		 @ galaxStructDecls
		 @ (emitRead readEDs)
		 @ (emitPred isFunEDs)
                 @ (emitAccum accumEDs)
	         @ (emitHist histEDs)
	         @ (emitCluster clusterEDs)
                 @ (emitWrite writeFunEDs)
		 @ (emitWrite fmtFunEDs)
                 @ (emitXML galaxEDs)
	     end


          fun cnvPOpt ({name : string, params: (pcty * pcdecr) list, args: pcexp list,
			isRecord, isSource : bool, pred : (pcexp PX.OptPredicate) option, 
			baseTy: PX.Pty })=
	      let val someTag = "some_"^name
		  fun cvtDecon {some,none} = 
		      case some of NONE => (NONE, none)
		      | SOME (var, conds) => (SOME (P.substPostCond  [(var, PT.Id (someTag))] conds), none)
		  val (predend, (predsome, prednone)) = 
		      case pred of NONE => ([], (NONE, NONE))
		      | SOME(PX.Simple x) => (PE.error ("Form of constraint on "^name^ " opt is currently not supported.");
					      (x, (NONE, NONE)))
 	              | SOME(PX.Decon d) => ([], cvtDecon d)
		  val some = PX.Full {pty = baseTy, 
				      args = args,
				      name = someTag, 
				      isVirtual = false,
				      isEndian = false,
				      isRecord = false,
				      containsRecord = false,
				      largeHeuristic = false,
				      pred = predsome, 
				      comment = SOME "value is present",
				      optDecl =false,
				      optPred = NONE,
				      arrayDecl = false, 
				      size = NONE,
				      arraypred = []}
		   val none =  PX.Manifest 
				    { tyname = PL.uint32PCT,
				      name   = "none_"^name,
				      args   = [],
				      isVirtual = true,
				      expr = P.intX 0,
				      pred = prednone,
				      comment = SOME "value was not present"}
		   val branches = PX.Ordered [some,none]
		   val unionVal = {name = name,
				   params = params,
				   isLongestMatch = false,
				   isRecord = isRecord,
				   isSource = isSource,
				   containsRecord = false, (* dummies to be filled in later *)
				   largeHeuristic = false, (* dummies to be filled in later *)
				   variants = branches,
				   postCond = predend,
				   fromOpt = true}
	      in
		  cnvPUnion unionVal
	      end


	     and cnvPUnion {name: string, params: (pcty * pcdecr) list, isLongestMatch: bool,
			    isRecord: bool, containsRecord, largeHeuristic, isSource: bool, 
			    variants: (pcty, pdty, pcdecr, pcexp) PX.PBranches, postCond : (pcexp PX.PPostCond) list,
			    fromOpt} =
		 let val unionName = name
		     val which = if fromOpt then "opt" else "union"
		     val checkIf = if isLongestMatch then "Check If " else ""
		     val macStart = if isLongestMatch then "PCGEN_UNION_READ_LONGEST" else "PCGEN_UNION_READ"
		     fun whereNeedsEndChk1 cond =
			 case cond
			  of PX.General expr => false
			   | PX.ParseCheck expr => PTSub.isFreeInExp([PNames.unionEnd], expr)
		     val whereNeedsEnd = (List.exists whereNeedsEndChk1 postCond)
		     (* Functions for walking over list of branch, variant *)
		     fun mungeBV f b m eopt (PX.Full fd) = f (eopt, fd)
		       | mungeBV f b m eopt (PX.Brief e) = b (eopt, e)
		       | mungeBV f b m eopt (PX.Manifest md)  = m (eopt, md)
		     fun mungeBVs f b m [] [] = []
		       | mungeBVs f b m (x::xs) (y::ys) = (mungeBV f b m x y) @ (mungeBVs f b m xs ys)
		       | mungeBVs f b m _ _ = raise Fail "This case should never happen"

                     (* Function for moving default clause to end of switched union branch list *)
                     fun mungeBranches (cases, branches) = 
                       let fun mB([], [], acs, abs, acds, abds) = 
			       let val numDefaults = List.length acds
			       in
			          if (numDefaults >= 2) 
				      then (PE.error ("Switched union "^ unionName ^" can have at most "^
						      "one default clause\n");
					    (true (* has default clause*), 
					     (List.rev acs) @ [hd acds], (List.rev abs) @ [hd abds]))
				  else (numDefaults = 1, (List.rev acs) @ acds, (List.rev abs) @ abds)
			       end
                             | mB(NONE::cases, b::bs, acs, abs, acds, abds) = 
					    mB(cases, bs, acs, abs, NONE::acds, b::abds)
                             | mB(c::cases, b::bs, acs, abs, acds, abds) = 
					    mB(cases, bs, c::acs, b::abs, acds, abds)
                             | mB _ = raise Fail "This case can't happen"
		       in
			   mB(cases, branches, [], [], [], [])
		       end


                     val branches = variants
                     val (descOpt, hasDefault, cases, variants) = 
				    case branches 
			            of PX.Ordered v => (NONE, false (* no default clause *), [], v)
			            |  PX.Switched {descriminator, cases, branches} => 
					    let val (hasDefault, cases, branches) = mungeBranches(cases, branches)
					    in
						(SOME descriminator, hasDefault, cases, branches)
					    end

                     (* -- collection of expressions to be substituted for in constraints *)
                     (* -- efficiency could be improved with better representations *)
                     val readSubList : (string * pcexp) list ref = ref []
                     val postReadSubList : (string * pcexp) list ref = ref []
                     fun addReadSub (a : string * pcexp) = readSubList := (a:: (!readSubList))
                     fun addPostReadSub (a : string * pcexp) = postReadSubList := (a:: (!postReadSubList))
		     val (hasParseCheck, (allVars, omitNames, omitVars, readSubs, pdSubs, postReadSubs, tys, tyNames)) =
			 checkStructUnionFields("Punion", unionName, isLongestMatch, variants)
		     val _ = List.map addReadSub readSubs
		     val _ = List.map addReadSub pdSubs
		     val _ = List.map addPostReadSub postReadSubs

		     val dummy = "_dummy"
		     val cParams : (string * pcty) list = List.map mungeParam params
		     val paramNames = #1(ListPair.unzip cParams)
                     val value = PNames.unionVal
		     val tag = PNames.unionTag

                     (* Process in-line declarations *)
                     fun cvtInPlaceFULL ( f as {pty, args, name, pred, comment, size, arraypred,isVirtual, isEndian,
						optPred, optDecl, arrayDecl,...}:BU.pfieldty) = 
			   if not (arrayDecl orelse optDecl) then 
			       (if Option.isSome optPred then PE.error ("Field "^name^" in "^unionName^ " has option-style constraints "^
									"but is not an in-line option declaration.\n")
			        else ();
			       [([], PX.Full f)])
			   else
			       let val declName = case List.find (fn(nm,_) => nm = name) (ListPair.zip(allVars, tyNames))
				                  of NONE => (PE.bug "Compiler bug";  padsID name)
						  |  SOME (fname, tynm) => tynm
						      
				   fun doArray() = 
				       let val arrayPX = {name=declName, baseTy = pty, params = params, 
							 isRecord = false, containsRecord = false, largeHeuristic = false, isSource = false,
							 args = args, sizeSpec=size, constraints=arraypred, postCond = []}
				      in
					  (cnvPArray arrayPX, NONE)
				      end
				  fun doOpt () = 
				      let val () = case pred of NONE => () | _ => PE.error ("The form of constraint "^
											    "on opt field " ^name^
											    " is not currently supported.")
					  val optPX = {name     = declName, params   = params, args     = args,
						       isRecord = false, isSource = false, pred = optPred, baseTy   = pty}
				      in
					   (cnvPOpt optPX, pred)
				      end
				  val (newAsts,modpred) = if arrayDecl then doArray() else doOpt ()
				  val sfield = {pty=PX.Name declName, args=(List.map (fn x=> PT.Id x) paramNames),
						name=name, isVirtual=isVirtual, isEndian=isEndian,
						isRecord=false, containsRecord=false, largeHeuristic=false, pred=pred,
						comment=comment,optPred = NONE,
						optDecl = false, arrayDecl = false, size=NONE, arraypred=[]} : BU.pfieldty
			      in
				  [(newAsts, PX.Full sfield)]
	 		      end
                      fun cvtInPlaceBrief x = [([],PX.Brief x)]
                      fun cvtInPlaceMan   x = [([],PX.Manifest x)]
                      fun cvtRep variants = 
			  let val res = P.mungeFields cvtInPlaceFULL cvtInPlaceBrief cvtInPlaceMan variants
			      val (asts, newfields) = ListPair.unzip res
			  in
			      (List.concat asts, newfields)
			  end
		      val (asts, variants) = cvtRep variants

                     (* generate enumerated type describing tags *)
		     val tagVal = ref 0
		     val firstTag = ref "bogus"
		     val lastTag = ref "bogus"
		     fun chkTag(name) = 			 
			 let val name = if enumConstDefined name then 
			                  let val t0 = unionName^"_"^name 
					  in 
					      if enumConstDefined t0 then
						  let fun getname base next = 
						       let val t = base^"_"^(Int.toString next)
						       in
						          if enumConstDefined t
							      then getname base (next + 1)
							      else t
						       end
						  in
						      getname t0 0
						  end
					      else t0
					  end
					else name
			 in
			 (if !tagVal = 0 then firstTag := name else ();
			  lastTag := name;
			  tagVal := !tagVal + 1;
			  [(name, P.intX(!tagVal), NONE)])
			 end

		     fun genTagFull ({pty: PX.Pty, args: pcexp list, name: string, 
				     isVirtual: bool, isEndian: bool, 
				     isRecord, containsRecord, largeHeuristic: bool,
				     pred, comment: string option,...}:BU.pfieldty) = 
			 chkTag(name)
		     fun genTagBrief e = case getString e of NONE => [] | SOME s => chkTag s
                     fun genTagMan {tyname, name, args, isVirtual, expr, pred, comment} = chkTag name

		     val tagFields = P.mungeFields genTagFull genTagBrief genTagMan variants
		     val tagFieldsWithError = (errSuf name, P.zero, NONE) :: tagFields 
		     val tagED = P.makeTyDefEnumEDecl(tagFieldsWithError, tgSuf name)
		     val tagDecls = cnvExternalDecl tagED
		     val tagPCT = P.makeTypedefPCT(tgSuf name)

		      (* Generate CheckSet mask *)
		     fun genMFull ({pty: PX.Pty, args: pcexp list, name: string, 
				    isVirtual: bool, isEndian: bool, 
                                    isRecord, containsRecord, largeHeuristic: bool,
				    pred, comment,...}:BU.pfieldty) = 
			 [(name, P.makeTypedefPCT(BU.lookupTy (pty, mSuf, #mname)), SOME "nested constraints")]
			 @ (case pred of NONE => [] | SOME _ => [(mConSuf name, PL.base_mPCT, SOME "union constraints")])
		     fun genMBrief e = []
		     (* fun genMMan m = [] foofoofoo *)
		     fun genMMan {tyname : pcty, name, args, isVirtual, expr, pred, comment} = 
			 case isPadsTy tyname
			  of PTys.CTy => []
			   | _ => (let val pty : pty = getPadsName tyname
				   in 
				       [(name, P.makeTypedefPCT(BU.lookupTy (pty, mSuf, #mname)), SOME "nested constraints")]
				       @ (case pred of NONE => [] | SOME _ =>  [(mConSuf name, PL.base_mPCT, SOME "union constraints")])
				   end)
		     val mFieldsNested = P.mungeFields genMFull genMBrief genMMan variants
		     val auxMFields    = [(PNames.unionLevel, PL.base_mPCT, NONE)]
                     val mFields = auxMFields @ mFieldsNested
		     val mFirstPCT = getFirstEMPCT mFields
		     val mStructED = P.makeTyDefStructEDecl (mFields, mSuf name)
		     val mPCT = P.makeTypedefPCT (mSuf name)			  

		     (* Generate parse description *)
		     fun genEDFull ({pty: PX.Pty, args: pcexp list, name: string, 
				    isVirtual: bool, isEndian: bool,
				    isRecord, containsRecord, largeHeuristic: bool,
				    pred, comment,...}:BU.pfieldty) = 
			 [(name, P.makeTypedefPCT(BU.lookupTy (pty, pdSuf, #pdname)), NONE)]
		     fun genEDBrief e = case getString e of NONE => [] | SOME s => [(s, PL.base_pdPCT, NONE )]
		     val pdVariants = P.mungeFields genEDFull genEDBrief genEDMan variants
		     val pdVariants = if List.length pdVariants = 0
			                    then [(dummy, PL.uint32PCT, SOME "Dummy field inserted to avoid empty union pd")]
					    else pdVariants			        
		     val unionPD = P.makeTyDefUnionEDecl(pdVariants, (unSuf o pdSuf) name)
		     val (unionPDDecls, updTid) = cnvCTy unionPD
		     val unionPDPCT = P.makeTypedefPCT((unSuf o pdSuf) name)
		     val structEDFields = [(pstate, PL.flags_t, NONE), (nerr, PL.uint32PCT, NONE),
				  	   (errCode, PL.errCodePCT, NONE), (loc, PL.locPCT, NONE)]
                                          @ (if isGalax() then [(identifier, PL.idPCT, SOME "Identifier tag for Galax")] else [])
					  @[(tag, tagPCT, NONE), (value, unionPDPCT, NONE)]
		     val pdStructED = P.makeTyDefStructEDecl (structEDFields, pdSuf name)
		     val (pdStructPDDecls, pdTid) = cnvCTy pdStructED
		     val pdPCT = P.makeTypedefPCT (pdSuf name)			  

		     (* Generate accumulator type *)
		     fun genAccFull ({pty: PX.Pty, args: pcexp list, name: string, 
				     isVirtual: bool, isEndian: bool, 
				     isRecord, containsRecord, largeHeuristic: bool, 
				     pred, comment,...}:BU.pfieldty) = 
			 if not isVirtual then
			     case lookupAcc pty of NONE => []
			   | SOME a => [(name, P.makeTypedefPCT a, NONE)]
			 else []
		     fun genAccBrief e = [] (* literals are not stored in in-memory rep, so can't be accumulated *)
		     val auxAccFields = [(tag, PL.intAccPCT, NONE)]
		     val accFields = auxAccFields @ (P.mungeFields genAccFull genAccBrief genAccMan variants)
		     val accED = P.makeTyDefStructEDecl (accFields, accSuf name)
		     val accPCT = P.makeTypedefPCT (accSuf name)			  

		     (* Calculate and insert type properties into type table *)
		     fun genTyPropsFull ({pty: PX.Pty, args: pcexp list, name: string, 
					 isVirtual: bool, isEndian: bool, 
					 isRecord, containsRecord, largeHeuristic: bool,
					 pred, comment: string option,...}:BU.pfieldty) = 
			  let val PX.Name ftyName = pty
			      val mc = lookupMemChar pty
			      val ds = computeDiskSize(name, paramNames, pty, args)
			      val contR = lookupContainsRecord pty	 
			      val lH = lookupHeuristic pty 
			  in [{diskSize=ds, memChar=mc, endian=false, isRecord=isRecord, 
			       containsRecord=contR, largeHeuristic=lH, 
			       labels = [SOME (name, ftyName, (paramNames, args), isVirtual, comment)]}] 
			  end
		     (* Not storing strings read via RE yet, so Static for now *) 
		     fun genTyPropsBrief (e, labelOpt) = case extractString e 
                           of NONE =>  (* either regular expression or error case; error reported elsewhere *)
			        [{diskSize=TyProps.Variable, memChar=TyProps.Static, endian=false, isRecord=false, 
				  containsRecord=false, largeHeuristic=false, 
				  labels = [NONE]}] 
		           | SOME s => 
			     let val  ds = TyProps.Size(IntInf.fromInt (String.size s), IntInf.fromInt 0)
			     in [{diskSize=ds, memChar=TyProps.Static, endian=false, isRecord=false, 
				  containsRecord=false, largeHeuristic=false, 
				  labels = [NONE]}] 
			     end

		     val tyProps = P.mungeFields genTyPropsFull genTyPropsBrief genTyPropsMan variants
                     (* check that all variants are records if any are *)
		     (* val () = case tyProps of [] => ()
			      | 
			  ({isRecord=first,...}::xs) => 
			           (if List.exists (fn {isRecord, diskSize, memChar, endian,
							containsRecord, largeHeuristic, labels} => not (isRecord = first)) xs 
				    then PE.error "All branches of Punion must terminate record if any branch does"
				    else ()) *)
					
		     val {diskSize, memChar, endian, isRecord=_, containsRecord, largeHeuristic, labels} = 
			 List.foldl (PTys.mergeTyInfo (fn (x, y) => x) ) PTys.minTyInfo tyProps
		     fun computeUnionDiskSize tyProps = 
			 case tyProps of [] => TyProps.mkSize(0,0)
			 | [r:PTys.sTyInfo] => #diskSize r
			 | (r::rs) => TyProps.overlay(#diskSize r,  computeUnionDiskSize rs   )
		     val diskSize = computeUnionDiskSize tyProps
		     val compoundDiskSize = TyProps.Union ((ListPair.zip(List.rev labels, 
									  (List.map (fn (r : PTys.sTyInfo) => #diskSize r) tyProps))))
		     val numArgs = List.length params
		     val unionProps = buildTyProps(name, PTys.Union, diskSize, compoundDiskSize, memChar, 
						   endian, isRecord, containsRecord, 
						   largeHeuristic, isSource, pdTid, numArgs)
                     val () = PTys.insert(Atom.atom name, unionProps)

                     (* union: generate canonical representation *)
		     fun genRepFull ({pty: PX.Pty, args: pcexp list, name: string, 
				     isVirtual: bool, isEndian: bool, isRecord, containsRecord, largeHeuristic: bool,
				     pred, comment: string option,...}:BU.pfieldty) = 
			 if not isVirtual then
			     let val predStringOpt = Option.map BU.constraintToString pred
				 val fullCommentOpt = BU.stringOptMerge(comment, predStringOpt)
			     in
				 [(name, P.makeTypedefPCT(BU.lookupTy (pty, repSuf, #repname)), fullCommentOpt )]
			     end
			 else []
		     fun genRepBrief (e,labelOpt) = 
			 let fun chk e = 
			         case e 
				 of PT.MARKexpression(loc, e) => chk e
				 | PT.IntConst i => if IntInf.<(i,IntInf.fromInt 0) orelse IntInf.>(i,IntInf.fromInt 255) then
				                       PE.error("In Punion "^name^": integer literals not supported.")
						    else ()
                                 | PT.ExprExt(PX.Pregexp e') => if not (Option.isSome labelOpt) then
							PE.error("In Punion "^name^": regular expression literals must have a label.")
							else ()
				 | PT.String s => ()
				 | _ => PE.error("In Punion "^name^": general expression literals not supported.")
			     in
				 []
			 end
		     val canonicalVariants = P.mungeFields genRepFull genRepBrief genRepMan variants
		     val canonicalVariants = if List.length canonicalVariants = 0
			                    then ((* PE.warn ("PUnion "^unionName^" does not contain any non-omitted fields\n"); *)
						 [(dummy, PL.uint32PCT, SOME "Dummy field inserted to avoid empty union")])
					    else canonicalVariants
		     val unionPD = P.makeTyDefUnionEDecl(canonicalVariants, unSuf name)
		     val unionDecls = cnvExternalDecl unionPD
                     val unionPCT = P.makeTypedefPCT(unSuf name)
                     val structFields = [(tag, tagPCT, NONE),
					 (value, unionPCT, NONE)]
		     val canonicalStructED = P.makeTyDefStructEDecl (structFields, repSuf name)
		     val (canonicalDecls, canonicalTid) = cnvRep(canonicalStructED, valOf (PTys.find (Atom.atom name)))
                     val canonicalPCT = P.makeTypedefPCT (repSuf name)			 

                     (* Process where clause *)
		     val (whereReadXs, whereIsXs) =
			 let val env = [(tag, tagPCT, P.fieldX(rep, tag)), (value, unionPCT, P.fieldX(rep, value))]
			     val wsubs = [(tag, P.fieldX(rep, tag)), (value, P.fieldX(rep, value))]
			     fun errMsg s = "Pwhere clause for "^ which ^" " ^name^" has type "^s^", expected type int"
			     fun cvtOne postCond = 
				 let val (isParseCheck, exp, bindingInfoList) = 
				     case postCond
				     of PX.General exp => (false, exp, env)
				     |  PX.ParseCheck exp => (true, exp, env
							           @ [(PNames.unionBegin, PL.posPCT, P.dotX(locX', PT.Id "b")),
							              (PNames.unionEnd,   PL.posPCT, P.dotX(locX', PT.Id "e"))])
				     val modexp = PTSub.substExps ((getBindings bindingInfoList) @ wsubs) exp
				 in
				     pushLocalEnv();
				     augTyEnv bindingInfoList;
				     ignore(List.map insTempVar cParams);
				     expEqualTy(exp, CTintTys, errMsg);
				     popLocalEnv();	
				     ([modexp], if isParseCheck then [] else [modexp] )
				 end
			     val (whereReadXss, whereIsXss) = ListPair.unzip(List.map cvtOne postCond)
			 in
			     (List.concat whereReadXss, List.concat whereIsXss)
			 end


                     (* Generate tag to string function *)
		     val tagFields' = List.map (fn(name, exp, comment) => (name, name, exp, comment)) tagFields
		     val toStringEDs = [genEnumToStringFun(tgSuf name, tagPCT, tagFields')]

                      (* Generate m_init function union case *)
                      val maskInitName = maskInitSuf name 
                      val maskFunEDs = genMaskInitFun(maskInitName, mPCT)

                      (* Generate init function, union case *)
                      val baseFunName = lookupMemFun (PX.Name name)
                      fun genInitEDs (suf, var, varPCT) = 
			  case #memChar unionProps
			  of TyProps.Static => 
			      [genInitFun(suf baseFunName, var, varPCT, [PT.Return PL.P_OK], true)]
			   | TyProps.Dynamic => 
			       let val zeroSs = [PL.bzeroS(PT.Id var, P.sizeofX(varPCT)),PT.Return PL.P_OK]
			       in
				   [genInitFun(suf baseFunName, var, varPCT, zeroSs, false)]
		               end
                      val initRepEDs = genInitEDs (initSuf, rep, canonicalPCT)
		      val initPDEDs = genInitEDs((initSuf o pdSuf), pd, pdPCT)

                      (* Generate cleanup function, union case *)
		      fun genCleanupEDs (suf, var, varPCT) = case #memChar unionProps
			  of TyProps.Static => [genInitFun(suf baseFunName, var, varPCT, [PT.Return PL.P_OK], true)]
			   | TyProps.Dynamic => 
			       let fun genCleanupFull ({pty as PX.Name tyName :PX.Pty, args : pcexp list, 
						    name:string, isVirtual:bool, isEndian:bool, isRecord, containsRecord, largeHeuristic:bool,
						    pred, comment:string option,...}:BU.pfieldty) = 
				    if (isVirtual andalso var = rep) orelse (TyProps.Static = lookupMemChar pty) then []
				    else let val baseFunName = lookupMemFun (PX.Name tyName)
					 in
					     [PT.CaseLabel(PT.Id name,
							   PT.Return(PT.Call(PT.Id(suf baseFunName),
									     [PT.Id pads, P.getUnionBranchX(var, name)])))]
					 end
				   fun genCleanupBrief e = []
				   fun genCleanupMan _ = []
				   val branchSs = P.mungeFields genCleanupFull 
				                   genCleanupBrief genCleanupMan variants
				   val allBranchSs = branchSs @ P.mkDefBreakCase(NONE)
				   val bodySs = [PT.Switch(P.arrowX(PT.Id var, PT.Id tag), PT.Compound allBranchSs),PT.Return PL.P_OK]
			       in
				   [genInitFun(suf baseFunName, var, varPCT, bodySs, false)]
		               end
			   
		      val cleanupRepEDs = genCleanupEDs(cleanupSuf, rep, canonicalPCT)
		      val cleanupPDEDs = genCleanupEDs(cleanupSuf o pdSuf, pd, pdPCT)

                      (* Generate Copy Function union case *)
                      fun genCopyEDs(suf, csuf, pdOpt, base, aPCT) = 
			  let val copyFunName = suf baseFunName
			      val cleanupFunName = csuf baseFunName
			      val dst = dstSuf base
			      val src = srcSuf base
			  in
			      case #memChar unionProps
			       of TyProps.Static =>
				  let val copySs = [PL.memcpyS(PT.Id dst, PT.Id src, P.sizeofX aPCT), PT.Return PL.P_OK]
				  in [genCopyFun(copyFunName, dst, src, aPCT, copySs, false)]
				  end
				|  TyProps.Dynamic => 
			           let fun genCopyFull ({pty as PX.Name tyName :PX.Pty, args : pcexp list, 
							name:string, isVirtual:bool, isEndian:bool, isRecord, containsRecord, largeHeuristic:bool,
							pred, comment:string option,...}:BU.pfieldty) = 
					   let val nestedCopyFunName = suf (lookupMemFun pty)
					   in
					       if (isVirtual andalso base = rep) 
					       then []
					       else (if (TyProps.Static = lookupMemChar pty)
						     then [PT.CaseLabel(PT.Id name,
									PT.Compound([PL.memcpyS(P.getUnionBranchX(dst, name),
												P.getUnionBranchX(src, name),
												P.sizeofEX(P.unionBranchX(src, name))),
										     PT.Return PL.P_OK]))]
						     else [PT.CaseLabel(PT.Id name,
									PT.Return(PT.Call(PT.Id(nestedCopyFunName),
											  [PT.Id pads, 
											   P.getUnionBranchX(dst, name),
											   P.getUnionBranchX(src, name)])))]
						    )
					   end
				       fun genCopyBrief e  = []
				       fun noop _ = []
				       val branchSs = P.mungeFields genCopyFull genCopyBrief noop variants
				       val branchSs = branchSs @ P.mkDefBreakCase(NONE)
				       val bodySs = [PT.Expr(PT.Call(PT.Id("PCGEN_UNION_"^pdOpt^"COPY_PRE"),
								     [PT.String(copyFunName), PT.Id(cleanupFunName)])),
						     PT.Switch (P.arrowX(PT.Id src, PT.Id tag), PT.Compound branchSs),
						     PT.Return PL.P_OK]
				   in
				       [genCopyFun(copyFunName, dst, src, aPCT, bodySs, false)]
				   end
			  end
		      val copyRepEDs = genCopyEDs(copySuf o repSuf, cleanupSuf o repSuf, "", rep, canonicalPCT)
		      val copyPDEDs  = genCopyEDs(copySuf o pdSuf, cleanupSuf o pdSuf, "PD_", pd,  pdPCT)

                     (* Generate read function *)

                     (* -- Some useful names/ids *)
		     val readName      = readSuf unionName
		     val writeName     = writeSuf name
		     val writeXMLName  = writeXMLSuf name
		     val fmtName       = fmtSuf name
		     val errTag        = PT.Id(errSuf unionName)
		     val repInit       = PT.Id(initSuf unionName)
		     val pdInit        = PT.Id((initSuf o pdSuf) unionName)
		     val repCopy       = PT.Id(copySuf unionName)
		     val pdCopy        = PT.Id((copySuf o pdSuf) unionName)
		     val repCleanup    = PT.Id(cleanupSuf unionName)
		     val pdCleanup     = PT.Id((cleanupSuf o pdSuf) unionName)
		     val addStat       = (if #memChar unionProps = TyProps.Static then "_STAT" else "")

                     (* -- Some helper functions *)

		     fun addVirt(isVirt) = (if isVirt then "_VIRT" else "")
		     fun addSFN(theTag)  = (if #memChar unionProps = TyProps.Static then "_STAT"
					    else (if theTag = !firstTag then "_FIRST" else "_NEXT"))
		     fun addSFNL(theTag) = (if #memChar unionProps = TyProps.Static then "_STAT"
					    else (if theTag = !firstTag then "_FIRST"
						  else (if theTag = !lastTag then "_LAST" else "_NEXT")))

		     fun uReadSetup (theTag)=
			 [PT.Expr(PT.Call(PT.Id(macStart^"_SETUP"^addStat),
					  [PT.String readName, PT.Id theTag, repCleanup, repInit, repCopy, pdCleanup, pdInit, pdCopy]))]
		     val xmlwriteCall : ParseTree.expression ref = ref(PT.Id("placeholder"))
		     val setEndArg = PT.Id(if hasParseCheck then setEndID else noopID)
		     fun uRead (theTag, predOpt, readCall) =
			 case predOpt of
			     NONE       => [PT.Expr(PT.Call(PT.Id(macStart^addSFNL(theTag)),
							    [PT.String readName, PT.String theTag, PT.Id theTag,
							     repCleanup, repInit, repCopy,
							     pdCleanup,  pdInit, pdCopy, readCall, !xmlwriteCall, setEndArg]))]
			   | SOME check => [PT.Expr(PT.Call(PT.Id(macStart^addSFNL(theTag)^"_CHECK"),
							    [PT.String readName, PT.String theTag, PT.Id theTag,
							     repCleanup, repInit, repCopy,
							     pdCleanup,  pdInit, pdCopy, readCall, !xmlwriteCall, setEndArg, check]))]
		     fun uReadManPre (theTag, isVirt) =
			 [PT.Expr(PT.Call(PT.Id(macStart^"_MAN"^addSFN(theTag)^addVirt(isVirt)^"_PRE"),
					  [PT.String readName, PT.Id theTag, repInit, pdInit]))]
		     fun uReadManPost (theTag, predOpt) =
			 case predOpt of
			     NONE       => [PT.Expr(PT.Call(PT.Id(macStart^"_MAN"^addStat^"_POST"),
							    [PT.String readName, repCopy, repCleanup, pdCopy, pdCleanup]))]
			   | SOME check => [PT.Expr(PT.Call(PT.Id(macStart^"_MAN"^addStat^"_POST_CHECK"),
							    [PT.String readName, repCopy, repCleanup, pdCopy, pdCleanup, check]))]
		     fun uReadFailed () =
			 [P.mkCommentS (checkIf^"Failed to match any branch of union "^unionName),
			  PT.Expr(PT.Call(PT.Id (macStart^"_CHECK_FAILED"),
					  [PT.String readName, PT.String unionName, errTag]))]
		     fun swReadPostCheck (theTag, predOpt) =
			 case predOpt of
			     NONE       => []
			   | SOME check => [PT.Expr(PT.Call(PT.Id "PCGEN_SWUNION_READ_POST_CHECK",
							    [PT.String readName, PT.Id theTag, errTag, check]))]
		     fun swRead (theTag, predOpt, readCall) =
			 [PT.Expr(PT.Call(PT.Id("PCGEN_SWUNION_READ"^addStat),
					  [PT.String readName, PT.Id theTag, errTag, repCleanup, repInit, repCopy,
					   pdCleanup, pdInit, pdCopy, readCall, setEndArg]))]
			 @ swReadPostCheck(theTag, predOpt) @ [PT.Break]
		     fun swReadManPre (theTag, isVirt) =
			 [PT.Expr(PT.Call(PT.Id("PCGEN_SWUNION_READ_MAN"^addStat^addVirt(isVirt)^"_PRE"),
					  [PT.String readName, PT.Id theTag, repCleanup, repInit, repCopy, pdCleanup, pdInit, pdCopy]))]
		     fun swReadManPost (theTag, predOpt) = swReadPostCheck(theTag, predOpt) @ [PT.Break]
		     fun swReadFailed () =
		         [P.mkCommentS ("Switch value does not match any branch of switched union "^unionName),
			  PT.Expr(PT.Call(PT.Id "PCGEN_SWUNION_READ_FAILED",
					  [PT.String readName, PT.String unionName, errTag]))]

		     fun readWhereCheck () =
		         if List.length whereReadXs = 0 then []
			 else let val needsEnd = if whereNeedsEnd then "_END" else ""
			          val isOptX = if fromOpt then P.trueX else P.falseX
				  val whereCheck
				    = case descOpt of NONE => macStart^"_WHERE"^needsEnd^"_CHECK"
						    | SOME descriminator => "PCGEN_SWUNION_READ_WHERE"^needsEnd^"_CHECK"
			      in
				  [P.mkCommentS "Checking Pwhere constraint",
				   PT.Expr(PT.Call(PT.Id whereCheck, [PT.String readName, (P.andBools whereReadXs), isOptX]))]
			      end
		     fun mkLabel(s) = [PT.Labeled(s, PT.Compound([]))]
		     fun branchesDoneLabel() = if isLongestMatch then [] else mkLabel("branches_done")
		     fun finalCheckLabel()   = mkLabel("final_check")
		     fun eorCheck() =
			 (if isRecord then [PT.Expr(PT.Call(PT.Id "PCGEN_FIND_EOR", [PT.String readName]))] else [])

                     fun genReadFull({pty :PX.Pty, args:pcexp list, name:string,
				     isVirtual:bool, isEndian:bool, isRecord, containsRecord, largeHeuristic:bool, 
				     pred, comment,...}:BU.pfieldty) = 
			 let val modPred = modUnionPred(unionName, name, allVars, pred, (!readSubList))
			     val readFieldName = BU.lookupTy(pty, readSuf, #readname)
	                     val tyname = P.makeTypedefPCT(BU.lookupTy (pty, repSuf, #repname))
			     val repX = unionRepX(rep, name, isVirtual, isLongestMatch)
			     val pdX = unionPdX(pd, name, isVirtual, isLongestMatch)
			     val modArgs = List.map (PTSub.substExps (!readSubList)) args
                             val () = checkParamTys(name, readFieldName, modArgs, 4, 0)
			     val () = pushLocalEnv()
			     val readCall
			       = PL.readFunX(readFieldName, PT.Id pads, P.addrX(P.fieldX(m, name)),
					     modArgs, P.addrX(pdX), P.addrX(repX))
			     val () = popLocalEnv()
			     val commentSs = [P.mkCommentS ("Read branch '"^name^"'")]
			 in
			     commentSs @ uRead(name, modPred, readCall)
			 end

		     fun readBriefUtil (r as (e:pcexp, labelOpt)) = 
			 case labelOpt of NONE => 
			    (case (getString r) of NONE => NONE
			     | SOME s => 
			       let val cmt = "Pliteral branch '"^s^"'.\n"
				   val repX = unionRepX(rep, s, true, isLongestMatch)
				   val readCall = PL.matchFunX(PL.cstrlitMatch, PT.Id pads, PT.String s, P.trueX)
			       in
				   SOME (cmt, s, readCall)
			       end)
                         | SOME label => 
			     let val reOpt = getRE e
				 val repX = unionRepX(rep, label, true, isLongestMatch)
			     in
				 case reOpt of NONE => 
				    (case extractString e of NONE => NONE (* error reported eariler *)
                                     | SOME s => 
				         let val cmt = "Pliteral branch '"^s^"'.\n"
					     val readCall = PL.matchFunX(PL.cstrlitMatch, PT.Id pads, PT.String s, P.trueX)
					 in
					     SOME(cmt,label,readCall)
					 end)
                                 | SOME e => (let val cmt = "Pliteral branch regexp.\n"
						  val readCall = PL.matchFunX(PL.reMatchFromString, PT.Id pads, e, P.trueX)
					      in 
						  SOME(cmt, label, readCall)
					      end)

			     end

                     fun genReadBrief e = 
			  case readBriefUtil e of 
			      NONE => []
			  | SOME (cmt, tag, readCall) => 
			     [P.mkCommentS cmt] @ uRead(tag, NONE, readCall)

                     fun genReadUnionEOR _ = []

		     fun genReadMan {tyname, name, args, isVirtual, expr, pred, comment} = 
			 let val modPred = modUnionPred(unionName, name, allVars, pred, (!readSubList))
			     val () = chkManArgs("Punion", unionName, tyname, name, args, (!readSubList))
			     val repX = unionRepX(rep, name, isVirtual, isLongestMatch)
			     val pdX = unionPdX(pd, name, isVirtual, isLongestMatch)
			     val pos = "ppos"
			     val needsPosition = PTSub.isFreeInExp([PNames.position], expr) 
			     val () = pushLocalEnv()
			     val () = if needsPosition then ignore(insTempVar(pos, PL.posPCT)) else ()
			     val exp = PTSub.substExps ((!readSubList) @ [(PNames.position, PT.Id pos)] ) expr
			     val assignS = genAssignMan(tyname, name, repX, exp)
			     val () = popLocalEnv()
			     val initSs = if needsPosition
					  then [PT.Compound[
					      	  P.varDeclS'(PL.posPCT, pos),
						  PL.alwaysGetPosS(PT.Id pads, PT.Id pos),
					          assignS]]
				          else [assignS]
			     val commentSs = [P.mkCommentS ("Pcompute branch '"^name^"'")]
			 in
			     commentSs @ uReadManPre(name, isVirtual) @ initSs @ uReadManPost(name, modPred)
			 end

		     fun chkCaseLabel eOpt = 
			 case eOpt of NONE => ()
		       | SOME e => expAssignTy(e, CTintTys, 
					      fn s=> (" case label for variant "^
						      name ^ " has type " ^ s ^
						      ", expected type int"))
		     fun genReadSwFull (eOpt,
			               ({pty :PX.Pty, args:pcexp list, name:string, 
				        isVirtual:bool, isEndian:bool, isRecord, containsRecord, largeHeuristic:bool, 
				        pred, comment,...}:BU.pfieldty)) = 
			 let val () = chkCaseLabel eOpt
			     val modPred = modUnionPred(unionName, name, allVars, pred, (!readSubList))
			     val readFieldName = BU.lookupTy(pty, readSuf, #readname)
	                     val tyname = P.makeTypedefPCT(BU.lookupTy (pty, repSuf, #repname))
			     val repX = unionRepX(rep, name, isVirtual, isLongestMatch)
			     val pdX = unionPdX(pd, name, isVirtual, isLongestMatch)
			     val modArgs = List.map (PTSub.substExps (!readSubList)) args
			     val () = checkParamTys(name, readFieldName, modArgs, 4, 0)
			     val () = pushLocalEnv()
			     val readCall = PL.readFunX(readFieldName, PT.Id pads, P.addrX(P.fieldX(m, name)),
							modArgs, P.addrX(pdX), P.addrX(repX))
			     val () = popLocalEnv()
			     val readSs = swRead(name, modPred, readCall)
			     val cmt = "Read branch '"^name^"'"
			     val swPart = case eOpt of NONE =>    P.mkDefCommentCase(cmt, SOME readSs)
						     | SOME e =>  P.mkCommentCase(e, cmt, SOME readSs)
			 in
			     swPart
			 end

                     fun genReadSwBrief (eOpt, e) = 
			 case readBriefUtil e of NONE => []
                         | SOME(cmt, tag, readCall) =>
                           (let val readSs = swRead(tag, NONE, readCall)
				val swPart = case eOpt of NONE =>    P.mkDefCommentCase(cmt, SOME readSs)
			                                | SOME e =>  P.mkCommentCase(e, cmt, SOME readSs)
			     in
				 swPart
			     end)

		     fun genReadSwMan (eOpt, {tyname, name, args, isVirtual, expr, pred, comment}) =
			 let val () = chkCaseLabel eOpt
			     val () = chkManArgs("Punion", unionName, tyname, name, args, (!readSubList))
			     val modPred = modUnionPred(unionName, name, allVars, pred, (!readSubList))
			     val repX = unionRepX(rep, name, isVirtual, isLongestMatch)
			     val pdX = unionRepX(pd, name, isVirtual, isLongestMatch)
			     val pos = "ppos"
			     val needsPosition = PTSub.isFreeInExp([PNames.position], expr)
			     val () = pushLocalEnv()
			     val () = if needsPosition then ignore(insTempVar(pos, PL.posPCT)) else ()
			     val exp = PTSub.substExps ((!readSubList) @ [(PNames.position, PT.Id pos)] ) expr
			     val assignS = genAssignMan(tyname, name, repX, exp)
			     val () = popLocalEnv()
			     val initSs = if needsPosition
					  then [PT.Compound[
					      	  P.varDeclS'(PL.posPCT, pos),
						  PL.alwaysGetPosS(PT.Id pads, PT.Id pos),
					          assignS]]
				          else [assignS]
			     val readS = swReadManPre(name, isVirtual) @ initSs @ swReadManPost(name, modPred)
			     val cmt = "Pcompute branch '"^name^"'"
			     val swPart = case eOpt of NONE   => P.mkDefCommentCase(cmt, SOME readS)
						     | SOME e => P.mkCommentCase(e, cmt, SOME readS)
			 in
			     swPart
			 end

                     fun genSwDefaultIfAbsent () = P.mkDefCase(SOME(swReadFailed()))

                     fun buildSwitchRead (descriminator) = 
			     let val () = expAssignTy(descriminator, CTintTys, 
						     fn s=> (" Descriminator for union "^
							     name ^ " has type " ^ s ^
							     ", expected type int"))
				 val readFields = mungeBVs genReadSwFull genReadSwBrief genReadSwMan cases variants
				 val augReadFields = if hasDefault then readFields 
				                     else readFields @ (genSwDefaultIfAbsent())
				 val bodyS = PT.Switch(descriminator, PT.Compound augReadFields)
			     in
				 [bodyS] @ readWhereCheck() @ branchesDoneLabel() @ eorCheck()
			     end

                     fun buildReadFun () = 
			 let val localDeclSs = if isLongestMatch
					       then [P.varDeclS'(canonicalPCT, pcgenName("trep")),
						     P.varDeclS'(pdPCT, pcgenName("tpd"))] 
						    @ omitVarDecls(omitVars)
					       else omitVarDecls(omitVars)
			     val localInitSs = omitVarInits(omitVars)
			     val coreSs = 
                               case descOpt of NONE => 
			         let val readFields = P.mungeFields genReadFull genReadBrief genReadMan variants  (* does type checking *)
				     val readBodySs = [PT.Compound(uReadSetup(!firstTag)
								   @ readFields
								   @ (uReadFailed())
								   @ branchesDoneLabel()
								   @ readWhereCheck()
								   @ finalCheckLabel()
								   @ eorCheck())]
				 in
				     readBodySs
				 end
			       | SOME descriminator => buildSwitchRead(descriminator)
			     val bodySs = localDeclSs @ localInitSs @ coreSs @ [BU.stdReturnS]
			 in
			     [PT.Compound bodySs]
			 end

                     (* -- Assemble read function union case *)
		     val _ = pushLocalEnv()                                        (* create new scope *)
		     (* add rep, possibly temp-rep to scope *)
		     val () = ignore(insTempVar(rep, P.ptrPCT canonicalPCT))
		     val () = ignore(insTempVar(pd, P.ptrPCT pdPCT))
		     val () = if isLongestMatch then ignore(insTempVar(pcgenName("trep"), canonicalPCT)) else ()
		     val cParams : (string * pcty) list = List.map mungeParam params
		     val xtraParamNames = #1(ListPair.unzip cParams)
		     val xtraParams = List.map PT.Id xtraParamNames
		     val xmlwriteArgs = [PT.Id pads, PT.Id sfstderr, PT.Id pd, PT.Id rep, PT.String name, P.intX 4] @ xtraParams 
		     val () = ignore(xmlwriteCall := PT.Call(PT.Id(ioSuf writeXMLName), xmlwriteArgs))
		     val () = ignore(List.map insTempVar omitVars)                 (* insert virtuals into scope *)
                     val () = ignore (List.map insTempVar cParams)                 (* add params for type checking *)
                     val () = ignore (insTempVar(setEndID, P.int))                   (* add phantom arg to conrol setting end location
										       to scope to fake out type checker. *)
		     val () = ignore (insTempVar(noopID, P.int))                   
		     val bodySs = buildReadFun() 
		     val readFunEDs = genReadFun(readName, cParams, mPCT, pdPCT, canonicalPCT, 
						 mFirstPCT, true, bodySs)
		     val _ = popLocalEnv()                                         (* remove scope *)

                     val readEDs = toStringEDs @ initRepEDs @ initPDEDs @ cleanupRepEDs @ cleanupPDEDs
			         @ copyRepEDs @ copyPDEDs @ maskFunEDs @ readFunEDs

                     (* Generate is function union case *)
                     val isName = PNames.isPref name
                     val bodySs = 	
			 let val agg = "isValid"
			     fun setAgg to   = P.assignS(PT.Id agg, to)
			     fun setAggSs to = PT.Compound[setAgg(to), PT.Break]

				     
			     fun mkPadsIsCase(pty, args, name, isVirt, pred) =
				 let val predListOption = Option.map P.getIsPredXs pred
				     val hasTest =
					 (case predListOption
					   of NONE => (case lookupPred pty of NONE => false | SOME fieldPred => true)
					    | SOME [] => false
					    | SOME e  => true)
				 in
				     if hasTest
				     then 
					 let val predXs  = case predListOption of NONE   => [] 
								      | SOME e => [PTSub.substExps (!postReadSubList) (P.andBools e)]
					     val fieldXs = case lookupPred pty of NONE           => []
										| SOME fieldPred => 
										  [PT.Call(PT.Id fieldPred,
											   [P.getUnionBranchX(rep, name)] @ args)]
					     val condX = P.andBools(predXs @ fieldXs)
					 in
					     P.mkBreakCase(PT.Id name, SOME [setAgg(condX)])
					 end
				     else
					 let val cmt = "PADS type has no is_ function and there is no user constraint"
					 in
					     P.mkCommentBreakCase(PT.Id name, cmt, NONE)
					 end
				 end
			     fun mkCtyIsCase(tyname, args, name, pred) =
				 case pred
				  of NONE =>
				     let val cmt = "Pcompute branch (with C type) : no user constraint"
				     in
					 P.mkCommentBreakCase(PT.Id name, cmt, NONE)
				     end
				   | SOME e =>
				     let val e = P.andBools (P.getIsPredXs e)
					 val condX  = PTSub.substExps (!postReadSubList) e
					 val cmt = "Pcompute branch (with C type)"
				     in
					 P.mkCommentBreakCase(PT.Id name, cmt, SOME [setAgg(condX)])
				     end
			     fun mkVirtIsCase(name, pred) =
				 let val addCmt = (case pred of NONE => "no user constraint" | SOME e => "cannot check user constraint")
				     val cmt = "Pomit branch: "^addCmt 
				 in
				     P.mkCommentBreakCase(PT.Id name, cmt, NONE)
				 end
			     fun getConFull({pty: PX.Pty, args: pcexp list, name: string, isVirtual: bool, 
					    isEndian: bool, isRecord, containsRecord, largeHeuristic: bool,
					    pred, comment: string option,...}:BU.pfieldty) = 
				 if isVirtual
				 then mkVirtIsCase(name, pred)
				 else mkPadsIsCase(pty, args, name, isVirtual, pred)
			     fun getConBrief e = 
				 case getString e of NONE => [] 
				     | SOME s => mkVirtIsCase(s, NONE)
			     fun getConMan ({tyname, name, args, isVirtual, expr, pred, comment} : BU.pmanty) =
				 if isVirtual
				 then mkVirtIsCase(name, pred)
				 else case isPadsTy tyname
				       of PTys.CTy => mkCtyIsCase(tyname, args, name, pred)
					| _        => mkPadsIsCase(getPadsName tyname, args, name, false, pred)
			     val fieldConCases = P.mungeFields getConFull getConBrief getConMan variants
			     val fieldConCases = fieldConCases
						 @ P.mkCommentBreakCase(PT.Id(errSuf name), "error case", SOME [setAgg(P.falseX)])
			     val fieldConS = [PT.Switch (P.arrowX(PT.Id rep, PT.Id tag), PT.Compound fieldConCases)]
			     val aggDecl = P.varDeclS(P.int, agg, P.trueX)
			     val whereConS = case whereIsXs of [] => [] | xl => [P.assignS(PT.Id agg, P.andBools whereIsXs)]
			     val constraintSs = fieldConS @ whereConS
			 in
                              [aggDecl]
			    @ constraintSs
			    @ [PT.Return (PT.Id agg)]
			 end

		      val isFunEDs = [genIsFun(isName, cParams, rep, canonicalPCT, bodySs) ]


                      (* Generate Accumulator functions (union case) *)
                      (* -- generate accumulator init, reset, and cleanup functions *)
		      fun genResetInitCleanup theSuf = 
			  let val theFun = (theSuf o accSuf) name
			      val theDeclSs = [P.varDeclS(PL.uint32PCT, nerr, P.zero)]
			      fun genAccTheFull ({pty :PX.Pty, args:pcexp list, name:string, 
						 isVirtual:bool, isEndian:bool, isRecord, containsRecord, largeHeuristic:bool,
						 pred, comment,...}:BU.pfieldty) = 
				  if isVirtual then []
				  else case lookupAcc(pty) of NONE => []
							    | SOME a => BU.chk3Pfun(theSuf a, [P.getFieldX(acc, name)])
			      fun genAccTheBrief e = []
			      val tagFields = P.mungeFields genAccTheFull genAccTheBrief 
				              (genAccTheMan theSuf) variants
			      val auxFields = BU.chk3Pfun(theSuf PL.intAct, [P.getFieldX(acc, tag)])
			      val theFields = auxFields @ tagFields
			      val theReturnS = BU.genReturnChk (PT.Id nerr)
			      val theBodySs = theDeclSs @ theFields @ [theReturnS]
			      val theFunED = BU.gen3PFun(theFun, [accPCT], [acc], theBodySs)
			  in
			      theFunED
			  end
		      val initFunED = genResetInitCleanup initSuf
		      val resetFunED = genResetInitCleanup resetSuf
                      val cleanupFunED = genResetInitCleanup cleanupSuf

                      (* -- generate accumulator function *)
                      (*  Perror_t T_acc_add (P_t* , T_acc* , T_pd*, T* ) *)
		      val addFun = (addSuf o accSuf) name
		      val addDeclSs = [P.varDeclS(PL.uint32PCT, nerr, P.zero), P.varDeclS'(PL.base_pdPCT, tpd)]
		      val initTpdSs = [P.assignS(P.dotX(PT.Id tpd, PT.Id errCode), 
						 P.condX(P.eqX(P.arrowX(PT.Id pd, PT.Id errCode),
							       PL.P_UNION_MATCH_FAILURE),
							 PL.P_UNION_MATCH_FAILURE, PL.P_NO_ERROR))]
		      val addTagSs = BU.chkAddFun(addSuf PL.intAct, P.getFieldX(acc, tag), P.addrX(PT.Id tpd), 
						  PT.Cast(P.ptrPCT PL.intPCT, P.getFieldX(rep, tag)))
		      fun fieldAddrX (base, name) = P.addrX(P.arrowX(PT.Id base, PT.Id name))

		      fun genCase (name, pty, initSs, pdX) = 
			  case lookupAcc(pty)
			   of NONE =>
			      P.mkCommentBreakCase(PT.Id name, "Type for branch does not have acc_add function: cannot accumulate", NONE)
			    | SOME a =>
			      (let val funName = addSuf a
				   val repX = P.getUnionBranchX(rep, name)
				   val caseSs = initSs @ BU.chkAddFun(funName, fieldAddrX(acc, name), pdX, repX)
			       in
				   P.mkBreakCase(PT.Id name, SOME caseSs)
			       end
		      (* end accOpt SOME case *))
		      fun genVirt (name) =
			  P.mkCommentBreakCase(PT.Id name, "Pomit branch: cannot accumulate", NONE)
		      fun genAccAddFull ({pty :PX.Pty, args:pcexp list, name:string, 
					 isVirtual:bool, isEndian:bool, isRecord, containsRecord, largeHeuristic:bool, 
					 pred, comment,...}:BU.pfieldty) = 
			  if isVirtual then genVirt(name)
			  else genCase(name, pty, [], P.getUnionBranchX(pd, name))
		      fun genAccAddBrief e = 
			  case getString e of NONE => [] | SOME s => genVirt(s)
		      fun genAccAddMan  {tyname, name, args, isVirtual, expr, pred, comment} = 
			  if isVirtual
			  then genVirt(name)
			  else case isPadsTy tyname 
				of PTys.CTy =>
				   P.mkCommentBreakCase(PT.Id name, "branch has C type: C type accum not implemented (yet)", NONE)
				 | _ =>
				   genCase(name, getPadsName tyname, [], P.getUnionBranchX(pd, name))
		      val nameBranchSs = P.mungeFields genAccAddFull genAccAddBrief genAccAddMan variants
		      val errBranchSs = P.mkCommentBreakCase(PT.Id(errSuf name), "error case", NONE)
		      val addBranchSs = nameBranchSs @ errBranchSs
                      val addVariantsSs = [PT.Switch (P.arrowX(PT.Id rep, PT.Id tag), PT.Compound addBranchSs)]
		      val addReturnS = BU.genReturnChk (PT.Id nerr)
                      val addBodySs = addDeclSs @ initTpdSs @ BU.ifNotPanicSkippedSs(addTagSs @ addVariantsSs) @ [addReturnS]
                      val addFunED = BU.genAddFun(addFun, acc, accPCT, pdPCT, canonicalPCT, addBodySs)

                      (* -- generate report function (internal and external)  punion *)
                      (*  Perror_t T_acc_report (P_t* , [Sfio_t * outstr], const char* prefix, 
		                                    const char * what, int nst, T_acc*  ) *)
		      val reportFun = (reportSuf o accSuf) name
		      val header = if fromOpt then "Opt tag" else "Union tag"
                      val reportTags = [BU.chkPrint(BU.callEnumPrint((ioSuf o reportSuf o mapSuf) PL.intAct,
						    PT.String header, PT.String "tag", P.intX ~1,
						    PT.Id((toStringSuf o tgSuf) name), P.getFieldX(acc, tag))),
					PL.sfprintf(PT.Id outstr, 
						    PT.String "\n[Describing each tag arm of %s]\n", 
						    [PT.Id prefix])]
		      fun genAccReportFull ({pty :PX.Pty, args:pcexp list, name:string, 
					    isVirtual:bool, isEndian: bool, isRecord, containsRecord, largeHeuristic:bool, 
					    pred, comment,...}:BU.pfieldty) = 
			  if isVirtual then [P.mkCommentS("Pomit branch: cannot accumulate")]
			  else cnvPtyForReport(reportSuf, ioSuf, pty, name, "branch")
                      fun genAccReportBrief e = []
		      val checkNoValsSs = [PT.Expr(PT.Call(PT.Id "PCGEN_UNION_ACC_REP_NOVALS", []))]
		      val reportVariants = P.mungeFields genAccReportFull genAccReportBrief 
			                      (genAccReportMan (reportSuf, ioSuf, "branch")) variants
                      val reportFunEDs = BU.genReportFuns(reportFun, which ^ " "^name, 
						       accPCT, acc, checkNoValsSs @ reportTags @ reportVariants)
		      val accumEDs = accED :: initFunED :: resetFunED :: cleanupFunED :: addFunED :: reportFunEDs


		      (* Generate histogram declarations, union case *)
		      val histEDs = Hist.genUnion (isPadsTy, getPadsName) (name, variants, canonicalPCT, pdPCT, fromOpt)

		      (* Generate cluster declarations, union case *)
		      val clusterEDs = Cluster.genUnion (isPadsTy, getPadsName) (name, variants, canonicalPCT, pdPCT, fromOpt)

                      (* Generate Write function union case *)
		      fun genWriteFull ({pty :PX.Pty, args:pcexp list, name:string, 
					isVirtual:bool, isEndian:bool, isRecord, containsRecord, largeHeuristic:bool, 
					pred, comment,...}:BU.pfieldty) = 
			  if isVirtual
			  then
			      P.mkCommentBreakCase(PT.Id name, "Pomit branch: cannot output", NONE)
                          else
			    let val writeFieldName = (bufSuf o writeSuf) (lookupWrite pty) 
				val caseSs = writeFieldSs(writeFieldName,
							  [P.getUnionBranchX(pd, name), P.getUnionBranchX(rep, name)] @ args,
							  true)
			    in
				P.mkBreakCase(PT.Id name, SOME caseSs)
			    end
		      fun genWriteBrief e = 
			  case getString e of NONE => [] | 
			      SOME s => let val writeFieldName = PL.cstrlitWriteBuf
					    val caseSs = writeFieldSs(writeFieldName, [PT.String s], true)
					in
					    P.mkBreakCase(PT.Id s, SOME caseSs)
					end
		      fun genWriteMan {tyname, name, args, isVirtual, expr, pred, comment} = 
			  (* Manifest fields do not need to be written *)
			  let val cmt = (if isVirtual
					 then "Pomit branch: cannot output"
					 else "Pcompute branch: format-preserving write functions do not output")
			  in
			      P.mkCommentBreakCase(PT.Id name, cmt, NONE)
			  end

		      fun genXMLWriteFull ({pty :PX.Pty, args:pcexp list, name:string, 
					   isVirtual:bool, isEndian:bool, isRecord, containsRecord, largeHeuristic:bool, 
					   pred, comment,...}:BU.pfieldty) = 
			  if isVirtual
			  then
			      P.mkCommentBreakCase(PT.Id name, "Pomit branch: cannot output", NONE)
                          else
			    let val writeXMLFieldName = (bufSuf o writeXMLSuf) (lookupWrite pty) 
				val caseSs = writeXMLFieldSs(writeXMLFieldName,
							     [P.getUnionBranchX(pd, name), P.getUnionBranchX(rep, name)],
							     PT.String(name), true, true, args)
			    in
				P.mkBreakCase(PT.Id name, SOME caseSs)
			    end


		      fun genXMLWriteBrief e = 
			  case getString e of NONE => [] | 
			      SOME s => let val writeXMLFieldName = PL.cstrlitWriteXMLBuf
					    val caseSs = writeXMLFieldSs(writeXMLFieldName, [PT.String s], PT.String s, true, true, [])
					in
					    P.mkBreakCase(PT.Id s, SOME caseSs)
					end
		      fun genXMLWriteMan {tyname, name, args, isVirtual, expr, pred, comment} = 
			  if isVirtual then
			      P.mkCommentBreakCase(PT.Id name, "Pomit branch: cannot output", NONE)
                          else
			    let val pty = isPadsTy tyname
			    in case isPadsTy tyname
				of PTys.CTy => 
				   let val cmt = "Pcompute branch with C type: XML write for C types not implemented (yet)"
				   in
				       P.mkCommentBreakCase(PT.Id name, cmt, NONE)
				   end
				 | _ =>
				   let val writeXMLFieldName = (bufSuf o writeXMLSuf) (lookupWrite (getPadsName tyname))
				       val cmt = "Pcompute branch"
				       val caseSs = writeXMLFieldSs(writeXMLFieldName,
								    [P.getUnionBranchX(pd, name), P.getUnionBranchX(rep, name)],
								    PT.String(name), true, true, args)
				   in
				       P.mkCommentBreakCase(PT.Id name, cmt, SOME caseSs)
				   end
			    end

		      fun genFmtFull ({pty :PX.Pty, args:pcexp list, name:string, 
					   isVirtual:bool, isEndian:bool, isRecord, containsRecord, largeHeuristic:bool, 
					   pred, comment,...}:BU.pfieldty) = 
			  if isVirtual
			  then
			      P.mkCommentBreakCase(PT.Id name, "Pomit branch: cannot output", NONE)
                          else
			    let val fmtFieldName = (bufSuf o fmtSuf) (lookupWrite pty) 
				val caseSs = fmtBranchSs(fmtFieldName,
							 [P.getFieldX(m, name), P.getUnionBranchX(pd, name), P.getUnionBranchX(rep, name)] @ args, 
						         PT.String name  )
			    in
				P.mkBreakCase(PT.Id name, SOME caseSs)
			    end

		      fun genFmtBrief e =
			  case getString e of
			      NONE => [] |
			      SOME s => let val cmt = "fmt does not output literals"
					in
					    P.mkCommentBreakCase(PT.Id s, cmt, NONE)
					end

		      fun genFmtMan {tyname, name, args, isVirtual, expr, pred, comment} = 
			  if isVirtual then
			      P.mkCommentBreakCase(PT.Id name, "Pomit branch: cannot output", NONE)
                          else
			    let val pty = isPadsTy tyname
			    in case isPadsTy tyname
				of PTys.CTy => 
				   let val cmt = "Pcompute branch with C type: format for C types not implemented (yet)"
				   in
				       P.mkCommentBreakCase(PT.Id name, cmt, NONE)
				   end
				 | _ =>
				   let val fmtFieldName = (bufSuf o fmtSuf) (lookupWrite (getPadsName tyname))
				       val cmt = "Pcompute branch"
				       val caseSs = fmtBranchSs(fmtFieldName,
								[P.getFieldX(m, name), P.getUnionBranchX(pd, name), P.getUnionBranchX(rep, name)] @ args ,
								PT.String(name))
				   in
				       P.mkCommentBreakCase(PT.Id name, cmt, SOME caseSs)
				   end
			    end

		      val nameBranchSs = P.mungeFields genWriteFull genWriteBrief genWriteMan variants
		      val nameXMLBranchSs = P.mungeFields genXMLWriteFull genXMLWriteBrief genXMLWriteMan variants
		      val nameFmtBranchSs = P.mungeFields genFmtFull genFmtBrief genFmtMan variants
		      val errBranchSs = P.mkCommentBreakCase(PT.Id(errSuf name), "error case", NONE)
		      val writeBranchSs = nameBranchSs @ errBranchSs
		      val writeXMLBranchSs = nameXMLBranchSs @ errBranchSs
		      val fmtBranchSs = nameFmtBranchSs @ errBranchSs
		      fun mkSwitch bdSs = [PT.Switch (P.arrowX(PT.Id rep, PT.Id tag), PT.Compound bdSs)]
                      val writeVariantsSs = mkSwitch writeBranchSs
                      val writeXMLVariantsSs = mkSwitch writeXMLBranchSs
		      val fmtBufFinalName = bufFinalSuf fmtName
		      val fmtVariantsSs = mkSwitch fmtBranchSs
		      val bodySs = writeVariantsSs
		      val bodyXMLSs = [PT.Expr(PT.Call(PT.Id "PCGEN_TAG_OPEN_XML_OUT", [PT.String(name)])),
				       PT.Expr(PT.Call(PT.Id "PCGEN_UNION_PD_XML_OUT", []))]
					@ writeXMLVariantsSs
					@ [PT.Expr(PT.Call(PT.Id "PCGEN_TAG_CLOSE_XML_OUT", []))]
		      val bodyFmtFinalSs =  [PL.fmtFinalInitStruct (PT.String fmtBufFinalName) ] @ fmtVariantsSs 
                      val (writeFunEDs,  fmtFunEDs) = genWriteFuns(name, "STANDARD", writeName, writeXMLName, fmtName, isRecord, isSource, cParams, 
									mPCT, pdPCT, canonicalPCT, bodySs, bodyXMLSs, bodyFmtFinalSs)

		      (***** union PADS-Galax *****)
	              (* In the XML representation of unions, each alternative is always the second child 
                         (index 1), after the <pd> child. *)

		      (* Note on field types: *)
		      (*   full field - normal field *)
		      (*   manifest field - Pcompute *)
		      (*   brief - literals *)
		      (* --YHM *)
						      
		      fun genCaseBranch (name, pty) =  [(name, SOME(lookupPadsx pty))] 

(* 		      fun genBranchFull ({pty :PX.Pty, args:pcexp list, name:string,  *)
(* 					 isVirtual:bool, isEndian:bool, isRecord, containsRecord, largeHeuristic:bool,  *)
(* 					 pred, comment,...}:BU.pfieldty) =  genCaseBranch (name, pty) *)
		      fun genBranchFull ({pty :PX.Pty, name:string,...}:BU.pfieldty) =  genCaseBranch (name, pty)
		      fun genBranchBrief e = case getString e of NONE => [] | SOME s => [(s,NONE)]
		      fun genBranchMan ({tyname, name, isVirtual,... }:BU.pmanty)= 
			  case isPadsTy tyname of PTys.CTy => [] | _ => 
			      if isVirtual then [(name, NONE)] else genCaseBranch(name, getPadsName tyname)

		      val branches : (string * string option) list = P.mungeFields genBranchFull genBranchBrief genBranchMan variants
 
		      fun genGalaxUnionKthChildFun(name,branches) =		
			  let val nodeRepTy = PL.nodeT
			      val returnTy = P.ptrPCT nodeRepTy
                              val cnvName = PNames.nodeKCSuf name 
			      val paramTys = [P.ptrPCT nodeRepTy, PL.childIndexT]
                              val paramNames = [G.self,G.idx]
                              val formalParams =  List.map P.mkParam (ListPair.zip(paramTys, paramNames))

				  (* What are these types being used for? *)
                                  (* To create fake var. decls that allow us to pass type names to macros -- YHM *)
			      val uniqueBranchTys = G.getUniqueTys (List.mapPartial (fn(x,y) => y ) branches)
			      val caseSs = List.map (G.makeUnionKCCase name)  branches

		              val bodySs = G.makeInvisibleDecls(name :: uniqueBranchTys, nil)
					   @ [G.macroUnionKCBegin(name)]
					   @ caseSs
					   @ [G.macroUnionKCEnd(),
					      P.returnS (G.macroUnionKCRet())]
			  in   
                              P.mkFunctionEDecl(cnvName, formalParams, PT.Compound bodySs, returnTy)
			  end
			      
		      fun genGalaxUnionKthChildNamedFun(name) =		
			  let val nodeRepTy = PL.nodeT
			      val returnTy = P.ptrPCT nodeRepTy
                              val cnvName = PNames.nodeKCNSuf name 
			      val paramTys = [P.ptrPCT nodeRepTy, PL.childIndexT, P.ccharPtr]
                              val paramNames = [G.self,G.idx,G.childName]
                              val formalParams =  List.map P.mkParam (ListPair.zip(paramTys, paramNames))

		              val bodySs = G.makeInvisibleDecls([name], nil)
					   @ [G.macroUnionKCN(name)]
					   @ [P.returnS (G.macroUnionKCNRet())]
			  in   
                              P.mkFunctionEDecl(cnvName, formalParams, PT.Compound bodySs, returnTy)
			  end
			      

		      val galaxEDs = [G.makeNodeNewFun(name),
				      G.makeCNInitFun(name, P.intX 2),
				      genGalaxUnionKthChildFun(name, branches),
				      genGalaxUnionKthChildNamedFun(name),
				      G.makeCNKCFun(name, P.intX 2), 
				      G.makeSNDInitFun(name),				      
				      G.makeUnionSNDKthChildFun(name,branches),
				      G.makeUnionPathWalkFun(name,branches),
		                      G.makeNodeVtable(name),
		                      G.makeCachedNodeVtable(name),
		                      G.makeSNDNodeVtable(name)] 
		      val initAsts = 		
			  asts
			  @ tagDecls
			  @ unionDecls
			  @ canonicalDecls
			  @ cnvExternalDecl mStructED
			  @ unionPDDecls
			  @ pdStructPDDecls
			  @ (emitWrite writeFunEDs)
		      val readAsts = 
		          let val () = pushLocalEnv()
			      val () = ignore (insTempVar(setEndID, P.int))                   (* add phantom arg to conrol setting end location
											       to scope to fake out type checker. *)
			      val () = ignore (insTempVar(noopID, P.int))                   
			      val readDecls = (emitRead readEDs)
			      val () = popLocalEnv()
			  in
			      readDecls
			  end

		 in
                     initAsts @ readAsts
		     @ (emitPred isFunEDs)
		     @ (emitAccum accumEDs)
		     @ (emitHist histEDs)
		     @ (emitCluster clusterEDs)
 		     @ (emitWrite fmtFunEDs)
                     @ (emitXML galaxEDs)
		 end
	  

	      and cnvPStruct {isAlt, name: string, isRecord, containsRecord, largeHeuristic, isSource, 
                              params: (pcty * pcdecr) list, fields: (pcty, pdty, pcdecr, pcexp) PX.PSField list, 
                              postCond} = 
	          let val structName = name
					   (* -- collection of expressions to be substituted for in constraints *)
					   (* -- efficiency could be improved with better representations *)
		      val structAlt = if isAlt then "ALT" else "STRUCT"
                      val readSubList : (string * pcexp) list ref = ref []
                      val postReadSubList : (string * pcexp) list ref = ref []
                      fun addReadSub (a : string * pcexp) = readSubList := (a:: (!readSubList))
                      fun addPostReadSub (a : string * pcexp) = postReadSubList := (a:: (!postReadSubList))
		      val (hasParseCheck, (allVars, omitNames, omitVars, readSubs, pdSubs, postReadSubs, tys, tyNames)) =
			  checkStructUnionFields("Pstruct", structName, false, fields)
		      val _ = List.map addReadSub readSubs
		      val _ = List.map addReadSub pdSubs
		      val _ = List.map addPostReadSub postReadSubs
		      val dummy = "_dummy"
		      val cParams : (string * pcty) list = List.map mungeParam params
		      val paramNames = #1(ListPair.unzip cParams)

                      (* Process in-line declarations *)
		      fun findOffset p [] n = NONE
                        | findOffset p (x::xs) n = if p x then SOME (n, x) else findOffset p xs (n+1)

                       fun cvtInPlaceFULL (f as {pty, args, name, pred, comment, size, arraypred,isVirtual, isEndian,
						 optPred, optDecl, arrayDecl,...}:BU.pfieldty) = 
			   if not (arrayDecl orelse optDecl) then 
			       (if Option.isSome optPred then PE.error ("Field "^name^" in "^structName^ " has option-style constraints "^
									"but is not an in-line option declaration.\n")
			        else ();
			       [([], PX.Full f)])
			   else
			      let val (offset, declName) = 
				       case findOffset (fn(nm,_) => nm = name) (ListPair.zip (allVars, tyNames)) 0
			               of SOME (n,(fname,tynm)) => (n,tynm)
				       | NONE => (PE.bug "Compiler bug"; (0, padsID name))
				  val otherFields = List.take (ListPair.zip (tys, List.map (PT.PointerDecr o PT.VarDecr) allVars), offset)
				  val params = params @ otherFields
				  val relSubs = List.take (readSubs, offset)
				  val otherArgs = List.map (fn x=>P.addrX x) (#2 (ListPair.unzip relSubs))
                                  val modRelSubs = List.map (fn (name,rep) => (name, P.starX (PT.Id name))) relSubs
				  val otherArgs =   List.map (fn x => P.addrX x) (List.take (#2(ListPair.unzip readSubs), offset))

				  fun doArray () = 
				      let val (modargs, modsize, modarraypred) = reduceArrayParts(modRelSubs, args, size, arraypred)
					  val arrayPX = {name=declName, baseTy = pty, params = params, 
							 isRecord = false, containsRecord = false, largeHeuristic = false, isSource = false,
							 args = modargs, sizeSpec=modsize, constraints=modarraypred, postCond = []}
				      in
					  (cnvPArray arrayPX, NONE)
				      end
				  fun doOpt () = 
				      let val modpred = Option.map (P.substPostCond modRelSubs) pred
					  val () = case modpred of NONE => () | _ => PE.error ("The form of constraint "^
											       "on opt field " ^name^
											       " is not currently supported.")
					  val modArgs = List.map (PTSub.substExps modRelSubs) args
					  val optPX = {name     = declName, params   = params, args     = modArgs,
						       isRecord = false, isSource = false, pred = optPred, baseTy   = pty}
				      in
					   (cnvPOpt optPX, modpred)
				      end
				  val (newAsts,modpred) = if arrayDecl then doArray() else doOpt ()
				  val sfield = {pty=PX.Name declName, args=(List.map (fn x=> PT.Id x) paramNames)@otherArgs, 
						name=name, isVirtual=isVirtual, isEndian=isEndian,
						isRecord=false, containsRecord=false, largeHeuristic=false, pred=modpred,
						comment=comment,optPred = NONE,
						optDecl = false, arrayDecl = false, size=NONE, arraypred=[]} : BU.pfieldty
			      in
				  [(newAsts, PX.Full sfield)]
	 		      end
                      fun cvtInPlaceBrief x = [([],PX.Brief x)]
                      fun cvtInPlaceMan   x = [([],PX.Manifest x)]

                      fun cvtRep fields = 
			  let val res = P.mungeFields cvtInPlaceFULL cvtInPlaceBrief cvtInPlaceMan fields
			      val (asts, newfields) = ListPair.unzip res
			  in
			      (List.concat asts, newfields)
			  end
		      val (asts, fields) = cvtRep fields
                      
					(* Generate CheckSet mask *)
		      fun genMFull ({pty: PX.Pty, args: pcexp list, name: string, 
				     isVirtual: bool, isEndian: bool, isRecord, containsRecord, largeHeuristic: bool,
				     pred, comment,...} : BU.pfieldty ) = 
			  [(name, P.makeTypedefPCT(BU.lookupTy (pty, mSuf, #mname)), SOME "nested constraints")]
			  @ (case pred of NONE => [] | SOME _ =>  [(mConSuf name, PL.base_mPCT, SOME "struct constraints")])
		      fun genMBrief e = []
		      fun genMMan {tyname : pcty, name, args, isVirtual, expr, pred, comment} = 
			  case isPadsTy tyname
			   of PTys.CTy => []
			    | _ => (let val pty : pty = getPadsName tyname
				    in 
					[(name, P.makeTypedefPCT(BU.lookupTy (pty, mSuf, #mname)), SOME "nested constraints")]
					@ (case pred of NONE => [] | SOME _ =>  [(mConSuf name, PL.base_mPCT, SOME "struct constraints")])
				    end)
		      val mFieldsNested = P.mungeFields genMFull genMBrief genMMan fields
		      val auxMFields = [(PNames.structLevel, PL.base_mPCT, NONE)]
		      val mFields = auxMFields @ mFieldsNested

		      val mFirstPCT = getFirstEMPCT mFields
		      val mStructED = P.makeTyDefStructEDecl (mFields, mSuf name)
		      val mDecls = cnvExternalDecl mStructED 
                      val mPCT = P.makeTypedefPCT (mSuf name)			  

						  (* Generate parse description *)
		      fun genEDFull ({pty: PX.Pty, args: pcexp list, name: string,  
				     isVirtual: bool, isEndian: bool, 
                                     isRecord, containsRecord, largeHeuristic: bool, 
				     pred, comment,...}: BU.pfieldty) = 
			  [(name, P.makeTypedefPCT(BU.lookupTy (pty, pdSuf, #pdname)), NONE)]
		      fun genEDBrief e = []
					     (* fun genEDMan e = [] *) (* XXX use the one above *)
		      val auxEDFields = [(pstate, PL.flags_t, NONE), (nerr, PL.uint32PCT, NONE),
					 (errCode, PL.errCodePCT, NONE), (loc, PL.locPCT, NONE)]
                                        @ (if isGalax() then [(identifier, PL.idPCT, SOME "Identifier tag for Galax")] else [])
		      val pdFields = auxEDFields @ (P.mungeFields genEDFull genEDBrief genEDMan fields)
		      val pdStructED = P.makeTyDefStructEDecl (pdFields, pdSuf name)
		      val (pdDecls, pdTid) = cnvCTy pdStructED
                      val pdPCT = P.makeTypedefPCT (pdSuf name)

						   (* Generate accumulator type *)
		      fun genAccFull ({pty: PX.Pty, args: pcexp list, name: string, 
				      isVirtual: bool, isEndian: bool, 
				      isRecord, containsRecord, largeHeuristic: bool,
				      pred, comment: string option,...}: BU.pfieldty) = 
			  if not isVirtual then 
			      let val predStringOpt = Option.map BU.constraintToString pred
			          val fullCommentOpt = BU.stringOptMerge(comment, predStringOpt)
				  val accOpt = lookupAcc pty
			      in
				  case accOpt of NONE => []
					       | SOME acc => 
  						 [(name, P.makeTypedefPCT acc, fullCommentOpt )]
			      end
			  else []
		      fun genAccBrief e = []
		      val accFields = P.mungeFields genAccFull genAccBrief genAccMan fields
		      val auxAccFields = [(nerr, PL.uint32AccPCT, NONE)]
		      val accED = P.makeTyDefStructEDecl (auxAccFields @ accFields, accSuf name)
                      val accPCT = P.makeTypedefPCT (accSuf name)			 

						    (* Struct: Calculate and insert type properties into type table *)
		      fun genTyPropsFull ({pty: PX.Pty, args: pcexp list, name: string, 
					  isVirtual: bool, isEndian: bool, isRecord, containsRecord, 
					  largeHeuristic: bool, pred, comment:string option,...}: BU.pfieldty) = 
			  let val ftyName = P.tyName pty
			      val mc = lookupMemChar pty
			      val ds = computeDiskSize (name, paramNames, pty, args)
                              val supportsEndian = lookupEndian pty
			      val isE1 = if isEndian andalso not supportsEndian
				         then (PE.error ("Endian annotation not supported on fields of type "
							 ^(P.tyName pty)^"\n"); false)
				         else true
			      val isE2 = if isEndian andalso not (Option.isSome pred)
				         then (PE.error ("Endian annotations require constraints ("^name^")\n"); false)
				         else true
			      val contR = lookupContainsRecord pty 
			      val lH = lookupHeuristic pty
			  in [{diskSize = ds, memChar = mc, endian = isEndian andalso isE1 andalso isE2, 
                               isRecord = isRecord, containsRecord = contR, 
			       largeHeuristic = lH, labels = [SOME (name, ftyName, (paramNames, args), isVirtual, comment )]}] 
                          end
		      fun genTyPropsBrief (e,labelOpt) = 
			  (* assume field is correct; error checking done in genReadBrief below *)
                              (* conservative analysis: variable expresions with type char could also lead to size of 1,0*)
			      let fun getStaticSize eX =
			              case eX of PT.MARKexpression(l, e) => getStaticSize e
					       | PT.String s => TyProps.mkSize(String.size s, 0)
					       | PT.IntConst i => TyProps.mkSize(1,0)
					       | PT.ExprExt (PX.Pregexp e) => TyProps.Variable
					       | _ => TyProps.Variable
				  val diskSize = getStaticSize e
				  val () = case labelOpt of NONE => () | SOME s => 
				      (PE.error ("Pstruct "^ name ^" contains a literal renaming, which is not supported."))
			      in
				  [{diskSize = diskSize, memChar = TyProps.Static, 
				    endian = false, isRecord = false, 
				    containsRecord = false, largeHeuristic = false, labels = [NONE]}]
		              end

		      val tyProps = P.mungeFields genTyPropsFull genTyPropsBrief genTyPropsMan fields
                      val {diskSize, memChar, endian, isRecord=_, containsRecord, largeHeuristic, labels} = 
 			  List.foldl (PTys.mergeTyInfo TyProps.add) PTys.minTyInfo tyProps

		      val compoundDiskSize = TyProps.Struct ((ListPair.zip(List.rev labels, 
									   (List.map (fn (r : PTys.sTyInfo) => #diskSize r) tyProps))))
		      val numArgs = List.length params
		      val structProps = buildTyProps(name, PTys.Struct, diskSize, compoundDiskSize, memChar, endian, 
                                                     isRecord, containsRecord, largeHeuristic, isSource, pdTid, numArgs)
                      val () = PTys.insert(Atom.atom name, structProps)

					  (* Struct: Generate canonical representation *)
		      fun genRepFull ({pty: PX.Pty, args: pcexp list, name: string, 
				      isVirtual: bool, isEndian: bool, isRecord, containsRecord, largeHeuristic: bool,
				      pred, comment:string option,...}: BU.pfieldty) = 
			  if not isVirtual then 
			      let val predStringOpt = Option.map BU.constraintToString pred
			          val fullCommentOpt = BU.stringOptMerge(comment, predStringOpt)
			      in
				  [(name, P.makeTypedefPCT(BU.lookupTy (pty, repSuf, #repname)), fullCommentOpt )]
			      end
			  else []
		      fun genRepBrief e = []
		      val canonicalFields = P.mungeFields genRepFull genRepBrief genRepMan fields
		      val canonicalFields = if List.length canonicalFields = 0 
			                    then ((* PE.warn ("PStruct "^structName^" does not contain any non-omitted fields\n"); *)
						  [(dummy, PL.uint32PCT, SOME "Dummy field inserted to avoid empty struct")])

					    else canonicalFields
		      val canonicalStructED = P.makeTyDefStructEDecl (canonicalFields, repSuf name)
		      val (canonicalDecls, canonicalTid) = cnvRep(canonicalStructED, valOf (PTys.find (Atom.atom name)))

                      val canonicalPCT = P.makeTypedefPCT (repSuf name)			 

							  (* Generate Init Function struct case *)
		      val baseFunName = lookupMemFun (PX.Name name)
                      fun genInitEDs(suf, base, aPCT) = case #memChar structProps
							 of TyProps.Static => [genInitFun(suf baseFunName, base, aPCT, [PT.Return PL.P_OK], true)]
							  | TyProps.Dynamic => 
							    let val zeroSs = [PL.bzeroS(PT.Id base, P.sizeofX(aPCT)),PT.Return PL.P_OK]
							    in
								[genInitFun(suf baseFunName, base, aPCT, zeroSs, false)]
							    end
		      val initRepEDs = genInitEDs (initSuf o repSuf, rep, canonicalPCT)
                      val initPDEDs  = genInitEDs (initSuf o pdSuf,  pd, pdPCT)
                      fun genCleanupEDs isPD (suf, base, aPCT) = 
			  case #memChar structProps
			      of TyProps.Static => [genInitFun(suf baseFunName, base, aPCT, [PT.Return PL.P_OK], true)]
			    | TyProps.Dynamic => 
				  let fun doDynamic (isVirtual, pty, name) = 
				      if not isVirtual then
					  if TyProps.Static = lookupMemChar pty then []
					  else let val baseFunName = lookupMemFun (pty)
					       in
						   [PT.Expr(
							    PT.Call(PT.Id(suf baseFunName),
								    [PT.Id pads, 
								     P.addrX(P.arrowX(
										      PT.Id base,
										      PT.Id name))]))]
					       end
				      else []
				      fun genInitFull ({pty: PX.Pty, args: pcexp list, 
						       name: string, isVirtual: bool, isEndian: bool,
						       isRecord, containsRecord, largeHeuristic: bool,
						       pred, comment: string option,...}:BU.pfieldty) = 
					  doDynamic(isVirtual, pty, name)
				      fun genInitBrief _ = []
				      fun genInitMan {tyname, name, args, isVirtual, expr, pred, comment} = 
					  if isPD then [] 
					  else (case isPadsTy tyname 
						    of PTys.CTy => [] 
						  | _ =>  doDynamic(isVirtual, getPadsName tyname, name))
				      val eltSs = P.mungeFields genInitFull genInitBrief genInitMan fields
				      val bodySs = eltSs @ [PT.Return PL.P_OK]
				  in
				      [genInitFun(suf baseFunName, base, aPCT, bodySs, false)]
				  end
		      val cleanupRepEDs = genCleanupEDs false (cleanupSuf o repSuf, rep, canonicalPCT)
                      val cleanupPDEDs  = genCleanupEDs true (cleanupSuf o pdSuf,  pd, pdPCT)

							(* Generate Copy Function struct case *)
                      fun genCopyEDs isPD (suf, base, aPCT) = 
			  let val copyFunName = suf baseFunName
			      val dst = dstSuf base
			      val src = srcSuf base
			      val copySs = [PL.memcpyS(PT.Id dst, PT.Id src, P.sizeofX aPCT),
					    PT.Return PL.P_OK]
			  in
			      case #memChar structProps
			       of TyProps.Static => [genCopyFun(copyFunName, dst, src, aPCT, copySs, false)]
				|  TyProps.Dynamic => 
			           let val haveMemcpy : bool ref = ref false
				       val multiField : bool ref = ref false
				       val memcpySrcLoc : ParseTree.expression ref = ref(PT.Id("placeholder"))
				       val memcpyDstLoc : ParseTree.expression ref = ref(PT.Id("placeholder"))
				       val memcpySize   : ParseTree.expression ref = ref(PT.Id("placeholder"))
				       val cmtStr       : string ref = ref "" 
				       fun addMemcpyField(s) = 
					   if !haveMemcpy
					   then ignore(memcpySize := (P.plusX(!memcpySize, P.sizeofEX(P.fieldX(src, s)))),
						       cmtStr     := !cmtStr^", "^s,
						       multiField := true)
					   else ignore(haveMemcpy := true,
						       memcpySrcLoc  := P.getFieldX(src, s),
						       memcpyDstLoc  := P.getFieldX(dst, s),
						       memcpySize    := P.sizeofEX(P.fieldX(src, s)),
						       cmtStr        := s)
				       fun genMemcpy() =
					   if !haveMemcpy
					   then let val mcpy  = PL.memcpyS(!memcpyDstLoc, !memcpySrcLoc,!memcpySize)
						    val multi = !multiField
						    val _    = (haveMemcpy := false, multiField := false)
						in if multi
						   then [P.mkCommentS("Copy fields "^(!cmtStr)),
							 mcpy]
						   else [mcpy]
						end
					   else []
				       fun doCopy (isVirtual, pty, name) = 
					   if isVirtual then []
					   else let val nestedCopyFunName = suf (lookupMemFun pty)
						in if TyProps.Static = lookupMemChar pty then
						       let val _ = ignore(addMemcpyField(name))
						       in []
						       end
						   else
						       genMemcpy() @
						       [PT.Expr(
							PT.Call(PT.Id(nestedCopyFunName),
								[PT.Id pads, 
								 P.getFieldX(dst, name),
								 P.getFieldX(src, name)]))]
						end
				       fun genCopyFull ({pty as PX.Name tyName: PX.Pty, args: pcexp list, 
							name: string, isVirtual: bool, isEndian: bool, 
							isRecord, containsRecord, largeHeuristic: bool,
							pred, comment: string option,...}:BU.pfieldty) = 
					   doCopy(isVirtual, pty, name)
				       fun noop _ = []
				       fun genCopyMan {tyname, name, args, isVirtual, expr, pred, comment} = 
					   if isPD then [] else
					   case isPadsTy tyname 
					    of PTys.CTy => [] 
                                             | _ =>  doCopy(isVirtual, getPadsName tyname, name)
				       val fieldCpySs = P.mungeFields genCopyFull noop genCopyMan fields
				       val bodySs = fieldCpySs @ genMemcpy() @ [PT.Return PL.P_OK]
				   in
				       [genCopyFun(copyFunName, dst, src, aPCT, bodySs, false)]
				   end
			  end
		      val copyRepEDs = genCopyEDs false (copySuf o repSuf, rep, canonicalPCT)
		      val copyPDEDs  = genCopyEDs true (copySuf o pdSuf, pd,  pdPCT)


						  (* Generate m_init function struct case *)
                      val maskInitName = maskInitSuf name 
                      val maskFunEDs = genMaskInitFun(maskInitName, mPCT)


						     (* Generate read function struct case *)

						     (* -- Some useful names/ids *)
		      val readName = readSuf name
		      val repCleanup = PT.Id(cleanupSuf structName)
		      val pdCleanup  = PT.Id((cleanupSuf o pdSuf) structName)
		      val addStat    = (if #memChar structProps = TyProps.Static then "_STAT" else "")

					   (* -- Some helper functions *)

		      fun stReadPre (name) =
			  [PT.Expr(PT.Call(PT.Id("PCGEN_"^structAlt^"_READ_PRE"),
					   [PT.String readName, PT.Id name]))]

		      fun stReadPostCheck (name, predOpt, isEndian, swapBytesLoc) =
			  case predOpt of
			      NONE       => []
			    | SOME check => let val endAdd = (if isEndian then "_ENDIAN" else "")
						val swapBytesCall = (if isEndian then [PL.swapBytesX(swapBytesLoc)] else [])
						val macroCall = PT.Expr(PT.Call(PT.Id("PCGEN_"^structAlt^"_READ_POST_CHECK"^endAdd),
										[PT.String readName, PT.Id name]
										@ swapBytesCall @ [check]))
					    in
						[macroCall]
					    end

		      val first = ref true
		      val next  = ref 0

		      fun genReadFull ({pty: PX.Pty, args: pcexp list, name: string,
				       isVirtual: bool, isEndian: bool, isRecord, containsRecord, largeHeuristic: bool,
				       pred, comment, ...}:BU.pfieldty) =
			  let val firstNext = if isAlt then "" else (if !first then (first := false; "_FIRST") else "_NEXT")
			      val modPred = modStructPred(structName, name, allVars, pred, (!readSubList))
			      val readFieldName = BU.lookupTy(pty, readSuf, #readname)
			      val repX = structRepX(rep, name, isVirtual)
			      val modArgs = List.map (PTSub.substExps (!readSubList)) args
                              val () = checkParamTys(name, readFieldName, modArgs, 4, 0)
			      val comment = ("Read field '"^name^"'"^ 
					     (if isEndian then ", doing endian check" else ""))
			      val commentS = P.mkCommentS (comment)
			      val readCallX = PL.readFunX(readFieldName, 
							  PT.Id pads,
							  P.addrX(P.fieldX(m, name)),
							  modArgs,
							  P.addrX(P.fieldX(pd, name)),
							  P.addrX repX)
			      val macroNm = "PCGEN_"^structAlt^"_READ"^firstNext
			      val macroArgs = [PT.String readName, PT.Id name, readCallX]
			      val (checkAdd, checkArgs) =
				  case modPred of NONE => ("", [])
						| SOME predX => ("_CHECK", [predX])
			      val (endAdd, endArgs) =
				  if isEndian then ("_ENDIAN", [PL.swapBytesX(repX)]) else ("", [])
			      val setEndArgs = [PT.Id(if hasParseCheck then setEndID else noopID)]

			      val macroCallS = PT.Expr(PT.Call(PT.Id(macroNm^checkAdd^endAdd), macroArgs @ checkArgs @ endArgs @ setEndArgs))
			  in
			      [commentS, macroCallS]
			  end

		      fun genReadBrief (eOrig, labelOpt) =
			  let val firstNext = if isAlt then "" else (if !first then (first := false; "_FIRST") else "_NEXT")
			      val e = PTSub.substExps (!readSubList) (unMark eOrig)
			      val eptopt = getRE e
			      val (expTy, expAst) = cnvExpression e
			      val cstr = CExptoString expAst

			      fun getCharComment eX =
				  let val cval = #1(evalExpr eX)
				      val defaultStr = CExptoString expAst
				  in
				      case cval of NONE => defaultStr
						 | SOME e => ("'" ^ (Char.toString(Char.chr (IntInf.toInt e))) ^"'"
					  		      handle _ => defaultStr)
				  end
			      fun getStrLen eX =
				  case eX of PT.String s => P.intX (String.size s)
					   | _ => PL.strLen eX
			  in
			      if Option.isSome eptopt then
				  [P.mkCommentS("Read delimeter field: "^cstr),
				   PT.Expr(PT.Call(PT.Id("PCGEN_"^structAlt^"_READ"^firstNext^"_REGEXP"),
						   [PT.String readName, e])) ]
			      else if CTisIntorChar expTy then
				  [P.mkCommentS("Read delimter field: "^getCharComment(e)),
				   PT.Expr(PT.Call(PT.Id("PCGEN_"^structAlt^"_READ"^firstNext^"_CHAR_LIT"),
						   [PT.String readName, e])) ]
			      else if CTisString expTy then
				  [P.mkCommentS("Read delimeter field: "^cstr),
				   PT.Expr(PT.Call(PT.Id("PCGEN_"^structAlt^"_READ"^firstNext^"_STR_LIT"),
						   [PT.String readName, e, getStrLen(e)])) ]
			      else
				  (PE.error ("Currently only characters, strings, and regular expressions "^
					     "supported as delimiters. Delimiter type: "^ (CTtoString expTy));
				   [P.mkCommentS("XXX Cannot read delimeter field: "^cstr),
				    P.mkCommentS("Currently only characters, strings, and regular expressions "^
					         "supported as delimiters.")])
			  end

			      (* Given manifest representation, generate operations to set representation *)
		      fun genReadMan {tyname, name, args, isVirtual, pred, expr, comment} =
			  let val firstNext = if isAlt then "" else (if !first then (first := false; "_FIRST") else "_NEXT")
			      val modPred = modStructPred(structName, name, allVars, pred, (!readSubList))
			      val () = chkManArgs("Pstruct", structName, tyname, name, args, (!readSubList))
			      val repX = structRepX(rep, name, isVirtual)
			      val pos = "ppos"
			      val needsPosition = PTSub.isFreeInExp([PNames.position], expr) 
			      val () = pushLocalEnv()
			      val () = if needsPosition then ignore(insTempVar(pos, PL.posPCT)) else ()
			      val exp = PTSub.substExps ((!readSubList) @ [(PNames.position, PT.Id pos)] ) expr
			      val assignSs = stReadPre(name) @ [genAssignMan(tyname, name, repX, exp)]
			      val () = popLocalEnv()
			      val initSs = if needsPosition
					   then [PT.Compound([
						 P.varDeclS'(PL.posPCT, pos),
						 PL.alwaysGetPosS(PT.Id pads, PT.Id pos)] @ assignSs)]
					   else assignSs
			      val commentSs = [P.mkCommentS ("Pcompute field '"^name^"'")]
			  in
			      [PT.Compound(commentSs @ initSs @ stReadPostCheck(name, modPred, false, repX))]
			  end

		      fun getIsExp postCon = 
			  let fun cvtOne one = case one
                       				of PX.ParseCheck _ => []
						 |  PX.General e => [PTSub.substExps (!postReadSubList) e]
			      val exps = (List.concat(List.map cvtOne postCon))
			  in
			      P.andBools exps
			  end

		      fun checkPostConstraint loc postCon = 
			  let val (exp, bindingInfoList) = 
				  case postCon 
				   of PX.ParseCheck exp => (exp, [(PNames.structBegin, PL.posPCT, P.dotX(PT.Id loc, PT.Id "b")),
								  (PNames.structEnd,   PL.posPCT, P.dotX(PT.Id loc, PT.Id "e"))])
		       		    |  PX.General    exp => (exp, [])
			      val exp = PTSub.substExps (!postReadSubList) exp
			      val () = augTyEnv bindingInfoList
			      val () = expEqualTy(exp, CTintTys, 
					       fn s=> ("Pwhere clause for Pstruct "^
						       name ^ " does not have integer type"))
			      val exp = PTSub.substExps (getBindings bindingInfoList)  exp
			  in
			      exp
			  end
			  
		      fun genCheckPostConstraint postCon = 
			  let val strLocD = P.varDeclS'(PL.locPCT, tloc)
			      val locX = PT.Id tloc
			      val condXs = List.map (checkPostConstraint tloc) postCon
			      val condX = P.andBools condXs
			      val getBeginLocS = PL.getLocBeginS(PT.Id pads, locX)
			      val getEndLocSs = [PL.getLocEndMinus1S(PT.Id pads, locX)]
			      val initSs = if (List.length condXs) > 0 then [strLocD, getBeginLocS] else []
			      val reportErrSs = getEndLocSs
						@ reportStructErrorSs(PL.P_USER_CONSTRAINT_VIOLATION, false, locX)
						@ [PL.userErrorS(PT.Id pads, P.addrX(locX), P.fieldX(pd, errCode),
								 readName, PT.String("Pwhere clause for Pstruct "^
										     name ^ " violated"), [])]
			      val condSs = 
                                  if List.length condXs = 0 then []
				  else
				      [P.mkCommentS ("Checking Pwhere for Pstruct "^ name),
				       PT.IfThen(
				       P.andX( PL.mTestSemCheckX(P.fieldX(m, PNames.structLevel)), P.notX condX),
				       PT.Compound reportErrSs)]
			  in
			      (initSs, condSs)
			  end
			      

			      (* -- Assemble read function *)
		      val _ = pushLocalEnv()                                        (* create new scope *)
		      val () = ignore (insTempVar(rep, P.ptrPCT canonicalPCT))      (* add rep to scope *)
		      val () = ignore (insTempVar(pd, P.ptrPCT pdPCT))              (* add pd to scope *)
		      val () = ignore (insTempVar(m,  P.ptrPCT mPCT))               (* add m to scope *)
		      val () = ignore (List.map insTempVar omitVars)                (* insert virtuals into scope *)
                      val () = ignore (List.map insTempVar cParams)                 (* add params for type checking *)
                      val () = ignore (insTempVar(setEndID, P.int))                   (* add phantom arg to conrol setting end location
										       to scope to fake out type checker. *)
		      val () = ignore (insTempVar(noopID, P.int))                   
		      val readFields = P.mungeFields genReadFull genReadBrief genReadMan fields  
		                                   (* does type checking *)
		      val augReadFields = if isAlt
					  then [PT.Compound([PT.Expr(PT.Call(PT.Id "PCGEN_ALT_READ_BEGIN", [PT.String readName]))]
							    @ readFields
							    @ [PT.Expr(PT.Call(PT.Id "PCGEN_ALT_READ_END", [PT.String readName]))])]
					  else readFields
		      val (postLocSs, postCondSs) = genCheckPostConstraint postCond
		      val eorCheck =
			  if isRecord then [PT.Expr(PT.Call(PT.Id "PCGEN_FIND_EOR", [PT.String readName]))] else []
		      val _ = popLocalEnv()                                         (* remove scope *)
		      val localDeclSs = omitVarDecls(omitVars)
		      val localInitSs = omitVarInits(omitVars)
		      val bodyS = localDeclSs @ postLocSs @ localInitSs @ augReadFields @ postCondSs @ eorCheck
		      val bodySs = if 0 = List.length localDeclSs andalso 0 = List.length postCond
				   then bodyS else [PT.Compound bodyS]
		      val bodySs = bodySs @ [BU.stdReturnS]

		      val readFunEDs = genReadFun(readName, cParams, mPCT, pdPCT, canonicalPCT, 
						  mFirstPCT, true, bodySs)

                      val readEDs = initRepEDs @ initPDEDs @ cleanupRepEDs @ cleanupPDEDs
			            @ copyRepEDs @ copyPDEDs @ maskFunEDs @ readFunEDs
		      (* convert readEDs now, with mapping of field name -> void* for each field in a temporary scope *)
		      val () = pushLocalEnv()
		      val () = ignore(List.map (fn(name) => insTempVar(name, P.voidPtr)) allVars)
                      val () = ignore (insTempVar(setEndID, P.int))                   (* add phantom arg to conrol setting end location
										       to scope to fake out type checker. *)
		      val () = ignore (insTempVar(noopID, P.int))                   
		      val readDecls = (emitRead readEDs)
		      val () = popLocalEnv()

										(* Generate is function struct case *)
		      val isName = PNames.isPref name
		      val predX = 
			  let fun getConM name pred = 
  			          case pred of NONE => [] 
			           | SOME e => if P.isFreeInPostCond omitNames e
					       then (PE.warn ("Omitted field passed to constraint "^
							      "for field "^name^". "^
							      "Excluding constraint in "^ isName); [])
					       else P.getIsPredXs(P.substPostCond (!postReadSubList) e)


			      fun getConFull({pty: PX.Pty, args: pcexp list, name: string, isVirtual: bool, 
					     isEndian: bool, isRecord, containsRecord, largeHeuristic: bool,
					     pred, comment: string option,...}:BU.pfieldty) = 
			          if isVirtual then [] 
                                  else let val predXs  = getConM name pred
					   val fieldXs = case lookupPred pty of NONE => []
									      | SOME fieldPred => 
										if List.exists(fn a=>PTSub.isFreeInExp(omitNames, a)) args
										then (PE.warn ("Omitted field passed to nested field type for field "^name^". "^
											       "Excluding call to "^fieldPred ^" from "^ isName); [])
										else let val modArgs = List.map(PTSub.substExps (!postReadSubList)) args
										     in
											 [PT.Call(PT.Id fieldPred, [P.getFieldX(rep, name)] @ modArgs)]
										     end
				       in
					   fieldXs @ predXs 
				       end
			      fun getConMan  {tyname, name, args, isVirtual, pred, expr, comment} = getConM name pred
			      val fieldConS = P.mungeFields getConFull (fn x=>[]) getConMan fields
			      val whereConS = [getIsExp postCond]
			      val constraintSs = List.map (PTSub.substExps (!postReadSubList)) (fieldConS @ whereConS)
			  in
			      P.andBools constraintSs
			  end
		      val bodySs = [PT.Return predX]
		      val isFunEDs = [genIsFun(isName, cParams, rep, canonicalPCT, bodySs) ]


					 (* Generate Accumulator functions struct case *)
					 (* -- generate accumulator init, reset, cleanup, and report functions *)
		      fun genResetInitCleanup theSuf = 
			  let val theFun = (theSuf o accSuf) name
			      val auxFields = BU.chk3Pfun(theSuf PL.uint32Act, [P.getFieldX(acc, nerr)])
			      fun genAccTheFull ({pty: PX.Pty, args: pcexp list, name: string, 
						 isVirtual: bool, isEndian: bool, 
						 isRecord, containsRecord, largeHeuristic: bool,
						 pred, comment,...}:BU.pfieldty) = 
				  if not isVirtual then
				      case lookupAcc(pty) of NONE => []
							   | SOME a => BU.callFun(theSuf a, acc, name,[])
				  else []
			      fun genAccTheBrief e = []

			      val theDeclSs = [P.varDeclS(PL.uint32PCT, nerr, P.zero)]
			      val theFields = P.mungeFields genAccTheFull genAccTheBrief (genAccTheMan theSuf) fields
			      val theReturnS = BU.genReturnChk (PT.Id nerr)
			      val theBodySs = theDeclSs @ auxFields @ theFields @ [theReturnS]
			      val theFunED = BU.gen3PFun(theFun, [accPCT], [acc], theBodySs)
			  in
			      theFunED
			  end
		      val initFunED = genResetInitCleanup initSuf
		      val resetFunED = genResetInitCleanup resetSuf
                      val cleanupFunED = genResetInitCleanup cleanupSuf


							     (* -- generate accumulator function *)
							     (*  Perror_t T_acc_add (P_t* , T_acc* , T_pd*, T* , ) *)
		      val addFun = (addSuf o accSuf) name
		      val addDeclSs = [P.varDeclS(PL.uint32PCT, nerr, P.zero),  P.varDeclS'(PL.base_pdPCT, tpd)]
		      val initTpdSs = [P.assignS(P.dotX(PT.Id tpd, PT.Id errCode), PL.P_NO_ERROR)]

		      fun genAccAddFull ({pty: PX.Pty, args: pcexp list, name: string, 
					 isVirtual: bool, isEndian: bool, 
					 isRecord, containsRecord, largeHeuristic: bool,
					 pred, comment,...}:BU.pfieldty) = 
			  if isVirtual then []
			  else case lookupAcc(pty) 
			       of NONE => []
	                       | SOME a => BU.chkAddFun(addSuf a, P.getFieldX(acc,name), P.getFieldX(pd,name), P.getFieldX(rep,name))
                      fun genAccAddBrief e = []

		      fun genAccAddMan {tyname, name, args, isVirtual, expr, pred, comment} = 
			  if isVirtual then [] else
			  case isPadsTy tyname 
                           of PTys.CTy => [] 
			    | _  => (let val pty = getPadsName tyname
				     in
					 BU.chkAddFun(addSuf(lookupAcc' pty), P.getFieldX(acc,name), P.addrX(PT.Id tpd), P.getFieldX(rep, name))
				     end)

		      val addNErrSs = BU.chkAddFun(addSuf PL.uint32Act, P.getFieldX(acc, nerr),
						P.addrX(PT.Id tpd),
						P.getFieldX(pd, nerr))
		      val addFieldsSs = P.mungeFields genAccAddFull genAccAddBrief genAccAddMan fields
		      val addReturnS = BU.genReturnChk (PT.Id nerr)
                      val addBodySs = addDeclSs @ initTpdSs @ addNErrSs @ BU.ifNotPanicSkippedSs(addFieldsSs) @ [addReturnS]
                      val addFunED = BU.genAddFun(addFun, acc, accPCT, pdPCT, canonicalPCT, addBodySs)

					      (* -- generate report function pstruct *)
					      (*  Perror_t T_acc_report (P_t* , T_acc* , const char* prefix , ) *)
		      val reportFun = (reportSuf o accSuf) name
		      val checkNoValsSs = [PT.Expr(PT.Call(PT.Id "PCGEN_STRUCT_ACC_REP_NOVALS", []))]
		      val reportNerrSs = [BU.chkPrint(
 				          PL.errAccReport(PT.Id pads, PT.Id outstr, PT.String "Errors", 
							  PT.String "errors", P.intX ~1, P.getFieldX(acc, nerr))) ]
		      val headerSs = [PL.sfprintf(PT.Id outstr, 
						  PT.String "\n[Describing each field of %s]\n", 
						  [PT.Id prefix])]

		      fun genAccReportFull ({pty: PX.Pty, args: pcexp list, name: string, 
					    isVirtual: bool, isEndian: bool, 
					    isRecord, containsRecord, largeHeuristic: bool,
					    pred, comment,...}:BU.pfieldty) = 
			  if not isVirtual then cnvPtyForReport(reportSuf, ioSuf, pty, name, "field")
			  else []
                      fun genAccReportBrief e = []
		      val reportFields = (P.mungeFields genAccReportFull genAccReportBrief 
						      (genAccReportMan (reportSuf, ioSuf, "field")) fields)
                      val reportFunEDs = BU.genReportFuns(reportFun, "struct "^name, accPCT, acc,
							  checkNoValsSs @ reportNerrSs @ headerSs @ reportFields)

		      val accumEDs = accED :: initFunED :: resetFunED :: cleanupFunED :: addFunED :: reportFunEDs

		      (* Generate histogram declarations, struct case *)
		      val histEDs = Hist.genStruct (isPadsTy, getPadsName) (name, fields, canonicalPCT, pdPCT)


		      (* Generate cluster declarations, struct case *)
		      val clusterEDs = Cluster.genStruct (isPadsTy, getPadsName) (name, fields, canonicalPCT, pdPCT)

													 
	              (* Generate Write function struct case *)
		      val writeName = writeSuf name
		      val writeXMLName = writeXMLSuf name
		      val fmtName = fmtSuf name
		      fun getLastField fs = 
			  let fun f'([], s) = s
                                | f'(f::fs, s) = 
			          (case f of PX.Full{name,...} => f'(fs, SOME f)
					   | PX.Brief _ => f'(fs, SOME f)
			                   | PX.Manifest _ => f'(fs, s) (* end case *))
			  in
			      f' (fs, NONE)
			  end
		      fun matchesLast (f, NONE) = false
                        | matchesLast (PX.Full f, SOME (PX.Full f')) = #name f = #name f'
                        | matchesLast (f as PX.Brief _, f' as SOME (PX.Brief _)) = false
                        | matchesLast _ = false

		      val lastField = getLastField fields

		      fun genWriteForM (fSpec, pty, args, name, isRecord, pdX, wrapSsFn) = 
			  let val writeFieldName = (bufSuf o writeSuf) (lookupWrite pty) 
			      fun checkOmitted args = List.exists(fn a=>PTSub.isFreeInExp(omitNames, a)) args
			      fun warnOmitted writeFieldName = 
				  (PE.warn ("Omitted field passed to nested field type for field "^name^". "^
					    "Excluding call to "^writeFieldName ^" from "^ writeName); [])
			  in
			      if checkOmitted(args)
			      then warnOmitted(writeFieldName)
			      else
				  let val modArgs = List.map(PTSub.substExps (!postReadSubList)) args
				      val adjustLengths = isRecord orelse  not (matchesLast(fSpec, lastField))
				  in
				      wrapSsFn(
				      writeFieldSs(writeFieldName, [pdX, P.getFieldX(rep, name)] @ modArgs, adjustLengths))
				  end
			  end

		      fun genWriteFull (f as ({pty: PX.Pty, args: pcexp list, name: string, 
					      isVirtual: bool, isEndian: bool, 
  					      isRecord=_, containsRecord, largeHeuristic: bool,
					      pred, comment,...}:BU.pfieldty)) = 
			  if isVirtual then [] (* have no rep of virtual (omitted) fields, so can't print *)
                          else genWriteForM(PX.Full f, pty, args, name, isRecord, P.getFieldX(pd, name), fn x=>x)

		      fun genWriteMan (m as {tyname, name, args, isVirtual, expr, pred, comment}) = 
			  if isVirtual then [] else
			  case isPadsTy tyname of PTys.CTy => [] 
						| _ => let val padsName = getPadsName tyname
						       in
							   genWriteForM(PX.Manifest m, padsName, args, name, false(*manifest fields can't be records*),
									P.addrX(PT.Id tpd),
								     fn ss => [PT.Compound(
									       [P.varDeclS'(P.makeTypedefPCT(BU.lookupTy(padsName, pdSuf, #pdname)), tpd),
										P.assignS(P.dotX(PT.Id tpd, PT.Id errCode),
											  P.arrowX(PT.Id pd, PT.Id errCode))]
									       @ ss)])
						       end



		      fun genWriteBrief (eOrig, labelOpt) = 
			  if PTSub.isFreeInExp(omitNames, eOrig) then
			      (PE.warn ("Omitted field passed to literal field. Omitted literal write from "^writeName); [])
			  else
			      let val e = PTSub.substExps (!postReadSubList) (unMark eOrig)
				  val reOpt = getRE e
				  val (expTy, expAst) = cnvExpression e
				  val isString = CTisString expTy
				  val writeFieldName = if Option.isSome reOpt then PL.reWriteBuf
				                       else if isString then PL.cstrlitWriteBuf
						       else PL.charlitWriteBuf
				  val adjustLengths = isRecord orelse not(matchesLast(PX.Brief (e, labelOpt), lastField))
				  val writeFieldSs = writeFieldSs(writeFieldName, [e], adjustLengths)
			      in
				  writeFieldSs
			      end


		      fun genXMLWriteForM (fSpec, pty, args, name, isRecord, pdX, wrapSsFn) = 
			  let val writeXMLFieldName = (bufSuf o writeXMLSuf) (lookupWrite pty) 
			      fun checkOmitted args = List.exists(fn a=>PTSub.isFreeInExp(omitNames, a)) args
			      fun warnOmitted writeXMLFieldName = 
				  (PE.warn ("Omitted field passed to nested field type for field "^name^". "^
					    "Excluding call to "^writeXMLFieldName ^" from "^ writeName); [])
			  in
			      if checkOmitted(args)
			      then warnOmitted(writeXMLFieldName)
			      else
				  let val modArgs = List.map(PTSub.substExps (!postReadSubList)) args
				  in
				      wrapSsFn(
				      writeXMLFieldSs(writeXMLFieldName, [pdX, P.getFieldX(rep, name)],
						      PT.String(name), true, true, modArgs))
				  end
			  end

		      fun genXMLWriteFull (f as ({pty: PX.Pty, args: pcexp list, name: string, 
						 isVirtual: bool, isEndian: bool, 
  						 isRecord=_, containsRecord, largeHeuristic: bool,
						 pred, comment,...}:BU.pfieldty)) = 
			  if isVirtual then [] (* have no rep of virtual (omitted) fields, so can't print *)
                          else genXMLWriteForM(PX.Full f, pty, args, name, isRecord, P.getFieldX(pd, name), fn x=>x)

		      fun genXMLWriteMan (m as {tyname, name, args, isVirtual, expr, pred, comment}) = 
			  if isVirtual then [] else
			  case isPadsTy tyname of PTys.CTy => [] 
						| _ => let val padsName = getPadsName tyname
						       in 
							   genXMLWriteForM(PX.Manifest m, padsName, args, name, false(*manifest fields can't be records*),
									   P.addrX(PT.Id tpd),
									fn ss => [PT.Compound(
										  [P.varDeclS'(P.makeTypedefPCT(BU.lookupTy(padsName, pdSuf, #pdname)), tpd),
										   P.assignS(P.dotX(PT.Id tpd, PT.Id errCode),
											     P.arrowX(PT.Id pd, PT.Id errCode))]
										  @ ss)])
						       end

		      fun genXMLWriteBrief e = []
		      fun genXMLWriteBrief_NotUsed e = 
			  if PTSub.isFreeInExp(omitNames, e) then
			      (PE.warn ("Omitted field passed to literal field. Omitted literal write from "^writeName); [])
			  else
			      let val e = PTSub.substExps (!postReadSubList) e
				  val reOpt = getRE e
				  val (expTy, expAst) = cnvExpression e
				  val isString = CTisString expTy
				  val writeXMLFieldName = if Option.isSome reOpt then PL.reWriteXMLBuf
							  else if isString then PL.cstrlitWriteXMLBuf
							  else PL.charlitWriteXMLBuf
				  val litKind = if Option.isSome reOpt then "regexp"
				                else if isString then "string_lit"
						else "char_lit"
				  val wrXMLFieldSs = writeXMLFieldSs(writeXMLFieldName, [e], PT.String(litKind), true, true, [])
			      in
				  wrXMLFieldSs
			      end


		      fun genFmtForM (fSpec, pty, args, name, isRecord, pdX, wrapSsFn) = 
			  let val fmtFieldName = (bufSuf o fmtSuf) (lookupWrite pty) 
			      fun checkOmitted args = List.exists(fn a=>PTSub.isFreeInExp(omitNames, a)) args
			      fun warnOmitted fmtFieldName = 
				  (PE.warn ("Omitted field passed to nested field type for field "^name^". "^
					    "Excluding call to "^fmtFieldName ^" from "^ fmtName); [])
			  in
			      if checkOmitted(args)
			      then warnOmitted(fmtFieldName)
			      else
				  let val modArgs = List.map(PTSub.substExps (!postReadSubList)) args
				  in
				      wrapSsFn(
				      fmtFieldSs(fmtFieldName, 
						 [P.getFieldX(m, name),pdX, P.getFieldX(rep, name)] @ modArgs))
				  end
			  end

		      fun genFmtFull (f as ({pty: PX.Pty, args: pcexp list, name: string, 
					      isVirtual: bool, isEndian: bool, 
  					      isRecord=_, containsRecord, largeHeuristic: bool,
					      pred, comment,...}:BU.pfieldty)) = 
			  if isVirtual then [] (* have no rep of virtual (omitted) fields, so can't print *)
                          else genFmtForM(PX.Full f, pty, args, name, isRecord, P.getFieldX(pd, name), fn x=>x)

		      fun genFmtMan (m as {tyname, name, args, isVirtual, expr, pred, comment}) = 
			  if isVirtual then [] else
			  case isPadsTy tyname of PTys.CTy => [] 
						| _ => let val padsName = getPadsName tyname
						       in
							   genFmtForM(PX.Manifest m, padsName, args, name, false(*manifest fields can't be records*),
									P.addrX(PT.Id tpd),
								     fn ss => [PT.Compound(
									       [P.varDeclS'(P.makeTypedefPCT(BU.lookupTy(padsName, pdSuf, #pdname)), tpd),
										P.assignS(P.dotX(PT.Id tpd, PT.Id errCode),
											  P.arrowX(PT.Id pd, PT.Id errCode))]
									       @ ss)])
						       end


		      val _ = pushLocalEnv()       (* We convert literals to determine which write function to use*)
(* unneeded?          val cParams : (string * pcty) list = List.map mungeParam params (* so we have to add params to scope *) *)
                      val () = ignore (List.map insTempVar cParams)  (* add params for type checking *)
		      val wrFieldsSs = P.mungeFields genWriteFull genWriteBrief genWriteMan fields
		      val wrXMLFieldsSs = P.mungeFields genXMLWriteFull genXMLWriteBrief genXMLWriteMan fields
		      val fmtBufFinalName = bufFinalSuf fmtName
		      val fmtFieldsFinalSs = [PL.fmtFinalInitStruct (PT.String fmtBufFinalName) ] @ (P.mungeFields genFmtFull (fn x => []) genFmtMan fields) @ [PL.fmtFixLast()]
		      val _ = popLocalEnv()                                         (* remove scope *)
		      val bodySs = wrFieldsSs
		      val bodyXMLSs = [PT.Expr(PT.Call(PT.Id "PCGEN_TAG_OPEN_XML_OUT", [PT.String(name)])),
				       PT.Expr(PT.Call(PT.Id "PCGEN_STRUCT_PD_XML_OUT", []))]
				      @ wrXMLFieldsSs
				      @ [PT.Expr(PT.Call(PT.Id "PCGEN_TAG_CLOSE_XML_OUT", []))]
                      val (writeFunEDs, fmtFunEDs) = genWriteFuns(name, "STANDARD", writeName, writeXMLName, fmtName, isRecord, isSource, cParams, 
								       mPCT, pdPCT, canonicalPCT, bodySs, bodyXMLSs, fmtFieldsFinalSs)

						    (***** struct PADS-Galax *****)

		      fun genFieldFull ({pty: PX.Pty, name: string, isVirtual: bool, ...}:BU.pfieldty) = 
			  if isVirtual then [] else [(name, lookupPadsx(pty), false)]
		      fun genFieldBrief e = []
		      fun genFieldMan {tyname, name, args, isVirtual, expr, pred, comment} =
			  if isVirtual then [] else
			  case isPadsTy tyname
                           of PTys.CTy => []
			    | _ => (let val pty = getPadsName tyname
				    in [(name, lookupPadsx pty, true)]
                                    end)

		      val localFields = P.mungeFields genFieldFull genFieldBrief genFieldMan fields

						    (* counting Full and Computed fields *)
		      fun countFieldFull ({isVirtual: bool,...}:BU.pfieldty) =
			  if isVirtual then [] else [1]
		      fun countFieldMan m = []
		      fun countFieldBrief e = [1]
		      val countFields = List.length (P.mungeFields countFieldFull countFieldMan countFieldBrief fields) 

		      fun genGalaxStructKthChildFun(name,fields) =		
			  let val nodeRepTy = PL.nodeT
			      val returnTy = P.ptrPCT nodeRepTy
                              val cnvName = PNames.nodeKCSuf name 
			      val paramTys = [P.ptrPCT nodeRepTy, PL.childIndexT]
                              val paramNames = [G.self,G.idx]
                              val formalParams =  List.map P.mkParam (ListPair.zip(paramTys, paramNames))

			      val uniqueFieldTys = G.getUniqueTys (List.map (fn(x,y,z) => y) fields)
			      val fieldNames = map (fn (n,_,_) => n) fields						   
		              val bodySs = G.makeInvisibleDecls(name :: uniqueFieldTys, fieldNames)
					   @ [G.macroStructKCBegin(name)]
					   @ (List.map (G.makeKCCase name) (G.enumerate fields))
					   @ [G.macroStructKCEnd(List.length fields),
					      P.returnS (G.macroStructKCRet())]
			  in   
                              P.mkFunctionEDecl(cnvName, formalParams, PT.Compound bodySs, returnTy)
			  end
			      
		      fun genGalaxStructKthChildNamedFun(name,fields) =		
			  let val nodeRepTy = PL.nodeT
			      val returnTy = P.ptrPCT nodeRepTy
                              val cnvName = PNames.nodeKCNSuf name 
			      val paramTys = [P.ptrPCT nodeRepTy, PL.childIndexT, P.ccharPtr]
                              val paramNames = [G.self,G.idx,G.childName]
                              val formalParams =  List.map P.mkParam (ListPair.zip(paramTys, paramNames))

			      val fieldNames = map (fn (n,_,_) => n) fields						   
		              val bodySs = G.makeInvisibleDecls([name], nil)
					   @ [G.macroStructKCN(name,fieldNames)]
					   @ [P.returnS (G.macroStructKCNRet())]
			  in   
                              P.mkFunctionEDecl(cnvName, formalParams, PT.Compound bodySs, returnTy)
			  end
			      
		      val galaxEDs = [G.makeNodeNewFun(name),
				      G.makeCNInitFun(name, P.intX (countFields + 1)),
				      genGalaxStructKthChildFun(name, localFields),
				      genGalaxStructKthChildNamedFun(name, localFields),
				      G.makeCNKCFun(name, P.intX (countFields + 1)), 
				      G.makeSNDInitFun(name),				      
				      G.makeStructSNDKthChildFun(name,localFields),
				      G.makeStructPathWalkFun(name,localFields),
		                      G.makeNodeVtable(name),
		                      G.makeCachedNodeVtable(name),
		                      G.makeSNDNodeVtable(name)] 


		  in 
		      asts
 		      @ canonicalDecls (* converted earlier because used in typechecking constraints *)
                      @ mDecls
                      @ pdDecls
	              @ readDecls
	              @ (emitPred isFunEDs)
                      @ (emitAccum accumEDs)
                      @ (emitHist histEDs)
                      @ (emitCluster clusterEDs)
                      @ (emitWrite writeFunEDs)
   		      @ (emitWrite fmtFunEDs)
  		      @ (emitXML galaxEDs)
		  end


	  fun cnvPEnum  {name:string, params: (pcty * pcdecr) list, 
			 isRecord, containsRecord, largeHeuristic, isSource, prefix = eprefix : string option,
			 members: (string * string option * pcexp option * string option) list } =
	      let val baseTy = PL.strlit
		  val baseEM = mSuf baseTy
		  val basePD = pdSuf baseTy
		  val baseMatchFun = PL.strlitMatch
		  val cParams : (string * pcty) list = List.map mungeParam params
		  val paramNames = #1(ListPair.unzip cParams)
		  val () = if (List.length cParams) > 0 then PE.warn ("Parameters are not supported for Penums") else ()
                  fun mungeMembers (name, fromXOpt, expOpt, commentOpt) = 
		      let val expr = case expOpt of NONE =>   PT.EmptyExpr | SOME e => e
			  val prefix = case eprefix of NONE => "" | SOME p => p
		      in
			  case fromXOpt of NONE => (prefix^name, name, expr, commentOpt)
                          | SOME fromName =>       (prefix^name, fromName, expr, commentOpt)
			                     (* enum label, on disk name, value of enum label, comment *)
			   
		      end

		  val enumFields = List.map mungeMembers members
		  val enumFieldsforTy = List.map (fn(ename, dname, expr, comment) => (ename, expr, comment)) enumFields


                  (* generate CheckSet mask *)
		  val baseMPCT = PL.base_mPCT
		  val mED      = P.makeTyDefEDecl (baseMPCT, mSuf name)
		  val mDecls   = cnvExternalDecl mED
		  val mPCT     = P.makeTypedefPCT (mSuf name)		

                  (* generate parse description *)
		  val baseEDPCT = PL.base_pdPCT
		  val pdED      = P.makeTyDefEDecl (baseEDPCT, pdSuf name)
		  val (pdDecls, pdTid) = cnvCTy pdED
		  val pdPCT     = P.makeTypedefPCT (pdSuf name)		

		  (* Generate accumulator type *)
		  val accED     = P.makeTyDefEDecl (PL.intAccPCT, accSuf name)
		  val accPCT    = P.makeTypedefPCT (accSuf name)		

                  (* Calculate and insert type properties into type table for enums. *)
                  val labels = List.map #2 enumFields
		  val ds = if List.length labels > 1 then
		              let val len = String.size (hd labels)
			      in
				  if List.all (fn s => len = String.size s) labels
				      then TyProps.mkSize (len, 0)
				  else TyProps.Variable
			      end
			   else TyProps.mkSize (0,0)
		  val numArgs = List.length params
                  val enumProps = buildTyProps(name, PTys.Enum, ds, TyProps.Enum ds,
					       TyProps.Static, true, isRecord, containsRecord,
					       largeHeuristic, isSource, pdTid, numArgs)
		  val () = PTys.insert(Atom.atom name, enumProps)

                  (* enums: generate canonical representation *)
		  val canonicalED = P.makeTyDefEnumEDecl(enumFieldsforTy, repSuf name)
		  val (canonicalDecls, canonicalTid) = cnvRep(canonicalED, valOf (PTys.find (Atom.atom name)))
		  val canonicalPCT = P.makeTypedefPCT(repSuf name)

		  (* Generate enum to string function *)
		  val toStringEDs = [genEnumToStringFun(name, canonicalPCT, enumFields)]

		  (* Generate Init function (enum case) *)
		  val initFunName = lookupMemFun (PX.Name name)
		  fun genInitEDs (suf, argName, aPCT) =  (* always static *)
		      [genInitFun(suf initFunName, argName, aPCT, [PT.Return PL.P_OK], true)]
		  val initRepEDs = genInitEDs (initSuf, rep, canonicalPCT)
		  val initPDEDs  = genInitEDs ((initSuf o pdSuf), pd, pdPCT)
		  val cleanupRepEDs = genInitEDs (cleanupSuf, rep, canonicalPCT)
		  val cleanupPDEDs  = genInitEDs ((cleanupSuf o pdSuf), pd, pdPCT)

                  (* Generate Copy Function enum case *)
		  fun genCopyEDs(suf, base, aPCT) = 
		      let val copyFunName = suf initFunName
			  val dst = dstSuf base
			  val src = srcSuf base
			  val bodySs = [PL.memcpyS(PT.Id dst, PT.Id src, P.sizeofX aPCT),
					PT.Return PL.P_OK]
		      in
			  [genCopyFun(copyFunName, dst, src, aPCT, bodySs, false)]
		      end
		  val copyRepEDs = genCopyEDs(copySuf o repSuf, rep, canonicalPCT)
		  val copyPDEDs  = genCopyEDs(copySuf o pdSuf,  pd,  pdPCT)
				   
				   
                  (* Generate m_init function enum case *)
                  val maskInitName = maskInitSuf name 
                  val maskFunEDs = genMaskInitFun(maskInitName, mPCT)
				   
				   
                  (* Generate read function *)
                  (* -- Some useful names *)
                  val readName = readSuf name
		  fun readOneBranch (ename, dname, bvalOpt, commentOpt) =
		      let val labelLenX = P.intX(String.size dname)
		      in
                         [P.assignS(P.dotX(PT.Id "strlit", PT.Id(PL.str)), PT.String dname),
			  P.assignS(P.dotX(PT.Id "strlit", PT.Id(PL.len)), labelLenX)]
                       @ PL.chkPtS(PT.Id pads, readName)
                       @ [PT.IfThenElse(
			    PL.matchFunChkX(PL.P_ERROR, baseMatchFun, PT.Id pads, P.addrX(PT.Id "strlit"), P.trueX (*eat lit *)),
			    PT.Compound (PL.restoreS(PT.Id pads, readName)),
			    PT.Compound (  PL.commitS(PT.Id pads, readName)
				         @ [P.assignS(P.starX (PT.Id rep), PT.Id ename),
					    P.assignS(PT.Id result, PL.P_OK),
					    PT.Goto (findEORSuf name)]))]
		      end
                  fun genReadBranches () = 
                      [P.varDeclS'(PL.stringPCT, "strlit"),
		       P.varDeclS'(PL.toolErrPCT, result)]
		      @ List.concat(List.map readOneBranch enumFields)
		  val cleanupSs =  [P.mkCommentS("We didn't match any branch")]
			           @ BU.reportErrorSs([locS], locX, false,
						   PL.P_ENUM_MATCH_FAILURE,
						   true, 
						   readName,
						   ("Did not match any branch of enum "^name),
						   [])
			           @ [PL.setPanicS(PT.Id pd),
				      P.assignS(PT.Id result, PL.P_ERROR)]
		  val slurpToEORSs = if isRecord then genReadEOR (readName, reportBaseErrorSs, PL.P_ERROR) () else []
                  val gotoSs = [PT.Labeled(findEORSuf name,
					   PT.Compound (slurpToEORSs @ [PT.Return (PT.Id result)]))]
			       
		  (* -- Assemble read function enum case*)
		  val _ = pushLocalEnv()                                        (* create new scope *)
		  val () = ignore (insTempVar(rep, P.ptrPCT canonicalPCT)) (* add modrep to scope *)
		  val () = ignore (List.map insTempVar cParams)  (* add params for type checking *)
		  val readFields = genReadBranches()                            (* does type checking *)
		  val _ = popLocalEnv()                                         (* remove scope *)
		  val bodySs = [PT.Compound(readFields @ cleanupSs @ gotoSs)]
		  val readFunEDs = genReadFun(readName, cParams, 
					      mPCT, pdPCT, canonicalPCT, NONE, true, bodySs)

                  val readEDs = toStringEDs @ initRepEDs @ initPDEDs @ cleanupRepEDs @ cleanupPDEDs
				@ copyRepEDs @ copyPDEDs @ maskFunEDs @ readFunEDs
				
                  (* Generate is function enum case *)
                  val isName = PNames.isPref name
		  fun cnvOneBranch(bname, _, _) = P.mkCase(PT.Id bname, SOME [PT.Return P.trueX])
		  val defBranch = P.mkDefCase(SOME [PT.Return P.falseX])
		  val branches  = (List.concat(List.map cnvOneBranch enumFieldsforTy)) @ defBranch
		  val bodySs    = [PT.Switch (P.starX(PT.Id rep), PT.Compound branches), PT.Return P.trueX]
                  val isFunEDs  = [genIsFun(isName, cParams, rep, canonicalPCT, bodySs)]
				  
				  
                  (* Generate Accumulator functions (enum case) *)
                  (* -- generate accumulator init, reset, and cleanup functions *)
		  fun genResetInitCleanup theSuf = 
		      let val theFun : string = (theSuf o accSuf) name
			  val theBodyE = PT.Call(PT.Id(theSuf PL.intAct), [PT.Id pads, PT.Id acc])
                          val theReturnS = PT.Return theBodyE
			  val theFunED = BU.gen3PFun(theFun, [accPCT], [acc], [theReturnS])
			  in
			      theFunED
			  end
		   val initFunED = genResetInitCleanup initSuf
		   val resetFunED = genResetInitCleanup resetSuf
                   val cleanupFunED = genResetInitCleanup cleanupSuf

                   (* -- generate accumulator function *)
                   (*  Perror_t T_acc_add (P_t* , T_acc* , T_pd*, T* ) *)
		   val addFun = (addSuf o accSuf) name
		   val addX = PT.Call(PT.Id(addSuf PL.intAct), 
				      [PT.Id pads, PT.Id acc, PT.Id pd, 
				       PT.Cast(P.ptrPCT PL.intPCT, PT.Id rep)])
		   val addReturnS = PT.Return addX
		   val addBodySs =  [addReturnS]
		   val addFunED = BU.genAddFun(addFun, acc, accPCT, pdPCT, canonicalPCT, addBodySs)

		   (* -- generate report function enum *)
		   (*  Perror_t T_acc_report (P_t* , T_acc* , const char* prefix ) *)
		   val reportFun = (reportSuf o accSuf) name
		   val repioCallX = BU.callEnumPrint((ioSuf o reportSuf o mapSuf) PL.intAct,
						   PT.Id prefix, PT.Id what, PT.Id nst,
						   PT.Id(toStringSuf name), PT.Id acc)
		   val reportFunEDs = genTrivReportFuns(reportFun, "enum "^name, NONE, accPCT, repioCallX)
		   val accumEDs = accED :: initFunED :: resetFunED :: cleanupFunED :: addFunED :: reportFunEDs

                   (* -- generate histogram functions *)
                   val histEDs = Hist.genEnum(name, canonicalPCT, pdPCT)

                   (* -- generate cluster functions *)
                   val clusterEDs = Cluster.genEnum(name, canonicalPCT, pdPCT)
 
                   (* Generate Write functions (enum case) *)
		   val writeName = writeSuf name
		   val writeXMLName = writeXMLSuf name
		   val fmtName = fmtSuf name
		   val fmtBufFinalName = bufFinalSuf fmtName
		   val writeBaseName = PL.cstrlitWriteBuf
		   val writeXMLBaseName = PL.cstrlitWriteXMLBuf
                   val expX = PT.Call(PT.Id(toStringSuf name), [P.starX(PT.Id rep)])
		   val bodySs = writeFieldSs(writeBaseName, [expX], isRecord)
		   val bodyXMLSs = [PT.Expr(PT.Call(PT.Id "PCGEN_ENUM_XML_OUT", [PT.String(name), PT.Id(toStringSuf name)]))]
				   
		   val bodyFmtFinalSs = [PL.fmtFinalInitEnum(PT.String fmtBufFinalName), PL.fmtEnum(PT.String fmtBufFinalName, expX)] 
		   val (writeFunEDs, fmtFunEDs) = genWriteFuns(name, "ENUM", writeName, writeXMLName, fmtName, isRecord, isSource, cParams,
								    mPCT, pdPCT, canonicalPCT, bodySs, bodyXMLSs, bodyFmtFinalSs)
						       
	           (***** enum PADS-Galax *****)

		   fun genGalaxEnumKthChildFun(name) =		
		       let val nodeRepTy = PL.nodeT
			   val returnTy = P.ptrPCT nodeRepTy
                           val cnvName = PNames.nodeKCSuf name 
			   val paramTys = [P.ptrPCT nodeRepTy, PL.childIndexT]
                           val paramNames = [G.self,G.idx]
                           val formalParams =  List.map P.mkParam (ListPair.zip(paramTys, paramNames))
		           val bodySs = G.makeInvisibleDecls([name],nil)
					@ [G.macroEnumKC(name),
					   P.returnS (G.macroEnumKCRet())]
		       in   
                           P.mkFunctionEDecl(cnvName, formalParams, PT.Compound bodySs, returnTy)
		       end
			   

		   fun genGalaxEnumKthChildNamedFun(name) =		
		       let val nodeRepTy = PL.nodeT
			   val returnTy = P.ptrPCT nodeRepTy
                           val cnvName = PNames.nodeKCNSuf name 
			   val paramTys = [P.ptrPCT nodeRepTy, PL.childIndexT, P.ccharPtr]
                           val paramNames = [G.self,G.idx,G.childName]
                           val formalParams =  List.map P.mkParam (ListPair.zip(paramTys, paramNames))
					       
		           val bodySs = [G.macroEnumKCN()] 
					@ [P.returnS (G.macroEnumKCNRet())] 
		       in   
                           P.mkFunctionEDecl(cnvName, formalParams, PT.Compound bodySs, returnTy)
		       end
			 
		  val galaxEDs = [G.makeNodeNewFun(name),
				  G.makeCNInitFun(name, P.intX 2),
				  genGalaxEnumKthChildFun(name),
				  genGalaxEnumKthChildNamedFun(name),
				  G.makeCNKCFun(name, P.intX 2), 
				  G.makeSNDInitFun(name),				      
				  G.makeEnumSNDKthChildFun(name),
				  G.makeEnumPathWalkFun(name),
		                  G.makeNodeVtable(name),
		                  G.makeCachedNodeVtable(name),
		                  G.makeSNDNodeVtable(name)] 


	      in
		  canonicalDecls
                @ mDecls
                @ pdDecls
                @ (emitRead readEDs)
                @ (emitPred isFunEDs)
                @ (emitAccum accumEDs)
                @ (emitHist histEDs)
                @ (emitCluster clusterEDs)
                @ (emitWrite writeFunEDs)
 		@ (emitWrite fmtFunEDs)
                @ (emitXML galaxEDs)
	      end


	  fun cnvPCharClass {name, pred} = 
	      let val _ = pushLocalEnv()
		  val (apredCT, _ ) = cnvExpression pred
		  val _ = popLocalEnv()
		  val errorMsg = "Predicate for Pcharclass "^name^" has type "^
					  (CTtoString apredCT) ^", expected type compatible with int (*)(int)"
		  fun rptError () = 
		      let val done : bool ref = ref false
		      in
			  if not (!done) then (done := true; PE.error errorMsg) else ()
		      end
			 
		  val (body, decls) = 
		        case TU.getFunction ttab apredCT
			of SOME(retCT, [argCT]) => (
                             if not (isAssignable(CTint, retCT, NONE)) then rptError() else ();
                             if CTisInt argCT then (pred, []) 
                             else if CTisIntorChar argCT then
				  let val wrapperName = padsID(isPref name) 
				      val formalParams = [P.mkParam(P.int, "i")]
				      val argPT = CTtoPTct argCT
				      val bodySs = [P.varDeclS(argPT, "y", PT.Cast(argPT, PT.Id "i")),
						    PT.Return(P.andX(P.eqX(PT.Id "i", PT.Id "y"), 
								     PT.Call(pred, [PT.Id "y"])))]
				  in
				      (PT.Id wrapperName, [P.mkFunctionEDecl(wrapperName, formalParams, PT.Compound bodySs, P.int)])
				  end
			     else (case CTgetPtrBase argCT 
				   of NONE => (PE.error errorMsg; (pred, [])) 
				   |  SOME argPtrCT  => (
				        if CTisInt argPtrCT then
				           let val wrapperName = padsID(isPref name) 
					       val formalParams = [P.mkParam(P.int, "i")]
					       val bodySs = [PT.Return( PT.Call(pred, [P.addrX(PT.Id "i")]))]
					   in
					       (PT.Id wrapperName, 
					        [P.mkFunctionEDecl(wrapperName, formalParams, PT.Compound bodySs, P.int)])
					   end
					else if CTisIntorChar argPtrCT then
					        let val wrapperName = padsID(isPref name) 
						    val formalParams = [P.mkParam(P.int, "i")]
						    val argPT = CTtoPTct argPtrCT
						    val bodySs = [P.varDeclS(argPT, "y", PT.Cast(argPT, PT.Id "i")),
								  PT.Return(P.andX(P.eqX(PT.Id "i", PT.Id "y"), 
										   PT.Call(pred, [P.addrX(PT.Id "y")])))]
						in
						   (PT.Id wrapperName, 
						    [P.mkFunctionEDecl(wrapperName, formalParams, PT.Compound bodySs, P.int)])
						end				  
					else (PE.error errorMsg; (pred, [])) 
                                       (*end some cty case *))
				       (* end ptrbase case *))
			       (* end Some singleton case *))
                        | _ => (PE.error errorMsg; (pred, [])) 
		  val regS = PL.regexpCharClass(PT.String name, body)
		  val () = CharClass.insert regS
	      in
		  emitRead decls
	      end


	  fun cnvPSelect {selName, tyName, varName, path} = 
	      let val (Select.Id root):: path = Select.sexprToPath(P.stripExp path)
		  val () = if root = varName then ()
			       else raise Fail (selName^": parameter ("^varName^
						") and root of path expression ("^root^") don't match")
		  val errS = selName^": ill-typed path expression"
		  fun getPos(tyName, path, accumSize, args) = 
		      let val cds = lookupCompoundDiskSize (PX.Name tyName)
			            handle Fail s => raise Fail (s^" Required for " ^selName^" request")
		      in
			  case cds
			  of TyProps.Base ds    => (tyName, accumSize, reduceCDSize(args, ds), args)
			  |  TyProps.Enum ds => 
			      let val size = reduceCDSize(args, ds)
				  (* params should be fixed size of branches *)
				  val params = case size of TyProps.Size(n, nrec) => [PT.IntConst n] | _ => []
			      in
				  ("Pstring", accumSize, reduceCDSize(args, ds), params)
			      end
			  |  TyProps.Typedef (ds, baseName, targs) => 
			      let val closedDS = reduceCDSize(args, ds)
			      in
				  getPos(baseName, path, accumSize, reduceArgList(args, targs))
			      end
                          |  TyProps.Struct dsl => 
			      let val (f, path) = case path of ((Select.Dot f)::path) => (f, path) | _ => raise Fail errS
				  fun findField ([], accum) = raise Fail errS
				    | findField((sOpt, diskSize)::ss, accum) = 
				      let val closedDS = reduceCDSize(args, diskSize)
				      in
				         case sOpt of NONE => findField(ss, TyProps.add(closedDS, accum)) (* literal*)
                                         | SOME (l, tyName, sargs:TyProps.argList, isVirtual, comment) => 
					     if not (l = f) then 
						 findField(ss, TyProps.add(closedDS, accum))
					     else if (tyName = "Pcompute") then
						 raise Fail (selName ^ ": ill-formed request: Computed field "^l^
							     " has no external representation")
					     else
						  getPos(tyName, path, accum, reduceArgList(args, sargs))
				      end
			      in
				  findField(dsl, accumSize)
			      end (* struct case *)
			  | TyProps.Union dsl => 
			      (* ksf: This case is not type safe.  
			         After we add alternates, we should make it illegal to select out of a union statically.
				 Alternatively, we could enrich cookie language to allow dependencies on data.
			       *)
			      let val (f, path) = case path of ((Select.Dot f)::path) => (f, path) | _ => raise Fail (errS^" didn't find dot")
				  fun findAlt ([]) = raise Fail (errS^"ran through all choices\n")
				    | findAlt((sOpt, diskSize)::ss) = 
				      let val closedDS = reduceCDSize(args, diskSize)
				      in
				         case sOpt of NONE => findAlt(ss) (* literal: won't happen for union. *)
                                         | SOME (l, tyName, sargs:TyProps.argList, isVirtual,commentOpt) => 
					     if not (l = f) then findAlt ss
					     else if (tyName = "Pcompute") then
						 raise Fail (selName ^ ": ill-formed request: Computed field "^l^
							     " has no external representation")
					     else
						  getPos(tyName, path, accumSize, reduceArgList(args, sargs))
				      end
			      in
				  findAlt dsl
			      end (* union case *)
                          | TyProps.Array {baseTy, args=arrayArgs, elem, sep, term, length} =>
		             let val (i, path) = case path of ((Select.Sub i)::path) => (i, path)  | _ => raise Fail errS
				 val closedLen = reduceCDSize(args, length)
				 val max = case closedLen of TyProps.Size(n, nr) => n 
			                   | _ => raise Fail (selName^": can't index into arrays of unknown size")
				 val () = if IntInf.>=(i, max) 
					  then raise Fail (selName ^": index "^(IntInf.toString i)^
							   " greater than array length "^(IntInf.toString max))
					  else ()
				 val index = TyProps.Size(i, IntInf.fromInt 0)
				 val prelimSize = coreArraySize(elem, sep, index)
				 val prelimClosed = reduceCDSize(args, prelimSize)
				 val accum = TyProps.add(accumSize, prelimClosed)
			     in
				  getPos(baseTy, path, accum, reduceArgList(args, arrayArgs))
			     end
		      end
		  val (itemType, offset, size, argList) = getPos(tyName, path, TyProps.mkSize(0,0), [](* top level must be closed *))
	      in
		((case offset
		  of TyProps.Variable => PE.error (selName^ ": location of request depends on data") 
                  |  TyProps.Param(_) => PE.error (selName^ ": location of request depends on parameters") 
                  |  TyProps.Size(location, nr) => 
		      (case size 
		       of TyProps.Variable => PE.error (selName^ ": size of request depends on data") 
		       |  TyProps.Param(_) => PE.error (selName^ ": size of "^selName^" request depends on parameters") 
                       |  TyProps.Size(n, nr) => 
			   Select.insert(Select.Select{selName = selName, tyName = itemType, 
						       args = evalArgList argList, offset = location, size = n})
		      (* end case size *))
	        (* end case offset*));
		[] (* return no AST decls *))
	      end handle Fail s => (PE.error s; [])


	  fun cnvPDone () = 
	      let val () = (if !seenDone then PE.error ("Unexpected Pdone declaration") else (); seenDone := true)
		  val bodySs = [P.mkCommentS "Initialize character classes"]
		               @ (CharClass.listClasses ())
		  val initFunED = P.mkFunctionEDecl(PL.libInit, [], PT.Compound bodySs, P.void)
	      in
		  cnvExternalDecl initFunED
	      end
		  
	  in (* matches let of pcnvExternalDecl *)
	      case decl 
	      of PX.PTypedef     t => cnvPTypedef   t
              |  PX.PArray       a => cnvPArray     a
              |  PX.Popt         p => cnvPOpt       p
              |  PX.PUnion       u => cnvPUnion     u
              |  PX.PStruct      s => cnvPStruct    s
              |  PX.PEnum        e => cnvPEnum      e
	      |  PX.PCharClass   c => cnvPCharClass c
	      |  PX.PSelect      s => cnvPSelect    s
	      |  PX.PDone          => cnvPDone      ()
	  end

      fun pcnvStat (PX.PComment s) =  wrapSTMT(Ast.StatExt(AstExt.SComment(formatComment s)))
      fun pcnvExp  (PX.Pregexp e) =   cnvExpression e

      fun pcnvDeclaration (PX.PPhantomDecl (tyName,varName)) = 
	  let val ty =  case lookSym (SYM.typedef tyName)
			 of SOME(B.TYPEDEF{ctype,...}) => ctype
			  | _ => (error("typedef " ^ tyName ^ " has not been defined.");
				  Ast.Error)
	      val varSym = SYM.object varName			   
			   
	      val id = {name = varSym, 
			uid = Pid.new(),
			location = getLoc(),
			ctype = ty, 
			stClass = Ast.AUTO,
			status = Ast.DECLARED,
			global = false,
			kind = Ast.NONFUN}
	  in
	      (bindSym (varSym, B.ID id);
	      nil)
	  end
						
	      

      in (* matches let from fun makeExtensionFuns *)
	  {CNVExp = pcnvExp,
	   CNVStat = pcnvStat,
	   CNVBinop = CNVBinop,
	   CNVUnop = CNVUnop,
	   CNVExternalDecl = pcnvExternalDecl,
	   CNVSpecifier = CNVSpecifier,
	   CNVDeclarator = CNVDeclarator,
	   CNVDeclaration = pcnvDeclaration}
      end
end
