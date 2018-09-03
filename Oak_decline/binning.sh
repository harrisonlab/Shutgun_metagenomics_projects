PREFIX=BIGWOOD # and etc.
P1=${PREFIX:0:1}

# functional binning with HirBin
# I've had to hack some of the HirBin scripts 

# HirBin does an hmm alignment of an assembly to a protein domain database 
# this will take a looong time unless the assembly and preferbly the hmm database is divided into chunks

# it has three/four steps

# annotate uses functionalAnnotaion.py, but splits input file into 20,000 droid chunks for running on cluster (25 concurrent jobs)
#functionalAnnotation.py -m METADATA_FILE -db DATABASE_FILE -e EVALUE_CUTOFF -n N -p MAX_ACCEPTABLE_OVERLAP

$PROJECT_FOLDER/metagenomics_pipeline/scripts/fun_bin.sh \
 1 $PROJECT_FOLDER/data/assembled/megahit/$PREFIX \
 $PREFIX.contigs.fa \
 ~/pipelines/common/resources/pfam/Pfam-A.hmm \
 -e 1e-03

# concatenate annotate output
find -type f -name X.gff|head -n1|xargs -I% head -n1 % >$PREFIX.gff
find -type f -name X.gff|xargs -I% grep -v "##" % >>$PREFIX.gff
find -type f -name X.pep|xargs -I% cat % >$PREFIX.pep
find -type f -name X.hmmout|head -n1|xargs -I% head -n3 % >$PREFIX.hmmout   
find -type f -name X.hmmout|xargs -I% grep -v "#" % >>$PREFIX.hmmout
find -type f -name X.hmmout|head -n1|xargs -I% tail -n10 % >>$PREFIX.hmmout

grep -v "#" $PREFIX.hmmout|awk -F" " '($21~/^[0-9]+$/) && ($20~/^[0-9]+$/) {print $4,$1,$20,$21,$3,$7}' OFS="\t" > $PREFIX.hmm.cut
awk -F"\t" '{print $1}' $PREFIX.hmm.cut|sort|uniq > $PREFIX.domains # this is better method as some domains may not be present in gff due to filtering
# cut -f9 $PREFIX.gff|sort|uniq|sed 's/ID=//'|tail -n +2 > $PREFIX.2.domains # the tail bit gets rid of the first line of output an d the grep removes errors in the output

# Get gff with different MAX_ACCEPTABLE_OVERLAP - example below will produce gff with all overlapping features
con_coor.py -p 1 -o $PREFIX.2.gff -d $PREFIX.pep -m $PREFIX.hmmout

# mapping
# mapping is not implemented very well in HirBin, will do this seperately with bbmap
# align reads to assembly - will need to index first
bbmap.sh ref=$PREFIX.contigs.fa.gz usemodulo=t #k=11

for FR in $PROJECT_FOLDER/data/fastq/$P1*_1.fq.gz; do
  RR=$(sed 's/_1/_2/' <<< $FR)
  $PROJECT_FOLDER/metagenomics_pipeline/scripts/PIPELINE.sh -c align -p bbmap \
  16 blacklace[01][0-9].blacklace \
  $PROJECT_FOLDER/data/assembled/aligned/megahit \
  $PREFIX \
  $PROJECT_FOLDER/data/assembled/megahit/$PREFIX/${PREFIX}.contigs.fa.gz \
  $FR \
  $RR \
  maxindel=100 \
  unpigz=t \
  touppercase=t \
  path=$PROJECT_FOLDER/data/assembled/megahit/$PREFIX/ 
  usemodulo=T 
done

# bedtools code is inefficient at getting over-lapping counts (if min overlap is set to 1)
# I've written something in perl which is way less memory hungry and takes about a millionth of the time to run
# output is not a cov file but just counts per domain - not certain the sub-binning is worth while (could modify bam_count to return a cov/tab file to implement this step)
# takes about ten minutes on a single core to run, could easily get it to produce a cov file
# bam_scaffold_count.pl will output a cov file rather than counts per domain, it is memory hungry ~10G for large (>2G) gff files
samtools view bam_file|~/pipelines/metagenomics/scripts/bam_scaffold_count.pl $PREFIX.gff > bam_counts.txt
samtools view bam_file|~/pipelines/metagenomics/scripts/bam_scaffold_count.pl $PREFIX.gff cov> bam_file.cov

