/*
 * Template: pglx_smart_query.h 
 * Incrementally load PADS source using smart arrays, run Galax query,
 * and serialize result in XML.
 */

#include "pads.h"
#include "pglx.h"

#define exit_on_error(_Expr) {err = _Expr; if (err != 0) {error(0, "%s\n", galax_error_string); exit(err);}}	


#define MAX_NODES 1000
#define MAX_ELTS 1000

#ifndef EXTRA_ARGS
#  define EXTRA_ARGS
#endif

#ifndef MAX_RECS
#  define MAX_RECS 0
#endif

int main(int argc, char** argv) {
  P_t*          pads;
  PADS_TY( )         rep;
  PADS_TY(_pd)       pd ;
  PADS_TY(_m)        m;
  PDCI_node_t    *smart_node,*result_node;  

  galax_err err;
  item doc,doc2;
  itemlist docitems;

  Sfio_t       *io;
  Pdisc_t       mydisc; 

  mydisc = Pdefault_disc; 
  mydisc.copy_strings = 1; 
#ifdef WSPACE_OK
  mydisc.flags |= (Pflags_t)P_WSPACE_OK;
#endif


  /* When linking with the Galax library, which contains a custom O'Caml runtime system, 
     it is necessary to call galax_init first, so the runtime is initialized and then 
     can delegate control back to the C program 
  */
  galax_init();

  if (argc != 4) { error(2, "Usage: test_load_XXX <XXX-data-file> <XXX-query> <XXX_child-name> \n"); exit(-1); }

  if (P_ERR == P_open(&pads,&mydisc,0)) {
    error(2, "*** P_open failed ***");
    exit(-1);
  }
  io = P_fopen(argv[1],"r");
  if (!io) {
    error(2, "*** P_fopen failed ***");
    exit(-1);
  }
  if (P_ERR == P_io_set(pads, io)) {
    error(2, "*** P_io_set failed ***");
    exit(-1);
  }

  /* init -- must do this! */
  /* Initialize pads-galax */

  /* Initialize nodeid generator */
  PDCI_ID_RESET(pads,0);

  NodeMM_initMM(pads, MAX_NODES);  
  
  /* End initialize pads-galax */

  if (P_ERR == PADS_TY(_init)(pads, &rep)) {
    error(ERROR_FATAL, "*** representation initialization failed ***");
  }
  if (P_ERR == PADS_TY(_pd_init)(pads, &pd)) {
    error(ERROR_FATAL, "*** parse description initialization failed ***");
  }
  /* init mask -- must do this! */
  PADS_TY(_m_init)(pads, &m, P_CheckAndSet);

  // Read header here, if any:
  // ...

  // Create the new smart node.
  PDCI_MK_TOP_NODE_NORET (smart_node, &PADS_TY(_node_vtable), pads, "doc", &m, &pd, &rep, "main");
  PADS_TY(_smartNode_init)(smart_node, MAX_ELTS  EXTRA_ARGS);

  //  printf("1st Traversal.\n");

  err = padsDocument(argv[1], (nodeRep)smart_node, &doc);
  exit_on_error(err); 

  err = galax_eval_statement_from_file_with_context_item_from_xml(doc, argv[2], &docitems);
  exit_on_error(err); 

  //  printf("About to serialize.\n");
  err = galax_serialize_to_stdout(docitems);
  exit_on_error(err);

  /*
  result_node = Puint32_node_new(smart_node,"result",NULL,NULL,NULL,"element","main");
  (result_node->vt->cachedNode_init)(result_node);
  result_node->child_cache[0]= PGLX_generic_kth_child_named((nodeRep)smart_node,0,argv[3]);
  result_node->child_cache[1]= result_node->child_cache[0];

  printf("Forming document ....\n");
  err = padsDocument("pd.xml", (nodeRep)result_node, &doc2);
  exit_on_error(err); 
  docitems = itemlist_cons(doc2, itemlist_empty()); 
  err = galax_serialize_to_stdout(docitems);
  exit_on_error(err);
  */

  /*
  printf("2nd Traversal.\n");

  // create a second cursor over the data:
  err = padsDocument(argv[1], (nodeRep)smart_node, &doc2);
  exit_on_error(err); 

  docitems = itemlist_cons(doc2, itemlist_empty()); 
  err = galax_serialize_to_stdout(docitems);
  exit_on_error(err);
  */

  //  printf("\nFinished Traversals.\n");

  /* 
   * The smart code doesn't use rep->elts, pd->elts, 
   * but it does use the length variables. Therefore,
   * we need to reset them to 0 before cleanup.
   */
  rep.length = 0;
  if (P_ERR == PADS_TY(_cleanup)(pads, &rep)) {
    error(ERROR_FATAL, "** representation cleanup failed **");
  }
  
  pd.length = 0;
  if (P_ERR == PADS_TY(_pd_cleanup)(pads, &pd)) {
    error(ERROR_FATAL, "** parse descriptor cleanup failed **");
  }
  /**/
  P_io_close(pads);

  NodeMM_freeMM(pads);
  P_close(pads);
  return 0;
}
