structure PInput = 
struct

type PinputTy = {outputAccum  : bool ref,
		 outputRead   : bool ref,
		 outputWrite  : bool ref,
		 outputXML    : bool ref,
		 outputExper  : bool ref}


val inputs : PinputTy = {outputAccum  = ref true,
			 outputRead   = ref true,
			 outputWrite  = ref true,
			 outputXML    = ref false,
			 outputExper  = ref false}

fun emitAccum      status = (#outputAccum inputs) := status
fun emitRead       status = (#outputRead inputs) := status
fun emitWrite      status = (#outputWrite inputs) := status
fun emitXML        status = (#outputXML inputs) := status
fun emitExperiment status = (#outputExper inputs) := status
end