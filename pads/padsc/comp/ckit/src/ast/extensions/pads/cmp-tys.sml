structure PTys = 

struct
  datatype PKind = Typedef | Struct | Union | Array | Enum

  type sTyInfo = {diskSize : TyProps.diskSize,
		  memChar  : TyProps.memChar,
		  endian   : bool,
                  isRecord : bool} 

  type pTyInfo = {kind     : PKind,
		  diskSize : TyProps.diskSize,
		  memChar  : TyProps.memChar,
		  endian   : bool,
                  isRecord : bool,
		  repName  : string,
		  repInit  : string option,
		  repRead  : string,
		  repClean : string option,
		  edName   : string,
		  edInit   : string option,
		  edClean  : string option,
		  accName  : string,
		  accInit  : string,
		  accAdd   : string,
		  accReport: string,
		  accClean : string}

  fun mergeTyInfo f (r1 : sTyInfo, r2:sTyInfo) =
      {diskSize = TyProps.mergeDiskSize f (#diskSize r1, #diskSize r2),
       memChar  = TyProps.mergeMemChar(#memChar r1,   #memChar  r2),
       endian   = #endian r1 andalso #endian r2,
       isRecord = #isRecord r1}

  val minTyInfo = {diskSize = TyProps.Size (0,0), memChar = TyProps.Static, endian = true, isRecord = false}

  type pTyMap = pTyInfo PBaseTys.PBST.map

  val pTys : pTyMap ref = ref PBaseTys.PBST.empty

  fun insert(name:Atom.atom, data:pTyInfo) = 
     pTys := PBaseTys.PBST.insert(!pTys, name, data)

  val find: Atom.atom -> pTyInfo option = fn a => PBaseTys.PBST.find(!pTys, a)
end