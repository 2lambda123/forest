#include "padsc.h"
#include "format7.h"
#include "pglx.h"

#define exit_on_error(_Expr) {err = _Expr; if (err != 0) {printf("%s\n", glx_error_string); exit(err);}}	

int try_galax() { 
  processing_context pc; 
  module_context sc;
  itemlist items;
  glx_err err;
  char *str;

  err = glx_default_processing_context(&pc); 
  err = glx_load_standard_library(pc, &sc); 

  err = glx_eval_statement_from_string(sc, "<a/>", &items);
  err = glx_serialize_to_string(items, &str);
  printf("%s\n", str); 
  return err;
}

int main(int argc, char** argv) {
  PDC_t*          pdc;
  PDC_disc_t      mydisc = PDC_default_disc;
  myfile          rep;
  myfile_pd       pd ;
  myfile_m        m;
  PDCI_node_t    *doc_node;

  glx_err err;
  item doc;
  node n; 
  char *str = "";
  itemlist k, docitems;
  atomicValue_list av;
  int i;

  /* When linking with the Galax library, which contains a custom O'Caml runtime system, 
     it is necessary to call glx_init first, so the runtime is initialized and then 
     can delegate control back to the C program 
  */
  char *fake_argv[2];

  fake_argv[0] = "caml";
  fake_argv[1] = 0;
  glx_init(fake_argv);

  if (argc != 2) { error(2, "Usage: test_children <format7-data-file>\n"); exit(-1); }

  /* Try out some Galax functions first */
  /* try_galax(); */

  mydisc.flags |= PDC_WSPACE_OK;

  if (PDC_ERR == PDC_open(&pdc,&mydisc,0)) {
    error(2, "*** PDC_open failed ***");
    exit(-1);
  }
  if (PDC_ERR == PDC_IO_fopen(pdc, argv[1])) {
    error(2, "*** PDC_IO_fopen failed ***");
    exit(-1);
  }

  /* init -- must do this! */
  PDC_INIT_ALL(pdc, myfile, rep, m, pd, PDC_CheckAndSet);

  /* make the top-level node */
  PDCI_MK_TOP_NODE_NORET (doc_node, &myfile_vtable, pdc, "doc", &m, &pd, &rep, "main");

  /* Try to read entire file */
  error(0, "\ncalling myfile_read");
  if (PDC_OK == myfile_read(pdc, &m, &pd, &rep)) {
    exit_on_error(padsDocument(argv[1], (nodeRep)doc_node, &doc)); 
    docitems = itemlist_cons(doc, itemlist_empty());
    err = glx_serialize_to_string(docitems, &str);
    printf("%d: %s\n", strlen(str), str);  
    exit_on_error(glx_serialize_to_output_channel(docitems));

    exit_on_error(glx_children(doc, &k)); 	
    for (i = 0; !is_empty(k); i++) {
      printf("%d...", i);
      n = items_first(k); 
      exit_on_error(glx_node_kind(n, &str)); 
      printf("%s\n", str);  
      exit_on_error(glx_node_name(n, &av)); 
      exit_on_error(glx_serialize_to_string(av, &str));
      printf("%s\n", str);  
      k = items_next(k); 
    }
    exit_on_error(glx_node_kind(doc, &str)); 
    printf("%s\n", str);  
    /* 
       exit_on_error(glx_serialize_to_string(k, &str));
    printf("%s\n", str); */
    /* 
    */
    error(0, "\nmyfile_read returned: ok");
  } else {
    error(0, "myfile_read returned: error");
  }

  PDC_CLEANUP_ALL(pdc, myfile, rep, pd);
  PDC_IO_close(pdc);
  PDC_close(pdc);
  return 0;
}
