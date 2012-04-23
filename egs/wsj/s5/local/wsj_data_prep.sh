#!/bin/bash

# Copyright 2009-2012  Microsoft Corporation  Daniel Povey
# Apache 2.0.


if [ $# -le 3 ]; then
   echo "Arguments should be a list of WSJ directories, see ../run.sh for example."
   exit 1;
fi

mkdir -p data/local
local=`pwd`/local
utils=`pwd`/utils

sph2pipe=`cd ../../..; echo $PWD/tools/sph2pipe_v2.5/sph2pipe`
if [ ! -x $sph2pipe ]; then
   echo "Could not find (or execute) the sph2pipe program at $sph2pipe";
   exit 1;
fi
export PATH=$PATH:`pwd`/../../../tools/irstlm/bin

cd data/local


# Make directory of links to the WSJ disks such as 11-13.1.  This relies on the command
# line arguments being absolute pathnames.
rm -r links/ 2>/dev/null
mkdir links/
ln -s $* links

# Do some basic checks that we have what we expected.
if [ ! -d links/11-13.1 -o ! -d links/13-34.1 -o ! -d links/11-2.1 ]; then
  echo "wsj_data_prep.sh: Spot check of command line arguments failed"
  echo "Command line arguments must be absolute pathnames to WSJ directories"
  echo "with names like 11-13.1."
  exit 1;
fi

# This version for SI-84

cat links/11-13.1/wsj0/doc/indices/train/tr_s_wv1.ndx | \
 $local/ndx2flist.pl $* | sort | \
 grep -v 11-2.1/wsj0/si_tr_s/401 > train_si84.flist

# This version for SI-284
cat links/13-34.1/wsj1/doc/indices/si_tr_s.ndx \
 links/11-13.1/wsj0/doc/indices/train/tr_s_wv1.ndx | \
 $local/ndx2flist.pl  $* | sort | \
 grep -v 11-2.1/wsj0/si_tr_s/401 > train_si284.flist


# Now for the test sets.
# links/13-34.1/wsj1/doc/indices/readme.doc 
# describes all the different test sets.
# Note: each test-set seems to come in multiple versions depending
# on different vocabulary sizes, verbalized vs. non-verbalized
# pronunciations, etc.  We use the largest vocab and non-verbalized
# pronunciations.
# The most normal one seems to be the "baseline 60k test set", which
# is h1_p0. 

# Nov'92 (333 utts)
# These index files have a slightly different format;
# have to add .wv1
cat links/11-13.1/wsj0/doc/indices/test/nvp/si_et_20.ndx | \
  $local/ndx2flist.pl $* |  awk '{printf("%s.wv1\n", $1)}' | \
  sort > test_eval92.flist

# Nov'92 (330 utts, 5k vocab)
cat links/11-13.1/wsj0/doc/indices/test/nvp/si_et_05.ndx | \
  $local/ndx2flist.pl $* |  awk '{printf("%s.wv1\n", $1)}' | \
  sort > test_eval92_5k.flist

# Nov'93: (213 utts)
# Have to replace a wrong disk-id.
cat links/13-32.1/wsj1/doc/indices/wsj1/eval/h1_p0.ndx | \
  sed s/13_32_1/13_33_1/ | \
  $local/ndx2flist.pl $* | sort > test_eval93.flist

# Nov'93: (213 utts, 5k)
cat links/13-32.1/wsj1/doc/indices/wsj1/eval/h2_p0.ndx | \
  sed s/13_32_1/13_33_1/ | \
  $local/ndx2flist.pl $* | sort > test_eval93_5k.flist

# Dev-set for Nov'93 (503 utts)
cat links/13-34.1/wsj1/doc/indices/h1_p0.ndx | \
  $local/ndx2flist.pl $* | sort > test_dev93.flist

# Dev-set for Nov'93 (513 utts, 5k vocab)
cat links/13-34.1/wsj1/doc/indices/h2_p0.ndx | \
  $local/ndx2flist.pl $* | sort > test_dev93_5k.flist


# Dev-set Hub 1,2 (503, 913 utterances)

# Note: the ???'s below match WSJ and SI_DT, or wsj and si_dt.  
# Sometimes this gets copied from the CD's with upcasing, don't know 
# why (could be older versions of the disks).
find `readlink links/13-16.1`/???1/??_??_20 -print | grep ".WV1" | sort > dev_dt_20.flist
find `readlink links/13-16.1`/???1/??_??_05 -print | grep ".WV1" | sort > dev_dt_05.flist


# Finding the transcript files:
for x in $*; do find -L $x -iname '*.dot'; done > dot_files.flist

# Convert the transcripts into our format (no normalization yet)
for x in train_si84 train_si284 test_eval92 test_eval93 test_dev93 test_eval92_5k test_eval93_5k test_dev93_5k dev_dt_05 dev_dt_20; do
   $local/flist2scp.pl $x.flist | sort > ${x}_sph.scp
   cat ${x}_sph.scp | awk '{print $1}' | $local/find_transcripts.pl  dot_files.flist > $x.trans1
done

# Do some basic normalization steps.  At this point we don't remove OOVs--
# that will be done inside the training scripts, as we'd like to make the
# data-preparation stage independent of the specific lexicon used.
noiseword="<NOISE>";
for x in train_si84 train_si284 test_eval92 test_eval93 test_dev93 test_eval92_5k test_eval93_5k test_dev93_5k dev_dt_05 dev_dt_20; do
   cat $x.trans1 | $local/normalize_transcript.pl $noiseword | sort > $x.txt || exit 1;
done
 
# Create scp's with wav's. (the wv1 in the distribution is not really wav, it is sph.)
for x in train_si84 train_si284 test_eval92 test_eval93 test_dev93 test_eval92_5k test_eval93_5k test_dev93_5k dev_dt_05 dev_dt_20; do
  awk '{printf("%s '$sph2pipe' -f wav %s |\n", $1, $2);}' < ${x}_sph.scp > ${x}_wav.scp
done

# Make the utt2spk and spk2utt files.
for x in train_si84 train_si284 test_eval92 test_eval93 test_dev93 test_eval92_5k test_eval93_5k test_dev93_5k dev_dt_05 dev_dt_20; do
   cat ${x}_sph.scp | awk '{print $1}' | perl -ane 'chop; m:^...:; print "$_ $&\n";' > $x.utt2spk
   cat $x.utt2spk | $utils/utt2spk_to_spk2utt.pl > $x.spk2utt || exit 1;
done


#in case we want to limit lm's on most frequent words, copy lm training word frequency list
cp links/13-32.1/wsj1/doc/lng_modl/vocab/wfl_64.lst .

# The 20K vocab, open-vocabulary language model (i.e. the one with UNK), without
# verbalized pronunciations.   This is the most common test setup, I understand.

cp links/13-32.1/wsj1/doc/lng_modl/base_lm/bcb20onp.z lm_bg.arpa.gz || exit 1;
chmod u+w lm_bg.arpa.gz

# trigram would be:
cat links/13-32.1/wsj1/doc/lng_modl/base_lm/tcb20onp.z | \
 perl -e 'while(<>){ if(m/^\\data\\/){ print; last;  } } while(<>){ print; }' | \
 gzip -c -f > lm_tg.arpa.gz || exit 1;

prune-lm --threshold=1e-7 lm_tg.arpa.gz lm_tgpr.arpa || exit 1;
gzip -f lm_tgpr.arpa || exit 1;

# repeat for 5k language models
cp links/13-32.1/wsj1/doc/lng_modl/base_lm/bcb05onp.z  lm_bg_5k.arpa.gz || exit 1;
chmod u+w lm_bg_5k.arpa.gz

# trigram would be: !only closed vocabulary here!
cp links/13-32.1/wsj1/doc/lng_modl/base_lm/tcb05cnp.z lm_tg_5k.arpa.gz || exit 1;
chmod u+w lm_tg_5k.arpa.gz
gunzip lm_tg_5k.arpa.gz
tail -n 4328839 lm_tg_5k.arpa | gzip -c -f > lm_tg_5k.arpa.gz
rm lm_tg_5k.arpa

prune-lm --threshold=1e-7 lm_tg_5k.arpa.gz lm_tgpr_5k.arpa || exit 1;
gzip -f lm_tgpr_5k.arpa || exit 1;


if [ ! -f wsj0-train-spkrinfo.txt ]; then
  wget http://www.ldc.upenn.edu/Catalog/docs/LDC93S6A/wsj0-train-spkrinfo.txt
fi

if [ ! -f wsj0-train-spkrinfo.txt ]; then
  echo "Could not get the spkrinfo.txt file from LDC website (moved)?"
  echo "This is possibly omitted from the training disks; couldn't find it." 
  echo "Everything else may have worked; we just may be missing gender info"
  echo "which is only needed for VTLN-related diagnostics anyway."
  exit 1
fi
# Note: wsj0-train-spkrinfo.txt doesn't seem to be on the disks but the
# LDC put it on the web.  Perhaps it was accidentally omitted from the
# disks.  

cat links/11-13.1/wsj0/doc/spkrinfo.txt \
    links/13-32.1/wsj1/doc/evl_spok/spkrinfo.txt \
    links/13-34.1/wsj1/doc/dev_spok/spkrinfo.txt \
    links/13-34.1/wsj1/doc/train/spkrinfo.txt \
   ./wsj0-train-spkrinfo.txt  | \
    perl -ane 'tr/A-Z/a-z/; m/^;/ || print;' | \
   awk '{print $1, $2}' | grep -v -- -- | sort | uniq > spk2gender


echo "Data preparation succeeded"