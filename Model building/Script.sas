
libname study "C:\Users\toulsie\Desktop\bib";
run;

proc format;
picture LTPVAL (round) low-.0009999999="<0.001"(noedit) .001-.09999="009.999" .1-high="0009.99";
RUN; 

proc format;
value age
low-40="<40"
40-high=">40";
run;

proc format;
value menopause
1="Pre-menopausal"
2="Post-menopausal";
run;

proc format;
value traitement
0='None'
1="HRT/pills"
2="HRT/pills";
run;

proc format;
value atcd
0='None'
1="Family history of BC"
2="Family history of BC";
run;

proc format;
value mutation
0="None"
1="BRCA1/2"
2="BRCA1/2";
run;

proc format;
value pt
1='T1'
2="T2"
3="T3"
4="T4"
5="T4"
6="T4"
7="T4"
;
run;

proc format;
value taille
0-20="<20"
20-high=">20";
run;

proc format;
value ganglion
1='N0'
2="N+"
3="N+"
4="N+"
;
run;

proc format;
value grade
1="I"
2="II"
3="III"
.="NA"
;
run;

proc format;
value emboles
.="NA"
1="Present"
0="Absent";
run;

proc format;
value ki
.="NA"
0-20="<20"
20-high=">20";
run;

proc format;
value tils
. ="NA"
0-20="<20"
20-high=">20";
run;

proc format;
value type
1='Invasive ductal carcinoma'
2="Invasive lobular carcinoma"
3="Invasive ductal carcinoma"
;
run;

proc format;
value cote
1="Right"
2="Left";
run;

proc format;
value nb
1="Unique"
2="Multiple";
run;

proc format;
value densite
5="a,b"
6="c,d";
run;

proc format;
value rehaussementfond
2="Low"
1="High";
run;

proc format;
value contours
1="Regular"
2-3="Irregular/Spiculated";
run;

proc format;
value rehaussement
1="Homogenous"
2-4="Heterogenous";
run;

proc format;
value rnm
1="Present"
0="Absent";
run;

proc format;
value cinetique
1="Ascendant"
2="Plate"
3="Wash-out";
run;

proc format;
value her
0="HER2-zero"
1-2="HER2-low"
3="HER2-positive";
run;

proc format;
value he
0="HER2-zero"
1-2="HER2-low/positive"
3="HER2-low/positive";
run;

*Import robust features (ICC > 0.75 and Spearman > 0.80) into a list format;
data list;
set study.features_ICC_spearman;
drop F1;
run; 

proc contents data=list noprint out=_contents_;
run;

proc sql noprint;
select name into :names separated by ' '
from _contents_;
quit; 
%put &names;

*Import the training set database;
data database_training;
set study.database;
if  cohorte='Validation' then delete;
if her2=0 then gold=0; else gold=1;
run;

*Perform k-fold cross validation LASSO for feature selection;
ods graphics on;
proc surveyselect data=database_training  out=traintest seed=123 samprate=0.7 method =SRS outall;
run;
ods graphics off;

ods output ParameterEstimates=paramest;
proc glmselect data=traintest plots=all seed=123 NAMELEN=35;
partition role=selected (train='1' test='0');
model her2 = &names	/selection=lasso (choose=CVex stop=7) cvmethod=random(10);
format her2 he.;
run;

*Import LASSO-selected features into a list format;
proc sql noprint;
select parameter into :feature_list separated by ' '
from paramest where parameter ne ('Intercept');
quit; 
%put &feature_list;

*Logistic model performance & Plot AUC (training set);
ods graphics on / height=7in width=6in;
proc logistic descending data =database_training plots=effect plots(only)=ROC outest=estim;
model her2 (ref="HER2-zero")= &feature_list /outroc=rocdata;
output out=pred predicted=pred;
format her2 he.;
run;
ods graphics off;

*Bootstrap 95% confidence interval;
%boot1auc(dsn=pred,marker=pred,gold=gold,boot=1000,alpha=0.05)

*Optimal cut-off value with Youden index;
ods graphics on / height=7in width=6in;
proc logistic descending data =pred  plots=effect plots(only)=ROC outest=estim;
model her2 = pred /rsquare outroc=rocdata2;
format her2 he.;
run;
ods graphics off;

data CAT3(keep=cutoff prob Sensitivity Specificity Youden d diff);
set rocdata2;
logit=log(_prob_/(1-_prob_));*calculate logit;
cutoff=(logit+2.7911)/(5.4402); *calculate cutoff;
prob= _prob_; *calculate cutoff;
Sensitivity = _SENSIT_; *calculate sensitivity;
Specificity = 1-_1MSPEC_; *calculate specificity;
Youden= _SENSIT_+ (1-_1MSPEC_)-1; *calculate Youden index;
D=sqrt((1-Sensitivity)**2+(1-Specificity)**2);
diff=abs(Sensitivity-Specificity);
run;
 
