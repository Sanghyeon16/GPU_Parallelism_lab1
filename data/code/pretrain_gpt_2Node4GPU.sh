#!/bin/bash
#SBATCH --job-name=dli
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1          # crucial - only 1 task per dist per node!
##SBATCH --gres=gpu:4                 # number of gpus


set -x -e


echo "START TIME: $(date)"

DATA_OUTPUT_PATH=/dli/megatron/checkpoints/tr8-104B
CHECKPOINT_PATH=/dli/megatron/checkpoints
TENSORBOARD_PATH=/dli/megatron/tensorboard
LOGS_PATH=/dli/megatron/logs


VOCAB_FILE=/dli/megatron/GPT-2_assets/gpt2-vocab.json
MERGE_FILE=/dli/megatron/GPT-2_assets/gpt2-merges.txt
DATA_PATH=/dli/megatron/GPT-2_assets/my-gpt2_text_document


MASTER_ADDR=$(scontrol show hostnames $SLURM_JOB_NODELIST | head -n 1)
MASTER_PORT=6000

GPUS_PER_NODE=2
NNODES=2
TP_SIZE=1
PP_SIZE=1
MICRO_BATCH_SIZE=4
GLOBAL_BATCH_SIZE=16
NLAYERS=12
NHIDDEN=768
NHEADS=32
SEQ_LEN=1024
VOCAB_SIZE=50257
SAVE_INTERVAL=300



OPTIMIZER_ARGS=" \
            --optimizer adam \
            --adam-beta1 0.9 \
            --adam-beta2 0.95 \
            --adam-eps 1e-8 \
            --lr 6e-5 \
            --min-lr 6e-6 \
            --lr-decay-style cosine \
            --lr-decay-iters 800 \
            --lr-warmup-fraction .01 \
            --clip-grad 1.0 \
            --weight-decay 1e-1 \
              "

EXIT_OPTS=" \
            --exit-duration-in-mins 1190 \
          "

GPT_ARGS=" \
            --num-layers $NLAYERS \
            --hidden-size $NHIDDEN \
            --num-attention-heads $NHEADS \
            --seq-length $SEQ_LEN \
            --max-position-embeddings $SEQ_LEN \
            --micro-batch-size $MICRO_BATCH_SIZE \
            --global-batch-size $GLOBAL_BATCH_SIZE \
            --train-iters 100 \
            --vocab-file $VOCAB_FILE \
            --merge-file $MERGE_FILE \
            --init-method-std 0.006 \
            --fp16 \
            --checkpoint-activations \
            $OPTIMIZER_ARGS \
            $EXIT_OPTS \
        "

OUTPUT_ARGS=" \
            --log-interval 10 \
            --save-interval $SAVE_INTERVAL \
            --eval-interval 1000 \
            --eval-iters 10 \
            --tensorboard-dir $TENSORBOARD_PATH \
            --tensorboard-queue-size 5 \
            --log-timers-to-tensorboard \
            --log-batch-size-to-tensorboard \
            --log-validation-ppl-to-tensorboard \
            "


export LAUNCHER="python -u -m torch.distributed.launch \
                --nproc_per_node $GPUS_PER_NODE \
                --nnodes $NNODES \
                --master_addr $MASTER_ADDR \
                --master_port $MASTER_PORT \
                "

export CMD=" \
               `pwd`/Megatron-LM/pretrain_gpt.py \
               --tensor-model-parallel-size $TP_SIZE \
               --pipeline-model-parallel-size $PP_SIZE \
               $GPT_ARGS \
               $OUTPUT_ARGS \
               --save $CHECKPOINT_PATH \
               --data-path $DATA_PATH \
               --data-impl mmap \
               --split 949,50,1 \
               --distributed-backend nccl \
             "

echo $CMD
NAME="log"


clear; srun --jobid $SLURM_JOBID bash -c '$LAUNCHER --node_rank $SLURM_PROCID $CMD' 2>&1 | tee -a $LOGS_PATH/main_log.txt
echo "END TIME: $(date)"
