Pstruct entry{
  Pstring(:':':) name; ':';
  Puint32 dist;
};

Precur tree;

Punion inode {
  tree interior;
  Popt entry tip;
};

Pstruct tree{
  '(';
  inode[] branches: Psep(',') && Pterm(')');
  ')';
  //  ':'; Puint32 dist;
};