
%macro existchk(data=, var=, dmsg=e, vmsg=e);
   %global status; %let status=ok;
   %if &dmsg=e %then %let dmsg=ERROR;
   %else %if &dmsg=w %then %let dmsg=WARNING;
   %else %let dmsg=NOTE;
   %if &vmsg=e %then %let vmsg=ERROR;
   %else %if &vmsg=w %then %let vmsg=WARNING;
   %else %let vmsg=NOTE;
   %if %quote(&data) ne %then %do;
     %if %sysfunc(exist(&data)) ne 1 %then %do;
       %put &dmsg: Data set %upcase(&data) not found.;
       %let status=nodata;
     %end;
     %else %if &var ne %then %do;
       %let dsid=%sysfunc(open(&data));
       %if &dsid %then %do;
         %let i=1;
         %do %while (%scan(&var,&i) ne %str() );
            %let var&i=%scan(&var,&i);
            %if %sysfunc(varnum(&dsid,&&var&i))=0 %then %do;
              %put &vmsg: Variable %upcase(&&var&i) not found in data %upcase(&data).;
              %let status=novar;
            %end;
            %let i=%eval(&i+1);
         %end;
         %let rc=%sysfunc(close(&dsid));
       %end;
       %else %put ERROR: Could not open data set &data.;
     %end;
   %end;
   %else %do;
     %put &dmsg: Data set not specified.;
     %let status=nodata;
   %end;   
%mend;

%macro PRcurve(version, data=_last_, inpred=, pred=, npoints=100,  
               beta=1, optvars=, sensdelta=1e-10, sensinc=1e-14,
               options=area pprob markers br ppvzero nooptimal) / minoperator;


%let time = %sysfunc(datetime());
%let _version=1.0;
%if &version ne %then %put NOTE: &sysmacroname macro Version &_version;
%if %quote(&data)=_last_ %then %let data=&syslast;
%local notesopt; 
%let notesopt = %sysfunc(getoption(notes)) _last_=%sysfunc(getoption(_last_));
%let version=%upcase(&version);
%if %index(&version,DEBUG) %then %do;
  options notes mprint
    %if %index(&version,DEBUG2) %then mlogic symbolgen;
  ;  
  %put _user_;
%end;
%else %do;
  options nonotes nomprint nomlogic nosymbolgen;
%end;

/* Check for newer version */
%let _notfound=0; %let _newver=0;
filename _ver url 'http://ftp.sas.com/techsup/download/stat/versions.dat' 
         termstr=crlf;
data _null_;
  infile _ver end=_eof;
  input name:$15. ver;
  if upcase(name)="&sysmacroname" then do;
    call symput("_newver",ver); stop;
  end;
  if _eof then call symput("_notfound",1);
  run;
options notes;
%if &syserr ne 0 or &_notfound=1 or &_newver=0 %then
  %put NOTE: Unable to check for newer version of &sysmacroname macro.;
%else %if %sysevalf(&_newver > &_version) %then %do;
  %put NOTE: A newer version of the &sysmacroname macro is available at;
  %put NOTE- this location: http://support.sas.com/ ;
%end;
%if %index(%upcase(&version),DEBUG)=0 %then options nonotes;;

/* Check inputs */
%existchk(data=&data)
%if &status=nodata %then %goto exit;
%let dsid=%sysfunc(open(&data));
%if &dsid %then %do;
   %let type=;
   %if %sysfunc(varnum(&dsid,%upcase(problevel))) %then %let type=ctable;
   %if %sysfunc(varnum(&dsid,%upcase(_prob_))) %then %let type=roc;
%end;
%let rc=%sysfunc(close(&dsid)); 
%if &type= %then %do;
   %put ERROR: DATA= data set must be and OUTROC= or CTABLE data set.;
   %goto exit;
%end;
%if &inpred ne %then %do;
   %existchk(data=&inpred)
   %if &status=nodata %then %goto exit;
   %if &pred= or &optvars= %then %do;
     %put ERROR: PRED= and OPTVARS= are required when INPRED= is specified.;
     %goto exit;
   %end;
   %else %do;
     %existchk(data=&inpred, var=&pred &optvars);
     %if &status=novar %then %goto exit;
   %end;
%end;
%if &npoints= %then %do;
   %put ERROR: NOPOINTS= must be an integer value greater than zero.;
   %goto exit;
%end;
%else %do;
  %if %sysevalf(%sysfunc(mod(&npoints,1)) ne 0 or &npoints<=0) %then %do;
    %put ERROR: The NPOINTS= value must be an integer value greater than zero.;
    %goto exit;
  %end;
%end;
%if %sysevalf(&sensdelta=) %then %do;
   %put ERROR: SENSDELTA= must be a positive value less than 1.;
   %goto exit;
%end;
%else %do;
  %if %sysevalf(&sensdelta<=0 or &sensdelta>1) %then %do;
    %put ERROR: SENSDELTA= must be a positive value less than 1.;
    %goto exit;
  %end;