Proc sort data=CAT3 ;
by descending youden ;
run;
 
Proc print data=CAT3 (firstobs= 1 obs= 10);
TITLE 'First ten values of Youden index';
Run;

proc format;
value radiomic
low-0.669="Low"
0.669-high="High";
run;

*Compute se sp PPV and NPV (training set);
proc freq data=pred;
tables pred*HER2/senspec;
format her2 he. pred radiomic.;
run;

*Univariable analysis of main objective (training set);
data database_training_univariable;
set pred;
LABEL 
	all='All cohort' age = 'Age (years)' menopause='Menopausal status' substitutif='Hormonal substitution' atcd='Cancer history' mutation='Genetic predisposition' ptnm='Clinical tumor stage' grd_axe='Largest size (mm)'
	pN2='Clinical nodal status' rep_complete1='Pathological response' grade_ee='Grade' emboles='Lymphovascular invasion' ki67='ki67 (%)' cat_infiltrant='Molecular subtype'
	histo_cancer='Histopathology' cote_index='Side' nb_l_sion='Number of lesions' densit='Breast density' rht_fond='Glandular enhancement' masse_contours='Tumor shape'
    masse_rehaussement_interne='Tumor enhancement' birads_rnm___3='MRI associated non-mass enhancement' tils='TILs (%)' cat_infiltrant2='Hormonal receptor'
	her2="HER2 status"
   ;
	format age age. menopause menopause. substitutif traitement. atcd atcd. mutation mutation. ptnm pt. grd_axe taille. cat_infiltrant2 hr. cat_infiltrant cat. cat_infiltrant1 ca. pn2 ganglion.  grade_ee grade.  ki67 ki.  histo_cancer type. cote_index cote. nb_l_sion nb. emboles emboles. densit densite. rht_fond rehaussementfond. masse_contours contours. masse_rehaussement_interne rehaussement. birads_rnm___3 rnm. cinetique cinetique.  tils tils.  her2 he. pred radiomic.;
	run;

%UNI_LOGREG(dataset = database_training_univariable, 
	outcome = her2, 
	event = "HER2-low/positive", 
	clist = age(ref="<40")*menopause(ref="Pre-menopausal")*atcd(ref="None")*mutation(ref="None")*substitutif(ref="None")*ptnm(ref="T1")*pn2(ref="N0")*m_ta*histo_cancer*grade_ee(ref="I/II")*ki67(ref="<20")*emboles(ref="Absent")*cat_infiltrant2(ref="HR-negative")*tils(ref="<20")*densit*rht_fond*nb_l_sion*grd_axe(ref="<20")*contours(ref="2.00")*T2_intra(ref="0.00")*rht_interne(ref="0.00")*restriction_adc_oui*rht_tardif(ref="0.00")*birads_rnm___3(ref="Absent")*pred(ref="Low"),
	nlist = ,
    outpath = , 
	fname = univariable_logistic_regression_training);

*Boxplot radiomics prediction (training set);
ods graphics on;
proc sgplot data=pred noautolegend;
styleattrs datacontrastcolors=(VIGB salmon);
format her2 he.;
vbox pred / category=her2 group=HER2 lineattrs=(pattern=solid thickness=2) whiskerattrs=(pattern=solid thickness=2 ) nofill medianattrs=(thickness=3 );
*scatter x=her2 y=pred /jitter jitterwidth=0.5 group= her2 markerattrs=(symbol=CircleFilled size=6)  transparency=0.4 ;
styleattrs datacolors=(VIGB slamon);
xaxis  label="True HER2 expression" ; 
yaxis  label="Radiomic signature"  OFFSETMAX=0.2;
run;
ods graphics off;

*Repeat model performance by histomolecular category (training test);
ods graphics on / height=7in width=6in;
proc logistic descending data =database_training (where=(cat_infiltrant<3)) plots=effect plots(only)=ROC outest=estim; *Luminal HER2-negative class;
model her2 (ref="HER2-zero")= &feature_list /outroc=rocdata3;
output out=pred3 predicted=pred3;
format her2 her. pred3 radiomic.;
run;
ods graphics off;

*Bootstrap 95% confidence interval;
%boot1auc(dsn=pred3,marker=pred3,gold=gold,boot=1000,alpha=0.05)