for BAM in $PROJECT_FOLDER/data/assembled/aligned/megahit/$P1*.bam; do
  $PROJECT_FOLDER/metagenomics_pipeline/scripts/PIPELINE.sh -c coverage -p bam_count \
  blacklace[01][0-9].blacklace \
  $BAM \
  $PROJECT_FOLDER/data/assembled/megahit/$PREFIX/${PREFIX}.gff \
  $PROJECT_FOLDER/data/assembled/counts/megahit \
  cov
done

Rscript $PROJECT_FOLDER/metagenomics_pipeline/scripts/cov_count.R "." "$P1.*\\.cov" "$PREFIX.countData"

# Sub binning - if required
# I've hacked around with a few of the HirBin settings - for speed mostly and for consistency (or the lack of) in domain names
# will require a tab (converted cov) file from bam_scaffold_count.pl e.g. awk -F"\t" '{sub("ID=","|",$(NF-1));OUT=$1$(NF-1)":"$4":"$5":"$7;print OUT,$NF}' OFS="\t" x.cov > x.tab
for F in $P1*.cov; do
  O=$(sed 's/_.*_L/_L/' <<<$F|sed 's/_1\.cov/.tab/')
  awk -F"\t" '{sub("ID=","|",$(NF-1));OUT=$1$(NF-1)":"$4":"$5":"$7;print OUT,$NF}' OFS="\t" $F > $O
done 

# then create the required metadata file
echo -e \
"Name\tGroup\tReference\tAnnotation\tCounts\tDomain\n"\
"$PREFIX\tSTATUS\t$PREFIX.pep\t$PREFIX.hmm.cut\tEMPTY\t$PREFIX.domains" > metadata.txt

# The extractSequences module of clusterBinsToSubbins is inpractical for large pep files - the R script subbin_fasta_extractor.R should be used in it's palace

Rscript subbin_fasta_extractor.R $PREFIX.hmm.cut $PREFIX.pep $PREFIX_hirbin_output
# for some reason this R script didn't work correctly on the latest round. The below awk scripts will quickly fix it, but very odd...
# it due to a problem in reordeing the rows

for F in *.fasta; do
  awk '/^>/ {printf("\n%s\n",$0);next; } { printf("%s",$0);}  END {printf("\n");}' $F|sed -e '1d' > ${F}.2
done

for F in *.2; do
  G=$(sed 's/\..*//' <<<$F) 
  grep ">.*$G" -A 1 --no-group-separator $F >${F}.3; 
done

for F in *.2; do
  G=$(sed 's/\..*//' <<<$F) 
  awk -F" " -v G=$G '($1~/^>/)&&($2!~G){line=$0;OUTF=$2".fasta.2.3";getline;print line >> OUTF;print >> OUTF}' $F
done

rename 's/\..*/.fasta/' *.3

# clusterBinsToSubbins.py -m metadata.txt -id 0.7 --onlyClustering -f -o  $PREFIX_hirbin_output # this will create the sub bins - use subbin_fasta_extractor in preference to this 
clusterBinsToSubbins.py -m metadata.txt -id 0.7 --reClustering --onlyClustering -f -o  $PREFIX_hirbin_output# clustering without sub bin extraction (no parsing)
clusterBinsToSubbins.py -m metadata.txt -id 0.95 --reClustering -f -o  $PREFIX_hirbin_output# recluster at a different identity plus parsing
clusterBinsToSubbins.py -m metadata.txt -id 0.7 --onlyParsing -f -o  $PREFIX_hirbin_output# this will make count files for $PREFIX.tab to the bins and sub bins 

# ergh parsing gives impossible counts for the subbins - not certain if it's a bug I've introduced in hacking the code.
# probably caused by multiple with the same name from the same contig.
# double ergh - the problem is caused earlier in the pipeline, during the naming of the bins used for the clustering step. 
# These must be unique and relatable back to the tab files - at the moment bins can join to multiple subbins, hence counts are too high.
# will need to rerun the clustering using unique names (i.e include the domain location - can be derived from the hmm hit)
# the error is in subbin_fasta_extractor - I used the same naming convention as in hirbin... 



