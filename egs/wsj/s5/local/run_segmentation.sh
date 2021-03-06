#!/bin/bash

# Copyright 2014  Guoguo Chen
# Apache 2.0

# This script demonstrates how to re-segment long audios into short segments.
# The basic idea is to decode with an existing in-domain acoustic model, and a
# bigram language model built from the reference, and then work out the
# segmentation from a ctm like file.

. ./cmd.sh
. ./path.sh

local/append_utterances.sh data/train_si284 data/train_si284_long
steps/cleanup/split_long_utterance.sh \
  --seg-length 30 --overlap-length 5 \
  data/train_si284_long data/train_si284_split

steps/make_mfcc.sh --cmd "$train_cmd" --nj 64 \
  data/train_si284_split exp/make_mfcc/train_si284_split mfcc || exit 1;
steps/compute_cmvn_stats.sh data/train_si284_split \
  exp/make_mfcc/train_si284_split mfcc || exit 1;

steps/cleanup/make_segmentation_graph.sh \
  --cmd "$mkgraph_cmd" --nj 32 \
  data/train_si284_split/ data/lang exp/tri2b/ \
  exp/tri2b/graph_train_si284_split || exit 1;

steps/cleanup/decode_segmentation.sh \
  --nj 64 --cmd "$decode_cmd" --skip-scoring true \
  exp/tri2b/graph_train_si284_split/lats \
  data/train_si284_split exp/tri2b/decode_train_si284_split || exit 1;

steps/get_ctm.sh --cmd "$decode_cmd" data/train_si284_split \
  exp/tri2b/graph_train_si284_split exp/tri2b/decode_train_si284_split

steps/cleanup/make_segmentation_data_dir.sh --wer-cutoff 0.9 \
  --min-sil-length 0.5 --max-seg-length 15 --min-seg-length 1 \
  exp/tri2b/decode_train_si284_split/score_10/train_si284_split.ctm \
  data/train_si284_split data/train_si284_reseg

# Now, use the re-segmented data for training.
steps/make_mfcc.sh --cmd "$train_cmd" --nj 64 \
  data/train_si284_reseg exp/make_mfcc/train_si284_reseg mfcc || exit 1;
steps/compute_cmvn_stats.sh data/train_si284_reseg \
  exp/make_mfcc/train_si284_reseg mfcc || exit 1;

steps/align_fmllr.sh --nj 20 --cmd "$train_cmd" \
  data/train_si284_reseg data/lang exp/tri3b exp/tri3b_ali_si284_reseg || exit 1;

steps/train_sat.sh  --cmd "$train_cmd" \
  4200 40000 data/train_si284_reseg \
  data/lang exp/tri3b_ali_si284_reseg exp/tri4c || exit 1;

utils/mkgraph.sh data/lang_test_tgpr exp/tri4c exp/tri4c/graph_tgpr || exit 1;
steps/decode_fmllr.sh --nj 10 --cmd "$decode_cmd" \
  exp/tri4c/graph_tgpr data/test_dev93 exp/tri4c/decode_tgpr_dev93 || exit 1;
steps/decode_fmllr.sh --nj 8 --cmd "$decode_cmd" \
  exp/tri4c/graph_tgpr data/test_eval92 exp/tri4c/decode_tgpr_eval92 || exit 1;
