# add project folders
mkdir -p ~/projects/Oak_decline/metagenomics/data
PROJECT_FOLDER=~/projects/Oak_decline/metagenomics
ln -s ~/pipelines/metagenomics $PROJECT_FOLDER/metagenomics_pipeline
ln -s ~/pipelines/metatranscriptomics $PROJECT_FOLDER/metatranscriptomics_pipeline

mkdir $PROJECT_FOLDER/data/fastq
mkdir $PROJECT_FOLDER/data/trimmed
mkdir $PROJECT_FOLDER/data/filtered
mkdir $PROJECT_FOLDER/data/normalised

# adapter/phix/filtering
for FR in $PROJECT_FOLDER/data/fastq/*_1.fq.gz; do
  RR=$(sed 's/_1/_2/' <<< $FR)
  $PROJECT_FOLDER/metatranscriptomics_pipeline/scripts/PIPELINE.sh -c MEGAFILT \
  $PROJECT_FOLDER/metatranscriptomics_pipeline/common/resources/adapters/truseq.fa \
  $PROJECT_FOLDER/metatranscriptomics_pipeline/common/resources/contaminants/phix_174.fa \
  NOTHING \
  $PROJECT_FOLDER/data/filtered \
  $FR \
  $RR \
  false
done  

# human contaminant filter
for FR in $PROJECT_FOLDER/data/filtered/*_1.fq.gz.filtered.fq.gz; do
  RR=$(sed 's/_1/_2/' <<< $FR)
  $PROJECT_FOLDER/metagenomics_pipeline/scripts/PIPELINE.sh -c filter -p bbmap \
  $PROJECT_FOLDER/metagenomics_pipeline/common/resources/contaminants/bbmap_human/hg19_main_mask_ribo_animal_allplant_allfungus.fa \
  $PROJECT_FOLDER/data/cleaned \
  $FR \
  $RR \
  path=$PROJECT_FOLDER/metagenomics_pipeline/common/resources/contaminants/bbmap_human \
  minid=0.95 \
  maxindel=3 \
  bwr=0.16 \
  bw=12 \
  quickmatch \
  fast \
  minhits=2 \
  t=12
done

# normalition and error correction - normalisation may not be necessary
for FR in $PROJECT_FOLDER/data/cleaned/*_1.fq.gz.filtered.fq.gz.cleaned.fq.gz; do
  RR=$(sed 's/_1/_2/' <<< $FR)
  $PROJECT_FOLDER/metagenomics_pipeline/scripts/PIPELINE.sh -c normalise -p bbnorm \
  $PROJECT_FOLDER/data/corrected \
  $FR \
  $RR  \
  target=100 \
  min=2 \
  ecc=t \
  passes=1 \
  bits=16 prefilter
done

# rename files (should get the scripts to name them correctly...)
rename 's/\.filtered.*//' $PROJECT_FOLDER/data/filtered/*
rename 's/\.filtered.*//' $PROJECT_FOLDER/data/cleaned/*
rename 's/\.filtered.*//' $PROJECT_FOLDER/data/corrected/*