# The below will produce a two column output of the clustering. 
# Column 1 is the name of the bin and column 2 is the name of the sub bin to which it belongs

awk -F"\t" '($1~/[HS]/){print $2, $9, $10}' *.uc| \
awk -F" " '{sub(/_[0-9]+$/,"",$2);sub(/_[0-9]+$/,"",$6);A=$2"\t"$3"\t"$1"\t"$4"\t"$5;if($6~/\*/){B=A}else{B=$6"\t"$7"\t"$1"\t"$8"\t"$9"\t"};print A,B}' OFS="\t" > reduced.txt

# awk -F" " '{sub(/_[0-9]+$/,"",$2);sub(/_[0-9]+$/,"",$6 );A=$2"£"$1"|"$3;if($6~/\*/){B=A}else{B=$6"£"$1"|"$7};print A,B}' OFS="\t" > reduced.txt


# should be relatively easy to run through the tab files (bin_counts) and assign the counts to the correct sub_bins (reduced.txt), then rename the sub-bins.
# e.g. in SQL: SELECT subbin, SUM(count) FROM bin_counts LEFT JOIN sub_bins ON bin_count.bin = sub_bins.bin GROUP BY subbin
# should be able to convert this to R data.table/dplyr syntax
##R
library(data.table)
library(tidyverse)
library(parallel)

sub_bins   <- fread("reduced.txt",header=F) # loaded in 48 seconds
sub_bins <- unique(sub_bins) # should all be unique after the edits above

qq  <- mclapply(list.files(".","C.*.tab",full.names=F),function(x) {fread(x)},mc.cores=12)

# get count file names and substitute to required format
names <- sub("(\\.tab)","",list.files(".","*",full.names=F,recursive=F))

#### apply names to appropriate list columns and do some renaming  - splitting columns by string values (strsplit) is slow
colsToDelete <- c("TEMP","V1","DIR","BIN_ID")
mclapply(qq,function(DT) {
  DT[,c("BIN_ID","TEMP"):=tstrsplit(V1, "|",fixed=T)]
  DT[,c("DOM","START","END","DIR"):=tstrsplit(TEMP, ":",fixed=T)]
  setnames(DT,"V2","count")
  DT[,"BIN_NAME":=paste(BIN_ID,DOM,START,END,sep="_")]
  DT[, (colsToDelete) := NULL]
  setcolorder(DT,c("BIN_NAME","DOM","START","END","count"))
},mc.cores=12) # NOTE: this works as everything is being set by reference (DT references qq[[x]]), therefore no copies taken and original is modified

sub_bins[,"BIN_NAME":=paste(V1,V2,V4,V5,sep="_")]
sub_bins[,"SUB_BIN_NAME":=paste(V6,V7,V9,V10,sep="_")]
colsToDelete <- c("V1","V2","V3","V4","V5","V6","V7","V8","V9","V10","V11")
sub_bins[, (colsToDelete) := NULL]

### sum_counts systimes: plyr;1563 DT;754 parallel_DT;150 

#sum_counts <- lapply(qq,function(bin_counts) left_join(bin_counts,sub_bins) %>% group_by(SUB_BIN_NAME) %>%  summarise(sum(count)))
#sum_counts <- lapply(1:length(sum_counts),function(i) {X<-sum_counts[[i]];colnames(X)[2]<- names[i];return(as.data.table(X))})
#count_table <- sum_counts %>% purrr::reduce(full_join,by="subbin") # dplyr method - much slower than using data table method here

# or data.table way - maybe (lots of copies, will it be faster?)
sum_counts <- mclapply(qq,function(DT) {
  DDT <- copy(sub_bins)
  DDT <- DDT[DT,on="BIN_NAME"] # this is not by reference
  DDT <- DDT[,.(Count=sum(count)),.(SUB_BIN_NAME)] # this is not by reference, but wayyyy faster than plyr
  DDT 
},mc.cores=12)
count_table <- Reduce(function(...) {merge(..., all = TRUE)}, sum_counts)
fwrite(count_table,"CHESTNUTS.countData.sub_bins",sep="\t")
       
countData[,"PFAM_NAME":=sub("(k[0-9]+_)([0-9]+_)(.*)(_[0-9]+_[0-9]+$)","\\3",countData$SUB_BIN_NAME)]
