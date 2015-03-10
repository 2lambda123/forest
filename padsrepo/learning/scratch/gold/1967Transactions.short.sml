structure Trans = struct
    open Model
    val aux : AuxInfo = { coverage = 999, label = NONE, tycomp = zeroComps }
    val loc: location = { lineNo = 0, beginloc = 0, endloc = 0, recNo = 0 }
    val sp : Ty = Base (aux, [(Pwhite " ", loc)] )
    val type_t: Ty = RefinedBase(aux, Enum [IntConst 0101, IntConst 0102, IntConst 0103, IntConst 0104 ], [])
    val id:Ty = Base (aux, [(Pint (2701, "2701"), loc)])
    val value1:Ty = Base (aux, [(Pfloat ("99", "07"), loc)])
    val value2:Ty = Base (aux, [(Pfloat ("99", "07"), loc)])
    val value3:Ty = Base (aux, [(Pfloat ("99", "07"), loc)])
    val trans: Ty = Pstruct ( aux, [ type_t, sp, id, sp, value1, sp, value2, sp, value3, sp ] )
end