*Import the test set database;
data database_test;
set study.database;
if cohorte='Training' then delete;
if her2=0 then gold=0; else gold=1;
run;

*Logistic model performance & Plot AUC (test set);
ods graphics on / height=7in width=6in;
proc logistic descending data =database_test plots=effect plots(only)=ROC outest=estim;
model her2 (ref="HER2-zero")= &feature_list /outroc=rocdata4;
output out=pred4 predicted=pred4;
format her2 he.;
run;
ods graphics off;

*Precision-recall analysis (test set);
%prcurve(data=rocdata4, inpred=pred4, pred=pred4, options=optimal, optvars=pred4);

*Compute se sp PPV and NPV (test set);
proc freq data=pred4  ;
tables pred4*HER2/senspec;
format her2 he. pred4 radiomic.;
run;

*Univariable analysis of main objective (test set);
data database_test_univariable;
set pred4;
LABEL 
	all='All cohort' age = 'Age (years)' menopause='Menopausal status' substitutif='Hormonal substitution' atcd='Cancer history' mutation='Genetic predisposition' ptnm='Clinical tumor stage' grd_axe='Largest size (mm)'
	pN2='Clinical nodal status' rep_complete1='Pathological response' grade_ee='Grade' emboles='Lymphovascular invasion' ki67='ki67 (%)' cat_infiltrant='Molecular subtype'
	histo_cancer='Histopathology' cote_index='Side' nb_l_sion='Number of lesions' densit='Breast density' rht_fond='Glandular enhancement' masse_contours='Tumor shape'
    masse_rehaussement_interne='Tumor enhancement' birads_rnm___3='MRI associated non-mass enhancement' tils='TILs (%)' cat_infiltrant2='Hormonal receptor'
	her2="HER2 status"
   ;
	format age age. menopause menopause. substitutif traitement. atcd atcd. mutation mutation. ptnm pt. grd_axe taille. cat_infiltrant2 hr. cat_infiltrant cat. cat_infiltrant1 ca. pn2 ganglion.  grade_ee grade.  ki67 ki.  histo_cancer type. cote_index cote. nb_l_sion nb. emboles emboles. densit densite. rht_fond rehaussementfond. masse_contours contours. masse_rehaussement_interne rehaussement. birads_rnm___3 rnm. cinetique cinetique.  tils tils.  her2 he. pred4 radiomic.;
	run;

%UNI_LOGREG(dataset = database_test_univariable, 
	outcome = her2, 
	event = "HER2-low/positive", 
	clist = age(ref="<40")*menopause(ref="Pre-menopausal")*atcd(ref="None")*mutation(ref="None")*substitutif(ref="None")*ptnm(ref="T1")*pn2(ref="N0")*m_ta*histo_cancer*grade_ee(ref="I/II")*ki67(ref="<20")*emboles(ref="Absent")*cat_infiltrant2(ref="HR-negative")*tils(ref="<20")*densit*rht_fond*nb_l_sion*grd_axe(ref="<20")*contours(ref="2.00")*T2_intra(ref="0.00")*rht_interne(ref="0.00")*restriction_adc_oui*rht_tardif(ref="0.00")*birads_rnm___3(ref="Absent")*pred4(ref="Low"),
	nlist = ,
    outpath = , 
	fname = univariable_logistic_regression_test);

*Boxplot radiomics prediction (test set);
ods graphics on;
proc sgplot data=pred4 noautolegend;
styleattrs datacontrastcolors=(VIGB salmon);
format her2 he.;
vbox pred4 / category=her2 group=HER2 lineattrs=(pattern=solid thickness=2) whiskerattrs=(pattern=solid thickness=2 ) nofill medianattrs=(thickness=3 );
*scatter x=her2 y=pred4 /jitter jitterwidth=0.5 group=her2 markerattrs=(symbol=CircleFilled size=6)  transparency=0.4 ;
styleattrs datacolors=(VIGB slamon);
xaxis  label="True HER2 expression" ; 
yaxis  label="Radiomic signature"  OFFSETMAX=0.2;
run;
ods graphics off;

*Repeat model performance by histomolecular category (test set);
ods graphics on / height=7in width=6in;
proc logistic descending data =database_test (where=(cat_infiltrant>4)) plots=effect plots(only)=ROC outest=estim; *TNBC class;
model her2 (ref="HER2-zero")= &feature_list /outroc=rocdata5;
output out=pred5 predicted=pred5;
format her2 her. pred5 radiomic.;
run;
ods graphics off;

*Bootstrap 95% confidence interval;
%boot1auc(dsn=pred5,marker=pred5,gold=gold,boot=1000,alpha=0.05);
