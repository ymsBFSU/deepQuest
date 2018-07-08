echo "Analysing input parameters"

PARSED_OPTIONS=$(getopt -n "$0"  -o h --long "help,pred-task:,pred-target:,pred-source:,est-task:,est-target:,est-source:,score:,device:"  -- "$@")

if [ $# -eq 0 ]; 
then
  echo 'No parameters provided. use --help option for more details'
  exit 1
fi
 
eval set -- "$PARSED_OPTIONS"

while true;
do
  case "$1" in
 
    -h|--help)
     echo -e "usage $0 -h display help \n \
    --help display help \n \
    --pred-task name of the folder containing the Predictor task \n \
    --pred-source extension of the Predictor source language file \n \
    --pred-target extension of the Predictor target (human reference translations) language file \n \
    --est-task name of the folder containing the Estimator QE task \n \
    --est-source extension of the Estimator source language file \n \
    --est-target extension of the Estimator machine-translated file \n \
    --score extension of the file with predicted scores \n \
    --device cuda device "
      shift
      exit 0;;
   
    --pred-task)
      if [ -n "$2" ];
      then
        pred_task_name=$2
      fi
      shift 2;;
  
    --est-task)
      if [ -n "$2" ];
      then
        est_task_name=$2
      fi
      shift 2;;

 
    --pred-source)
      if [ -n "$2" ];
      then
        pred_src=$2
      fi
      shift 2;;
   
   --pred-target)
      if [ -n "$2" ];
      then
        pred_trg=$2
      fi
      shift 2;;
   
   --est-source)
      if [ -n "$2" ];
      then
        est_src=$2
      fi
      shift 2;;

   --est-target)
      if [ -n "$2" ];
      then
        est_trg=$2
      fi
      shift 2;;
    
   --score)
      if [ -n "$2" ];
      then
        score=$2
      fi
      shift 2;;

   --device)
      if [ -n "$2" ];
      then
        device=$2
      fi
      shift 2;;

    --)
      shift;
      break;;
  esac
done


# we copy the base config
pred_conf=config-Predictor-small.py
pred_model_type=Predictor
pred_model_name=${pred_task_name}_${pred_src}${pred_trg}_${pred_model_type}

cp ../configs/$pred_conf ./config.py

echo "Traning the model "${pred_model_name}
THEANO_FLAGS=device=$device python main.py TASK_NAME=$pred_task_name DATASET_NAME=$pred_task_name DATA_ROOT_PATH=examples/${pred_task_name} SRC_LAN=${pred_src} TRG_LAN=${pred_trg} MODEL_TYPE=$pred_model_type MAX_EPOCH=2 SAVE_EACH_EVALUATION=True > log-${pred_model_name}.txt 2>&1

# we copy the base config
est_conf=config-sentQEPostech.py
est_model_type=EstimatorSent
est_model_name=${est_task_name}_${est_src}${est_trg}_${est_model_type}
patience=5

# pre-trained Predictor Weights + Vocab
pred_vocab=datasets/Dataset_${pred_task_name}_${pred_src}${pred_trg}.pkl
pred_weights=trained_models/${pred_model_name}/epoch_2_weights.h5

cp ../configs/$est_conf ./config.py

echo "Traning the model "${est_model_name}
THEANO_FLAGS=device=$device python main.py TASK_NAME=$est_task_name DATASET_NAME=$est_task_name DATA_ROOT_PATH=examples/${est_task_name} SRC_LAN=${est_src} TRG_LAN=${est_trg} PRED_SCORE=$score PRED_VOCAB=$pred_vocab PRED_WEIGHTS=$pred_weights MODEL_TYPE=$est_model_type NEW_EVAL_ON_SETS=val PATIENCE=$patience SAVE_EACH_EVALUATION=True > log-${est_model_name}-prep.txt 2>&1

awk '/^$/ {nlstack=nlstack "\n";next;} {printf "%s",nlstack; nlstack=""; print;}' log-${est_model_name}-prep.txt > log-${est_model_name}.txt

best_epoch=$(tail -1 log-${est_model_name}.txt | tr ":" "\n" | tr ' ' '\n' | tail -3 | head -1)
echo 'Best model weights are dumped into 'trained_models/${est_model_name}/epoch_${best_epoch}_weights.h5

# pre-trained Weights + Vocab to use for scoring
est_vocab=datasets/Dataset_${est_task_name}_${est_src}${est_trg}.pkl
est_weights=trained_models/${est_model_name}/epoch_${best_epoch}_weights.h5

echo "Scoring test."${est_trg}

THEANO_FLAGS=device=$device python main.py TASK_NAME=$est_task_name DATASET_NAME=$est_task_name DATA_ROOT_PATH=examples/${est_task_name} SRC_LAN=${est_src} TRG_LAN=${est_trg} PRED_SCORE=$score MODEL_TYPE=$est_model_type PRED_VOCAB=$est_vocab PRED_WEIGHTS=$est_weights MODE=sampling NEW_EVAL_ON_SETS=test PATIENCE=$patience SAVE_EACH_EVALUATION=True >> log-${est_model_name}.txt 2>&1

mv trained_models/${est_model_name}/test_epoch_0_output_0.pred trained_models/${est_model_name}/test_epoch_${best_epoch}_output_0.pred

echo "Model output in trained_models/"${est_model_name}"/test_epoch_"${best_epoch}"_output_0.pred"
