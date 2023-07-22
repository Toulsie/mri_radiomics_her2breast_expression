

%macro boot1auc(dsn,marker,gold,boot=1000,alpha=0.05);

%let conflev=%sysevalf(100*(1-&alpha));
%let ll=%sysevalf((&alpha/2)*&boot);
%let ul=%sysevalf((1-(&alpha)/2)*&boot);

proc datasets;delete bootsample bootdist;

proc sql noprint;
  select n(&marker) into :n
  from &dsn;
quit;

proc surveyselect data=&dsn method=urs n=&n out=bootsample outhits rep=&boot noprint;
run;

filename junk 'junk.txt';
proc printto print=junk;run;

proc logistic data=bootsample;
  by replicate;
  model &gold=&marker;
  ods output association=assoc;
run;

proc printto;run;
data bootdist(keep=nvalue2 rename=(nvalue2=auc));
  set assoc(where=(label2='c'));
run;
options formdlim=' ';
title "Bootstrap Analysis of the AUC for &marker";

proc sql;
  select mean(auc) as AUC, std(auc) as StdErr
  from bootdist;
run;

proc sort data=bootdist;by auc;run;
title "&conflev.% Confidence Interval";

proc sql;
  select a.auc as LowerLimit, b.auc as UpperLimit
  from bootdist(firstobs=&ll obs=&ll) a, bootdist(firstobs=&ul obs=&ul) b; 
quit;
options formdlim='';
%mend;

%boot1auc(dsn=pred4,marker=pred4,gold=gold1,boot=1000,alpha=0.05)
