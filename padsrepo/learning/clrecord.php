<?
class ClRecord {
  var $Tokens; // thi holds the memory reference to the ClToken objects.


  function FnPrintRecord(){
    while (list($key, $val) = each($this->Tokens)) {
      echo "$val->Content"."|";
    }
    echo "\n";
    reset($this->Tokens);
  }

}
?>