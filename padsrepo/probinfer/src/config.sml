structure Config = struct
    (********************************************************************************)
    (*********************  Configuration *******************************************)
    (********************************************************************************)
    val DEF_HIST_PERCENTAGE   = 0.01
    val DEF_STRUCT_PERCENTAGE = 0.1
    val DEF_JUNK_PERCENTAGE   =  0.1
    val DEF_NOISE_PERCENTAGE  =  0.0
    val DEF_ARRAY_WIDTH_THRESHOLD =  4
    val DEF_ARRAY_MIN_WIDTH_THRESHOLD =  0
    val DEF_MAX_TABLE_ROWS = 2000
    val DEF_MAX_TABLE_COLS = 200
    val DEF_EXTRACT_HEADER_FOOTER = true
    val def_maxHeaderChunks = 3
    val def_depthLimit   = 50
    val def_outputDir    = "gen/"
    val def_descName     = "generatedDescription"
    val def_srcFiles     = [] : string list
    val def_printLineNos = false
    val def_printIDs     = true
    val def_entropy      = false

    val depthLimit        = ref def_depthLimit
    val outputDir         = ref def_outputDir
    val descName          = ref def_descName
    val srcFiles          = ref def_srcFiles
    val printLineNos      = ref def_printLineNos
    val printIDs          = ref def_printIDs
    val printEntropy      = ref def_entropy
    val executableDir     = ref ""
    val lexName	          = ref "vanilla"
    val basetokenName	          = ref "basetokens"
    val goldenRun         = ref false

    val trainingRun       = ref false
    val inctrainingRun    = ref false
    val testingRun        = ref false
    val examHMMPre        = ref false
    val examHMMPost       = ref false
    val lambda            = ref 0.0
    val defaultLambda     = 0.01
    val evaluateHMMPost   = ref false
    val evaluateVanilla   = ref false
    val fvectorbits       = 11
    val character         = ref false
    val trainingWeightsRun = ref false
    val inctrainingWeightsRun = ref false
    val hmmtokenize       = ref false
    val ghmmtrainingRun   = ref false
    val svmtrainingRun   = ref false
    val ghmmtestingRun    = ref false
    val svmtestingRun    = ref false
    val evaluatehmmseqset = ref false
    val evaluateghmmseqset = ref false
    val evaluatesvmseqset = ref false
    val dumpseqsets       = ref false
    val ghmm1             = ref false
    val ghmm2             = ref false
    val ghmm3             = ref false
    val ghmm4             = ref false
    val ghmm5             = ref false
    val showtokenvanilla         = ref false
    val showtokenhmm         = ref false
    val showtokenghmm         = ref false
    val showtokensvm         = ref false
    val modelexist           = ref false
                           
    exception GHMMOptionError

    (* 4 intenal strategy options *)
    val OPTIMAL_1ST_TOKEN   = ref false
    val RDC_UNION_BRANCHES  = ref false
    val rdc_ratio           = 2
    val COMBINED_HIST       = ref false
    val OPTIMAL_STRUCT      = ref true

    val HIST_PERCENTAGE   = ref DEF_HIST_PERCENTAGE
    val STRUCT_PERCENTAGE = ref DEF_STRUCT_PERCENTAGE
    val JUNK_PERCENTAGE   = ref DEF_JUNK_PERCENTAGE
    val NOISE_PERCENTAGE  = ref DEF_NOISE_PERCENTAGE
    val ARRAY_WIDTH_THRESHOLD = ref DEF_ARRAY_WIDTH_THRESHOLD
    val ARRAY_MIN_WIDTH_THRESHOLD = ref DEF_ARRAY_MIN_WIDTH_THRESHOLD

    fun histEqTolerance   x = Real.ceil((!HIST_PERCENTAGE)   * Real.fromInt(x)) 
    fun isStructTolerance x = Real.ceil((!STRUCT_PERCENTAGE) * Real.fromInt(x)) 
    fun isJunkTolerance   x = Real.ceil((!JUNK_PERCENTAGE)   * Real.fromInt(x)) 
    fun isNoiseTolerance  x = Real.ceil((!NOISE_PERCENTAGE)  * Real.fromInt(x)) 

    fun parametersToString () = 
	(   ("Source files to process: "^(String.concat (!srcFiles))   ^"\n")^
	    ("Output directory: "      ^(!outputDir) ^"\n")^
	    ("Output description file: " ^(!descName) ^"\n")^
	    ("Max depth to explore: "  ^(Int.toString (!depthLimit))^"\n")^
 	    ("Print line numbers in output contexts: "        ^(Bool.toString (!printLineNos))^"\n")^
 	    ("Print ids and output type tokens: "             ^(Bool.toString (!printIDs))^"\n")^
	    ("Print Entropy: "                                ^(Bool.toString (!printEntropy))^"\n")^
	    ("Histogram comparison tolerance (percentage): "  ^(Real.toString (!HIST_PERCENTAGE))^"\n")^
	    ("Struct determination tolerance (percentage): "  ^(Real.toString (!STRUCT_PERCENTAGE))^"\n")^
	    ("Noise level threshold (percentage): "           ^(Real.toString (!NOISE_PERCENTAGE))^"\n")^
	    ("Width threshold for array: "                    ^( Int.toString (!ARRAY_WIDTH_THRESHOLD))^"\n")^
	    ("Minimum width threshold for array: "            ^( Int.toString (!ARRAY_MIN_WIDTH_THRESHOLD))^"\n")^
	    ("Junk threshold (percentage): "                  ^(Real.toString (!JUNK_PERCENTAGE))^"\n"))

    fun printParameters () = print (parametersToString ())

    (********************************************************************************)
    (*********************  END Configuration ***************************************)
    (********************************************************************************)

end