%end;
%if %sysevalf(&beta=) %then %do;
   %put ERROR: BETA= must be a positive value.;
   %goto exit;
%end;
%else %do;
  %if %sysevalf(&beta<0) %then %do;
    %put ERROR: BETA= must be a positive value.;
    %goto exit;
  %end;
%end;
%let validopts=
AREA NOAREA PPROB NOPPROB MARKERS NOMARKERS BR BL TR
%str(        )TL PPVZERO NOPPVZERO OPTIMAL NOOPTIMAL;
%let showarea=1; %let markers=1; %let textloc=bottomright; 
%let pprob=1; %let flatppv=0; %let opt=0;
%let i=1;
%do %while (%scan(&options,&i) ne %str() );
   %let option&i=%upcase(%scan(&options,&i));
   %if &&option&i=NOAREA %then %let showarea=0;
   %else %if &&option&i=NOPPROB %then %let pprob=0;
   %else %if &&option&i=NOMARKERS %then %let markers=0;
   %else %if &&option&i=NOPPVZERO %then %let flatppv=1;
   %else %if &&option&i=OPTIMAL %then %let opt=1;
   %else %if &&option&i=BL %then %let textloc=bottomleft;
   %else %if &&option&i=TR %then %let textloc=topright;
   %else %if &&option&i=TL %then %let textloc=topleft;
   %else %do;
    %let chk=%eval(&&option&i in &validopts);
    %if not &chk %then %do;
      %put ERROR: Valid values of OPTIONS= are &validopts..;
      %goto exit;
    %end;
   %end;
   %let i=%eval(&i+1);
%end;
%if &showarea and %sysprod(ets)=0 %then %do;
    %put NOTE: SAS/ETS is not found. Area cannot be computed.;
    %let showarea=0;
  %end;

/* If data= is from CTABLE, edit names and sort so can use like OUTROC= input */
%if &type=ctable %then %do;
   proc sort data=&data 
             out=_prctbl(rename=(correctevents=_pos_ correctnonevents=_neg_ 
                         incorrectevents=_falpos_ incorrectnonevents=_falneg_ 
                         sensitivity=_sensit_ problevel=_prob_)
                         drop=specificity correct npv ppv false:);
      by descending problevel;
      run;
   %let prdata=_prctbl;
%end;

/* Apply Davis&Goadrich interpolation of points in P-R space, compute precision and recall,
   and optionally compute optimality criteria
*/
%else %let prdata=&data;
data _pr; 
   %if %index(&version,DEBUG)=0 %then %do;
       keep _threshold _sensitivity _ppv _marksens _markppv 
            %if &opt %then _fscore _mscore;;
   %end;
   _inc+&sensinc;
   retain _sensa _tpa _fpa;
   skip: set &prdata end=_eof; 
   %if &type=ctable %then _sensit_=_sensit_/100;;
   _sensb=_sensit_; 
   if _pos_=0 and _falpos_=0 then goto skip;
   _npos=_pos_+_falneg_;
   _ppvb=_pos_/(_pos_+_falpos_);
   %if &flatppv %then %do;
      if _ppvb=0 then goto skip;
   %end;
   if _n_=1 and _ppvb>0 then do; 
     _sensitivity=0; _ppv=_ppvb; output; 
   end;
   else do;
      if _n_=1 and _ppvb=0 then do; 
         _sensa=0; _tpa=0; _fpa=_falpos_;
      end;
      do _sensitivity=round(_sensa+1/&npoints-1/(2*&npoints),1/&npoints) to 
                      round(_sensit_-1/(2*&npoints),1/&npoints) by 1/&npoints;
        _tpb=_sensitivity*_npos;
        _x=_tpb-_tpa;
        _fpb=_fpa+_x*((_falpos_-_fpa)/(_tpb-_tpa));
        _ppv=_tpb/(_tpb+_fpb);
        if abs(_sensitivity-_sensb)>&sensdelta then output;
      end;
   end;
   _threshold=_prob_;
   _sensitivity=_sensb+_inc; _ppv=_ppvb; 
   _marksens=_sensb+_inc; _markppv=_ppvb; 
   %if &opt %then %do;
      _fscore=(1+&beta**2)*((_sensitivity*_ppv)/(_sensitivity+(_ppv*&beta**2)));
      _mden=(_pos_+_falpos_)*(_pos_+_falneg_)*(_neg_+_falpos_)*(_neg_+_falneg_);
      if _mden ne 0 then _mscore=((_pos_*_neg_)-(_falpos_*_falneg_))/sqrt(_mden);
   %end;
   output;
   _sensa=_sensit_; _tpa=_pos_; _fpa=_falpos_;
   if _eof then do; _sensitivity=_sensitivity+&sensdelta; output; end;
   run;
   
