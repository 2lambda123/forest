structure TEST_INC = struct
    open Model
    val aux: AuxInfo = {coverage = 35, label = NONE, tycomp = zeroComps, len=0.0 }
    val loc : location = {lineNo = 0, beginloc = 0, endloc = 0, recNo = 0}
    val dirLabel = Atom.atom("dirLabel")
    val dirAux: AuxInfo = {coverage = 34, label = SOME dirLabel, tycomp = zeroComps, len=0.0 }
    val sp = RefinedBase (aux, StringConst " ", [])
    val dashR:Refined = StringConst "-"
    val dR:Refined = StringConst "d"
    val word = Base(aux, [(Pstring("abc"), loc)])
    val date = Base(aux, [(Pdate("14/Dec/2006"), loc)])
    val time = Base(aux, [(Ptime("14/Dec/2006"), loc)])
    val ip = Base(aux, [(Pip("68.63.10.255"), loc)])
    val path = Base(aux, [(Ppath("68.63.10.255"), loc)])
    val url = Base(aux, [(Purl("68.63.10.255"), loc)])
    val intnum = Base (aux, [(Pint(0, "0"), loc)])
    val stuff = RefinedBase (aux, Blob(NONE, SOME "/(; )|(\\)\")/"), []) 
    val array1 = RArray (aux, SOME (StringConst "; "), SOME (StringConst ")\""), stuff, NONE, [])
    val sep : Refined = StringME "/[;#][ ]?/"
    val quad_dash = RefinedBase(aux, StringConst "____", [])
    val equal = RefinedBase(aux, StringConst "=", [])
    val pair = Pstruct(aux, [
		Poption(aux, quad_dash),
		word,
		equal,
		Poption (aux, RefinedBase (aux, StringME("/[^;#]+/"), []))
		])
    val arraybody : Ty = Punion (aux, 
				[Base (aux, [(Pempty, loc)]),
				 quad_dash,
				 pair])
    val test_inc : Ty = Pstruct (aux, [intnum, RefinedBase(aux, StringConst " ", []),
				       intnum])
(*    val test_inc : Ty = intnum *)
end	