/* Compute optional area under P-R curve and store for display in plot */
%if &showarea %then %do;
   proc expand data=_pr out=_tmp method=join;
      convert _ppv=area / observed=(beginning,total) transformout=(sum);
      id _sensitivity;
      run;
   proc sql noprint;
      select put(max(area),6.4) into :area from _tmp;
      quit;
%end;
   
/* Find overall positive proportion and optimal F score and MCC (maximums).
   Store for display in plot 
*/
proc sql noprint;
   %if &pprob %then select put((_pos_+_falneg_)/(_pos_+_neg_+_falpos_+_falneg_),6.4) 
                    into :posprob from &prdata;;
   quit;
%if &opt %then %do;
   proc summary data=_pr; 
      var _fscore _mscore;
      output out=_max max=_maxf _maxm;
      run;
   data _pr; set _pr;
      if _n_=1 then set _max;
      drop _type_ _freq_ _maxf _maxm;
      if _fscore=_maxf then do;
         _fMaxPPV=_ppv; _fMaxSens=_sensitivity;
         call symput("maxf",put(_maxf,6.4));
         call symput("maxfprob",put(_threshold,6.4));
      end;
      if _mscore=_maxm then do;
         _mMaxPPV=_ppv; _mMaxSens=_sensitivity;
         call symput("maxm",put(_maxm,6.4));
         call symput("maxmprob",put(_threshold,6.4));
      end;
      run;
%end;

/* Produce P-R plot with optional optimal points */
%let cv=;
%if &type=ctable %then %let cv=Crossvalidated;
proc sgplot data=_pr aspect=1   %if &opt=0 %then noautolegend;  ;
   xaxis values=(0 to 1 by .25) grid 
         offsetmin=.05 offsetmax=.05 label="Recall / Sensitivity"; 
   yaxis values=(0 to 1 by .25) grid 
         offsetmin=.05 offsetmax=.05 label="Precision / PPV";
   %if &pprob %then refline &posprob;;
   series y=_ppv x=_sensitivity;
   %if &markers %then scatter y=_markppv x=_marksens;;
   %if &opt %then %do;
      scatter y=_fmaxppv x=_fmaxsens / markerattrs=(symbol=squarefilled color=red size=10)
              name='fscore' legendlabel="Max F(&beta) = &maxf at Threshold = &maxfprob";
      scatter y=_mmaxppv x=_mmaxsens / markerattrs=(symbol=circlefilled color=orange size=10)
              name='mscore' legendlabel="Max MCC  = &maxm at Threshold = &maxmprob";
   %end;
   %if &pprob or &showarea %then %do;
     inset (%if &showarea %then "Area under curve" = "&area";
            %if &pprob %then "Positive proportion" = "&posprob";) 
           / opaque position=&textloc;
   %end;
   %if &opt %then keylegend "fscore" "mscore" / down=2;;
   title "&cv Precision-Recall Curve";
   run;

/* Find observation(s) in the inpred= data with same or nearest probability threshold */
%if &opt and &inpred ne and &pred ne and &optvars ne %then %do;
   data _optobs; set _pr; 
      where _fmaxppv ne . or _mmaxppv ne .; 
      drop _mark:;
      run;
   data _optmatch; 
      set _optobs; 
      _mindiff=1; _minpt=1;
      retain _mindiff _minpt;
      do _i=1 to _nobs;
        set &inpred point=_i nobs=_nobs;
        if &pred ne . then do;
           _diff=abs(_threshold-&pred); 
           if _i=1 then do; _mindiff=_diff; _minpt=1; end;
           if _diff<_mindiff then do; _mindiff=_diff; _minpt=_i; end;
        end;
        if _i=_nobs then do; set &inpred point=_minpt; output; end;
      end;
      run;
   data _PRopt; set _optmatch; 
      if _fmaxppv ne . then do; _OptName="Max F(&beta)"; _OptValue=_fscore; output; end;
      if _mmaxppv ne . then do; _OptName="Max MCC"; _OptValue=_mscore; output; end;
      drop _diff _sensitivity _ppv;
      run;
   proc sort data=_PRopt;
      by _optname;
      run;
   proc print data=_PRopt label split="/"; 
     id _optname _optvalue; 
     var   %if &type=ctable %then _threshold &pred;   &optvars; 
     label _optname="Optimality/Statistic" _optvalue="Optimality/Value"
           %if &type=ctable %then _threshold="Threshold/at Optimal" 
           &pred="Closest/Threshold";
     ;
     title "Optimal Points on the P-R Curve";
     run;
%end;
   
%exit:
%if %index(&version,DEBUG)=0 %then %do;  
   options nonotes;;
   proc datasets nolist nowarn;
     delete _tmp _prctbl _max _opt:;
     run; quit;
%end;
%if %index(&version,DEBUG) %then %do;
   options nomprint nomlogic nosymbolgen;
   %put _user_;
%end;
options &notesopt;
title;
%let time = %sysfunc(round(%sysevalf(%sysfunc(datetime()) - &time), 0.01));
%put NOTE: The &sysmacroname macro used &time seconds.;
%mend;
